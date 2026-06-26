#!/usr/bin/env bash
# check-pr-approval-status.sh — 批次檢查 PR 的 approval 數量（含 stale 偵測）
#
# Usage: echo '<pr_json>' | ./check-pr-approval-status.sh [--threshold <N>]
# Input (stdin): fetch-user-open-prs.sh 或 rebase-pr-branch.sh 的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 approval 資訊
# Progress (stderr): 檢查進度
#
# 附加欄位：
#   - valid_approvals   — 有效的 approve 數（review.commit_id == pr.head.sha）
#   - total_approvals   — 所有 APPROVED review 數
#   - has_stale         — 是否有 stale approve
#   - reviewers         — reviewer 明細 JSON array [{user, state, is_stale}]
#   - needs_review      — 是否需要（更多）review（valid < threshold）
#
# Staleness 判定走 scripts/lib/approval-staleness.sh（DP-315 canonical commit_id
# 基準的單一 writer path）：review 綁定的 commit_id 與 PR 當前 head.sha 相等才算
# valid，不相等或任一為空 / null 一律 fail-closed 判 stale。已移除舊的時間戳基準
# （review submit time 與 PR last-push time 比較），改為純 commit_id 比對。
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username \
#     | ./check-pr-approval-status.sh --threshold 2

set -euo pipefail

# Source the canonical commit_id-based staleness atom (DP-315). approval_staleness
# <review_commit_id> <head_sha> echoes "valid" / "stale"; this is the only writer
# path for the staleness decision, shared with review-inbox.
APPROVAL_STALENESS_HELPER="$(dirname "${BASH_SOURCE[0]}")/../../../../scripts/lib/approval-staleness.sh"
if [[ ! -f "$APPROVAL_STALENESS_HELPER" ]]; then
  echo "POLARIS_TOOL_MISSING:approval-staleness.sh (expected at $APPROVAL_STALENESS_HELPER)" >&2
  exit 1
fi
# shellcheck source=../../../../scripts/lib/approval-staleness.sh
source "$APPROVAL_STALENESS_HELPER"

ORG="${ORG:-}"
if [[ -z "$ORG" ]]; then
  echo "ERROR: ORG environment variable required (e.g. export ORG=my-github-org)" >&2
  exit 1
fi
THRESHOLD=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 讀取 stdin
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "🔎 檢查 ${total} 個 PR 的 approval 狀態（threshold: ${THRESHOLD}）..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')

  count=$((count + 1))

  # Input-shape guard：repo 應該是裸 repo 名（gh api 會自己拼上 "$ORG/"）。
  # 帶 "/" 的 org-prefixed 值（例如 "owner/repo"）形狀錯誤，會讓後續
  # "repos/$ORG/$repo/..." 變成 "repos/$ORG/owner/repo/..."，命中錯誤或不存在
  # 的 endpoint。fail-closed，不在錯誤輸入上繼續消費 gh。
  if [[ "$repo" == */* ]]; then
    echo "POLARIS_APPROVAL_INPUT_SHAPE: repo '$repo' 含 '/'（org-prefixed 形狀錯誤，應為裸 repo 名）" >&2
    exit 2
  fi

  # 取得 reviews（commit_id 為 staleness 判定基準；submitted_at 僅用於挑出
  # 同一 reviewer 的最新一筆 review）。兩段式捕捉 exit code：成功才採用輸出，
  # 非零（含網路 / 404 / auth 失敗）一律 fail-closed，不靜默吞成 []。
  if ! reviews=$(gh api "repos/$ORG/$repo/pulls/$number/reviews" \
    --jq '[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at, commit_id: .commit_id}]'); then
    echo "POLARIS_APPROVAL_API_ERROR: gh api 取得 $repo #$number reviews 失敗" >&2
    exit 2
  fi

  # 取得 PR 當前 head commit SHA（沿用同一個 PR endpoint，僅改 --jq 投影，
  # 不新增 API round-trip）。同樣兩段式 fail-closed。
  if ! head_sha=$(gh api "repos/$ORG/$repo/pulls/$number" \
    --jq '.head.sha'); then
    echo "POLARIS_APPROVAL_API_ERROR: gh api 取得 $repo #$number head.sha 失敗" >&2
    exit 2
  fi

  # 計算每位 reviewer 的最新狀態
  # 先取得所有 unique reviewers，再找各自最新的 review
  reviewer_users=$(echo "$reviews" | jq -r '[.[].user] | unique | .[]')

  reviewer_tmpfile=$(mktemp)
  valid_approvals=0
  total_approvals=0
  has_stale=false

  for user in $reviewer_users; do
    # 該 reviewer 最新的 review
    latest=$(echo "$reviews" | jq "[.[] | select(.user == \"$user\")] | sort_by(.submitted_at) | last")
    state=$(echo "$latest" | jq -r '.state')
    commit_id=$(echo "$latest" | jq -r '.commit_id')

    is_stale=false

    if [ "$state" = "APPROVED" ]; then
      total_approvals=$((total_approvals + 1))
      # 走 canonical helper：commit_id == head.sha 才 valid，否則 stale（fail-closed）。
      if [ "$(approval_staleness "$commit_id" "$head_sha")" = "valid" ]; then
        valid_approvals=$((valid_approvals + 1))
      else
        is_stale=true
        has_stale=true
      fi
    fi

    jq -n \
      --arg user "$user" \
      --arg state "$state" \
      --argjson is_stale "$is_stale" \
      '{user: $user, state: $state, is_stale: $is_stale}' >> "$reviewer_tmpfile"
  done

  reviewers=$(jq -s '.' "$reviewer_tmpfile")
  rm -f "$reviewer_tmpfile"

  needs_review=false
  if [ "$valid_approvals" -lt "$THRESHOLD" ]; then
    needs_review=true
  fi

  # 保留原本的欄位，附加新欄位
  original=$(echo "$row" | base64 --decode)
  enriched=$(echo "$original" | jq \
    --argjson valid_approvals "$valid_approvals" \
    --argjson total_approvals "$total_approvals" \
    --argjson has_stale "$has_stale" \
    --argjson reviewers "$reviewers" \
    --argjson needs_review "$needs_review" \
    --argjson threshold "$THRESHOLD" \
    '. + {valid_approvals: $valid_approvals, total_approvals: $total_approvals, has_stale: $has_stale, reviewers: $reviewers, needs_review: $needs_review, threshold: $threshold}')

  echo "$enriched" >> "$tmpfile"

  status_str="${valid_approvals}/${THRESHOLD}"
  if [ "$has_stale" = true ]; then
    status_str="${status_str} (stale)"
  fi
  echo "  [$count/$total] $repo #$number — $status_str" >&2
done

# 排序：valid_approvals 升序（最需要 review 的排前面）
results=$(jq -s '.' "$tmpfile")
echo "$results" | jq 'sort_by(.valid_approvals)'

needs=$(echo "$results" | jq "[.[] | select(.needs_review == true)] | length")
done_count=$((total - needs))
echo "✅ 完成：$needs 個需要 review，$done_count 個已達標" >&2
