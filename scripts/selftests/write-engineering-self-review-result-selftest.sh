#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
WRITER="$ROOT/scripts/write-engineering-self-review-result.sh"
VALIDATOR="$ROOT/scripts/validate-engineering-self-review-result.sh"
TMP="$(mktemp -d -t engineering-self-review-writer.XXXXXX)"
REPO="$TMP/repo"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

git init -q "$REPO"
git -C "$REPO" config user.email selftest@example.com
git -C "$REPO" config user.name selftest
printf 'base\n' >"$REPO/example.txt"
printf '.polaris/\n' >"$REPO/.gitignore"
git -C "$REPO" add example.txt .gitignore
git -C "$REPO" commit -qm init

critic_result() {
  local passed="$1" output="$2" state head_sha state_sha
  state="$(bash "$VALIDATOR" --print-current-state --repo "$REPO")"
  head_sha="$(polaris_with_runtime_tools jq -r '.reviewed_head_sha' <<<"$state")"
  state_sha="$(polaris_with_runtime_tools jq -r '.reviewed_state_sha256' <<<"$state")"
  polaris_with_runtime_tools jq -n --argjson passed "$passed" --arg head "$head_sha" --arg state "$state_sha" '{passed:$passed,reviewed_head_sha:$head,reviewed_state_sha256:$state,blocking:(if $passed then [] else [{file:"example.txt",line:1,rule:"fixture rule",message:"fix"}] end),non_blocking:[],summary:(if $passed then "pass" else "fail" end)}' >"$output"
}

prior=""
round1_result=""
round3_result=""
round=1
while [[ "$round" -le 4 ]]; do
  critic="$TMP/critic-r$round.json"
  critic_result false "$critic"
  if [[ -n "$prior" ]]; then
    writer_output="$(bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
      --critic-result "$critic" --review-round "$round" --prior-result "$prior" \
    )"
    out="${writer_output#WROTE: }"
    bash "$VALIDATOR" "$out" --repo "$REPO" --prior "$prior" >/dev/null
  else
    writer_output="$(bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
      --critic-result "$critic" --review-round "$round")"
    out="${writer_output#WROTE: }"
    bash "$VALIDATOR" "$out" --repo "$REPO" >/dev/null
  fi
  if [[ "$round" -lt 4 ]]; then
    [[ "$(polaris_with_runtime_tools jq -r '.next_action' "$out")" == "remediate" ]] ||
      fail "round $round must remediate"
    printf 'round-%s\n' "$round" >>"$REPO/example.txt"
  else
    [[ "$(polaris_with_runtime_tools jq -r '.next_action' "$out")" == "human_review" ]] ||
      fail "round 4 FAIL must require human review"
    [[ "$(polaris_with_runtime_tools jq -r '.terminal_review' "$out")" == "true" ]] ||
      fail "round 4 must be terminal review"
  fi
  if [[ "$round" -eq 1 ]]; then
    round1_result="$out"
  fi
  if [[ "$round" -eq 3 ]]; then
    round3_result="$out"
  fi
  prior="$out"
  round=$((round + 1))
done

cp "$round1_result" "$TMP/round1-backup.json"
printf '\n' >>"$round1_result"
if bash "$VALIDATOR" "$prior" --repo "$REPO" --prior "$round3_result" \
  >/dev/null 2>&1; then
  fail "完整 round chain 任一歷史 artifact 遭竄改時必須拒絕"
fi
mv "$TMP/round1-backup.json" "$round1_result"

critic_result false "$TMP/malformed-critic.json"
polaris_with_runtime_tools jq '.blocking=[{"message":"缺少定位欄位"}]' \
  "$TMP/malformed-critic.json" >"$TMP/malformed-critic-next.json"
if bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
  --critic-result "$TMP/malformed-critic-next.json" --review-round 1 \
  >/dev/null 2>&1; then
  fail "writer 必須拒絕缺少 file/line/rule 的 finding"
fi

cp "$round3_result" "$TMP/forged-prior.json"
printf 'forged-prior-state\n' >>"$REPO/example.txt"
critic_result false "$TMP/critic-after-forged-prior.json"
if bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
  --critic-result "$TMP/critic-after-forged-prior.json" --review-round 4 \
  --prior-result "$TMP/forged-prior.json" >/dev/null 2>&1; then
  fail "arbitrary path 的偽造 prior 必須拒絕"
fi

critic_result false "$TMP/critic-r5.json"
if bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
  --critic-result "$TMP/critic-r5.json" --review-round 5 --prior-result "$prior" \
  >/dev/null 2>&1; then
  fail "round 5 must be rejected"
fi

critic_result false "$TMP/critic-with-out.json"
if bash "$WRITER" --repo "$REPO" --work-item-id DP-422-T1 \
  --critic-result "$TMP/critic-with-out.json" --review-round 1 \
  --out "$TMP/noncanonical-result.json" >/dev/null 2>&1; then
  fail "公開 --out 不可寫入非 canonical result"
fi

critic_result false "$TMP/critic-path-traversal.json"
if bash "$WRITER" --repo "$REPO" \
  --work-item-id '../../../escape-dir/DP-422-T1' \
  --critic-result "$TMP/critic-path-traversal.json" --review-round 1 \
  >/dev/null 2>&1; then
  fail "path traversal work_item_id 必須拒絕"
fi
if [[ -e "$REPO/escape-dir" ]]; then
  fail "invalid work_item_id 不可在 canonical evidence dir 外建立路徑"
fi

echo "PASS: write engineering self-review result selftest"
