#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${ROOT_DIR}/scripts/lib/framework-release-topology.sh"
TMPDIR="$(mktemp -d -t framework-release-topology.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

# shellcheck source=../lib/framework-release-topology.sh
. "$LIB"

make_task() {
  local file="$1"
  local task_id="$2"
  local base="$3"
  local branch="$4"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<MD
# ${task_id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-392 |
| Work item ID | ${task_id} |
| Task ID | ${task_id} |
| JIRA key | N/A |
| Base branch | ${base} |
| Branch chain | ${base} -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
MD
}

assert_fail_contains() {
  local expected="$1"
  shift
  if "$@" >"$TMPDIR/fail.out" 2>"$TMPDIR/fail.err"; then
    echo "expected command to fail: $*" >&2
    cat "$TMPDIR/fail.out" >&2
    exit 1
  fi
  grep -q "$expected" "$TMPDIR/fail.err" || {
    echo "expected failure to contain: $expected" >&2
    cat "$TMPDIR/fail.err" >&2
    exit 1
  }
}

TASK_DIR="$TMPDIR/tasks"
make_task "$TASK_DIR/T1/index.md" "DP-392-T1" "feat/DP-392" "task/DP-392-T1-one"
make_task "$TASK_DIR/T2/index.md" "DP-392-T2" "task/DP-392-T1-one" "task/DP-392-T2-two"
make_task "$TASK_DIR/T3/index.md" "DP-392-T3" "feat/DP-392" "task/DP-392-T3-three"

framework_release_topology_classify_task_mds "$TASK_DIR/T1/index.md" >"$TMPDIR/single.out"
grep -q "topology=single_pr" "$TMPDIR/single.out" || {
  echo "single task should classify as single_pr" >&2
  cat "$TMPDIR/single.out" >&2
  exit 1
}

framework_release_topology_classify_task_mds "$TASK_DIR/T1/index.md" "$TASK_DIR/T2/index.md" >"$TMPDIR/stack.out"
grep -q "topology=stack_pr" "$TMPDIR/stack.out" || {
  echo "declared task base chain should classify as stack_pr" >&2
  cat "$TMPDIR/stack.out" >&2
  exit 1
}

assert_fail_contains "sibling_parallel_invalid" \
  framework_release_topology_classify_task_mds "$TASK_DIR/T1/index.md" "$TASK_DIR/T3/index.md"

cat >"$TMPDIR/pr-stack.tsv" <<'TSV'
task_id|task_branch|task_base|pr_number|pr_base|pr_head_branch|pr_head_sha
DP-392-T1|task/DP-392-T1-one|feat/DP-392|11|feat/DP-392|task/DP-392-T1-one|1111111111111111111111111111111111111111
DP-392-T2|task/DP-392-T2-two|task/DP-392-T1-one|12|task/DP-392-T1-one|task/DP-392-T2-two|2222222222222222222222222222222222222222
TSV
framework_release_topology_validate_pr_records <"$TMPDIR/pr-stack.tsv" >"$TMPDIR/pr-stack.out"
grep -q "topology=stack_pr" "$TMPDIR/pr-stack.out" || {
  echo "PR base/head records should classify as stack_pr" >&2
  cat "$TMPDIR/pr-stack.out" >&2
  exit 1
}

cat >"$TMPDIR/pr-sibling.tsv" <<'TSV'
task_id|task_branch|task_base|pr_number|pr_base|pr_head_branch|pr_head_sha
DP-392-T1|task/DP-392-T1-one|feat/DP-392|11|feat/DP-392|task/DP-392-T1-one|1111111111111111111111111111111111111111
DP-392-T3|task/DP-392-T3-three|feat/DP-392|13|feat/DP-392|task/DP-392-T3-three|3333333333333333333333333333333333333333
TSV
assert_fail_contains "offending PRs are sibling heads" \
  framework_release_topology_validate_pr_records <"$TMPDIR/pr-sibling.tsv"

REPO="$TMPDIR/repo"
git init -q -b main "$REPO"
(
  cd "$REPO"
  git config user.name "Polaris Selftest"
  git config user.email "polaris-selftest@example.com"
  printf 'base\n' > file.txt
  git add file.txt
  git commit -q -m "base"
  git checkout -q -b task/one
  printf 'one\n' >> file.txt
  git add file.txt
  git commit -q -m "one"
  ONE_HEAD="$(git rev-parse HEAD)"
  git checkout -q -b task/two
  printf 'two\n' >> file.txt
  git add file.txt
  git commit -q -m "two"
  TWO_HEAD="$(git rev-parse HEAD)"
  git checkout -q --orphan squash-like
  rm -f file.txt
  printf 'flattened\n' > file.txt
  git add file.txt
  git commit -q -m "flattened"
  SQUASH_HEAD="$(git rev-parse HEAD)"
  printf '%s\n%s\n%s\n' "$ONE_HEAD" "$TWO_HEAD" "$SQUASH_HEAD" > "$TMPDIR/heads.txt"
)
ONE_HEAD="$(sed -n '1p' "$TMPDIR/heads.txt")"
TWO_HEAD="$(sed -n '2p' "$TMPDIR/heads.txt")"
SQUASH_HEAD="$(sed -n '3p' "$TMPDIR/heads.txt")"
framework_release_topology_validate_ancestor_trace "$REPO" "$TWO_HEAD" "DP-392-T1=$ONE_HEAD" "DP-392-T2=$TWO_HEAD" >"$TMPDIR/ancestor.out"
grep -q "ancestor_trace=pass" "$TMPDIR/ancestor.out" || {
  echo "expected ancestor trace to pass for real stack" >&2
  cat "$TMPDIR/ancestor.out" >&2
  exit 1
}

assert_fail_contains "squash-like trace loss" \
  framework_release_topology_validate_ancestor_trace "$REPO" "$SQUASH_HEAD" "DP-392-T1=$ONE_HEAD"

echo "[framework-release-topology-selftest] PASS"
