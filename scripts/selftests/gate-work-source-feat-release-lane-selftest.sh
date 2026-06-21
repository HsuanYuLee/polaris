#!/usr/bin/env bash
# Purpose: Verify gate-work-source.sh feat-release lane resolves the DP container
#          from a worktree-aware specs root (resolve_specs_root "$REPO_ROOT")
#          instead of a bare $REPO_ROOT/docs-manager path, so that a release run
#          launched from a feat/DP-NNN worktree (whose specs live only in the main
#          checkout) still resolves the container and passes the lane (DP-351 G4).
# Inputs:  none (self-contained git fixtures under a mktemp workdir).
# Outputs: exit 0 + "PASS" on success; exit 1 + "FAIL (...)" on first failure.
# Side effects: creates/removes temp git repos and worktrees under $WORKDIR only.
#
# Coverage:
#   IS7  PASS:    release run from a checkout already on feat/DP-NNN, DP container
#                 + IMPLEMENTED tasks/pr-release task present in that same checkout
#                 → feat-release lane accepts (exit 0).
#   IS8  PASS:    release run from a feat/DP-NNN *worktree* while the main checkout
#                 is on another branch and the DP container lives only in the main
#                 checkout (not in the worktree). The specs root must resolve from
#                 the main checkout via resolve_specs_root → exit 0. This is the
#                 core worktree-awareness regression: a bare $REPO_ROOT/docs-manager
#                 lookup would fail to find the container and falsely BLOCK.
#   IS9  PASS:    archived DP container (under design-plans/archive/) resolves under
#                 the worktree-aware main-checkout archive path → exit 0.
#   BLOCKED:      DP container exists but has no IMPLEMENTED pr-release task →
#                 fail-closed exit 2.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-work-source.sh"
WORKDIR="$(mktemp -d -t dp351-feat-release-lane.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate is not executable: $GATE" >&2
  exit 1
fi

# run_gate <repo>: invoke the gate against a fixture repo with POLARIS_WORKSPACE_ROOT
# and POLARIS_SPECS_ROOT unset. resolve_specs_root short-circuits to those env vars
# first, so an inherited workspace/specs root (e.g. when run under
# run-verify-command.sh) would otherwise resolve away from the fixture and break
# the worktree-awareness assertions. Unsetting them keeps each fixture hermetic.
run_gate() {
  local repo="$1"
  (cd "$repo" && env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT "$GATE" --repo "$repo")
}

# setup_main_checkout <repo> <branch>: a Polaris-governed git repo on <branch>.
# Mirrors the chore-followup selftest's setup so the gate's repo-governed signal
# and protected-branch handling behave identically.
setup_main_checkout() {
  local repo="$1"
  local branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-351 selftest"
  printf 'language: zh-TW\n' >"$repo/workspace-config.yaml"
  touch "$repo/AGENTS.md"
  printf '#!/usr/bin/env bash\n' >"$repo/scripts/polaris-pr-create.sh"
  chmod +x "$repo/scripts/polaris-pr-create.sh"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "init"
  # The init commit already lands on the default branch (main). Only create a new
  # branch when a different target branch is requested.
  if [[ "$branch" != "main" ]]; then
    git -C "$repo" checkout -q -b "$branch"
  fi
}

# write_dp_container <repo> <dp> <archived> <implemented>: emit a DP container
# under the canonical specs path with one tasks/pr-release task whose status is
# IMPLEMENTED (1) or PLANNED (0); under archive/ when <archived>=1.
write_dp_container() {
  local repo="$1"
  local dp="$2"
  local archived="$3"
  local implemented="$4"
  local base="$repo/docs-manager/src/content/docs/specs/design-plans"
  local container
  if [[ "$archived" == "1" ]]; then
    container="$base/archive/${dp}-archived-fixture"
  else
    container="$base/${dp}-active-fixture"
  fi
  mkdir -p "$container/tasks/pr-release/T1"
  cat >"$container/index.md" <<MD
---
title: "$dp fixture"
status: IMPLEMENTED
---

# $dp
MD
  local status
  if [[ "$implemented" == "1" ]]; then
    status="IMPLEMENTED"
  else
    status="PLANNED"
  fi
  cat >"$container/tasks/pr-release/T1/index.md" <<MD
---
title: "$dp T1"
status: $status
---

# $dp T1
MD
  git -C "$repo" add -A >/dev/null
  git -C "$repo" -c commit.gpgsign=false commit -q -m "$dp fixture (archived=$archived implemented=$implemented)"
}

# ── IS7: release run from a checkout already on feat/DP-NNN ────────────────────
# DP container + IMPLEMENTED pr-release task in the same checkout → exit 0.
repo7="$WORKDIR/is7"
setup_main_checkout "$repo7" "feat/DP-710"
write_dp_container "$repo7" "DP-710" 0 1
set +e
run_gate "$repo7" >"$WORKDIR/is7.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS7: feat checkout + IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/is7.out" >&2
  exit 1
fi
grep -q 'feat-release lane' "$WORKDIR/is7.out" || {
  echo "FAIL (IS7): expected feat-release lane PASS message" >&2
  cat "$WORKDIR/is7.out" >&2
  exit 1
}

# ── IS8: release run from a feat/DP-NNN WORKTREE (core regression) ─────────────
# Topology: the DP container is committed on `main` and lives in the main
# checkout, which stays on `main`. feat/DP-820 is branched from that same tip and
# checked out as a separate worktree. The canonical specs tree is then removed
# from the worktree working tree to mirror specs being a gitignored,
# main-checkout-only artifact — so $REPO_ROOT (the worktree) has no specs root and
# resolve_specs_root must chain to the main checkout via resolve_main_checkout.
# The container must be reachable from the main checkout's branch (main), so it is
# committed BEFORE feat/DP-820 is created, not on the feat branch.
main8="$WORKDIR/is8-main"
setup_main_checkout "$main8" "main"
write_dp_container "$main8" "DP-820" 0 1
# Branch feat/DP-820 from the current main tip (which carries the container) and
# leave the main checkout on `main`, so the worktree is the only place feat/DP-820
# is checked out — this proves worktree-awareness, not a coincidental cwd.
git -C "$main8" branch feat/DP-820
wt8="$WORKDIR/is8-worktree"
git -C "$main8" worktree add -q "$wt8" feat/DP-820
rm -rf "$wt8/docs-manager/src/content/docs/specs"
set +e
run_gate "$wt8" >"$WORKDIR/is8.out" 2>&1
rc=$?
set -e
git -C "$main8" worktree remove --force "$wt8" >/dev/null 2>&1 || true
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS8: feat worktree, specs only in main checkout): expected exit 0, got $rc" >&2
  echo "  → bare \$REPO_ROOT/docs-manager lookup cannot find the container from a worktree;" >&2
  echo "    the lane must resolve the specs root via resolve_specs_root (worktree-aware)." >&2
  cat "$WORKDIR/is8.out" >&2
  exit 1
fi
grep -q 'feat-release lane' "$WORKDIR/is8.out" || {
  echo "FAIL (IS8): expected feat-release lane PASS message" >&2
  cat "$WORKDIR/is8.out" >&2
  exit 1
}

# ── IS9: archived DP container resolves under main-checkout archive path ───────
repo9="$WORKDIR/is9"
setup_main_checkout "$repo9" "feat/DP-930"
write_dp_container "$repo9" "DP-930" 1 1
set +e
run_gate "$repo9" >"$WORKDIR/is9.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (IS9: archived container + IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/is9.out" >&2
  exit 1
fi
grep -q 'feat-release lane' "$WORKDIR/is9.out" || {
  echo "FAIL (IS9): expected feat-release lane PASS message" >&2
  cat "$WORKDIR/is9.out" >&2
  exit 1
}

# ── BLOCKED: DP container exists but no IMPLEMENTED pr-release task ────────────
repoB="$WORKDIR/blocked"
setup_main_checkout "$repoB" "feat/DP-940"
write_dp_container "$repoB" "DP-940" 0 0
set +e
run_gate "$repoB" >"$WORKDIR/blocked.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (BLOCKED: no IMPLEMENTED pr-release task): expected exit 2, got $rc" >&2
  cat "$WORKDIR/blocked.out" >&2
  exit 1
fi
grep -q 'feat-release lane requires DP DP-940 to have an IMPLEMENTED pr-release task' "$WORKDIR/blocked.out" || {
  echo "FAIL (BLOCKED): expected no-IMPLEMENTED block message" >&2
  cat "$WORKDIR/blocked.out" >&2
  exit 1
}

echo "PASS: gate-work-source feat-release lane selftest"
