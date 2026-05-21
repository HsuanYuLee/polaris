#!/usr/bin/env bash
# gate-work-source-chore-followup-selftest.sh — DP-217 chore-followup lane.
#
# DP-217 carves out a narrow chore-followup lane in gate-work-source.sh so
# release-tail manifest / housekeeping fixes don't need a fresh task.md.
# This selftest verifies:
#
#   1. PASS: chore/DP-NNN-<slug> branch + DP container has IMPLEMENTED
#      tasks/pr-release/T*.md → exit 0.
#   2. PASS via archived container: DP container only exists under archive/
#      → exit 0.
#   3. BLOCKED: chore/DP-NNN-<slug> branch + DP container exists but no
#      tasks/pr-release/T*.md is status: IMPLEMENTED → exit 2.
#   4. BLOCKED: chore/DP-NNN-<slug> branch + no DP container at all →
#      exit 2.
#   5. BLOCKED: chore/<other>-<slug> branch (doesn't match DP regex) → falls
#      through to normal task.md resolver, which finds nothing → exit 2.
#
# Cases 3-5 cover AC-NEG3 ("chore lane must not become a generic escape").

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-work-source.sh"
WORKDIR="$(mktemp -d -t dp217-chore-followup.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$GATE" ]]; then
  echo "FAIL: gate is not executable: $GATE" >&2
  exit 1
fi

setup_repo() {
  local repo="$1"
  local branch="$2"
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name "DP-217 selftest"
  # Mark as a Polaris-governed repo via workspace-config.yaml presence.
  cat >"$repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
  mkdir -p "$repo/scripts"
  touch "$repo/AGENTS.md"
  # Provide an executable polaris-pr-create stub so is_polaris_governed_repo
  # treats the workspace-config.yaml signal as sufficient.
  echo "#!/usr/bin/env bash" >"$repo/scripts/polaris-pr-create.sh"
  chmod +x "$repo/scripts/polaris-pr-create.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init"
  git -C "$repo" checkout -q -b "$branch"
}

write_dp_container() {
  local repo="$1"
  local dp="$2"   # e.g. DP-217
  local archived="$3"  # 1 = under archive/, 0 = active
  local implemented="$4"  # 1 = at least one task.md status IMPLEMENTED
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

# Case 1: PASS active container with IMPLEMENTED pr-release task.
repo1="$WORKDIR/repo1"
setup_repo "$repo1" "chore/DP-217-followup"
write_dp_container "$repo1" "DP-217" 0 1
set +e
(cd "$repo1" && "$GATE" --repo "$repo1") >"$WORKDIR/case1.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case1: active+IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case1.out" >&2
  exit 1
fi
grep -q 'chore-followup lane' "$WORKDIR/case1.out"

# Case 2: PASS via archived container.
repo2="$WORKDIR/repo2"
setup_repo "$repo2" "chore/DP-555-archived-followup"
write_dp_container "$repo2" "DP-555" 1 1
set +e
(cd "$repo2" && "$GATE" --repo "$repo2") >"$WORKDIR/case2.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  echo "FAIL (case2: archived+IMPLEMENTED): expected exit 0, got $rc" >&2
  cat "$WORKDIR/case2.out" >&2
  exit 1
fi
grep -q 'chore-followup lane' "$WORKDIR/case2.out"

# Case 3: BLOCKED active container with no IMPLEMENTED pr-release task.
repo3="$WORKDIR/repo3"
setup_repo "$repo3" "chore/DP-999-no-impl"
write_dp_container "$repo3" "DP-999" 0 0
set +e
(cd "$repo3" && "$GATE" --repo "$repo3") >"$WORKDIR/case3.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case3: no IMPLEMENTED task): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case3.out" >&2
  exit 1
fi
grep -q 'requires parent DP DP-999 to have an IMPLEMENTED pr-release task' "$WORKDIR/case3.out"

# Case 4: BLOCKED chore branch references DP with NO container at all.
repo4="$WORKDIR/repo4"
setup_repo "$repo4" "chore/DP-777-missing-container"
# Make a non-related commit so git is happy.
echo "x" >"$repo4/scratch.txt"
git -C "$repo4" add -A >/dev/null
git -C "$repo4" -c commit.gpgsign=false commit -q -m "noop"
set +e
(cd "$repo4" && "$GATE" --repo "$repo4") >"$WORKDIR/case4.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case4: no container): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case4.out" >&2
  exit 1
fi
grep -q 'could not resolve DP container for DP-777' "$WORKDIR/case4.out"

# Case 5: BLOCKED non-DP chore/* branch (e.g. chore/cleanup-foo) falls through
# to normal task resolution and fails (no task.md to resolve).
repo5="$WORKDIR/repo5"
setup_repo "$repo5" "chore/cleanup-misc"
echo "x" >"$repo5/scratch.txt"
git -C "$repo5" add -A >/dev/null
git -C "$repo5" -c commit.gpgsign=false commit -q -m "noop"
set +e
(cd "$repo5" && "$GATE" --repo "$repo5") >"$WORKDIR/case5.out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 2 ]]; then
  echo "FAIL (case5: non-DP chore): expected exit 2, got $rc" >&2
  cat "$WORKDIR/case5.out" >&2
  exit 1
fi
if grep -q 'chore-followup lane' "$WORKDIR/case5.out"; then
  echo "FAIL (case5: non-DP chore): gate should not enter chore-followup lane" >&2
  cat "$WORKDIR/case5.out" >&2
  exit 1
fi

echo "PASS: gate-work-source chore-followup selftest"
