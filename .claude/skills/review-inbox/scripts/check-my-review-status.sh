#!/usr/bin/env bash
# check-my-review-status.sh — 批次檢查每個 PR 對指定 user 的 review 狀態
#
# Usage:
#   echo '<pr_json>' | ./check-my-review-status.sh <github_username>
#   echo '<pr_json>' | ./check-my-review-status.sh --my-user <github_username> --org <github_org>
# Input (stdin): scan-need-review-prs.sh 的 JSON 輸出
# Output (stdout): JSON array，每個 PR 附加 review_status 和 review_detail
#
# review_status 值：
#   - "needs_first_review"  — 從未 review 過
#   - "needs_re_approve"    — approve 後 head 已變動（review.commit_id != head.sha，stale）
#   - "needs_re_review"     — REQUEST_CHANGES 後作者有回覆 review comments（不論有無新 push）
#   - "valid_approve"       — approve 仍有效（review.commit_id == head.sha），不需動作
#   - "waiting_for_author"  — REQUEST_CHANGES 後作者未回覆 review comments（即使有新 push 也視為還在改）
#                            或 prior_review_no_new_push：我已 review 且 review 後 head 未變
#
# DP-315：approval-staleness（APPROVED→needs_re_approve）改走共用 helper
# scripts/lib/approval-staleness.sh，以 review.commit_id == head.sha 為唯一基準；
# 不再用 commit 時間戳（review submit time 與 PR last-push time 比較）判 approval 是否失效
# ——shared repo 中他人 push 不相干 branch 會 bump 時間戳，commit_id 比對不受影響。head.sha
# 由既有 /commits 呼叫的 .[-1].sha 投影取得（BS3），不新增 API round-trip。
#
# Example:
#   ./scan-need-review-prs.sh --exclude-author your-github-user \
#     | ORG=my-github-org ./check-my-review-status.sh your-github-user

set -euo pipefail

# 載入 DP-315 canonical commit_id 基準 staleness atom（單一 writer path，與
# check-pr-approvals 共用）。approval_staleness <review_commit_id> <head_sha>
# 輸出 "valid" / "stale"。
APPROVAL_STALENESS_HELPER="$(dirname "${BASH_SOURCE[0]}")/../../../../scripts/lib/approval-staleness.sh"
if [[ ! -f "$APPROVAL_STALENESS_HELPER" ]]; then
  echo "POLARIS_TOOL_MISSING:approval-staleness.sh (expected at $APPROVAL_STALENESS_HELPER)" >&2
  exit 1
fi
# shellcheck source=../../../../scripts/lib/approval-staleness.sh
source "$APPROVAL_STALENESS_HELPER"

usage() {
  cat >&2 <<'EOF'
Usage:
  check-my-review-status.sh <github_username>
  check-my-review-status.sh --my-user <github_username> [--org <github_org>]

ORG may be supplied by --org or ORG environment variable.
EOF
  exit 2
}

MY_USER=""
ORG="${ORG:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --my-user) MY_USER="${2:-}"; shift 2 ;;
    --org) ORG="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "Unknown option: $1" >&2; usage ;;
    *)
      if [[ -n "$MY_USER" ]]; then
        echo "Unexpected positional argument: $1" >&2
        usage
      fi
      MY_USER="$1"
      shift
      ;;
  esac
done

[[ -z "$MY_USER" ]] && usage
if [[ -z "$ORG" ]]; then
  echo "ERROR: GitHub org required via --org or ORG environment variable" >&2
  exit 1
fi

# 檢查 PR 作者是否在指定時間後回覆了 review comments 或 issue comments
# 回傳 "true" 或 "false"
check_author_replied() {
  local repo=$1 number=$2 author=$3 after_time=$4

  # 檢查 review comments（inline on diff）from author after my review
  local review_replies
  review_replies=$(gh api "repos/$ORG/$repo/pulls/$number/comments" --paginate \
    --jq "[.[] | select(.user.login == \"$author\" and .created_at > \"$after_time\")] | length" 2>/dev/null || echo "0")

  # 檢查 issue comments（general PR comments）from author after my review
  local issue_replies
  issue_replies=$(gh api "repos/$ORG/$repo/issues/$number/comments" --paginate \
    --jq "[.[] | select(.user.login == \"$author\" and .created_at > \"$after_time\")] | length" 2>/dev/null || echo "0")

  if [ "$review_replies" -gt 0 ] || [ "$issue_replies" -gt 0 ]; then
    echo "true"
  else
    echo "false"
  fi
}

# 讀取 stdin 的 PR JSON
prs=$(cat)
total=$(echo "$prs" | jq 'length')

if [ "$total" -eq 0 ]; then
  echo "[]"
  exit 0
fi

echo "🔎 檢查 ${total} 個 PR 的 review 狀態（user: ${MY_USER}）..." >&2

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(echo "$prs" | jq -r '.[] | @base64'); do
  _jq() { echo "$row" | base64 --decode | jq -r "$1"; }

  repo=$(_jq '.repo')
  number=$(_jq '.number')
  title=$(_jq '.title')
  url=$(_jq '.url')
  author=$(_jq '.author')
  created_at=$(_jq '.created_at')

  count=$((count + 1))

  # 取得該 PR 所有 reviews（投影含 commit_id，作為 DP-315 staleness 判定基準）
  reviews=$(gh api "repos/$ORG/$repo/pulls/$number/reviews" \
    --jq "[.[] | {user: .user.login, state: .state, submitted_at: .submitted_at, commit_id: .commit_id}]" 2>/dev/null || echo "[]")

  # 我所有 review，依 submit 時間排序（最舊→最新），供「最新且最高效力」判定使用
  my_reviews=$(echo "$reviews" | jq "[.[] | select(.user == \"$MY_USER\")] | sort_by(.submitted_at)")
  # 找出自己的最新 review（仍以時間為準，作為 CHANGES_REQUESTED / fallback 分類基礎）
  my_latest=$(echo "$my_reviews" | jq 'last // empty')

  if [ -z "$my_latest" ] || [ "$my_latest" = "null" ]; then
    # 從未 review
    status="needs_first_review"
    detail="首次 review"
  else
    my_state=$(echo "$my_latest" | jq -r '.state')
    my_time=$(echo "$my_latest" | jq -r '.submitted_at')
    # 我這筆 review 綁定的 commit_id（approval-staleness / push-since-review 判定基準）
    my_commit_id=$(echo "$my_latest" | jq -r '.commit_id')

    # 取得 PR 當前 head commit SHA（沿用既有 /commits 呼叫，僅改 --jq 投影為 .[-1].sha，
    # 不新增 API round-trip；BS3）
    head_sha=$(gh api "repos/$ORG/$repo/pulls/$number/commits" \
      --jq '.[-1].sha' 2>/dev/null || echo "")

    # push-since-review 判定改以 commit_id 比對：head 未變（commit_id == head.sha）即無新 push。
    # 與 approval-staleness 同一基準（commit_id != head.sha ⇒ stale / pushed），不再用 committer-date。
    pushed_since_review=false
    if [ "$(approval_staleness "$my_commit_id" "$head_sha")" = "stale" ]; then
      pushed_since_review=true
    fi

    # Gap 2（DP-312 / D2 / EC4）：以「最新且最高效力 review 是否為 valid APPROVED at head」為準。
    # 效力序 APPROVED / CHANGES_REQUESTED > COMMENTED：interleaved COMMENTED 不得把一個已
    # valid-approve（某筆 APPROVED 的 commit_id == head、之後無新 push）的 PR 翻成 needs_re_review。
    #   valid_approve_at_head ⟺ 我有一筆 APPROVED 其 commit_id == head_sha，
    #     且該 APPROVED 之後沒有更晚（submitted_at 較大）的 CHANGES_REQUESTED 覆蓋它。
    # 較晚的 COMMENTED（即使 commit_id stale）不影響此判定；較晚的 CHANGES_REQUESTED 才會覆蓋。
    valid_approve_at_head=$(echo "$my_reviews" | jq -r --arg head "$head_sha" '
      ([.[] | select(.state == "APPROVED" and .commit_id == $head)] | last) as $appr
      | if ($appr == null) then "false"
        else
          ([.[] | select(.state == "CHANGES_REQUESTED" and .submitted_at > $appr.submitted_at)] | length) as $cr_after
          | if $cr_after > 0 then "false" else "true" end
        end')

    if [ "$valid_approve_at_head" = "true" ]; then
      status="valid_approve"
      detail="✓ approve 有效（最高效力 review 為 head 上的 APPROVED；忽略 interleaved COMMENTED）"
    elif [ "$pushed_since_review" = "false" ] \
      && [[ "$my_state" =~ ^(COMMENTED|CHANGES_REQUESTED|APPROVED)$ ]]; then
      status="waiting_for_author"
      detail="⏳ prior_review_no_new_push（我已 review，head SHA 未變）"
    elif [ "$my_state" = "APPROVED" ]; then
      # DP-315：approval-staleness 唯一基準走 helper（commit_id == head.sha 才 valid）
      if [ "$(approval_staleness "$my_commit_id" "$head_sha")" = "valid" ]; then
        status="valid_approve"
        detail="✓ approve 有效"
      else
        status="needs_re_approve"
        detail="⚠️ 需 re-approve（approve commit: ${my_commit_id:0:7}, 當前 head: ${head_sha:0:7}）"
      fi
    elif [ "$my_state" = "CHANGES_REQUESTED" ]; then
      # 判斷作者是否回覆了我的 review comments（比單純看 push 更準確）
      author_replied=$(check_author_replied "$repo" "$number" "$author" "$my_time")

      if [ "$author_replied" = "true" ]; then
        # 作者有回覆 → 不論有無新 push，都該去 re-review
        if [ "$pushed_since_review" = "true" ]; then
          status="needs_re_review"
          detail="🔄 作者已修正並回覆，需 re-review"
        else
          status="needs_re_review"
          detail="🔄 作者已回覆 review comments，需 re-review"
        fi
      else
        # 作者沒回覆 → 即使有新 push 也視為還在改（還沒改到我提的問題）
        status="waiting_for_author"
        if [ "$pushed_since_review" = "true" ]; then
          detail="⏳ 作者有新 push 但尚未回覆 review comments"
        else
          detail="⏳ 等作者修正"
        fi
      fi
    else
      # COMMENTED or other — 視為需要 review
      if [ "$pushed_since_review" = "true" ]; then
        status="needs_re_review"
        detail="🔄 有新 commit，需 re-review"
      else
        status="needs_first_review"
        detail="首次 review（僅有 COMMENT）"
      fi
    fi
  fi

  # 組裝結果
  pr_result=$(jq -n \
    --arg repo "$repo" \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg author "$author" \
    --arg created_at "$created_at" \
    --arg review_status "$status" \
    --arg review_detail "$detail" \
    '{repo: $repo, number: $number, title: $title, url: $url, author: $author, created_at: $created_at, review_status: $review_status, review_detail: $review_detail}')

  echo "$pr_result" >> "$tmpfile"

  # 進度
  if [ $((count % 5)) -eq 0 ] || [ "$count" -eq "$total" ]; then
    echo "  [$count/$total] 檢查中..." >&2
  fi
done

# 輸出：排除 valid_approve 和 waiting_for_author，只留需要動作的
results=$(jq -s '.' "$tmpfile")
actionable=$(echo "$results" | jq '[.[] | select(.review_status != "valid_approve" and .review_status != "waiting_for_author")]')
skipped=$(echo "$results" | jq '[.[] | select(.review_status == "valid_approve" or .review_status == "waiting_for_author")] | length')

echo "$actionable"

actionable_count=$(echo "$actionable" | jq 'length')
echo "✅ 完成：$actionable_count 個需要 review，$skipped 個已跳過（valid approve / 等作者修正）" >&2
