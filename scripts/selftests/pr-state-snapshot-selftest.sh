#!/usr/bin/env bash
# Purpose: selftest for pr-state-snapshot.sh — resolver / freshness / mergeability /
#          review-thread stats plus issue-level conversation-comment
#          unaddressed_human_comments signal, automation filtering, and fail-closed.
# Inputs:  none (builds git + JSON fixtures under a temp dir).
# Outputs: stdout PASS/FAIL summary; exit 1 on any failed assertion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-pr-work-source.sh"
SNAPSHOT="${SCRIPT_DIR}/pr-state-snapshot.sh"
TMPROOT="$(mktemp -d -t polaris-pr-state-snapshot-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s want=%s got=%s\n' "$label" "$want" "$got" >&2
  fi
}

json_field() {
  local file="$1" field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
field = sys.argv[2]
value = data
for part in field.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

write_task() {
  local path="$1" base="$2" chain="$3" branch="$4"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
---
status: IN_PROGRESS
depends_on: []
---

# T1: fixture (1 pt)

> Source: DP-130 | Task: DP-130-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-130 |
| Task ID | DP-130-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | $base |
| Branch chain | $chain |
| Task branch | $branch |
| Depends on | N/A |
EOF
}

write_pr_json() {
  local path="$1" state="$2" head_branch="$3" head_sha="$4" base_branch="$5" merge_state="$6" review_decision="${7:-}" number="${8:-}"
  local number_field=""
  if [[ -n "$number" ]]; then
    number_field="\"number\":$number,"
  fi
  cat >"$path" <<EOF
{${number_field}"state":"$state","headRefName":"$head_branch","headRefOid":"$head_sha","baseRefName":"$base_branch","mergeStateStatus":"$merge_state","reviewDecision":"$review_decision"}
EOF
}

write_threads_json() {
  local path="$1" resolved="$2" outdated="$3"
  cat >"$path" <<EOF
{"pullRequest":{"reviewThreads":{"nodes":[{"id":"PRRT_1","isResolved":$resolved,"isOutdated":$outdated,"comments":{"nodes":[{"url":"https://example.invalid/thread"}]}}]}}}
EOF
}

write_checks_json() {
  local path="$1" state="$2"
  cat >"$path" <<EOF
[{"name":"ci","state":"$state"}]
EOF
}

# Reads a field from the Nth unaddressed_human_comments entry of a snapshot JSON.
comment_field() {
  local file="$1" idx="$2" key="$3"
  python3 - "$file" "$idx" "$key" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
items = data.get("unaddressed_human_comments") or []
idx = int(sys.argv[2])
key = sys.argv[3]
if 0 <= idx < len(items):
    value = items[idx].get(key)
    print("" if value is None else value)
else:
    print("")
PY
}

REPO="$TMPROOT/repo"
mkdir -p "$REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T1"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "selftest@example.com"
git -C "$REPO" config user.name "selftest"
printf 'root\n' >"$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -q -m init

git -C "$REPO" checkout -q -b task/upstream
printf 'upstream-1\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am upstream-1
UPSTREAM_SHA_1="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q -b task/downstream
printf 'downstream\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am downstream
DOWNSTREAM_SHA="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q task/upstream
printf 'upstream-2\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am upstream-2
UPSTREAM_SHA_2="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" checkout -q task/downstream

STACKED_TASK="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T1/index.md"
write_task "$STACKED_TASK" "task/upstream" "main -> task/upstream -> task/downstream" "task/downstream"

STACKED_PR="$TMPROOT/stacked-pr.json"
STACKED_THREADS="$TMPROOT/stacked-threads.json"
STACKED_CHECKS="$TMPROOT/stacked-checks.json"
write_pr_json "$STACKED_PR" "OPEN" "task/downstream" "$DOWNSTREAM_SHA" "task/upstream" "DIRTY" "CHANGES_REQUESTED"
write_threads_json "$STACKED_THREADS" false false
write_checks_json "$STACKED_CHECKS" SUCCESS

OUT="$TMPROOT/stacked-snapshot.json"
bash "$SNAPSHOT" --repo "$REPO" --task-md "$STACKED_TASK" --pr-json "$STACKED_PR" --threads-json "$STACKED_THREADS" --checks-json "$STACKED_CHECKS" >"$OUT"
assert_eq "stacked pr_type" "$(json_field "$OUT" "resolver.pr_type")" "stacked_task"
assert_eq "stacked freshness" "$(json_field "$OUT" "base_freshness")" "stale_downstream"
assert_eq "stacked mergeability" "$(json_field "$OUT" "mergeability")" "conflict"
assert_eq "stacked total unresolved" "$(json_field "$OUT" "total_unresolved_threads")" "1"
assert_eq "stacked active unresolved" "$(json_field "$OUT" "active_unresolved_threads")" "1"

OUTDATED_THREADS="$TMPROOT/outdated-threads.json"
write_threads_json "$OUTDATED_THREADS" false true
OUT="$TMPROOT/outdated-snapshot.json"
bash "$SNAPSHOT" --repo "$REPO" --task-md "$STACKED_TASK" --pr-json "$STACKED_PR" --threads-json "$OUTDATED_THREADS" --checks-json "$STACKED_CHECKS" >"$OUT"
assert_eq "outdated total unresolved" "$(json_field "$OUT" "total_unresolved_threads")" "1"
assert_eq "outdated active unresolved" "$(json_field "$OUT" "active_unresolved_threads")" "0"
assert_eq "outdated unresolved count" "$(json_field "$OUT" "outdated_unresolved_threads")" "1"

DIRECT_TASK="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T2/index.md"
write_task "$DIRECT_TASK" "main" "main -> task/direct" "task/direct"
git -C "$REPO" checkout -q main
git -C "$REPO" checkout -q -b task/direct
printf 'direct\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am direct
DIRECT_SHA="$(git -C "$REPO" rev-parse HEAD)"
DIRECT_PR="$TMPROOT/direct-pr.json"
DIRECT_CHECKS="$TMPROOT/direct-checks.json"
write_pr_json "$DIRECT_PR" "OPEN" "task/direct" "$DIRECT_SHA" "main" "CLEAN" "APPROVED"
write_checks_json "$DIRECT_CHECKS" SUCCESS
OUT="$TMPROOT/direct-snapshot.json"
bash "$SNAPSHOT" --repo "$REPO" --task-md "$DIRECT_TASK" --pr-json "$DIRECT_PR" --checks-json "$DIRECT_CHECKS" >"$OUT"
assert_eq "direct pr_type" "$(json_field "$OUT" "resolver.pr_type")" "direct_task"
assert_eq "direct freshness" "$(json_field "$OUT" "base_freshness")" "fresh"

FEATURE_PR="$TMPROOT/feature-pr.json"
write_pr_json "$FEATURE_PR" "OPEN" "feat/DP-130-demo" "$DIRECT_SHA" "main" "CLEAN" ""
OUT="$TMPROOT/feature-resolver.json"
bash "$RESOLVER" --repo "$REPO" --pr-json "$FEATURE_PR" >"$OUT"
assert_eq "feature pr_type" "$(json_field "$OUT" "pr_type")" "feature"
assert_eq "feature mutable" "$(json_field "$OUT" "mutable_allowed")" "true"

AGG_TASK="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T3/index.md"
write_task "$AGG_TASK" "task/upstream" "main -> task/upstream -> task/aggregate" "task/aggregate"
git -C "$REPO" checkout -q task/upstream
git -C "$REPO" checkout -q -b task/aggregate
printf 'aggregate\n' >>"$REPO/file.txt"
git -C "$REPO" commit -q -am aggregate
AGG_SHA="$(git -C "$REPO" rev-parse HEAD)"
AGG_PR="$TMPROOT/agg-pr.json"
write_pr_json "$AGG_PR" "OPEN" "task/aggregate" "$AGG_SHA" "main" "CLEAN" ""
OUT="$TMPROOT/agg-resolver.json"
bash "$RESOLVER" --repo "$REPO" --task-md "$AGG_TASK" --pr-json "$AGG_PR" --aggregate-release >"$OUT"
assert_eq "aggregate pr_type" "$(json_field "$OUT" "pr_type")" "aggregate_release"
assert_eq "aggregate base" "$(json_field "$OUT" "authoritative_base")" "main"

LEGACY_PR="$TMPROOT/legacy-pr.json"
write_pr_json "$LEGACY_PR" "OPEN" "task/no-task" "$DIRECT_SHA" "main" "CLEAN" ""
OUT="$TMPROOT/legacy-resolver.json"
bash "$RESOLVER" --repo "$REPO" --pr-json "$LEGACY_PR" --intent mutable >"$OUT"
assert_eq "legacy pr_type" "$(json_field "$OUT" "pr_type")" "no_task_legacy"
assert_eq "legacy mutable blocked" "$(json_field "$OUT" "mutable_allowed")" "false"

EXT_TASK="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T4/index.md"
write_task "$EXT_TASK" "vendor/release" "vendor/release -> task/external" "task/external"
OUT="$TMPROOT/external-resolver.json"
bash "$RESOLVER" --repo "$REPO" --task-md "$EXT_TASK" --intent mutable >"$OUT"
assert_eq "external pr_type" "$(json_field "$OUT" "pr_type")" "external_base"
assert_eq "external mutable blocked" "$(json_field "$OUT" "mutable_allowed")" "false"

# --- AC1: issue-level conversation comments -> unaddressed_human_comments ---
AC1_COMMENTS="$TMPROOT/ac1-comments.json"
cat >"$AC1_COMMENTS" <<'EOF'
{"pullRequest":{"comments":{"nodes":[{"id":"IC_h1","url":"https://example.invalid/c1","authorAssociation":"MEMBER","author":{"__typename":"User","login":"reviewer1"},"body":"這個判斷需要補上邊界檢查"}]}}}
EOF
OUT="$TMPROOT/ac1-snapshot.json"
bash "$SNAPSHOT" --repo "$REPO" --task-md "$DIRECT_TASK" --pr-json "$DIRECT_PR" --checks-json "$DIRECT_CHECKS" --comments-json "$AC1_COMMENTS" >"$OUT"
assert_eq "ac1 comments loaded" "$(json_field "$OUT" "conversation_comments_loaded")" "true"
assert_eq "ac1 unaddressed count" "$(json_field "$OUT" "unaddressed_human_comment_count")" "1"
assert_eq "ac1 author typename" "$(comment_field "$OUT" 0 "author_typename")" "User"
assert_eq "ac1 author association" "$(comment_field "$OUT" 0 "author_association")" "MEMBER"
assert_eq "ac1 body present" "$(comment_field "$OUT" 0 "body")" "這個判斷需要補上邊界檢查"

# --- AC3: bot / Polaris HTML marker / known-automation comments filtered out ---
AC3_COMMENTS="$TMPROOT/ac3-comments.json"
cat >"$AC3_COMMENTS" <<'EOF'
{"pullRequest":{"comments":{"nodes":[{"id":"IC_bot","url":"https://example.invalid/bot","authorAssociation":"NONE","author":{"__typename":"Bot","login":"github-actions"},"body":"All checks passed"},{"id":"IC_marker","url":"https://example.invalid/marker","authorAssociation":"MEMBER","author":{"__typename":"User","login":"someuser"},"body":"<!-- polaris-evidence-publication:v1 -->\nEvidence published at HEAD"},{"id":"IC_ccr","url":"https://example.invalid/ccr","authorAssociation":"CONTRIBUTOR","author":{"__typename":"User","login":"automation-account"},"body":"## Claude Code Review\n\n**Summary**: No blocking issues found."},{"id":"IC_jira","url":"https://example.invalid/jira","authorAssociation":"NONE","author":{"__typename":"User","login":"release-bot-user"},"body":"https://exampleco.atlassian.net/browse/PROJ-1234"}]}}}
EOF
OUT="$TMPROOT/ac3-snapshot.json"
bash "$SNAPSHOT" --repo "$REPO" --task-md "$DIRECT_TASK" --pr-json "$DIRECT_PR" --checks-json "$DIRECT_CHECKS" --comments-json "$AC3_COMMENTS" >"$OUT"
assert_eq "ac3 comments loaded" "$(json_field "$OUT" "conversation_comments_loaded")" "true"
assert_eq "ac3 all automation filtered" "$(json_field "$OUT" "unaddressed_human_comment_count")" "0"

# --- AC-NF1: gh unavailable -> conversation-comment fetch fail-closed, not fail-open ---
NF1_REPO="$TMPROOT/nf1-repo"
mkdir -p "$NF1_REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T1"
git init -q -b main "$NF1_REPO"
git -C "$NF1_REPO" config user.email "selftest@example.com"
git -C "$NF1_REPO" config user.name "selftest"
git -C "$NF1_REPO" remote add origin https://github.com/example/repo.git
printf 'root\n' >"$NF1_REPO/file.txt"
git -C "$NF1_REPO" add file.txt
git -C "$NF1_REPO" commit -q -m init
git -C "$NF1_REPO" checkout -q -b task/nf1
printf 'nf1\n' >>"$NF1_REPO/file.txt"
git -C "$NF1_REPO" commit -q -am nf1
NF1_SHA="$(git -C "$NF1_REPO" rev-parse HEAD)"
NF1_TASK="$NF1_REPO/docs-manager/src/content/docs/specs/design-plans/DP-130-fixture/tasks/T1/index.md"
write_task "$NF1_TASK" "main" "main -> task/nf1" "task/nf1"
NF1_PR="$TMPROOT/nf1-pr.json"
write_pr_json "$NF1_PR" "OPEN" "task/nf1" "$NF1_SHA" "main" "CLEAN" "" "42"
NF1_ERR="$TMPROOT/nf1-err.txt"
set +e
GH_BIN="$TMPROOT/nonexistent-gh-binary" bash "$SNAPSHOT" --repo "$NF1_REPO" --task-md "$NF1_TASK" \
  --pr-json "$NF1_PR" --threads-json "$STACKED_THREADS" --checks-json "$DIRECT_CHECKS" >"$TMPROOT/nf1-out.json" 2>"$NF1_ERR"
NF1_RC=$?
set -e
assert_eq "nf1 fail-closed exit code" "$NF1_RC" "2"
if grep -q 'POLARIS_TOOL_MISSING:gh' "$NF1_ERR"; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL: nf1 fail-closed marker missing; stderr=%s\n' "$(cat "$NF1_ERR")" >&2
fi

printf 'pr-state-snapshot selftest: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
