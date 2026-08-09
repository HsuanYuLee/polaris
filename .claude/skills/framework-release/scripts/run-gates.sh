#!/usr/bin/env bash
# 八道掃全樹的閘，一次跑完。commit 與 push 兩邊都用這一支。
#
# 這支以前叫 pre-push-quality-gate.sh，判準是「一旦 push 出去就收不回來，而且發生在 CLI
# 上」。2026-08-10 量掉了那個判準的前提：八道閘掃**整棵樹**合計 1.34 秒（最慢的
# template-leaks 0.38s，最快的 dangling-declarations 0.04s）。既然是免費的，把它們留在
# push 那一站就只有壞處——一個過不了閘的 commit 已經在歷史裡了，那時候修要改寫歷史；
# 擋在 commit 的話它從來不存在。
#
# 判準因此只剩一條：**掃全樹而且便宜。** hook 不會被帶到 claude.ai 與 Cowork，所以擋在
# 這裡的東西在那些地方本來就不存在；把不符合這個判準的檢查放進來，只會讓 CLI 跟其他地方
# 的行為不一樣。按 skill 切的 selftest 不走這裡，它有自己的 run-selftests.sh。
#
# **為什麼這幾道沒有擁有者。** 一件事只要說得出擁有者，它就該回到那支 skill 自己檢查自己
# ——那是 run-selftests.sh 的形狀，也是這兩道閘各自的 `--skill` 存在的理由。留在這一層的
# 只有一種東西：**它量的是關係，而關係沒有一端擁有它。** 外洩掃描問的是「這棵樹整體有沒有
# 東西不該出去」，任何單一支 skill 都答不出來；常駐指令新鮮度問的是生成物與來源之間的落差，
# 兩端分屬不同層；剩下兩道的斷指標，指的一端在這支 skill、另一端在別支或別層——判給任何
# 一端都會在另一端被搬走的時候變綠。
#
# 所以這一層的守則是：**一道閘只要說得出一個擁有者，就不該留在這裡。** 說不出來才留。
#
# 一、外洩掃描：live company slug 進公開 template repo。push 是不可逆的那一刻。
# 二、常駐指令新鮮度：generated CLAUDE.md / AGENTS.md 過期的話，之後每個 session 都會靜默
#    讀到錯的那一份，而且沒有人會發現。
# 三、skill 腳本的同目錄引用：腳本搬家會把寫死的相對路徑變成執行期才炸的洞。DP-462 拆完
#    共用 scripts/ 之後，三個斷點都是釋出跑到一半才炸的——那時候版號已經壓下去了。
# 四、散文引用行為：同一個洞的另一面。SKILL.md 指名的檔案、子命令、旗標，搬家之後會一個
#    一個變成空位，而讀的人第一行就被指過去。`engineering` 與 `verify-ac` 的「前置必讀」
#    指著兩個不存在的檔，從 DP-462 一路活到 4.1.0，沒有任何東西看得見。

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
bash "$GATES/gate-ignore-classes.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-dangling-declarations.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-skill-knowledge-locality.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-layer-vocabulary.sh" --repo "$ROOT_DIR" || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo "[polaris run-gates] 上面的閘沒過，停下。" >&2
  exit 1
fi
