#!/usr/bin/env bash
# Push 之前擋兩件事。
#
# 判準是「一旦 push 出去就收不回來，而且發生在 CLI 上」——兩條同時成立才值得用 hook 擋。
# hook 不會被帶到 claude.ai 與 Cowork，所以擋在這裡的東西在那些地方本來就不存在；把不符合
# 這個判準的檢查放進來，只會讓 CLI 跟其他地方的行為不一樣。
#
# 一、外洩掃描：live company slug 進公開 template repo。push 是不可逆的那一刻。
# 二、常駐指令新鮮度：generated CLAUDE.md / AGENTS.md 過期的話，之後每個 session 都會靜默
#    讀到錯的那一份，而且沒有人會發現。
# 三、skill 腳本的同目錄引用：腳本搬家會把寫死的相對路徑變成執行期才炸的洞。DP-462 拆完
#    共用 scripts/ 之後，三個斷點都是釋出跑到一半才炸的——那時候版號已經壓下去了。

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(git -C "$HOOK_DIR" rev-parse --show-toplevel)"
GATES="$HOOK_DIR"

fail=0
bash "$GATES/gate-template-leaks.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-runtime-instruction-manifest.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-skill-script-references.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-ignore-classes.sh" --repo "$ROOT_DIR" || fail=1
bash "$GATES/gate-dangling-declarations.sh" --repo "$ROOT_DIR" || fail=1

if [[ "$fail" -ne 0 ]]; then
  echo "[polaris pre-push] 上面的閘沒過，push 停下。" >&2
  exit 1
fi
