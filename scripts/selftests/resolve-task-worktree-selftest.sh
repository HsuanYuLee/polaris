#!/usr/bin/env bash
# Selftest for scripts/resolve-task-worktree.sh (AC33).
#
# Coverage:
#   - active worktree fixture → absolute path (single match)
#   - no worktree → NONE token
#   - dual worktree → fail-stop with POLARIS_DISPATCH_WORKTREE_AMBIGUOUS
#   - fully-qualified work_item_id (DP-228-T17) does not require --source-id
#   - JSON output shape (status / path / task_key)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-task-worktree.sh"

if [[ ! -x "$RESOLVER" ]]; then
  echo "[resolve-task-worktree-selftest] FAIL: $RESOLVER missing or not executable" >&2
  exit 1
fi

TMPDIR_RAW="$(mktemp -d -t polaris-resolve-task-worktree.XXXXXX)"
trap 'rm -rf "$TMPDIR_RAW"' EXIT

# macOS prefixes mktemp dirs with /var while git resolves them to /private/var.
# Normalize to the physical path so worktree absolute paths match exactly.
if command -v python3 >/dev/null 2>&1; then
  TMPDIR="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$TMPDIR_RAW")"
else
  TMPDIR="$TMPDIR_RAW"
fi

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "[resolve-task-worktree-selftest] FAIL [$TOTAL] $3: expected='$2' got='$1'" >&2
  fi
}

assert_rc() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "[resolve-task-worktree-selftest] FAIL [$TOTAL] $3: expected rc=$2 got=$1" >&2
  fi
}

assert_contains() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == *"$2"* ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "[resolve-task-worktree-selftest] FAIL [$TOTAL] $3: expected to contain '$2', got: $1" >&2
  fi
}

# Build a self-contained fixture repo with engineering worktrees so the test is
# hermetic and does not depend on the live workspace state.
FIXTURE_REPO="$TMPDIR/repo"
mkdir -p "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" init -q -b main
git -C "$FIXTURE_REPO" config user.email selftest@example.com
git -C "$FIXTURE_REPO" config user.name "Selftest"
echo "seed" >"$FIXTURE_REPO/README.md"
git -C "$FIXTURE_REPO" add README.md
git -C "$FIXTURE_REPO" commit -q -m "seed"

# --- Test 1: zero-match → NONE ---
out="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "NONE" "no worktree returns NONE"
assert_rc "$?" "0" "NONE path exits 0"

# --- Test 1b: JSON shape for NONE ---
out_json="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" --format json 2>/dev/null)"
assert_eq "$out_json" '{"status":"NONE","path":null,"task_key":"DP-228-T17"}' "json NONE shape"

# --- Set up a single active worktree on task/DP-228-T17-impl ---
WT_SINGLE="$FIXTURE_REPO/.worktrees/repo-engineering-DP-228-T17"
git -C "$FIXTURE_REPO" worktree add -q -b task/DP-228-T17-impl "$WT_SINGLE" main

# --- Test 2: active worktree fixture → absolute path ---
out="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_SINGLE" "active worktree returns absolute path"

# --- Test 2b: JSON shape for FOUND ---
out_json="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" --format json 2>/dev/null)"
assert_eq "$out_json" "{\"status\":\"FOUND\",\"path\":\"$WT_SINGLE\",\"task_key\":\"DP-228-T17\"}" "json FOUND shape"

# --- Test 3: fully-qualified work_item_id without --source-id ---
out="$("$RESOLVER" --work-item-id DP-228-T17 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_SINGLE" "fully-qualified work_item_id accepted without source-id"

# --- Test 3b: similar-prefix branch is NOT confused (DP-228-T1 vs DP-228-T17) ---
git -C "$FIXTURE_REPO" worktree add -q -b task/DP-228-T1-other "$FIXTURE_REPO/.worktrees/repo-engineering-DP-228-T1" main
out="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_SINGLE" "T1 prefix does not collide with T17"

# --- Test 4: dual worktree → ambiguous fail-stop ---
WT_DUP="$FIXTURE_REPO/.worktrees/repo-engineering-DP-228-T17-dup"
git -C "$FIXTURE_REPO" worktree add -q -b task/DP-228-T17-second "$WT_DUP" main

err_log="$TMPDIR/ambiguous.err"
set +e
out="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$FIXTURE_REPO" 2>"$err_log")"
rc=$?
set -e
assert_rc "$rc" "2" "dual worktree exits 2"
assert_contains "$(cat "$err_log")" "POLARIS_DISPATCH_WORKTREE_AMBIGUOUS" "ambiguous stderr token"

# Clean up the duplicate so subsequent tests stay deterministic.
git -C "$FIXTURE_REPO" worktree remove --force "$WT_DUP" 2>/dev/null || true

# --- Test 5: resolver works when invoked from inside a worktree ---
out="$("$RESOLVER" --source-id DP-228 --work-item-id T17 --repo "$WT_SINGLE" 2>/dev/null)"
assert_eq "$out" "$WT_SINGLE" "invocation from inside worktree still resolves"

# --- Test 6: missing required arg ---
set +e
out="$("$RESOLVER" --source-id DP-228 --repo "$FIXTURE_REPO" 2>/dev/null)"
rc=$?
set -e
assert_rc "$rc" "2" "missing --work-item-id exits 2"

# --- Test 7: short-form work_item_id without source-id fails ---
set +e
out="$("$RESOLVER" --work-item-id T17 --repo "$FIXTURE_REPO" 2>/dev/null)"
rc=$?
set -e
assert_rc "$rc" "2" "short-form work_item_id without source-id fails"

# ===========================================================================
# DP-294 T1 / AC1: canonical delivery-branch resolution covers BOTH
#   (a) per-task delivery  → task/{task_key}-* branch (legacy, tests 1-7), and
#   (b) bundle delivery    → bundle_branch_alias declared in the task.md.
# The bundle worktree is checked out on the bundle branch (NOT a task/ branch),
# so legacy resolution returns NONE for bundle-delivered work items. The fix
# reads the canonical bundle_branch_alias frontmatter (single source of truth,
# same reader shape as gate-work-source.sh / framework-release-closeout.sh) and
# matches the worktree on that exact branch.
# ===========================================================================

# Build a canonical specs container inside the fixture so the resolver can
# locate the work item's task.md and read its bundle_branch_alias.
SPECS_DP="$FIXTURE_REPO/docs-manager/src/content/docs/specs/design-plans/DP-294-bundle-fixture"
mkdir -p "$SPECS_DP/tasks/V1" "$SPECS_DP/tasks/T9" "$SPECS_DP/tasks/T8"

BUNDLE_ALIAS="bundle-DP-294-v9.9.9"

# V1 + T9 are bundle-delivered: their task.md declares bundle_branch_alias.
cat >"$SPECS_DP/tasks/V1/index.md" <<EOF
---
bundle_branch_alias: $BUNDLE_ALIAS
title: "fixture V1"
---
# fixture
EOF
cat >"$SPECS_DP/tasks/T9/index.md" <<EOF
---
bundle_branch_alias: $BUNDLE_ALIAS
title: "fixture T9"
---
# fixture
EOF
# T8 is per-task delivered: NO bundle_branch_alias → must use task/ pattern.
cat >"$SPECS_DP/tasks/T8/index.md" <<EOF
---
title: "fixture T8 per-task"
---
# fixture
EOF

# --- Test 8: bundle alias declared but no bundle worktree yet → NONE ---
out="$("$RESOLVER" --source-id DP-294 --work-item-id V1 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "NONE" "bundle alias declared but no bundle worktree -> NONE"

# --- Set up the bundle worktree on the alias branch ---
WT_BUNDLE="$FIXTURE_REPO/.worktrees/repo-aggregate-release-DP-294"
git -C "$FIXTURE_REPO" worktree add -q -b "$BUNDLE_ALIAS" "$WT_BUNDLE" main

# --- Test 9: bundle-delivered V task resolves to the bundle worktree (FOUND) ---
out="$("$RESOLVER" --source-id DP-294 --work-item-id V1 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_BUNDLE" "bundle V1 resolves to bundle worktree"

# --- Test 9b: a second bundle member (T9) resolves to the SAME bundle worktree ---
out="$("$RESOLVER" --source-id DP-294 --work-item-id T9 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_BUNDLE" "bundle T9 resolves to same bundle worktree"

# --- Test 9c: JSON shape for bundle FOUND ---
out_json="$("$RESOLVER" --source-id DP-294 --work-item-id V1 --repo "$FIXTURE_REPO" --format json 2>/dev/null)"
assert_eq "$out_json" "{\"status\":\"FOUND\",\"path\":\"$WT_BUNDLE\",\"task_key\":\"DP-294-V1\"}" "json bundle FOUND shape"

# --- Test 10: per-task NOT regressed — T8 has no alias, so even with a bundle
#             worktree present for the source, T8 uses the task/ pattern and
#             returns NONE (no task/DP-294-T8-* worktree exists yet) ---
out="$("$RESOLVER" --source-id DP-294 --work-item-id T8 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "NONE" "per-task T8 (no alias) ignores bundle worktree -> NONE"

# --- Test 10b: per-task delivery resolves its own task/ worktree even when a
#             sibling bundle worktree exists for the same source ---
WT_T8="$FIXTURE_REPO/.worktrees/repo-engineering-DP-294-T8"
git -C "$FIXTURE_REPO" worktree add -q -b task/DP-294-T8-impl "$WT_T8" main
out="$("$RESOLVER" --source-id DP-294 --work-item-id T8 --repo "$FIXTURE_REPO" 2>/dev/null)"
assert_eq "$out" "$WT_T8" "per-task T8 resolves task/ worktree alongside bundle"

echo "[resolve-task-worktree-selftest] $PASS/$TOTAL passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
