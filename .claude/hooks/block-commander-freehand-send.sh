#!/usr/bin/env bash
# block-commander-freehand-send.sh — PreToolUse hook（SendMessage）：指揮官只送 command-post 印出來的本文。
#
# 為什麼是 hook
# -------------
# command-post 的散文寫了指揮官怎麼派工、怎麼回覆，而 compact 之後散文只剩摘要。2026-10-19
# 指揮官跳過 driving-work-to-done 直接令線開單、自創報告結構，每一則都是手打的 SendMessage，
# 中間沒有一步會紅。官方文件對這件事的建議是「一定要成立的規矩用 hook」：hook 每一次都跑，
# 不讀對話，所以 compact 前後判法相同。
#
# 擋什麼
# ------
# 送訊息的 session 在 ~/.claude/sessions/declarations/{session_id}.json 宣告自己是「指揮官」，
# 而 SendMessage 帶著文字本文時：本文（去尾端空白）的 sha256 不在 command-post 的送出紀錄
# （$COMMAND_POST_DIR 或 ~/.claude/sessions/command-post 底下的 sent.jsonl）裡 → 擋。
# 送出紀錄由 command-post.py 的 --order、--review、--say 寫。印出來之後改過一個字也算手打。
#
# 不擋什麼
# --------
# 不是指揮官的 session；沒有文字本文的 SendMessage（例如只訂閱 idle 通知）；讀不到 session_id 的呼叫。
#
# 擋不到什麼，明講
# ----------------
# 只有 Claude Code 會跑這支。Codex 或其他 agent 那一側沒有 SendMessage，也沒有這道閘。
# 一個 session 不宣告自己是指揮官，這道閘就不認得它。
#
# POLARIS-SCOPE: universal
set -uo pipefail

printf '%s' "$(cat)" | python3 -c '
import hashlib, json, os, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if data.get("tool_name") != "SendMessage":
    sys.exit(0)
sid = data.get("session_id") or ""
msg = (data.get("tool_input") or {}).get("message")
if not sid or not isinstance(msg, str) or not msg.strip():
    sys.exit(0)
home = os.path.expanduser("~")
decl = os.path.join(home, ".claude", "sessions", "declarations", sid + ".json")
try:
    line = json.load(open(decl, encoding="utf-8")).get("line")
except (OSError, ValueError):
    sys.exit(0)
if line != "指揮官":
    sys.exit(0)
d = os.environ.get("COMMAND_POST_DIR") or os.path.join(home, ".claude", "sessions", "command-post")
sent = os.path.join(d, "sent.jsonl")
want = hashlib.sha256(msg.rstrip().encode("utf-8")).hexdigest()
try:
    for row in open(sent, encoding="utf-8"):
        try:
            if json.loads(row).get("sha256") == want:
                sys.exit(0)
        except ValueError:
            continue
except OSError:
    pass
cp = "python3 .claude/skills/command-post/scripts/command-post.py"
sys.stderr.write(
    "擋下：指揮官的 SendMessage 只送 command-post 印出來的本文，這一則在送出紀錄（" + sent + "）裡找不到。\n"
    "改用：\n"
    "  派工      " + cp + " --order --issue <單> --to <線>\n"
    "  互審      " + cp + " --review --issue <單> --to <線> --to <線> --about <判斷什麼>\n"
    "  其餘的話  " + cp + " --say --to <線> --text <本文>\n"
    "把它印出來的本文原樣放進 message，一個字都不改。\n")
sys.exit(2)
'
