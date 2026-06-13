#!/usr/bin/env bash
# Purpose: DP-322 resolver-level guard. Prove that resolve-task-md-by-branch.sh,
#          given --scan-root pointing at a clean worktree whose specs tree is
#          absent, resolves the worktree's git common-dir source repo for specs
#          and never leaks to a POLARIS_WORKSPACE_ROOT-driven (wrong) workspace.
# Inputs:  none (builds self-contained git fixtures under a tmp dir)
# Outputs: stdout PASS line on success; non-zero exit + stderr diff on failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-task-md-by-branch.sh"
TMPDIR="$(mktemp -d -t resolve-overlay-scan-root.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

SPECS_REL="docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks"

# make_task <repo_root> <task_id> <branch>
#   Writes a canonical task.md fixture whose `Task branch` table cell == branch.
make_task() {
  local repo_root="$1"
  local task_id="$2"
  local branch="$3"
  local file="$repo_root/$SPECS_REL/${task_id##*-}/index.md"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
# ${task_id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | ${task_id} |
| Task branch | ${branch} |
MD
}

# init_repo <repo_root>
#   git init + first commit so a linked worktree can be added.
init_repo() {
  local repo_root="$1"
  mkdir -p "$repo_root"
  git -C "$repo_root" init -q
  git -C "$repo_root" config user.email selftest@polaris.local
  git -C "$repo_root" config user.name selftest
  git -C "$repo_root" add -A
  git -C "$repo_root" commit -qm fixture
}

fail() {
  echo "[resolve-overlay-scan-root-selftest] FAIL: $1" >&2
  shift || true
  [[ $# -gt 0 ]] && printf '%s\n' "$@" >&2
  exit 1
}

QUERY_BRANCH="task/DP-999-T2-two"

# ---------------------------------------------------------------------------
# Scenario A — source repo HAS the matching task; a decoy workspace (pointed at
# by POLARIS_WORKSPACE_ROOT) carries an UNRELATED task. The resolver must
# resolve the scan-root's source repo and emit the source task.md, not miss.
# ---------------------------------------------------------------------------
SRC_A="$TMPDIR/source-a"
DECOY_A="$TMPDIR/decoy-a"
make_task "$SRC_A" "DP-999-T2" "$QUERY_BRANCH"
init_repo "$SRC_A"
make_task "$DECOY_A" "DP-999-T9" "task/DP-999-T9-unrelated"

WT_A="$TMPDIR/worktree-a"
git -C "$SRC_A" worktree add -q "$WT_A" HEAD
rm -rf "$WT_A/docs-manager/src/content/docs/specs"

set +e
OUT_A="$(POLARIS_WORKSPACE_ROOT="$DECOY_A" bash "$RESOLVER" --scan-root "$WT_A" "$QUERY_BRANCH" 2>"$TMPDIR/a.err")"
RC_A=$?
set -e
[[ $RC_A -eq 0 ]] || fail "scenario A expected exit 0, got $RC_A" "$(cat "$TMPDIR/a.err")"
# The resolver derives the source repo via `git rev-parse`, which yields the
# physical path; match it with `pwd -P` so macOS /var -> /private/var agrees.
EXPECT_A="$(cd "$SRC_A/$SPECS_REL/T2" && pwd -P)/index.md"
[[ "$OUT_A" == "$EXPECT_A" ]] || fail "scenario A resolved wrong path" "want: $EXPECT_A" "got:  $OUT_A"

# ---------------------------------------------------------------------------
# Scenario C (fail-closed, AC-NEG-shaped) — source repo does NOT have the
# matching task; the decoy workspace DOES carry a trap task on the same branch.
# If the resolver leaked to POLARIS_WORKSPACE_ROOT it would falsely match the
# decoy. Correct behaviour: scan the source repo only, find nothing, exit 1.
# ---------------------------------------------------------------------------
SRC_C="$TMPDIR/source-c"
DECOY_C="$TMPDIR/decoy-c"
make_task "$SRC_C" "DP-999-T5" "task/DP-999-T5-other"
init_repo "$SRC_C"
make_task "$DECOY_C" "DP-999-T2" "$QUERY_BRANCH"

WT_C="$TMPDIR/worktree-c"
git -C "$SRC_C" worktree add -q "$WT_C" HEAD
rm -rf "$WT_C/docs-manager/src/content/docs/specs"

set +e
OUT_C="$(POLARIS_WORKSPACE_ROOT="$DECOY_C" bash "$RESOLVER" --scan-root "$WT_C" "$QUERY_BRANCH" 2>"$TMPDIR/c.err")"
RC_C=$?
set -e
[[ $RC_C -eq 1 ]] || fail "scenario C expected exit 1 (no leak to decoy), got $RC_C" "stdout: $OUT_C" "stderr: $(cat "$TMPDIR/c.err")"
[[ -z "$OUT_C" ]] || fail "scenario C must emit no match path; leaked: $OUT_C"
# Match on path components (robust against macOS /var -> /private/var prefixing).
grep -q '/source-c/' "$TMPDIR/c.err" || fail "scenario C diagnostic should scan the source repo, not the decoy" "$(cat "$TMPDIR/c.err")"
grep -q '/decoy-c/' "$TMPDIR/c.err" && fail "scenario C leaked decoy workspace into scan" "$(cat "$TMPDIR/c.err")"

echo "[resolve-overlay-scan-root-selftest] PASS"
