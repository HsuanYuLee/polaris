#!/usr/bin/env bash
# Purpose: 每次推到一顆開著的 PR，由施工那條線以外派一個看不到施工對話的驗證者（DP-911）。
#          這一支負責接上 git hook：install／remove／status。派工與驗證本身在 push-verifier.py。
# Inputs:  install --repo <checkout> --issues <單的根目錄> [--agent-cmd '<啟動驗證者的命令>']
#          remove  --repo <checkout>
#          status  --repo <checkout>
# Outputs: 接上、拆掉、或現在的狀態，一行一件事。
# Exit:    0 成功 / 1 拆不掉、接不上、或沒接上（status）/ 2 用法錯
#
# 觸發點是 git 的 pre-push hook，所以 Claude Code 與 Codex 推都會觸發。它不擋 push，也不等驗證者。
#
# **不取代既有的 hook。** 產品 repo 的 hook 常常不在 .git/hooks：husky 把 core.hooksPath 指到
# .husky/_，有的 repo 一支都沒有。git 一個事件只跑 core.hooksPath 底下那一支，沒有用設定宣告
# 多支的機制（2.50 量過），而 repo 裡被追蹤的檔不歸我們改。所以這裡在 git-common-dir 底下放一組
# 轉呼叫：core.hooksPath 指到它，每一支先照樣跑原本那一支（輸出、stdin、exit code 原樣），只有
# pre-push 而且原本那一支成功時，才把同一份 stdin 交給派工。原本的 core.hooksPath 記在
# polaris.pushVerifier.chainedHooksPath，remove 時還原。
#
# 轉呼叫只為原本那個目錄裡已經有的 hook 名字與 pre-push 建：其餘名字的 hook 光是存在就會改變 git
# 的行為（例如 push-to-checkout）。原本那個目錄之後多了新的 hook，重跑一次 install。
#
# 擋不到的，明講：husky 在 npm install 時會把 core.hooksPath 寫回 .husky/_，那之後轉呼叫不在了，
# status 會說出來；`git push --no-verify` 跳過所有 hook，驗證者也不會被派。
set -euo pipefail

usage() { sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MARK="[polaris-push-verifier]"

cmd="${1:-}"; [[ -n "$cmd" ]] || usage; shift
REPO="" ISSUES="" AGENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issues) ISSUES="${2:-}"; shift 2 ;;
    --agent-cmd) AGENT="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "不認得的參數：$1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" ]] || usage
REPO="$(cd "$REPO" && pwd -P)"
g() { git -C "$REPO" "$@"; }
common="$(cd "$REPO" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
CHAIN="$common/polaris-push-verifier/hooks"

installed() { [[ "$(g config --get polaris.pushVerifier.installed || true)" == true ]]; }

# 原本那個 hook 目錄的絕對位置。相對路徑相對於工作樹的根，跟 git 自己解它的方式一樣。
original_dir() {
  local orig; orig="$(g config --get polaris.pushVerifier.chainedHooksPath || true)"
  if [[ -z "$orig" ]]; then printf '%s\n' "$common/hooks"
  elif [[ "$orig" == /* ]]; then printf '%s\n' "$orig"
  else printf '%s\n' "$REPO/$orig"; fi
}

write_stub() {
  cat > "$CHAIN/$1" <<'STUB'
#!/usr/bin/env bash
# [polaris-push-verifier] 先照樣跑原本那一支 hook，再（只在 pre-push、而且它成功時）派驗證者。
name="$(basename "$0")"
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
orig="$(git config --get polaris.pushVerifier.chainedHooksPath || true)"
if [[ -z "$orig" ]]; then dir="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)/hooks"
elif [[ "$orig" == /* ]]; then dir="$orig"
else dir="$top/$orig"; fi
rc=0
if [[ "$name" == pre-push ]]; then
  input="$(cat)"
  if [[ -x "$dir/$name" ]]; then printf '%s\n' "$input" | "$dir/$name" "$@"; rc=$?; fi
  script="$(git config --get polaris.pushVerifier.script || true)"
  if [[ $rc -eq 0 && -f "$script" ]]; then
    printf '%s\n' "$input" | python3 "$script" dispatch "$@" || true
  fi
else
  if [[ -x "$dir/$name" ]]; then "$dir/$name" "$@"; rc=$?; fi
fi
exit $rc
STUB
  chmod +x "$CHAIN/$1"
}

case "$cmd" in
  install)
    [[ -n "$ISSUES" && -d "$ISSUES" ]] || { echo "install 要 --issues <單的根目錄>（驗證者把判定寫進那裡的單）" >&2; exit 2; }
    current="$(g config --get core.hooksPath || true)"
    if ! installed; then
      g config polaris.pushVerifier.chainedHooksPath "$current"
      g config polaris.pushVerifier.installed true
    elif [[ "$current" != "$CHAIN" ]]; then
      echo "記著接上了，但 core.hooksPath 現在是「${current}」，不是轉呼叫那一組。被改回去了（例如 npm install 時 husky 重寫）；把它當成新的原本那一支重接。" >&2
      g config polaris.pushVerifier.chainedHooksPath "$current"
    fi
    g config polaris.pushVerifier.issues "$(cd "$ISSUES" && pwd -P)"
    g config polaris.pushVerifier.script "$HERE/push-verifier.py"
    [[ -n "$AGENT" ]] && g config polaris.pushVerifier.agentCmd "$AGENT"
    mkdir -p "$CHAIN"
    find "$CHAIN" -type f -exec grep -lF "$MARK" {} + 2>/dev/null | while read -r f; do rm -f "$f"; done
    orig="$(original_dir)"
    names=(pre-push)
    if [[ -d "$orig" ]]; then
      while IFS= read -r f; do
        n="$(basename "$f")"; [[ "$n" == *.sample || "$n" == pre-push ]] && continue
        [[ -x "$f" && -f "$f" ]] && names+=("$n")
      done < <(find "$orig" -maxdepth 1 -type f)
    fi
    for n in "${names[@]}"; do write_stub "$n"; done
    g config core.hooksPath "$CHAIN"
    echo "接上了：core.hooksPath → ${CHAIN}（原本是「$(g config --get polaris.pushVerifier.chainedHooksPath)」，轉呼叫 ${#names[@]} 支：${names[*]}）"
    ;;
  remove)
    installed || { echo "這個 checkout 沒有接上，沒有東西要拆。"; exit 0; }
    orig="$(g config --get polaris.pushVerifier.chainedHooksPath || true)"
    if [[ -n "$orig" ]]; then g config core.hooksPath "$orig"; else g config --unset core.hooksPath || true; fi
    g config --remove-section polaris.pushVerifier 2>/dev/null || true
    rm -rf "$common/polaris-push-verifier/hooks"
    echo "拆掉了：core.hooksPath 回到「${orig}」"
    ;;
  status)
    if ! installed; then echo "沒有接上：推到開著的 PR 不會派驗證者。"; exit 1; fi
    current="$(g config --get core.hooksPath || true)"
    if [[ "$current" != "$CHAIN" ]]; then
      echo "記著接上了，但 core.hooksPath 是「${current}」，不是轉呼叫那一組：驗證者不會被派。重跑 install。"; exit 1
    fi
    echo "接上了：原本的 hook 在「$(original_dir)」，單的根目錄 $(g config --get polaris.pushVerifier.issues)，啟動命令 $(g config --get polaris.pushVerifier.agentCmd || echo '（預設）')"
    ;;
  *) usage ;;
esac
