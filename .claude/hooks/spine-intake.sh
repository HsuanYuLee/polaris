#!/usr/bin/env bash
# spine-intake.sh — UserPromptSubmit hook：脊椎的上匝道
#
# 為什麼是 hook 而不是 skill description：description 是**邀請**，模型看得到也可以不理。
# 2026-08-02 的 dogfood 兩跑實測，`assert` 帶著情境化的 description 出現在清單上，模型仍然
# 直接開工，一次都沒叫（拆掉舊層再跑一次也一樣）。skill 的自動調用是裁量的，沒有東西強制它。
#
# hook 不同的地方只有一件：它**必然**執行，而且注入點就在使用者訊息旁邊，不是 context 最
# 上面。模型仍然可以不照做——沒有任何機制能強迫一次 tool call——但「要求有沒有送到眼前」
# 從裁量變成確定。這是這條路的天花板，明講，不假裝它是強制。
#
# 承載：DP-462 B-P4（立案判斷可見）。
# Input:  stdin JSON，欄位 user_prompt（或 prompt）
# Stdout: 注入 prompt context 的短提示
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

# 斜線指令自己就是明確的入口，不需要再提醒一次。
case "$prompt" in
  /*) exit 0 ;;
esac

# 判準留在一處：這裡只問問題，不重述 assert 的完整判準。把判準抄過來就會有兩份會漂的複本。
cat <<'TXT'
[spine intake] 動手之前，先說出立案判斷：這件事要不要立案，依據是什麼。
判準是「有沒有『怎麼算成功』需要人簽字」——唯讀查詢與說明不用，會改變行為的要。
不用立案就直接做；要立案就走 assert。判斷說出來讓人能當場推翻，不要靜默決定。
TXT
exit 0
