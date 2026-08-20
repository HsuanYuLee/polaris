#!/usr/bin/env bash
# spine-intake.sh — UserPromptSubmit hook：只做一件事，指路。
#
# 為什麼還留著一個 hook
# --------------------
# skill 的 description 是**邀請**，模型看得到也可以不理。2026-08-02 的 dogfood 兩跑實測，
# `refinement` 帶著情境化的 description 出現在清單上，模型仍然直接開工，一次都沒叫（拆掉舊層
# 再跑一次也一樣）。hook 不同的地方只有一件：它**必然**執行，而且注入點就在使用者訊息旁邊。
# 模型仍然可以不照做——沒有任何機制能強迫一次 tool call——但「入口有沒有送到眼前」從裁量
# 變成確定。這是這條路的天花板，明講，不假裝它是強制。
#
# 為什麼它只剩一行
# ----------------
# 上一版把立案判準整段抄在這裡，於是每一輪都逼出一句形式化的「立案判斷：不用立案」——用散文
# 應付散文，正是這條路最該防的東西。更糟的是它變成第二個回答「下一步是什麼」的地方：判準有
# 兩份就會漂，而漂掉的那一刻沒有人在看。
#
# 所以判準一句都不抄。這裡只說出入口的名字與磁碟上的現況，**不說任何「你該怎麼做」**——
# 一個只給名字、不給答案的東西，不可能跟殼給出不同的答案。
#
# 拿掉它會怎樣：四支 skill 照常成立，只是被叫起來的機率回到裁量。所以它是這個 repo 的便利，
# 不是流程的前提——搬去 claude.ai / Cowork 時不需要跟著搬。
#
# 這一行是宣告，不是註解：同步問「這個 hook 出不出得去」時讀的就是它。指路的內容
# 沒有一個字綁這台機器或這家公司，所以是 standalone；上面那段說的「不需要跟著搬」
# 指的是 claude.ai / Cowork 那條通道，那條通道從來不收 hook。
# POLARIS-SCOPE: standalone
#
# Input:  stdin JSON，欄位 user_prompt（或 prompt）
# Stdout: 一行 context
# Exit:   永遠 0——這是提示，不擋使用者的話

set -uo pipefail

payload="$(cat 2>/dev/null || true)"

prompt="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("user_prompt") or d.get("prompt") or "", end="")
' 2>/dev/null || true)"

[[ -n "$prompt" ]] || exit 0

# 斜線指令自己就是明確的入口，不需要再指一次路。
case "$prompt" in
  /*) exit 0 ;;
esac

# 有沒有單已經過了閘一。`issues/` 是使用者自己的 repo，可能根本不存在。
ISSUES_DIR="${CLAUDE_PROJECT_DIR:-.}/issues"
active="$(python3 - "$ISSUES_DIR" <<'PY' 2>/dev/null || true
import glob, json, os, sys

# 站在 engineering / verify-ac 表示閘一簽過了、還沒交付。refinement 不算：那正是還在上匝道上。
#
# 判準是站別，不是 loop 的 status。`converged` 說的是「這一輪收斂了」，不是「已經出貨」——
# 第一版拿它當已交付，於是一張站在 verify-ac、證據都齊、正等釋出的單被當成不在進行中。
rows = []
# 版面是 issues/{命名空間}/{單}/.spine/。命名空間只是路徑的一段，不參與任何判定。
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*", "*", ".spine", "loop-state.json"))):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if data.get("station") in ("engineering", "verify-ac"):
        issue_dir = os.path.dirname(os.path.dirname(path))
        name = os.path.join(os.path.basename(os.path.dirname(issue_dir)), os.path.basename(issue_dir))
        rows.append(f"{name} 在 {data['station']}")
print("；".join(rows), end="")
PY
)"

if [[ -n "$active" ]]; then
  echo "[spine intake] 進行中：${active}。流轉與立案的判準在 driving-work-to-done。"
else
  echo "[spine intake] 有工作進來的話，入口是 driving-work-to-done。"
fi
exit 0
