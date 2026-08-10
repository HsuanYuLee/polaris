#!/usr/bin/env bash
# check-swe-delivered.sh — 軟體工程的工作，「它出去了沒有」印在 stdout。
#
# 判準是 swe-knowledge 的〈之後呢〉那一節：**那個 PR 被 approve 或被 merge，這條流程就走完
# 了。** 之後那個 repo 自己怎麼釋出不由這裡管——每個 repo 有自己的節奏，而我們不是它的
# owner。這支腳本因此只問一件事，問完就停。
#
# 為什麼要拿身分字串而不是只拿路徑：一張單當初開在哪條分支上，只有它自己記得。走到這一步
# 時那個 repo 早就切走了、分支可能已經被刪掉——拿「現在站在哪」去問，問到的是別人的 PR。
# 身分字串是這個 pack 自己印出去的（`workspace-identity.sh`，形狀 `<repo 目錄名>:<分支名>`），
# 核心只是原樣存了下來再交還，所以這裡讀得回自己寫的東西。
#
# Usage: check-swe-delivered.sh <landing-path>... [--identity <repo:branch>]...
#        位置參數是這張單宣告的落腳處，--identity 是開輪次那一刻記下的身分，一個地方一組。
# Output: 一個落腳處一行 `<狀態>\t<哪一天出去的>\t<說明>`。狀態是 delivered|not-yet|
#         unmeasurable；日期是 `YYYY-MM-DD`，說不出來就 `-`。
#
# 為什麼日期由這裡印：核心要拿它當釋出日，而「它哪一天出去的」只有問得到 PR 的人知道。
# 核心自己填「今天」的話，一張上週就 merge、今天才被問到的單會被記成今天釋出——而
# `released/{日期}/` 是給人翻的，那個日期說謊比沒有更糟。
# Exit:  0 每一個都 delivered / 1 有還沒出去的 / 2 有問不到的、或參數給不齊
#
# 三種狀態都要印。**問不到不是還沒出去，也不是出去了**：一個因為 API 逾時而被讀成「還沒」
# 的單會安靜地停在待辦裡，被讀成「出去了」的那一種更糟。

set -uo pipefail

PREFIX="[swe-delivered]"
LANDINGS=()
IDENTITIES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITIES+=("${2:-}"); shift 2 ;;
    --repo) LANDINGS+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
    *) LANDINGS+=("$1"); shift ;;
  esac
done

if [[ "${#LANDINGS[@]}" -eq 0 ]]; then
  echo "$PREFIX 一個落腳處都沒有被指名——沒有東西可以問，那不是走完了。" >&2
  exit 2
fi
if [[ "${#IDENTITIES[@]}" -ne "${#LANDINGS[@]}" ]]; then
  # 對不齊就停：猜哪個身分配哪個落腳處，會在多 repo 的單上安靜地問錯 repo 的 PR。
  echo "$PREFIX ${#LANDINGS[@]} 個落腳處配 ${#IDENTITIES[@]} 個身分，對不起來。" >&2
  echo "$PREFIX 這張單開輪次時可能還沒記下身分（DP-482 之前的單），那要先補記再問。" >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || {
  echo "$PREFIX 量不到：沒有 gh，PR 的狀態問不到。" >&2
  printf 'unmeasurable\t-\t沒有 gh\n'
  exit 2
}

# Description: 一個落腳處的狀態，印一行。
# Args: $1 = repo 路徑, $2 = 身分字串 `<repo 目錄名>:<分支名>`
# Returns: 0 delivered / 1 not-yet / 2 unmeasurable
one() {
  local path="$1" identity="$2" branch slug
  branch="${identity#*:}"
  if [[ -z "$branch" || "$branch" == "$identity" ]]; then
    printf 'unmeasurable\t-\t身分字串 %s 裡沒有分支名，問不出要查哪一個 PR\n' "$identity"
    return 2
  fi
  if [[ ! -d "$path" ]]; then
    printf 'unmeasurable\t-\t落腳處 %s 不在這台機器上\n' "$path"
    return 2
  fi
  slug="$(git -C "$path" remote get-url origin 2>/dev/null \
          | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')"
  if [[ -z "$slug" ]]; then
    printf 'unmeasurable\t-\t%s 問不到 origin，不知道要跟哪個 repo 要 PR\n' "$path"
    return 2
  fi

  # 取這條分支上最新的那個 PR。同一條分支開過兩次 PR 是常態（第一次關掉重開），而舊的
  # 那個的狀態說不出這一次的結果。
  local json
  json="$(gh pr list --repo "$slug" --head "$branch" --state all \
            --json number,state,reviewDecision,mergedAt,latestReviews \
            --limit 1 2>/dev/null)" || {
    printf 'unmeasurable\t-\t%s 的 PR 問不到（gh 非 0）\n' "$slug"
    return 2
  }
  [[ -n "$json" && "$json" != "[]" ]] || {
    printf 'not-yet\t-\t%s 上的 %s 還沒有 PR\n' "$slug" "$branch"
    return 1
  }

  local number merged decision
  number="$(printf '%s' "$json" | sed -n 's/.*"number":\([0-9]*\).*/\1/p')"
  merged="$(printf '%s' "$json" | sed -n 's/.*"mergedAt":"\([^"]*\)".*/\1/p')"
  decision="$(printf '%s' "$json" | sed -n 's/.*"reviewDecision":"\([^"]*\)".*/\1/p')"

  if [[ -n "$merged" ]]; then
    printf 'delivered\t%s\t%s#%s 已 merge\n' "${merged%%T*}" "$slug" "$number"
    return 0
  fi
  if [[ "$decision" == "APPROVED" ]]; then
    # approve 就算走完：merge 常常是別人按的、按在別人的排程上。日期取最後一則 review 的
    # 時間，那才是「它被接受」的那一刻；取今天的話，這張單的釋出日會隨著誰哪天問而改變。
    local approved_at
    approved_at="$(printf '%s' "$json" | sed -n 's/.*"submittedAt":"\([^"]*\)".*/\1/p' | tail -1)"
    printf 'delivered\t%s\t%s#%s 已 approve，還沒 merge——按下去的時機不歸這裡管\n' \
      "${approved_at%%T*}" "$slug" "$number"
    [[ -n "$approved_at" ]] || printf 'unmeasurable\t-\t%s#%s approve 了但問不到是哪一天\n' \
      "$slug" "$number"
    return 0
  fi
  printf 'not-yet\t-\t%s#%s 還沒 approve 也還沒 merge（review=%s）\n' \
    "$slug" "$number" "${decision:-none}"
  return 1
}

WORST=0
for i in "${!LANDINGS[@]}"; do
  one "${LANDINGS[$i]}" "${IDENTITIES[$i]}"
  rc=$?
  # 問不到蓋過還沒出去：一份混著「還沒」與「問不到」的結果，整體只能說問不到。
  [[ "$rc" -gt "$WORST" ]] && WORST=$rc
done
exit "$WORST"
