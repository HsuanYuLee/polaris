#!/usr/bin/env bash
# Purpose: 每次推到一顆開著的 PR，由施工那條線以外派一個看不到施工對話的驗證者（DP-911）。
#          這一支負責接上 git hook：install／remove／status。派工與驗證本身在 push-verifier.py。
# Inputs:  install --repo <checkout> --issues <單的根目錄> [--agent-cmd '<啟動驗證者的命令>']
#          （已接上而會寫的每一格都相同就說出來並跳過，不寫任何東西；有一格不同就重接並說出是哪一格）
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
# pre-push 而且原本那一支成功時，才把同一份 stdin 交給派工。
#
# **指到它的那一行不寫在 .git/config 的 [core] 裡**，寫在一個另外的檔，由 .git/config 尾端的
# [include] 帶進來（DP-913）。husky 在 npm install 時用 git config 把 core.hooksPath 寫回 [core]，
# 而同一個鍵讀到的是檔案裡最後出現的那一個，所以 include 那一份照樣贏，linked worktree 也一樣。
# 原本的 hook 目錄因此就是 .git/config 自己那一格的值：husky 怎麼改它，轉呼叫就跟著轉到哪裡。
#
# 轉呼叫只為原本那個目錄裡已經有的 hook 名字與 pre-push 建：其餘名字的 hook 光是存在就會改變 git
# 的行為（例如 push-to-checkout）。原本那個目錄之後多了新的 hook，重跑一次 install：轉呼叫的名單也算
# 一格，少了一支就不會跳過。
#
# 擋不到的，明講：有人手動把那一行 [include] 拿掉，或在它後面再設一次 core.hooksPath，轉呼叫就不在了，
# status 會說出來，重跑 install 會在檔尾重寫一段 [include]（DP-997）。
# `git push --no-verify` 跳過所有 hook，驗證者也不會被派。
set -euo pipefail

usage() { sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

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
INC="$common/polaris-push-verifier/hooksPath.config"
own() { git config --file "$common/config" "$@"; }

installed() { [[ "$(g config --get polaris.pushVerifier.installed || true)" == true ]]; }

# 原本那個 hook 目錄的絕對位置：.git/config 自己那一格，不算 include 帶進來的那一份。
# 相對路徑相對於工作樹的根，跟 git 自己解它的方式一樣。
original_dir() {
  local orig; orig="$(own --get core.hooksPath || true)"
  if [[ -z "$orig" ]]; then printf '%s\n' "$common/hooks"
  elif [[ "$orig" == /* ]]; then printf '%s\n' "$orig"
  else printf '%s\n' "$REPO/$orig"; fi
}

# 轉呼叫要建哪幾支：pre-push，加上原本那個目錄裡每一支可執行的 hook
hook_names() {
  local orig f n; orig="$(original_dir)"; echo pre-push
  [[ -d "$orig" ]] || return 0
  while IFS= read -r f; do
    n="$(basename "$f")"; [[ "$n" == *.sample || "$n" == pre-push ]] && continue
    [[ -x "$f" && -f "$f" ]] && echo "$n"
  # 結尾的 /：原本目錄本身是指向目錄的 symlink 時，find 才會走進去。symlink 的 hook 也算，-f 跟著它判（DP-997）
  done < <(find "$orig/" -maxdepth 1 \( -type f -o -type l \))
  return 0
}

stub_body() {
  cat <<'STUB'
#!/usr/bin/env bash
# [polaris-push-verifier] 先照樣跑原本那一支 hook，再（只在 pre-push、而且它成功時）派驗證者。
name="$(basename "$0")"
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
common="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
orig="$(git config --file "$common/config" --get core.hooksPath || true)"
if [[ -z "$orig" ]]; then dir="$common/hooks"
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
}

write_stub() { stub_body > "$CHAIN/$1"; chmod +x "$CHAIN/$1"; }

# 轉呼叫那一組跟現在該有的樣子差在哪：多的、少的、內容舊的、不能執行的。一樣就不印。
stub_drift() {
  local want have n out="" body; body="$(stub_body)"
  want="$(hook_names | sort)"
  have="$(find "$CHAIN" -maxdepth 1 -type f -exec grep -lF "$MARK" {} + 2>/dev/null | xargs -n1 basename 2>/dev/null | sort || true)"
  n="$(comm -13 <(echo "$have") <(echo "$want") | grep . | tr '\n' ' ' || true)"; [[ -z "$n" ]] || out+="；轉呼叫少了：${n% }"
  n="$(comm -23 <(echo "$have") <(echo "$want") | grep . | tr '\n' ' ' || true)"; [[ -z "$n" ]] || out+="；轉呼叫多了：${n% }"
  while IFS= read -r n; do
    [[ -n "$n" && -f "$CHAIN/$n" ]] || continue
    [[ "$(cat "$CHAIN/$n")" == "$body" && -x "$CHAIN/$n" ]] || out+="；轉呼叫 ${n} 的內容或執行位元不是這一版的"
  done < <(comm -12 <(echo "$have") <(echo "$want"))
  printf '%s' "$out"
}

case "$cmd" in
  install)
    [[ -n "$ISSUES" && -d "$ISSUES" ]] || { echo "install 要 --issues <單的根目錄>（驗證者把判定寫進那裡的單）" >&2; exit 2; }
    # 已接上而設定相同就跳過，一個字都不寫：這一支會對整批 checkout 重跑（DP-996）
    issues_abs="$(cd "$ISSUES" && pwd -P)"
    if installed && [[ "$(g config --get core.hooksPath || true)" == "$CHAIN" ]]; then
      changed=""
      [[ "$(own --get core.hooksPath || true)" != "$CHAIN" ]] || changed+="；接法是 DP-913 之前寫在 [core] 的那一種，要遷進 include"
      changed+="$(stub_drift)"
      was="$(g config --get polaris.pushVerifier.issues || true)"
      [[ "$was" == "$issues_abs" ]] || changed+="；issues：${was:-（沒有）} → ${issues_abs}"
      was="$(g config --get polaris.pushVerifier.script || true)"
      [[ "$was" == "$HERE/push-verifier.py" ]] || changed+="；script：${was:-（沒有）} → ${HERE}/push-verifier.py"
      if [[ -n "$AGENT" ]]; then
        was="$(g config --get polaris.pushVerifier.agentCmd || true)"
        [[ "$was" == "$AGENT" ]] || changed+="；agentCmd：${was:-（預設）} → ${AGENT}"
      fi
      if [[ -z "$changed" ]]; then
        echo "已接上，設定相同，跳過：core.hooksPath → ${CHAIN}"
        exit 0
      fi
      echo "已接上，設定不同，重接：${changed#；}"
    fi
    # DP-913 之前的接法把轉呼叫直接寫進 [core]，原本的值記在 chainedHooksPath。先還原成原本的樣子。
    if [[ "$(own --get core.hooksPath || true)" == "$CHAIN" ]]; then
      prev="$(g config --get polaris.pushVerifier.chainedHooksPath || true)"
      if [[ -n "$prev" ]]; then own core.hooksPath "$prev"; else own --unset core.hooksPath || true; fi
    fi
    g config --unset polaris.pushVerifier.chainedHooksPath || true
    g config polaris.pushVerifier.installed true
    g config polaris.pushVerifier.issues "$issues_abs"
    g config polaris.pushVerifier.script "$HERE/push-verifier.py"
    [[ -n "$AGENT" ]] && g config polaris.pushVerifier.agentCmd "$AGENT"
    mkdir -p "$CHAIN"
    find "$CHAIN" -type f -exec grep -lF "$MARK" {} + 2>/dev/null | while read -r f; do rm -f "$f"; done
    names=()
    while IFS= read -r n; do names+=("$n"); done < <(hook_names)
    for n in "${names[@]}"; do write_stub "$n"; done
    git config --file "$INC" core.hooksPath "$CHAIN"
    own --get-all include.path 2>/dev/null | grep -qxF "$INC" || own --add include.path "$INC"
    # 讀到的不是 include 那一份，多半是那一條排在某個 core.hooksPath 前面。拿掉它，在檔尾自己寫一段
    # 新的——同一段還有別的 path 時，git config --add 會把它加回原本那一段（DP-997）。比 .git/config
    # 優先的設定層（例如 .git/config.worktree）也設了 core.hooksPath 的話，順序救不了，下面那一句會說出來。
    if [[ "$(g config --get core.hooksPath || true)" != "$CHAIN" ]]; then
      own --fixed-value --unset-all include.path "$INC" 2>/dev/null || true
      esc="${INC//\\/\\\\}"; esc="${esc//\"/\\\"}"
      # 寫不進檔尾（例如 .git/config 唯讀而 .git 可寫）就退回 git config：它用 rename 寫得過，而那一段
      # 被整段拿掉時它會把 include 開在檔尾。補換行也在同一次寫入裡，接不接得上交給下面那一句讀回來判。
      { [[ -z "$(tail -c1 "$common/config")" ]] || echo; printf '[include]\n\tpath = "%s"\n' "$esc"; } 2>/dev/null >> "$common/config" || {
        tail_failed=1; own --add include.path "$INC" || true; }
    fi
    if [[ "$(g config --get core.hooksPath || true)" != "$CHAIN" ]]; then
      # 讀到的那一份來自 .git/config 自己、或哪一層都沒有，才是「寫不進檔尾」害的；來自別的設定層就照另一句說
      origin="$(g config --show-origin --get core.hooksPath || true)"
      if [[ -n "${tail_failed:-}" && ( -z "$origin" || "$origin" == "file:.git/config"$'\t'* ) ]]; then
        echo "接不上：寫不進 ${common}/config 的檔尾，改用 git config 放回的那一條 include 仍讀不到（$(g config --show-origin --get core.hooksPath)）。讓那個檔可寫再重跑。" >&2
      else
        echo "接不上：.git/config 讀到的 core.hooksPath 不是 include 那一份（$(g config --show-origin --get core.hooksPath)）。我們那一條已經在 .git/config 的最後，讀到的那一份來自更優先的設定層：拿掉那裡的 core.hooksPath 再重跑。" >&2
      fi
      exit 1
    fi
    echo "接上了：core.hooksPath → ${CHAIN}（經 .git/config 尾端的 include；原本是「$(own --get core.hooksPath || true)」，轉呼叫 ${#names[@]} 支：${names[*]}）"
    ;;
  remove)
    installed || { echo "這個 checkout 沒有接上，沒有東西要拆。"; exit 0; }
    if [[ "$(own --get core.hooksPath || true)" == "$CHAIN" ]]; then
      prev="$(g config --get polaris.pushVerifier.chainedHooksPath || true)"
      if [[ -n "$prev" ]]; then own core.hooksPath "$prev"; else own --unset core.hooksPath || true; fi
    fi
    own --fixed-value --unset-all include.path "$INC" 2>/dev/null || true
    g config --remove-section polaris.pushVerifier 2>/dev/null || true
    rm -rf "$common/polaris-push-verifier"
    echo "拆掉了：core.hooksPath 回到「$(g config --get core.hooksPath || true)」"
    ;;
  status)
    if ! installed; then echo "沒有接上：推到開著的 PR 不會派驗證者。"; exit 1; fi
    current="$(g config --get core.hooksPath || true)"
    if [[ "$current" != "$CHAIN" ]]; then
      echo "記著接上了，但 core.hooksPath 是「${current}」，不是轉呼叫那一組：驗證者不會被派。重跑 install。"; exit 1
    fi
    # git 對沒有執行位元的 hook 只印一行 hint 就跳過（10/29 在 b2c-web 量到過一次）。
    if [[ ! -x "$CHAIN/pre-push" ]]; then
      echo "記著接上了，但 ${CHAIN}/pre-push 不能執行：git 會跳過它，驗證者不會被派。重跑 install。"; exit 1
    fi
    echo "接上了：原本的 hook 在「$(original_dir)」，單的根目錄 $(g config --get polaris.pushVerifier.issues)，啟動命令 $(g config --get polaris.pushVerifier.agentCmd || echo '（預設）')"
    ;;
  *) usage ;;
esac
