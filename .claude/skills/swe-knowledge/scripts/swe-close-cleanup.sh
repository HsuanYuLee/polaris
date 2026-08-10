#!/usr/bin/env bash
# swe-close-cleanup.sh — 一張單決定不做了之後，收拾它自己在版控上留下的痕跡。
#
# 為什麼要有這一支：2026-08-08 DP-440 關單並寫下理由，它的 branch 與 PR #1109 一路活到
# 2026-08-10 被人工看見才處理。**「這張單不做了」與「還有一條 branch 在等著被合」同時成立
# 了兩天**，而沒有任何東西回報這件事。狀態改了，痕跡沒改，兩邊各說各話。
#
# 收什麼、不收什麼，判準只有一條：**收得掉的只有這張單自己的東西。**
#
#   - 這張單開的那個 PR → 關掉，並且刪掉遠端那條分支。GitHub 把 commit 留在
#     `refs/pull/<n>/head` 上，所以關掉不等於丟掉——復原是 `git fetch origin refs/pull/<n>/head`。
#   - 本地那條 branch → **只有已經併進預設分支的才刪**。還沒併進去的留著並列出來：那裡面
#     有沒有人看過的工作，而刪掉它跟丟掉它之間只差一個 reflog 到期。
#   - 別人開的 PR、不是這張單的 branch → 一律不動。
#
# Usage: swe-close-cleanup.sh <landing-path>... [--identity <repo:branch>]... [--reason <一句話>]
# Output: 一件事一行 `<處置>\t<說明>`，處置是 closed|deleted|kept|unmeasurable。
# Exit:  0 全部收乾淨 / 1 有留下來的（kept） / 2 有問不到的、或參數給不齊
#
# **留下來的不得安靜。** 一個沒有被列出來的殘留，下一次就會被當成沒有殘留——這一支存在的
# 理由就是那兩天沒有人知道 DP-440 還有東西活著。

set -uo pipefail

PREFIX="[swe-close-cleanup]"
LANDINGS=()
IDENTITIES=()
REASON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITIES+=("${2:-}"); shift 2 ;;
    --repo) LANDINGS+=("${2:-}"); shift 2 ;;
    --reason) REASON="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
    *) LANDINGS+=("$1"); shift ;;
  esac
done

if [[ "${#LANDINGS[@]}" -eq 0 ]]; then
  echo "$PREFIX 一個落腳處都沒有被指名——沒有東西可以收，那不是收乾淨了。" >&2
  exit 2
fi
if [[ "${#IDENTITIES[@]}" -ne "${#LANDINGS[@]}" ]]; then
  echo "$PREFIX ${#LANDINGS[@]} 個落腳處配 ${#IDENTITIES[@]} 個身分，對不起來。" >&2
  exit 2
fi

# Description: 收一個落腳處，一件事印一行。
# Args: $1 = repo 路徑, $2 = 身分字串 `<repo 目錄名>:<分支名>`
# Returns: 0 收乾淨 / 1 有留下來的 / 2 問不到
one() {
  local path="$1" identity="$2" branch slug default worst=0
  branch="${identity#*:}"
  [[ -n "$branch" && "$branch" != "$identity" ]] || {
    printf 'unmeasurable\t身分字串 %s 裡沒有分支名，不知道要收哪一條\n' "$identity"; return 2; }
  [[ -d "$path" ]] || {
    printf 'unmeasurable\t落腳處 %s 不在這台機器上\n' "$path"; return 2; }

  # 這張單自己的 PR：拿分支名去問，問到的一定是這條分支上的。別人的 PR 掛在別的分支上。
  if command -v gh >/dev/null 2>&1; then
    slug="$(git -C "$path" remote get-url origin 2>/dev/null \
            | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
    if [[ -z "$slug" ]]; then
      printf 'unmeasurable\t%s 問不到 origin，PR 收不了\n' "$path"
      worst=2
    else
      local open_prs number
      open_prs="$(gh pr list --repo "$slug" --head "$branch" --state open \
                    --json number --jq '.[].number' 2>/dev/null)" || {
        printf 'unmeasurable\t%s 的 PR 問不到（gh 非 0）\n' "$slug"; open_prs=""; worst=2; }
      for number in ${open_prs:-}; do
        if gh pr close "$number" --repo "$slug" --delete-branch \
             --comment "不做了。${REASON:-理由記在那張單上。}"$'\n\n'"commit 留在這個 PR 的 ref 上，要復原：\`git fetch origin refs/pull/${number}/head\`" \
             >/dev/null 2>&1; then
          printf 'closed\t%s#%s 關掉了，遠端分支一起刪；復原用 refs/pull/%s/head\n' \
            "$slug" "$number" "$number"
        else
          printf 'unmeasurable\t%s#%s 關不掉（可能不是自己開的、或沒有權限）\n' "$slug" "$number"
          worst=2
        fi
      done
    fi
  else
    printf 'unmeasurable\t沒有 gh，PR 收不了\n'
    worst=2
  fi

  # 本地那條 branch：只刪已經併進預設分支的。
  if ! git -C "$path" rev-parse --verify --quiet "$branch" >/dev/null 2>&1; then
    printf 'deleted\t%s 上的 %s 本來就不在了\n' "$path" "$branch"
  else
    default="$(git -C "$path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    default="${default#origin/}"
    default="${default:-main}"
    if git -C "$path" merge-base --is-ancestor "$branch" "$default" 2>/dev/null; then
      git -C "$path" branch -q -D "$branch" 2>/dev/null \
        && printf 'deleted\t%s 上的 %s 已經在 %s 裡，刪掉了\n' "$path" "$branch" "$default" \
        || { printf 'unmeasurable\t%s 上的 %s 刪不掉\n' "$path" "$branch"; worst=2; }
    else
      # 留著並且說出來。它裡面有沒有人看過的工作，而刪掉跟丟掉之間只差一個 reflog 到期。
      printf 'kept\t%s 上的 %s 還有沒併進 %s 的 commit，留著——要丟請自己確認過再丟\n' \
        "$path" "$branch" "$default"
      [[ "$worst" -lt 1 ]] && worst=1
    fi
  fi
  return "$worst"
}

WORST=0
for i in "${!LANDINGS[@]}"; do
  one "${LANDINGS[$i]}" "${IDENTITIES[$i]}"
  rc=$?
  [[ "$rc" -gt "$WORST" ]] && WORST=$rc
done
exit "$WORST"
