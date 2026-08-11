#!/usr/bin/env bash
# check-pr-ci-status.sh — 批次補上每個 PR 的 CI 狀態。
#
# Usage: echo '<pr_json>' | ./check-pr-ci-status.sh
# Input (stdin): fetch-user-open-prs.sh 的 JSON array，每筆要有 org / repo / number
# Output (stdout): 同一批 PR，每筆附加 ci 欄位
# Progress (stderr): 逐筆進度；問不到的逐筆指名
#
# 附加欄位 ci：
#   - state    — PASS / FAIL / PENDING / NONE / UNREACHABLE
#   - failing  — 沒過的 check 名字（array）
#   - pending  — 還在跑的 check 名字（array）
#
# **問不到要說出來，不能算成 PASS。** 一個因為 API 逾時而被讀成「CI 過了」的 PR，會被
# 送去請人看，而它可能根本是紅的。所以 UNREACHABLE 自己一種狀態，跟 NONE（真的沒有
# 設任何 check）也分開——後者是「這個 repo 不跑 CI」，前者是「這一趟沒問到」。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_REST_LIB="${SCRIPT_DIR}/lib/github-rest.sh"

if [[ ! -f "$GITHUB_REST_LIB" ]]; then
  echo "POLARIS_TOOL_MISSING:github-rest.sh (expected at ${GITHUB_REST_LIB})" >&2
  exit 1
fi
# shellcheck source=lib/github-rest.sh
. "$GITHUB_REST_LIB"

prs="$(cat)"
total="$(printf '%s' "$prs" | jq 'length')"

if [[ "$total" -eq 0 ]]; then
  echo "[]"
  exit 0
fi

echo "🧪 檢查 ${total} 個 PR 的 CI 狀態..." >&2

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT
count=0

for row in $(printf '%s' "$prs" | jq -r '.[] | @base64'); do
  _jq() { printf '%s' "$row" | base64 --decode | jq -r "$1"; }

  org="$(_jq '.org')"
  repo="$(_jq '.repo')"
  number="$(_jq '.number')"
  count=$((count + 1))

  original="$(printf '%s' "$row" | base64 --decode)"

  if [[ -z "$org" || "$org" == "null" ]]; then
    ci='{"state":"UNREACHABLE","failing":[],"pending":[],"why":"這一筆沒有 org"}'
  elif ! checks="$(polaris_pr_checks_rest "${org}/${repo}" "$number" 2>/dev/null)"; then
    ci='{"state":"UNREACHABLE","failing":[],"pending":[],"why":"gh api 問不到"}'
    echo "  ⚠️ ${repo} #${number} 的 CI 問不到" >&2
  else
    # polaris_pr_checks_rest 回的是 gh pr checks 形狀的 array：每筆有 name 與 state。
    ci="$(printf '%s' "$checks" | jq -c '
      (map(select(.state == "FAILURE" or .state == "ERROR" or .state == "TIMED_OUT" or .state == "CANCELLED") | .name)) as $failing
      | (map(select(.state == "PENDING" or .state == "QUEUED" or .state == "IN_PROGRESS") | .name)) as $pending
      | {
          state: (if length == 0 then "NONE"
                  elif ($failing | length) > 0 then "FAIL"
                  elif ($pending | length) > 0 then "PENDING"
                  else "PASS" end),
          failing: $failing,
          pending: $pending
        }' 2>/dev/null)" || ci='{"state":"UNREACHABLE","failing":[],"pending":[],"why":"check 結果剖析不了"}'
  fi

  printf '%s' "$original" | jq --argjson ci "$ci" '. + {ci: $ci}' >> "$tmpfile"

  echo "  [${count}/${total}] ${repo} #${number} — CI $(printf '%s' "$ci" | jq -r '.state')" >&2
done

jq -s '.' "$tmpfile"

summary="$(jq -s '[.[].ci.state] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' "$tmpfile" -r)"
echo "✅ CI 檢查完成：${summary}" >&2
