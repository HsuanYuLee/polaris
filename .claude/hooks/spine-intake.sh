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
# 承載：DP-462 B-P4（立案判斷可見）。B-P4 說的是「**當一件工作進來時**」，不是每一句話。
# 第一版對每個非斜線訊息都問一次，包含工作進行中的「繼續」——那比它自己的斷言寬。代價不是
# 多幾行字：每輪逼出一句形式化的「立案判斷：不用立案」，就是用散文應付散文，正是這條路最該
# 防的東西；同時它在一條「開工之後不需要人再指定下一站」的流程裡，每輪重插一個判斷點。
#
# 所以要不要問，從磁碟決定：有 source 開著且已過閘一時，改成報站別，不重問。判斷這件事
# 不用猜——`sources/*/.spine/loop-state.json` 就寫在那裡。
#
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

# 有沒有 source 已經過了閘一。`sources/` 是使用者自己的 repo，可能根本不存在——不存在就
# 當作沒有進行中的工作，走完整上匝道。
SOURCES_DIR="${CLAUDE_PROJECT_DIR:-.}/sources"
active="$(python3 - "$SOURCES_DIR" <<'PY' 2>/dev/null || true
import glob, json, os, sys

# 站在 work / judge 表示閘一簽過了、還沒交付。assert 不算：那正是還在上匝道上。
#
# 判準是站別，不是 loop 的 status。`converged` 說的是「這一輪收斂了」，不是「已經出貨」——
# 第一版拿它當已交付，於是一個站在 judge、證據都齊、正等釋出的 source 被當成不在進行中，
# 下一句話又收到完整上匝道。當場在自己身上發生的。
rows = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*", ".spine", "loop-state.json"))):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if data.get("station") in ("work", "judge"):
        rows.append(f"{os.path.basename(os.path.dirname(os.path.dirname(path)))} 在 {data['station']}")
print("；".join(rows), end="")
PY
)"

# 判準留在一處：這裡只問問題，不重述 assert 的完整判準。把判準抄過來就會有兩份會漂的複本。
if [[ -n "$active" ]]; then
  cat <<TXT
[spine intake] 進行中：${active}。
同一件事就直接往下做，不用再說一次立案判斷——重問已經簽過的東西是儀式，不是把關。
換成另一件會改變行為的事，才做立案判斷並走 assert。不確定現在在哪就跑
\`spine-loop-state.sh where\`，不要問人。
TXT
else
  cat <<'TXT'
[spine intake] 動手之前，先說出立案判斷：這件事要不要立案，依據是什麼。
判準是「有沒有『怎麼算成功』需要人簽字」——唯讀查詢與說明不用，會改變行為的要。
不用立案就直接做；要立案就走 assert。判斷說出來讓人能當場推翻，不要靜默決定。
TXT
fi
exit 0
