#!/usr/bin/env bash
# 六道掃全樹的閘，一次跑完。commit 與 push 兩邊都用這一支。
#
# **留在這裡的門檻只有一條**（使用者 2026-08-13 拍板，寫在 .claude/instructions/core/
# bootstrap.md）：一道閘要守著一個**不可逆、或會出去到這個 repo 之外**的後果，而且那個
# 後果**看 diff 的人看不出來**。三個條件同時成立才留。
#
# 一、gate-template-leaks —— live company slug 進公開的 template repo。push 出去收不回來。
# 二、gate-runtime-instruction-manifest —— 生成的常駐指令過期。它跟著 template 出去，而且
#    之後每個 session 都靜默讀到錯的那一份。
# 三、gate-skill-script-references —— skill 腳本指名一條不存在的路徑。skill 會被單獨帶到
#    claude.ai 與 Cowork，那裡的人修不了它，而在這台機器上它從來不炸。
# 四、gate-prose-matches-behaviour —— 同一件事的散文面：SKILL.md 指名的檔案／子命令／旗標
#    對不上。帶出去之後讀的人第一行就被指去一個空位。
# 五、gate-skill-knowledge-locality —— 一支 skill 靠工作區底下沒有版控的東西才跑得動。
#    在寫下它的人的機器上全綠，別人拿到就是壞的（2026-08-07 rex 實際撞到）。
# 六、gate-copy-sets —— 同名副本漂開。其中一份會被同步出去，而漂掉的那一刻沒有東西說話。
#
# **2026-08-13 拿掉了四道**，因為它們守的後果留在這棵樹裡、而且會在下一次有人用到的時候
# 大聲壞掉：gate-layer-vocabulary（散文斷言散文——哪些詞不得出現在哪支 skill 的散文裡）、
# gate-ignore-classes（死的忽略規則）、gate-dangling-declarations（mise 任務指向被刪的檔案）、
# gate-docs-collection（文件站台的 frontmatter）。它們判準寫得對，但每一次無關的改動都要
# 付錢，而它們擋的東西 clone 一次、跑一次就看得到。
#
# 這六道掃全樹合計約 1.6 秒，所以它們掛在 **commit** 上，不是 push——一個過不了閘的 commit
# 已經在歷史裡了，那時候修要改寫歷史。按 skill 切的 selftest 不走這裡，它有自己的
# run-selftests.sh。
#
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATES="$HOOK_DIR"

ROOT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) ROOT_DIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

# git 在跑 hook 的時候會把 GIT_DIR 放進環境，而 `rev-parse --show-toplevel` 在 GIT_DIR
# 已經指定的情況下回的是**當下的工作目錄**，不是那個 repo 的根。所以這一行本來解出來的
# 是這支腳本自己所在的 scripts/ 目錄——六道閘全部拿著一個只裝著它們自己的「repo 根」去
# 掃：兩道因為找不到檔案而炸，另外四道安靜地回「0 個檔，都對得上」。
#
# 一道掃不到東西而回綠的閘，跟一道掃過了沒問題的閘，在輸出上長得一樣。所以這裡把那兩個
# 變數拿掉再問一次，並且在下面驗根解對了沒有——**解錯根要停，不能回綠**。
[[ -n "$ROOT_DIR" ]] || ROOT_DIR="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$HOOK_DIR" rev-parse --show-toplevel)"

if [[ ! -d "$ROOT_DIR/.claude/skills" ]]; then
  echo "[polaris run-gates] 解出來的 repo 根 '$ROOT_DIR' 底下沒有 .claude/skills；" >&2
  echo "[polaris run-gates] 這代表根解錯了，而不是這個 repo 沒有 skill。閘拿著錯的根會全部空掃回綠，所以停。" >&2
  exit 1
fi

fail=0
bash "$GATES/gate-template-leaks.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-runtime-instruction-manifest.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-skill-script-references.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-prose-matches-behaviour.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-skill-knowledge-locality.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-copy-sets.sh" --repo "$ROOT_DIR" || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo "[polaris run-gates] 上面的閘沒過，停下。" >&2
  exit 1
fi
