#!/usr/bin/env python3
"""Run one skill's question set against two versions of that skill, blind, and judge from transcripts.

Purpose: say whether a change to a skill made the agent do better or worse on the failures that
         skill has already caused, without the agent or the judge knowing which version is which.
Inputs:  --repo (a git repo carrying .claude/skills), --skill (its name), --base / --head (two refs),
         --out (where this run's files go). The questions live in that skill's evals/evals.json.
Outputs: <out>/summary.md (one row per question, both versions, where each transcript is),
         <out>/result.json, and per question and run the two transcripts and the judge's verdicts.
         Each question runs --runs times per version (default 2); a question whose verdicts
         differ between runs of the same version is marked as flipped and left out of the counts.
         Exit 0 when it ran to the end, whatever the verdicts are; 2 when it could not run.

The candidate runs in a fresh directory that holds the repo's skill tree at --head with only the
skill under test swapped to the version for that arm, plus whatever files the question names.
Nothing in that directory, its path, or the prompt says it is being measured. The judge sees two
transcripts labelled A and B; which ref is behind each label is drawn per question and run, and
written only to key.json, which the judge never sees.
"""

import argparse
import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_AGENT = (
    "claude -p --setting-sources project --strict-mcp-config --no-session-persistence "
    "--output-format stream-json --verbose --permission-mode bypassPermissions"
)
DEFAULT_JUDGE = "claude -p --setting-sources project --strict-mcp-config --no-session-persistence"
# 候選看得到的名字裡不得出現這些字（pstack Eval playbook 的盲測清單）。
TELLTALE = ("eval", "test", "judge", "experiment", "rubric", "score", "compare",
            "benchmark", "candidate", "arena")


def die(msg):
    print(f"UNABLE: {msg}", file=sys.stderr)
    sys.exit(2)


def git(repo, *args, **kw):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, **kw).stdout


def export_tree(repo, ref, path, dest):
    """Write `path` as it is at `ref` into `dest` (dest/<path>)."""
    archive = git(repo, "archive", "--format=tar", ref, "--", path)
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive, check=True)


def blind_name(case):
    name = case.get("workspace", "project")
    if any(word in name.lower() for word in TELLTALE):
        die(f"question {case['id']} names its workspace {name!r}, which gives the game away")
    return name


def prepare_workspace(repo, skill, ref_for_skill, head, case, skill_root):
    """A fresh directory the candidate works in. Only the skill under test differs between arms."""
    work = Path(tempfile.mkdtemp(prefix=f"{blind_name(case)}-"))
    export_tree(repo, head, ".claude/skills", work)
    target = work / ".claude/skills" / skill
    shutil.rmtree(target)
    staging = Path(tempfile.mkdtemp())
    export_tree(repo, ref_for_skill, f".claude/skills/{skill}", staging)
    shutil.move(str(staging / ".claude/skills" / skill), str(target))
    shutil.rmtree(staging)
    # 名字會洩題的東西不跟著候選走：evals/ 裡有預期行為與出處，selftests/ 與這支 runner 的
    # 名字本身就說出「這裡在量東西」。代價是候選那棵樹少了這些檔，拿掉幾個記在 removed 裡。
    removed = strip_telltales(work / ".claude")
    for rel in case.get("files", []):
        src = skill_root / rel
        dst = work / Path(rel).name
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, dst)
    subprocess.run(["git", "init", "-q", str(work)], check=True)
    subprocess.run(["git", "-C", str(work), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(work), "-c", "user.name=dev", "-c", "user.email=dev@example.com",
                    "commit", "-qm", "start"], check=True)
    # 題目要的現場（一段 diff、一張單、一份草稿）由出題的人寫成腳本，在候選的目錄裡跑一次。
    # 腳本住在 evals/ 底下、從那裡執行，所以它本身不會出現在候選看得到的地方。
    if case.get("setup"):
        env = {**os.environ, "GIT_AUTHOR_NAME": "dev", "GIT_AUTHOR_EMAIL": "dev@example.com",
               "GIT_COMMITTER_NAME": "dev", "GIT_COMMITTER_EMAIL": "dev@example.com"}
        try:
            subprocess.run(["bash", str(skill_root / case["setup"])], cwd=work, env=env, check=True,
                           stdout=subprocess.DEVNULL)
        except subprocess.CalledProcessError as e:
            shutil.rmtree(work, ignore_errors=True)
            die(f"question {case['id']}: setup {case['setup']} exited {e.returncode}")
    return work, removed


def strip_telltales(root):
    """Remove every file or directory under root whose name contains a telltale word; return the count."""
    removed = 0
    for path in sorted(root.rglob("*"), key=lambda p: len(p.parts)):
        if path.exists() and any(word in path.name.lower() for word in TELLTALE):
            shutil.rmtree(path) if path.is_dir() else path.unlink()
            removed += 1
    return removed


def run_candidate(agent_cmd, prompt, work, transcript_path, timeout):
    with open(transcript_path, "w") as out:
        try:
            proc = subprocess.run([*shlex.split(agent_cmd), prompt], cwd=work, stdout=out,
                                  stderr=subprocess.STDOUT, timeout=timeout)
            rc = proc.returncode
        except subprocess.TimeoutExpired:
            rc = "timeout"
        except FileNotFoundError:
            shutil.rmtree(work, ignore_errors=True)
            die(f"agent command not found: {shlex.split(agent_cmd)[0]}")
    changes = subprocess.run(["git", "-C", str(work), "status", "--short"],
                             capture_output=True, text=True).stdout
    forget_agent_trace(work)
    return rc, changes


def forget_agent_trace(cwd):
    """Claude Code 帶著 --no-session-persistence 仍會把 tool-results 寫進家目錄底下以工作目錄命名
    的那一格。工作目錄是這一趟開的暫存目錄，所以那一格也只會是這一趟造的。"""
    trace = Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(cwd).resolve()))
    shutil.rmtree(trace, ignore_errors=True)


def render_transcript(path):
    """stream-json → readable text: what the agent said, which tools it called with what, what came back.
    A transcript that is not stream-json (another agent CLI) is passed through as-is."""
    lines, raw = [], Path(path).read_text(errors="replace")
    for line in raw.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            return raw
        for block in (event.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "text":
                lines.append(f"[{event.get('type')}] {block['text']}")
            elif kind == "tool_use":
                lines.append(f"[tool call] {block.get('name')} {json.dumps(block.get('input'), ensure_ascii=False)[:2000]}")
            elif kind == "tool_result":
                content = block.get("content")
                if isinstance(content, list):
                    content = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
                lines.append(f"[tool result] {str(content)[:2000]}")
    return "\n".join(lines) or raw


JUDGE_PROMPT = """You are grading two agent transcripts, labelled A and B, for the same user request.
Grade each expectation for each transcript separately, from what the transcript shows the agent
actually did (tool calls and their results), not from what the agent claims about itself.

User request:
{prompt}

What a correct run does:
{expected}

Expectations:
{expectations}

Transcript A:
<<<
{a}
>>>

Transcript B:
<<<
{b}
>>>

Answer with JSON only, no prose, in this shape:
{{"A": [{{"expectation": 1, "verdict": "PASS|FAIL|UNKNOWN", "quote": "short quote from transcript A"}}],
  "B": [ ...same... ]}}
Use UNKNOWN when the transcript does not hold enough to decide. Every PASS and FAIL needs a quote."""


def judge(judge_cmd, case, text_a, text_b, verdict_path):
    expectations = "\n".join(f"{i}. {e}" for i, e in enumerate(case["expectations"], 1))
    prompt = JUDGE_PROMPT.format(prompt=case["prompt"], expected=case.get("expected_output", ""),
                                 expectations=expectations, a=text_a, b=text_b)
    # 判官拿到的全文留一份，事後查得到它到底看過什麼（例如有沒有看到版本）。
    Path(verdict_path).with_name("judge.prompt.txt").write_text(prompt)
    with tempfile.TemporaryDirectory() as cwd:
        out = subprocess.run([*shlex.split(judge_cmd), prompt], cwd=cwd, capture_output=True, text=True)
        forget_agent_trace(cwd)
    Path(verdict_path).write_text(out.stdout)
    start, end = out.stdout.find("{"), out.stdout.rfind("}")
    try:
        return json.loads(out.stdout[start:end + 1])
    except (ValueError, json.JSONDecodeError):
        return None


def case_verdict(grades, n):
    """PASS only when every expectation passed; any UNKNOWN (or an unreadable judge) is UNKNOWN."""
    if not grades or len(grades) != n:
        return "UNKNOWN"
    verdicts = [g.get("verdict", "UNKNOWN").upper() for g in grades]
    if "FAIL" in verdicts:
        return "FAIL"
    return "PASS" if all(v == "PASS" for v in verdicts) else "UNKNOWN"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--skill", required=True)
    ap.add_argument("--base", required=True, help="the ref before the change")
    ap.add_argument("--head", required=True, help="the ref after the change")
    ap.add_argument("--out", required=True)
    ap.add_argument("--agent-cmd", default=DEFAULT_AGENT,
                    help="command that runs the agent; the prompt is appended as the last argument")
    ap.add_argument("--judge-cmd", default=DEFAULT_JUDGE)
    ap.add_argument("--only", nargs="*", help="question ids to run")
    ap.add_argument("--group", choices=["capability", "regression"])
    ap.add_argument("--timeout", type=int, default=900, help="seconds per candidate run")
    ap.add_argument("--keep-workspaces", action="store_true")
    ap.add_argument("--runs", default="2", help="runs per question and version (default 2)")
    args = ap.parse_args()
    # 一趟的結果分不出兩版：同一題兩趟可以給相反的答案（DP-872 q6），所以預設跑兩趟。
    if not re.fullmatch(r"[1-9][0-9]*", args.runs.strip()):
        die(f"--runs must be a whole number of at least 1, got {args.runs!r}")
    args.runs = int(args.runs)

    repo = Path(args.repo).resolve()
    skill_root = repo / ".claude/skills" / args.skill
    questions = skill_root / "evals" / "evals.json"
    if not questions.is_file():
        die(f"{questions} does not exist")
    cases = json.loads(questions.read_text())["evals"]
    cases = [c for c in cases if (not args.only or str(c["id"]) in args.only)
             and (not args.group or c.get("group") == args.group)]
    if not cases:
        die("no question matched --only / --group")
    for ref in (args.base, args.head):
        try:
            git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}")
        except subprocess.CalledProcessError:
            die(f"ref {ref} does not exist in {repo}")

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    key, rows = {}, []
    for case in cases:
        cid = str(case["id"])
        n = len(case["expectations"])
        key[cid] = {}
        verdicts = {"base": [], "head": []}
        transcripts = {"base": [], "head": []}
        judges = []
        for run in range(1, args.runs + 1):
            # 版本照抽籤結果記，不從 ref 推回來：--base 與 --head 可以是同一個 ref。每一趟各抽一次。
            versions = ["base", "head"] if random.random() < 0.5 else ["head", "base"]
            labels = dict(zip("AB", versions))
            key[cid][str(run)] = labels
            arms = {label: getattr(args, version) for label, version in labels.items()}
            run_dir = out / f"q{cid}" / f"run{run}"
            run_dir.mkdir(parents=True, exist_ok=True)
            texts = {}
            for label, ref in arms.items():
                work, removed = prepare_workspace(repo, args.skill, ref, args.head, case, skill_root)
                transcript = run_dir / f"{label}.transcript.jsonl"
                rc, changes = run_candidate(args.agent_cmd, case["prompt"], work, transcript, args.timeout)
                (run_dir / f"{label}.changes.txt").write_text(
                    f"exit: {rc}\nremoved from the candidate's tree (telltale names): {removed}\n{changes}")
                texts[label] = render_transcript(transcript) + f"\n[files changed at the end]\n{changes}"
                (run_dir / f"{label}.transcript.txt").write_text(texts[label])
                if not args.keep_workspaces:
                    shutil.rmtree(work, ignore_errors=True)
            grades = judge(args.judge_cmd, case, texts["A"], texts["B"], run_dir / "judge.json") or {}
            for label, version in labels.items():
                verdicts[version].append(case_verdict(grades.get(label), n))
                transcripts[version].append(str(run_dir / f"{label}.transcript.txt"))
            judges.append(str(run_dir / "judge.json"))
            # 每趟寫一次：跑到一半死掉的話，已經跑完的那幾趟還解得了盲
            (out / "key.json").write_text(json.dumps(key, indent=1))
        # 同一版的幾趟判定不全相同就是翻面：單趟的那個結果換一次跑就可能反過來，不拿來比兩版。
        flipped = any(len(set(verdicts[v])) > 1 for v in ("base", "head"))
        rows.append({"id": cid, "group": case.get("group", "?"), "source": case.get("source", ""),
                     "base": verdicts["base"], "head": verdicts["head"], "flipped": flipped,
                     "base_transcripts": transcripts["base"], "head_transcripts": transcripts["head"],
                     "judges": judges})
        print(f"q{cid} [{rows[-1]['group']}] base={','.join(verdicts['base'])} "
              f"head={','.join(verdicts['head'])}{' FLIPPED' if flipped else ''}", flush=True)

    (out / "result.json").write_text(json.dumps({"skill": args.skill, "base": args.base,
                                                 "head": args.head, "runs": args.runs, "rows": rows}, indent=1, ensure_ascii=False))
    write_summary(out, args, rows)
    print(f"SUMMARY: {out / 'summary.md'}")


def write_summary(out, args, rows):
    lines = [f"# {args.skill}: {args.base} → {args.head}", "", f"每題每版跑 {args.runs} 趟。", ""]
    for group in ("capability", "regression"):
        part = [r for r in rows if r["group"] == group]
        if not part:
            continue
        steady = [r for r in part if not r["flipped"]]
        flipped = [f"q{r['id']}" for r in part if r["flipped"]]
        if not steady:
            lines.append(f"- {group}: 沒有可比的題（{len(part)} 題全部翻面：{', '.join(flipped)}）")
            continue
        # 沒翻面的題每一趟判定都一樣，取第一趟就是它的判定。
        count = lambda side, v: sum(1 for r in steady if r[side][0] == v)
        line = (f"- {group}: base PASS {count('base', 'PASS')}/{len(steady)}"
                f"（UNKNOWN {count('base', 'UNKNOWN')}），head PASS {count('head', 'PASS')}/{len(steady)}"
                f"（UNKNOWN {count('head', 'UNKNOWN')}）")
        if flipped:
            line += f"；翻面 {len(flipped)} 題不計入：{', '.join(flipped)}"
        lines.append(line)
    lines += ["", "| 題 | 組 | base | head | 翻面 | base transcript | head transcript | 判定 |",
              "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| q{r['id']} | {r['group']} | {' / '.join(r['base'])} | {' / '.join(r['head'])} | "
                     f"{'翻面' if r['flipped'] else ''} | {'<br>'.join(r['base_transcripts'])} | "
                     f"{'<br>'.join(r['head_transcripts'])} | {'<br>'.join(r['judges'])} |")
    lines.append("")
    if args.runs == 1:
        lines.append("只跑了一趟：看不出哪一題會翻面，通過數是單趟的結果。")
    else:
        lines.append("翻面：同一版幾趟的判定不全相同。翻面的題不算進兩版的通過數，要讀 transcript 看它為什麼不穩。")
    lines.append("UNKNOWN 不算通過也不算失敗。判定要人抽讀 transcript 核對，不照分數直接收。")
    (out / "summary.md").write_text("\n".join(lines) + "\n")

if __name__ == "__main__":
    main()
