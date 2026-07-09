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
# valid-approval 計數（含 stale 判定）走 shared canonical counter
# scripts/lib/pr-approval-count.sh（DP-413 T3），與 pr-action-classifier 共用同一
# 條計數路徑（AC6）。該 counter 內部再走 scripts/lib/approval-staleness.sh
# （DP-315 canonical commit_id 基準的單一 writer path）：review 綁定的 commit_id
# 與 PR 當前 head.sha 相等才算 valid，不相等或任一為空 / null 一律 fail-closed 判
# stale；舊的時間戳基準（review submit time 與 PR last-push time 比較）不再使用。
#
# Example:
#   ./fetch-user-open-prs.sh --author your-username \
#     | ./check-pr-approval-status.sh --threshold 2

set -euo pipefail

# Canonical valid-approval counter (DP-413 T3). The per-reviewer latest-review
# valid/stale tally (which itself reuses the DP-315 commit_id staleness atom)
# lives in scripts/lib/pr-approval-count.sh so check-pr-approvals and
# pr-action-classifier share exactly one counting path (AC6) instead of each
# keeping a private loop that can drift.
APPROVAL_COUNT_LIB="$(dirname "${BASH_SOURCE[0]}")/../../../../scripts/lib/pr-approval-count.sh"
if [[ ! -f "$APPROVAL_COUNT_LIB" ]]; then
  echo "POLARIS_TOOL_MISSING:pr-approval-count.sh (expected at $APPROVAL_COUNT_LIB)" >&2
  exit 1
fi

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

  # 走 shared canonical counter（DP-413 T3）：把 reviews + head_sha 交給
  # scripts/lib/pr-approval-count.sh 做 per-reviewer 最新 review 的 valid/stale
  # 計數，與 pr-action-classifier 共用同一條計數路徑（AC6），不再於此保留第二套。
  count_json=$(printf '%s' "$reviews" | bash "$APPROVAL_COUNT_LIB" --head-sha "$head_sha")
  valid_approvals=$(echo "$count_json" | jq -r '.valid_approvals')
  has_stale=$(echo "$count_json" | jq -r '.has_stale')

  needs_review=false
  if [ "$valid_approvals" -lt "$THRESHOLD" ]; then
    needs_review=true
  fi

  # 保留原本欄位，直接併入 shared counter 的計數物件（valid_approvals /
  # total_approvals / has_stale / reviewers），再補 needs_review 與 threshold。
  original=$(echo "$row" | base64 --decode)
  enriched=$(echo "$original" | jq --argjson c "$count_json" --argjson needs_review "$needs_review" --argjson threshold "$THRESHOLD" '. + $c + {needs_review: $needs_review, threshold: $threshold}')

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
