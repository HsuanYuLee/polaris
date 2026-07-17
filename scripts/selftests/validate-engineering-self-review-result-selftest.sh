#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
VALIDATOR="$ROOT/scripts/validate-engineering-self-review-result.sh"
TMP="$(mktemp -d -t engineering-self-review-validator.XXXXXX)"
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

state_json="$(bash "$VALIDATOR" --print-current-state --repo "$REPO")"
head_sha="$(polaris_with_runtime_tools jq -r '.reviewed_head_sha' <<<"$state_json")"
state_sha="$(polaris_with_runtime_tools jq -r '.reviewed_state_sha256' <<<"$state_json")"

EVIDENCE_DIR="$REPO/.polaris/evidence/engineering-self-review"
mkdir -p "$EVIDENCE_DIR"
PASS_RESULT="$EVIDENCE_DIR/DP-422-T1-r1-$head_sha.json"
polaris_with_runtime_tools jq -n --arg head "$head_sha" --arg state "$state_sha" '{schema_version:1,marker_kind:"engineering_self_review",writer:"write-engineering-self-review-result.sh",owning_skill:"engineering",reviewer:"critic",work_item_id:"DP-422-T1",reviewed_head_sha:$head,reviewed_state_sha256:$state,review_round:1,remediation_count:0,terminal_review:false,verdict:"PASS",blocking:[],non_blocking:[],summary:"current state passed",next_action:"proceed",critic_result_sha256:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",reviewed_at:"2026-07-16T00:00:00Z"}' >"$PASS_RESULT"

bash "$VALIDATOR" "$PASS_RESULT" --repo "$REPO" >/dev/null

if bash "$VALIDATOR" "$PASS_RESULT" >/dev/null 2>&1; then
  fail "result validation 缺少 --repo 時必須拒絕"
fi
if bash "$VALIDATOR" "$PASS_RESULT" --rep "$REPO" >/dev/null 2>&1; then
  fail "governance option 縮寫必須拒絕"
fi
cp "$PASS_RESULT" "$TMP/copied-result.json"
if bash "$VALIDATOR" "$TMP/copied-result.json" --repo "$REPO" >/dev/null 2>&1; then
  fail "current result 不在 canonical evidence path 時必須拒絕"
fi

cp "$PASS_RESULT" "$TMP/pass-backup.json"
polaris_with_runtime_tools jq '.verdict="FAIL" | .blocking=[{"message":"缺少定位欄位"}] | .next_action="remediate"' \
  "$PASS_RESULT" >"$TMP/malformed-finding.json"
mv "$TMP/malformed-finding.json" "$PASS_RESULT"
if bash "$VALIDATOR" "$PASS_RESULT" --repo "$REPO" >/dev/null 2>&1; then
  fail "finding 缺少 file/line/rule 時必須拒絕"
fi
mv "$TMP/pass-backup.json" "$PASS_RESULT"

printf 'changed\n' >>"$REPO/example.txt"
if bash "$VALIDATOR" "$PASS_RESULT" --repo "$REPO" >"$TMP/stale.out" 2>&1; then
  fail "stale worktree state must fail"
fi
grep -q 'POLARIS_ENGINEERING_SELF_REVIEW_STALE' "$TMP/stale.out" ||
  fail "stale failure marker missing"

printf 'continue anyway\n' >"$TMP/magic-phrase.txt"
if bash "$VALIDATOR" "$TMP/magic-phrase.txt" --repo "$REPO" >/dev/null 2>&1; then
  fail "freeform magic phrase must not validate"
fi

echo "PASS: validate engineering self-review result selftest"
