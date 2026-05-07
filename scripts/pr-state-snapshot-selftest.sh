#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  local path="$1" state="$2" head_branch="$3" head_sha="$4" base_branch="$5" merge_state="$6" review_decision="${7:-}"
  cat >"$path" <<EOF
{"state":"$state","headRefName":"$head_branch","headRefOid":"$head_sha","baseRefName":"$base_branch","mergeStateStatus":"$merge_state","reviewDecision":"$review_decision"}
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

printf 'pr-state-snapshot selftest: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
