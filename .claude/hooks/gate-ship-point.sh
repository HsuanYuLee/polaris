#!/usr/bin/env bash
# gate-ship-point.sh — PreToolUse hook：出貨動作之前問那張單判過了沒（DP-865 A-P5）。
#
# 判定不在這裡，在 swe-knowledge/scripts/check-ship-point.sh——任何 agent 都能從命令列叫它。
# 這支只做一件事：認出這一次 tool call 是哪一種出貨動作，把它翻成那支腳本的參數。
#
# 認得的三種：
#   - Bash 裡的 `gh pr merge`：問 gh 那顆 PR 的 head branch 與 head commit
#   - Bash 裡的 `git tag`、`git push` 推 tag、`gh release create`：解出 tag 名與它指的 commit
#   - 送訊息的工具（名字結尾是 send_message／schedule_message），而 tool_input 對上某支 skill
#     宣告的部署請求樣式：
#       <!-- {任意前綴}-SHIP-REQUEST: {對 tool_input 的 JSON（鍵排序過）做的 regex} -->
#     這一支不認得任何一家的頻道或 bot，那是宣告的人的事。
#
# 解不出來的（gh 問不到、tag 不存在、找不到單的根目錄）就放行：對不到單不是這一道管的事。
#
# 登記：要在 settings 的 hooks.PreToolUse 底下加兩個 matcher，`Bash` 與送訊息的那一類工具，
# command 都是 `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/gate-ship-point.sh"`。
#
# POLARIS-SCOPE: universal
set -uo pipefail

payload="$(cat)"
root="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$root" || ! -d "$root/issues" ]]; then
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] && root="$(dirname "$common")"
fi
[[ -n "$root" && -d "$root/issues" ]] || exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$here/../skills/swe-knowledge/scripts/check-ship-point.sh"
[[ -f "$check" ]] || exit 0

# 腳本本身走 heredoc 佔掉 stdin，所以 payload 從環境變數進去。
SHIP_POINT_PAYLOAD="$payload" python3 - "$root" "$check" "$here/../skills" <<'PY'
import glob, json, os, re, shlex, subprocess, sys

root, check, skills = sys.argv[1:4]
try:
    data = json.loads(os.environ.get("SHIP_POINT_PAYLOAD") or "")
except ValueError:
    sys.exit(0)
tool = data.get("tool_name") or ""
inp = data.get("tool_input") or {}
cwd = data.get("cwd") or os.getcwd()

def run(args, where):
    try:
        out = subprocess.run(args, cwd=where, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() if out.returncode == 0 else None

def commit_of(ref, where):
    return run(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"], where)

def positional(words, valued):
    out, skip = [], False
    for w in words:
        if skip:
            skip = False
        elif w in valued:
            skip = True
        elif not w.startswith("-"):
            out.append(w)
    return out

def gate(action, branch="", heads=(), text="", tags=()):
    args = ["bash", check, "--issues", os.path.join(root, "issues"), "--action", action,
            "--branch", branch, "--text", text]
    for t in tags:
        args += ["--tag", t]
    for h in heads:
        if h:
            args += ["--head", h]
    out = subprocess.run(args, capture_output=True, text=True)
    if out.returncode == 1:
        sys.stderr.write(out.stderr)
        sys.exit(2)

def declared_ship_requests():
    pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]*SHIP-REQUEST:\s*(.+?)\s*-->")
    found = []
    for skill in glob.glob(os.path.join(skills, "**", "SKILL.md"), recursive=True):
        try:
            found += pattern.findall(open(skill, encoding="utf-8").read())
        except OSError:
            pass
    return found

if re.search(r"(send_message|schedule_message)$", tool):
    flat = json.dumps(inp, ensure_ascii=False, sort_keys=True)
    if any(re.search(p, flat, re.S) for p in declared_ship_requests()):
        gate("deploy", text=inp.get("message") or inp.get("text") or "")
    sys.exit(0)

if tool != "Bash":
    sys.exit(0)

command = inp.get("command") or ""
where = cwd
for segment in re.split(r"&&|\|\||;|\n", command):
    try:
        words = shlex.split(segment)
    except ValueError:
        continue
    if not words:
        continue
    if words[0] == "cd" and len(words) > 1:
        where = os.path.join(where, os.path.expanduser(words[1]))
        continue
    if words[:3] == ["gh", "pr", "merge"]:
        rest = positional(words[3:], {"-R", "--repo", "-t", "--subject", "-b", "--body", "-F", "--body-file",
                                      "-A", "--author-email", "--match-head-commit"})
        repo = []
        for flag in ("-R", "--repo"):
            if flag in words:
                repo = [flag, words[words.index(flag) + 1]]
        view = run(["gh", "pr", "view", *rest[:1], *repo, "--json", "headRefName,headRefOid"], where)
        if view:
            pr = json.loads(view)
            gate("merge", branch=pr.get("headRefName") or "", heads=[pr.get("headRefOid")], text=segment)
    elif words[:2] == ["git", "tag"]:
        names = positional(words[2:], {"-m", "--message", "-F", "--file", "-u", "--local-user"})
        if any(w in ("-d", "--delete", "-l", "--list") for w in words[2:]) or not names:
            continue
        target = names[1] if len(names) > 1 else "HEAD"
        gate("tag", heads=[commit_of(target, where)], text=segment, tags=names[:1])
    elif words[:2] == ["git", "push"]:
        refs = positional(words[2:], {"-o", "--push-option", "--repo"})[1:]
        names = [r.split(":")[0].removeprefix("refs/tags/") for r in refs]
        pushed = [(n, commit_of("refs/tags/" + n, where)) for n in names]
        pushed = [(n, h) for n, h in pushed if h]
        if pushed:
            gate("tag", heads=[h for _, h in pushed], text=segment, tags=[n for n, _ in pushed])
    elif words[:3] == ["gh", "release", "create"]:
        names = positional(words[3:], {"--target", "-t", "--title", "-n", "--notes", "-F", "--notes-file",
                                       "-R", "--repo", "--discussion-category"})
        target = words[words.index("--target") + 1] if "--target" in words else None
        heads = [commit_of(names[0], where) if names else None, commit_of(target, where) if target else None]
        gate("tag", heads=heads, text=segment, tags=names[:1])
PY
