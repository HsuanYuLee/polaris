#!/usr/bin/env python3
"""Purpose: push-verifier.sh 接上的 pre-push 轉呼叫叫這一支（DP-911）。

  dispatch <remote> <url>     從 stdin 讀 git 給 pre-push 的那幾行，推到一顆開著的 PR 時在背景派驗證者
  run --issue <單> --repo <checkout> --head <sha> --base <branch> [--pr <n>]
                              驗證者本身：自己的 worktree、看不到施工對話的指示、判定寫回那張單

Exit: dispatch 永遠 0（它不擋 push）；run 0 判定寫成、1 寫不成、2 用法錯。

驗證者拿到的只有：那張單的凍結塊、那個 head 相對 base 的 diff、落腳 repo 的規矩檔、本機環境的
宣告（`{前綴}-ENVIRONMENT-{名}`）。不給施工對話、不給量測登錄、不給單上可以改的那部分。
判定是意見，不擋 merge：紅了那張單回 engineering，跑不到的寫「跑不到」與缺什麼，不判綠。

它碰得到的東西只有指示裡寫的上界，不是一道閘：預設命令不載 MCP、不讀這台機器的個人設定，
但 Bash 叫得到。真正擋推 ref 與改動的，是那個 worktree 是 detached、而且用完就拆。
"""
import argparse, glob, json, os, re, shlex, shutil, subprocess, sys, tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SKILLS = os.path.dirname(os.path.dirname(HERE))
SPINE = os.path.join(SKILLS, "driving-work-to-done", "scripts", "spine-loop-state.sh")
NINE = os.path.join(SKILLS, "check-your-own-work", "SKILL.md")
# --allowedTools 收不定個值，後面直接接 prompt 會把 prompt 吃掉；所以它不放最後（2026-10-28 實跑量到）
DEFAULT_AGENT = "claude -p --allowedTools Bash,Read,Grep,Glob,Write --setting-sources project --strict-mcp-config --no-session-persistence"
ZERO = "0" * 40
KEY = re.compile(r"[A-Z][A-Z0-9]+-\d+")
RULE_FILES = ("CLAUDE.md", "AGENTS.md")
AGENT_TIMEOUT = 3600


def say(msg):
    print(f"[push-verifier] {msg}", file=sys.stderr)


def git(repo, *args, check=True):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}：{r.stderr.strip()}")
    return r.stdout.strip()


def config(repo, key):
    return git(repo, "config", "--get", key, check=False)


def slug_of(url):
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", url or "")
    return m.group(1) if m else None


def find_ticket(issues, branch):
    """branch 名裡的單號對到 issues 底下帶 .spine/ 的那張單；對不到或不只一張就回 None 與原因。"""
    keys = set(KEY.findall(branch))
    if not keys:
        return None, f"branch {branch} 裡沒有單號"
    hits = []
    for spine in glob.glob(os.path.join(issues, "**", ".spine"), recursive=True):
        d = os.path.dirname(spine)
        m = KEY.match(os.path.basename(d))
        if m and m.group(0) in keys:
            hits.append(d)
    if len(hits) != 1:
        return None, f"單號 {'、'.join(sorted(keys))} 在 {issues} 對到 {len(hits)} 張單"
    return hits[0], None


def dispatch(remote, url):
    top = git(".", "rev-parse", "--show-toplevel")
    issues = config(top, "polaris.pushVerifier.issues")
    lines = [l.split() for l in sys.stdin.read().splitlines() if l.strip()]
    for parts in lines:
        if len(parts) != 4:
            continue
        local_ref, local_sha, _remote_ref, _ = parts
        if local_sha == ZERO or not local_ref.startswith("refs/heads/"):
            continue  # 刪分支、推 tag 不派
        branch = local_ref[len("refs/heads/"):]
        # 推的網址可能被 pushInsteadOf 改寫過；認不出來就問 remote 原本設的那一個
        slug = slug_of(url) or slug_of(git(top, "remote", "get-url", remote, check=False) if remote else "")
        if not slug:
            say(f"問不到 {branch} 有沒有 open PR：remote {url} 不是 GitHub 的網址。這次不派。")
            continue
        try:
            r = subprocess.run(["gh", "pr", "list", "--repo", slug, "--head", branch, "--state", "open",
                                "--json", "number,baseRefName"], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as e:
            say(f"問不到 {slug} {branch} 有沒有 open PR（{e}）。這次不派。")
            continue
        if r.returncode != 0:
            say(f"問不到 {slug} {branch} 有沒有 open PR（gh exit {r.returncode}：{r.stderr.strip()[:200]}）。這次不派。")
            continue
        prs = json.loads(r.stdout or "[]")
        if not prs:
            continue  # 沒有 open PR 不派，也不吵
        ticket, why = find_ticket(issues, branch) if issues else (None, "沒有記單的根目錄，重跑 push-verifier.sh install")
        if not ticket:
            say(f"{branch} 有 open PR #{prs[0]['number']}，但{why}。這次不派。")
            continue
        logdir = os.path.join(ticket, ".spine", "independent")
        os.makedirs(logdir, exist_ok=True)
        log = os.path.join(logdir, f"{local_sha[:12]}.log")
        cmd = [sys.executable, os.path.abspath(__file__), "run", "--issue", ticket, "--repo", top,
               "--head", local_sha, "--base", prs[0]["baseRefName"], "--pr", str(prs[0]["number"])]
        with open(log, "w") as fh:
            subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT,
                             start_new_session=True, env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
        say(f"已派驗證者：{os.path.basename(ticket)} head {local_sha[:12]}（PR #{prs[0]['number']}），紀錄 {log}")


def frozen_blocks(index_text):
    return "\n\n".join(m.group(0) for m in re.finditer(
        r"<!-- POLARIS-FROZEN-(\S+)-BEGIN -->.*?<!-- POLARIS-FROZEN-\1-END -->", index_text, re.S))


def environment_declarations(repo_root):
    """各 skill 宣告的本機環境起法；掃這支 skill 所在那棵樹與 checkout 自己那一棵。"""
    out = []
    for root in {SKILLS, os.path.join(repo_root, ".claude", "skills")}:
        for f in glob.glob(os.path.join(root, "**", "SKILL.md"), recursive=True):
            for m in re.finditer(r"<!--\s*[A-Za-z0-9_-]+-ENVIRONMENT-([A-Za-z0-9_.-]+):\s*(.*?)\s*-->", open(f, encoding="utf-8").read()):
                out.append(f"- {m.group(1)}：`{m.group(2)}`（宣告在 {f}）")
    return sorted(set(out))


def build_prompt(ticket, wt, diff_file, out_file, head, base):
    text = open(os.path.join(ticket, "index.md"), encoding="utf-8").read()
    rules = [os.path.join(wt, f) for f in RULE_FILES if os.path.isfile(os.path.join(wt, f))]
    rules += sorted(glob.glob(os.path.join(wt, ".claude", "rules", "*.md")))
    envs = environment_declarations(wt)
    return f"""你是一個獨立的驗證者。有人剛把 head {head} 推到一顆開著的 PR（base {base}）。你看不到寫它的人說過什麼，這是刻意的：只照下面的材料自己判。

工作目錄：{wt}（一個只給你用的 worktree，detached 在 {head}）。

## 這張單簽下的成功定義（凍結塊）

{frozen_blocks(text) or "（這張單沒有凍結塊）"}

## 這次的改動

{head} 相對 base 的 diff 在 {diff_file}。

## 這個 repo 自己的規矩

{chr(10).join("- " + r for r in rules) or "- 這個 repo 沒有 CLAUDE.md、AGENTS.md 或 .claude/rules/。"}

## 本機環境怎麼起

{chr(10).join(envs) or "- 沒有任何 skill 宣告本機環境的起法。起不起得來，照 repo 自己的 README 與規矩檔判。"}

## 你要做的兩件事

1. 照 {NINE} 的九問對這份 diff 各答一次，每一問寫抓到什麼。
2. diff 裡每一個新 route、新寫入點、新中介層行為，在本機用真實狀態的資料送一次完整請求，走完整條鏈（跨 repo 就本機起兩邊）。只有 Feature／Unit 測試綠不算走過。

## 判定

- 九問有一條沒處置、或有一條鏈的回應不對：FAIL。
- 本機起不起來、真實狀態的資料拿不到、鏈走不完：UNMEASURABLE，並在 missing 寫出缺什麼。不判 PASS。
- 兩件都走完而且都對：PASS。

把結果寫成 JSON 到 {out_file}，形狀：
{{"verdict": "PASS|FAIL|UNMEASURABLE", "nine_questions": [{{"q": 1, "finding": "..."}}], "request_chains": [{{"what": "...", "result": "...", "evidence": "..."}}], "missing": ["..."], "findings": ["紅的那幾條，一條一句"]}}

## 你碰得到的東西的上界

- 不改 {wt} 以外的任何檔案，只寫 {out_file}；本機起環境需要的暫存檔放在 {os.path.dirname(out_file)} 底下。
- 不 commit、不推任何 ref、不開或關 PR。
- 不送 Slack、不寫 JIRA、不留 PR review 或留言。
- 不碰其他 checkout、branch 與它們的 .env。
"""


def write_back(ticket, head, result):
    short = head[:12]
    os.makedirs(os.path.join(ticket, ".spine", "independent"), exist_ok=True)
    with open(os.path.join(ticket, ".spine", "independent", f"{head}.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    label = {"PASS": "綠", "FAIL": "紅", "UNMEASURABLE": "跑不到"}[result["verdict"]]
    lines = [f"\ncheck-your-own-work 九問，head {short}（驗證者）：{label}"]
    for q in result.get("nine_questions") or []:
        lines.append(f"{q.get('q')}. {q.get('finding')}")
    for c in result.get("request_chains") or []:
        lines.append(f"- 請求鏈 {c.get('what')}：{c.get('result')}")
    for m in result.get("missing") or []:
        lines.append(f"- 缺：{m}")
    for f in result.get("findings") or []:
        lines.append(f"- finding：{f}")
    with open(os.path.join(ticket, "index.md"), "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return label


def back_to_engineering(ticket, head):
    state = os.path.join(ticket, ".spine", "loop-state.json")
    station = json.load(open(state)).get("station")
    if station == "engineering":
        return "站別本來就是 engineering"
    r = subprocess.run(["bash", SPINE, "advance", "--state", state, "--to", "engineering",
                        "--by", "push-verifier"],
                       capture_output=True, text=True)
    return f"站別 {station} → engineering" if r.returncode == 0 else f"退回 engineering 失敗：{r.stderr.strip()[:300]}"


def commit_ticket(ticket, head):
    issues_top = git(ticket, "rev-parse", "--show-toplevel", check=False)
    if not issues_top:
        return "單的那棵樹不是 git repo，判定只寫在檔案裡"
    rel = os.path.relpath(ticket, issues_top)
    git(issues_top, "add", "--", rel, check=False)
    r = subprocess.run(["git", "-C", issues_top, "commit", "-q", "-m", f"push-verifier: {os.path.basename(ticket)} head {head[:12]}", "--", rel],
                       capture_output=True, text=True)
    return "已 commit" if r.returncode == 0 else f"commit 失敗：{r.stderr.strip()[:200]}"


def run(a):
    agent = config(a.repo, "polaris.pushVerifier.agentCmd") or DEFAULT_AGENT
    work = tempfile.mkdtemp(prefix="push-verifier-")
    wt = os.path.join(work, "wt")
    out_file = os.path.join(work, "verdict.json")
    result = None
    try:
        git(a.repo, "worktree", "add", "--detach", wt, a.head)
        base_ref = next((r for r in (f"origin/{a.base}", a.base) if git(wt, "rev-parse", "--verify", "-q", r, check=False)), None)
        diff_file = os.path.join(work, "change.diff")
        if base_ref:
            mb = git(wt, "merge-base", base_ref, a.head)
            open(diff_file, "w").write(git(wt, "diff", f"{mb}..{a.head}"))
        else:
            open(diff_file, "w").write(f"（問不到 base {a.base} 在這個 checkout 的 ref，diff 產不出來）\n")
        prompt = build_prompt(a.issue, wt, diff_file, out_file, a.head, a.base)
        try:
            p = subprocess.run(shlex.split(agent) + [prompt], cwd=wt, capture_output=True, text=True, timeout=AGENT_TIMEOUT,
                               env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
            print(p.stdout[-4000:]); print(p.stderr[-2000:], file=sys.stderr)
        except (OSError, subprocess.TimeoutExpired) as e:
            result = {"verdict": "UNMEASURABLE", "missing": [f"驗證者沒有跑完：{e}"]}
        if result is None:
            try:
                result = json.load(open(out_file, encoding="utf-8"))
                if result.get("verdict") not in ("PASS", "FAIL", "UNMEASURABLE"):
                    raise ValueError(f"verdict 是 {result.get('verdict')!r}")
            except (OSError, ValueError) as e:
                result = {"verdict": "UNMEASURABLE", "missing": [f"驗證者沒有寫出可讀的判定（{e}）"]}
    except RuntimeError as e:
        result = {"verdict": "UNMEASURABLE", "missing": [str(e)]}
    finally:
        git(a.repo, "worktree", "remove", "--force", wt, check=False)
        shutil.rmtree(work, ignore_errors=True)
    result.update({"head": a.head, "base": a.base, "pr": a.pr, "agent_cmd": agent,
                   "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")})
    label = write_back(a.issue, a.head, result)
    note = back_to_engineering(a.issue, a.head) if result["verdict"] == "FAIL" else "站別不動"
    print(f"判定：{label}；{note}；{commit_ticket(a.issue, a.head)}")
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "dispatch":
        try:
            dispatch(*(sys.argv[2:4] + ["", ""])[:2])
        except Exception as e:  # 派工壞掉不能讓 push 失敗
            say(f"派工本身出錯，這次沒派：{e}")
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run"])
    for k in ("--issue", "--repo", "--head", "--base"):
        ap.add_argument(k, required=True)
    ap.add_argument("--pr", default="")
    return run(ap.parse_args())


if __name__ == "__main__":
    sys.exit(main())
