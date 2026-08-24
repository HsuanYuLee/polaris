#!/usr/bin/env bash
# 把版控裡的 hook 接上 git／拆掉／看狀態。
#
# **它不生成 hook 的內容。** 內容住在 `../githooks/`，是版控裡的兩個檔案；這一支只做一件
# 事——把 `core.hooksPath` 指過去。以前它用 heredoc 把內容寫進 `.git/hooks/`，代價是閘的
# 改動不會出現在任何 diff 裡，而每台機器手上是哪一版沒有人說得出來。
#
# 切換到 `core.hooksPath` 的代價要說出來：**它會讓 `.git/hooks/` 底下所有東西失效**，包含
# 別人手寫的。所以接上之前會先掃那個目錄，有不是這套裝的就指名並停下來——用一個靜默的停用
# 換一個宣稱的保障，比不接還糟。
#
# 這一層不是安全網，是一層會被自願跑的檢查。它擋不住什麼、誰才是真的在擋，寫在
# `../SKILL.md`〈本機這一層擋得住什麼、擋不住什麼〉。
#
# Usage:
#   bash scripts/install-git-hooks.sh            # 接上
#   bash scripts/install-git-hooks.sh --remove   # 拆掉
#   bash scripts/install-git-hooks.sh --status   # 看狀態
#   --repo <path> 指名工作區（預設從 cwd 問 git）
# Exit: 0 成立 / 1 拒絕（有別人手寫的 hook、或版控裡那份不能執行）/ 2 量不到

set -euo pipefail

PREFIX="[polaris git-hooks]"
MODE="install"
REPO_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove) MODE="remove"; shift ;;
    --status) MODE="status"; shift ;;
    --repo) REPO_ARG="${2:-}"; shift 2 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; sed -n '20,25p' "$0" >&2; exit 2 ;;
  esac
done

# 版控裡那個目錄的位置，相對於 repo 根。`core.hooksPath` 用相對路徑存：它相對的是工作樹
# 的根，所以每一個 linked worktree 用的是它自己那一份，而不是主 checkout 的。
HOOKS_REL="scripts/githooks"
HOOK_NAMES=(pre-commit pre-push)
MARKER="# [polaris-git-hooks]"

REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "${REPO_ARG:-.}" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$PREFIX 量不到：${REPO_ARG:-這裡}不在 git repo 裡。" >&2; exit 2; }
HOOKS_ABS="$REPO_ROOT/$HOOKS_REL"
# linked worktree 的 `.git` 是一個檔案，「工作區根 ＋ /.git/hooks」那條路徑不存在。
# hook 目錄本來就只有一份，問 git 要。
LEGACY_DIR="$(env -u GIT_DIR -u GIT_WORK_TREE \
  git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hooks" || {
  echo "$PREFIX 量不到：問不出 git 的 hook 目錄。" >&2; exit 2; }

# Description: 列出 `.git/hooks/` 底下不是這套裝的檔案（git 自己的 `.sample` 不算）。
# Outputs: 一行一個絕對路徑；沒有就什麼都不印。
foreign_hooks() {
  local f
  [[ -d "$LEGACY_DIR" ]] || return 0
  for f in "$LEGACY_DIR"/*; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.sample ]] && continue
    grep -qF "$MARKER" "$f" && continue
    echo "$f"
  done
}

# Description: 現在 git 在用的 hook 目錄，換算成相對於 repo 根的形式。
# Outputs: 相對路徑；沒設就不印。
# Exit:   0 讀到了（含沒設）/ 2 讀不出來
configured_rel() {
  local raw rc=0 phys
  raw="$(git -C "$REPO_ROOT" config --get core.hooksPath 2>/dev/null)" || rc=$?
  # git config 對「沒設」回 1，其餘非 0 才是真的讀不出來。把兩者混成一個，會讓一個壞掉的
  # config 被讀成「沒接上」，然後修法印出來的是接上——而它接不上去。
  [[ "$rc" -eq 0 || "$rc" -eq 1 ]] || return 2
  [[ -n "$raw" ]] || return 0
  case "$raw" in
    "$HOOKS_REL") echo "$HOOKS_REL"; return 0 ;;
    "$HOOKS_ABS") echo "$HOOKS_REL"; return 0 ;;
  esac
  # 指到別的地方，或同一個地方的另一種寫法（symlink、`./` 前綴）。用實體路徑比一次再說。
  phys="$( (builtin cd "$REPO_ROOT/$raw" 2>/dev/null && pwd -P) || true)"
  if [[ -n "$phys" && "$phys" == "$( (builtin cd "$HOOKS_ABS" 2>/dev/null && pwd -P) || echo /dev/null)" ]]; then
    echo "$HOOKS_REL"
  else
    echo "$raw"
  fi
}

case "$MODE" in
  status)
    rc=0; current="$(configured_rel)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      echo "hooksPath  量不到：core.hooksPath 讀不出來（git config 回 ${rc}）"
      exit 2
    elif [[ -z "$current" ]]; then
      echo "hooksPath  沒接上：core.hooksPath 沒設，git 在用 ${LEGACY_DIR}——那裡沒有這套閘"
    elif [[ "$current" == "$HOOKS_REL" ]]; then
      echo "hooksPath  已接上：${HOOKS_REL}"
    else
      echo "hooksPath  指向別的地方：${current}（不是 ${HOOKS_REL}）"
    fi
    for h in "${HOOK_NAMES[@]}"; do
      if [[ ! -f "$HOOKS_ABS/$h" ]]; then echo "${h}  版控裡沒有這個檔"
      elif [[ ! -x "$HOOKS_ABS/$h" ]]; then echo "${h}  在版控裡，但沒有執行位元——git 會安靜地不跑它"
      else echo "${h}  在版控裡、可執行"; fi
    done
    foreign="$(foreign_hooks)"
    if [[ -n "$foreign" ]]; then
      echo ".git/hooks 底下有不是這套裝的檔案（接上 core.hooksPath 會讓它們失效）："
      printf '  %s\n' $foreign
    else
      echo ".git/hooks 只剩 git 自己的 .sample，沒有別人手寫的"
    fi
    exit 0
    ;;
  remove)
    git -C "$REPO_ROOT" config --unset core.hooksPath 2>/dev/null || true
    for h in "${HOOK_NAMES[@]}"; do
      f="$LEGACY_DIR/$h"
      if [[ -f "$f" ]] && grep -qF "$MARKER" "$f"; then rm -f "$f"; echo "removed: $h（舊層留在 .git/hooks 的那一份）"; fi
    done
    echo "$PREFIX 拆掉了：core.hooksPath 已取消，git 回去用 ${LEGACY_DIR}。"
    exit 0
    ;;
esac

# ── 接上 ──────────────────────────────────────────────────────────────────────

MISSING=()
NOT_EXEC=()
for h in "${HOOK_NAMES[@]}"; do
  if [[ ! -f "$HOOKS_ABS/$h" ]]; then MISSING+=("$HOOKS_REL/$h")
  elif [[ ! -x "$HOOKS_ABS/$h" ]]; then NOT_EXEC+=("$HOOKS_REL/$h"); fi
done

if [[ "${#MISSING[@]}" -gt 0 ]]; then
  echo "$PREFIX 量不到：版控裡少了這幾個 hook——" >&2
  printf '  %s\n' "${MISSING[@]}" >&2
  echo "$PREFIX 這個 checkout 的分支上沒有它們。切到有的分支，或先把它們帶進來。" >&2
  exit 2
fi

# 沒有執行位元的 hook，git 是**安靜地**不跑它——沒有警告，push 一樣過。實測 2026-08-10：
# `chmod -x` 之後 commit 照樣成立，輸出裡一個字都沒有提到 hook。
if [[ "${#NOT_EXEC[@]}" -gt 0 ]]; then
  echo "$PREFIX 拒絕接上：這幾個 hook 沒有執行位元，接上去 git 會安靜地不跑它們——" >&2
  printf '  %s\n' "${NOT_EXEC[@]}" >&2
  echo "$PREFIX 修法：chmod +x 上面那幾個檔，並且讓版控也記得：" >&2
  printf '  git update-index --chmod=+x %s\n' "${NOT_EXEC[@]}" >&2
  exit 1
fi

FOREIGN="$(foreign_hooks)"
if [[ -n "$FOREIGN" ]]; then
  echo "$PREFIX 拒絕接上：${LEGACY_DIR} 底下有不是這套裝的 hook——" >&2
  printf '  %s\n' $FOREIGN >&2
  echo "$PREFIX 接上 core.hooksPath 會讓它們全部失效，而且不會有任何東西說。" >&2
  echo "$PREFIX 修法二選一：把它們的內容搬進 ${HOOKS_REL}/（那裡的東西進版控、跟著 repo 走），" >&2
  echo "$PREFIX 或者確定不要了就自己刪掉，然後重跑一次。" >&2
  exit 1
fi

# 這一套自己以前寫進 .git/hooks/ 的那兩份留著沒有意義（接上之後它們不會被執行），而且會讓
# 下一個人以為閘有兩份。只刪帶標記的，別人手寫的上面已經擋下來了。
for h in "${HOOK_NAMES[@]}"; do
  f="$LEGACY_DIR/$h"
  if [[ -f "$f" ]] && grep -qF "$MARKER" "$f"; then
    rm -f "$f"; echo "$PREFIX 清掉舊層留在 .git/hooks 的 ${h}（接上之後它不會被執行）"
  fi
done

git -C "$REPO_ROOT" config core.hooksPath "$HOOKS_REL"
echo "$PREFIX 接上了：core.hooksPath = ${HOOKS_REL}（pre-commit, pre-push）"
