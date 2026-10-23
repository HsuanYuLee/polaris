#!/usr/bin/env python3
"""Run one skill's question set against two versions of that skill, blind, and judge from transcripts.

Purpose: say whether a change to a skill made the agent do better or worse on the failures that
         skill has already caused, without the agent or the judge knowing which version is which.
Inputs:  --repo (a git repo carrying .claude/skills), --skill (its name), --base / --head (two refs),
         --out (where this run's files go). The questions live in that skill's evals/evals.json.
Outputs: <out>/summary.md (one row per question, both versions, where each transcript is),
         <out>/result.json, and per question the two transcripts and the judge's verdicts.
         Exit 0 when it ran to the end, whatever the verdicts are; 2 when it could not run.

The candidate runs in a fresh directory that holds the repo's skill tree at --head with only the
skill under test swapped to the version for that arm, plus whatever files the question names.
Nothing in that directory, its path, or the prompt says it is being measured. The judge sees two
transcripts labelled A and B; which ref is behind each label is drawn per question and written
only to key.json, which the judge never sees.
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
    args = ap.parse_args()

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
        # 版本照抽籤結果記，不從 ref 推回來：--base 與 --head 可以是同一個 ref
        versions = ["base", "head"] if random.random() < 0.5 else ["head", "base"]
        key[cid] = dict(zip("AB", versions))
        arms = {label: getattr(args, version) for label, version in key[cid].items()}
        case_dir = out / f"q{cid}"
        case_dir.mkdir(exist_ok=True)
        texts = {}
        for label, ref in arms.items():
            work, removed = prepare_workspace(repo, args.skill, ref, args.head, case, skill_root)
            transcript = case_dir / f"{label}.transcript.jsonl"
            rc, changes = run_candidate(args.agent_cmd, case["prompt"], work, transcript, args.timeout)
            (case_dir / f"{label}.changes.txt").write_text(
                f"exit: {rc}\nremoved from the candidate's tree (telltale names): {removed}\n{changes}")
            texts[label] = render_transcript(transcript) + f"\n[files changed at the end]\n{changes}"
            (case_dir / f"{label}.transcript.txt").write_text(texts[label])
            if not args.keep_workspaces:
                shutil.rmtree(work, ignore_errors=True)
        grades = judge(args.judge_cmd, case, texts["A"], texts["B"], case_dir / "judge.json") or {}
        n = len(case["expectations"])
        by_version = {key[cid][label]: case_verdict(grades.get(label), n) for label in ("A", "B")}
        label_of = {v: k for k, v in key[cid].items()}
        rows.append({"id": cid, "group": case.get("group", "?"), "source": case.get("source", ""),
                     "base": by_version["base"], "head": by_version["head"],
                     "base_transcript": str(case_dir / f"{label_of['base']}.transcript.txt"),
                     "head_transcript": str(case_dir / f"{label_of['head']}.transcript.txt"),
                     "judge": str(case_dir / "judge.json")})
        # 每題寫一次：跑到一半死掉的話，已經跑完的那幾題還解得了盲
        (out / "key.json").write_text(json.dumps(key, indent=1))
        print(f"q{cid} [{rows[-1]['group']}] base={rows[-1]['base']} head={rows[-1]['head']}", flush=True)

    (out / "result.json").write_text(json.dumps({"skill": args.skill, "base": args.base,
                                                 "head": args.head, "rows": rows}, indent=1, ensure_ascii=False))
    write_summary(out, args, rows)
    print(f"SUMMARY: {out / 'summary.md'}")


def write_summary(out, args, rows):
    lines = [f"# {args.skill}: {args.base} → {args.head}", ""]
    for group in ("capability", "regression"):
        part = [r for r in rows if r["group"] == group]
        if not part:
            continue
        count = lambda side, v: sum(1 for r in part if r[side] == v)
        lines.append(f"- {group}: base PASS {count('base', 'PASS')}/{len(part)}"
                     f"（UNKNOWN {count('base', 'UNKNOWN')}），head PASS {count('head', 'PASS')}/{len(part)}"
                     f"（UNKNOWN {count('head', 'UNKNOWN')}）")
    lines += ["", "| 題 | 組 | base | head | base transcript | head transcript | 判定 |",
              "|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| q{r['id']} | {r['group']} | {r['base']} | {r['head']} | "
                     f"{r['base_transcript']} | {r['head_transcript']} | {r['judge']} |")
    lines += ["", "UNKNOWN 不算通過也不算失敗。判定要人抽讀 transcript 核對，不照分數直接收。"]
    (out / "summary.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
