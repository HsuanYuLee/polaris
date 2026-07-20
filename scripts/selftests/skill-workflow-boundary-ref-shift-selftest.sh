#!/usr/bin/env bash
# Purpose: Selftest for the DP-303 T2 ref-shift detection in
#          scripts/skill-workflow-boundary-gate.sh.
# Inputs:  none (builds isolated fixture repos under a mktemp dir)
# Outputs: PASS/FAIL lines on stdout; exit 0 all pass, exit 1 any fail
#
# Coverage matrix (per DP-303 AC2 / AC3 / AC-NEG3, EC2, R2):
#   - AC3  : a task/* delivery branch ref that MOVES during a verify-AC session
#            (ref-only, no in-scope file change) is detected by --check and
#            fails closed with POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED.
#   - AC3  : a task/* delivery branch ref that is REMOVED during a verify-AC
#            session is likewise detected and fails closed.
#   - AC2  : a verify-AC umbrella integration that only uses a throwaway
#            verify-integration-* branch (and never moves a task/* delivery
#            branch ref) passes --check.
#   - AC-NEG3 : creating AND deleting a throwaway verify-integration-* branch
#            is NOT mistaken for a delivery branch ref shift; --check passes.
#   - AC-NEG3 (scope): the ref-shift guard applies to verify-AC only;
#            engineering creating a task/* delivery branch is NOT flagged.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$script_dir/skill-workflow-boundary-gate.sh"

if [[ ! -x "$gate" ]]; then
  echo "FAIL: gate not executable: $gate" >&2
  exit 1
fi

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

pass=0
fail=0

record_pass() {
  echo "PASS $1"
  pass=$((pass + 1))
}

record_fail() {
  echo "FAIL $1" >&2
  fail=$((fail + 1))
}

# Build an isolated repo + DP-backed container with two extra commits so we
# have distinct shas to shift refs between.
make_repo() {
  local label="$1"
  local repo="$tmp_root/repo-$label"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@local
  git -C "$repo" config user.name selftest

  local container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-skill-boundary-fixture"
  mkdir -p "$container/verification/V1"
  mkdir -p "$container/tasks/V1"
  printf '# DP-999\n' > "$container/refinement.md"
  printf '{}\n' > "$container/refinement.json"
  printf '# DP-999 index\n' > "$container/index.md"
  printf '# V1\n' > "$container/tasks/V1/index.md"
  mkdir -p "$repo/scripts"
  printf '# repo\n' > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "init"

  # A second commit so a task/* branch can point at a different sha later.
  printf 'second\n' >> "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "second"

  printf '%s\n%s\n' "$repo" "$container"
}

repo_of() { printf '%s\n' "$1" | sed -n '1p'; }
container_of() { printf '%s\n' "$1" | sed -n '2p'; }

# ---- 1. AC3: task/* delivery branch ref shift during session -> fail-closed --
{
  out="$(make_repo "ac3-refshift")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"

  head_sha="$(git -C "$repo" rev-parse HEAD)"
  prev_sha="$(git -C "$repo" rev-parse HEAD~1)"
  # A task/* delivery branch exists, pointing at HEAD, BEFORE the session.
  git -C "$repo" branch "task/DP-999-T1-impl" "$head_sha"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null

  # During the session the delivery branch ref is shifted to a different commit
  # (ref-only mutation; no in-scope file change). This is the forbidden move.
  git -C "$repo" branch -f "task/DP-999-T1-impl" "$prev_sha"

  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:verify-AC' <<< "$err_out"; then
    record_pass "AC3: task/* delivery branch ref shift detected (exit 1 + marker)"
  else
    record_fail "AC3: task/* delivery branch ref shift not detected (rc=$rc, err=$err_out)"
  fi
}

# ---- 2. AC3: task/* delivery branch REMOVED during session -> fail-closed ----
{
  out="$(make_repo "ac3-refremove")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" branch "task/DP-999-T1-impl" "$head_sha"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null

  # Deleting a delivery branch during integration is a forbidden ref mutation.
  git -C "$repo" branch -D "task/DP-999-T1-impl" >/dev/null

  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:verify-AC' <<< "$err_out"; then
    record_pass "AC3: task/* delivery branch removed during session detected"
  else
    record_fail "AC3: task/* delivery branch removal not detected (rc=$rc, err=$err_out)"
  fi
}

# ---- 2b. AC-NEG3 (scope): engineering creating a task/* branch -> NOT flagged -
{
  out="$(make_repo "scope-eng-create")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"
  prev_sha="$(git -C "$repo" rev-parse HEAD~1)"
  task_md="$container/tasks/V1/index.md"   # any task.md with Allowed Files
  printf '# T\n## Allowed Files\n- `scripts/bar.sh`\n' > "$task_md"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null

  # engineering legitimately creates its own delivery branch.
  git -C "$repo" branch "task/DP-999-T1-impl" "$prev_sha"
  printf '#!/bin/bash\n' > "$repo/scripts/bar.sh"

  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null 2>&1; then
    record_pass "AC-NEG3 scope: engineering creating task/* branch not flagged"
  else
    record_fail "AC-NEG3 scope: engineering task/* branch falsely blocked"
  fi
}

# ---- 3. AC2: throwaway integration branch only, no task/* shift -> pass -------
{
  out="$(make_repo "ac2-throwaway-only")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" branch "task/DP-999-T1-impl" "$head_sha"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null

  # Umbrella integration creates a throwaway verify-integration-* branch and
  # writes the (in-scope) verification artifact. task/* refs are untouched.
  git -C "$repo" branch "verify-integration-DP-999-V1" "$head_sha"
  printf '# verify\n' > "$container/verification/V1/verify-report.md"

  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "AC2: throwaway integration branch + in-scope artifact passes"
  else
    record_fail "AC2: throwaway integration branch falsely blocked"
  fi
}

# ---- 4. AC-NEG3: create AND delete throwaway integration branch -> pass -------
{
  out="$(make_repo "ac-neg3-create-delete")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" branch "task/DP-999-T1-impl" "$head_sha"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null

  # Full throwaway lifecycle: create the integration branch, then delete it.
  git -C "$repo" branch "verify-integration-DP-999-V1" "$head_sha"
  git -C "$repo" branch -D "verify-integration-DP-999-V1" >/dev/null

  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "AC-NEG3: throwaway integration branch create/delete not flagged"
  else
    record_fail "AC-NEG3: throwaway integration branch lifecycle falsely blocked"
  fi
}

# ---- 5. AC2/AC3 regression: no branches move at all -> pass ------------------
{
  out="$(make_repo "stable-refs")"
  repo="$(repo_of "$out")"
  container="$(container_of "$out")"
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" branch "task/DP-999-T1-impl" "$head_sha"

  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# verify\n' > "$container/verification/V1/verify-report.md"

  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "regression: stable task/* refs + in-scope artifact passes"
  else
    record_fail "regression: stable refs falsely blocked"
  fi
}

if [[ "$fail" -ne 0 ]]; then
  echo "skill-workflow-boundary-ref-shift selftest: $pass pass, $fail fail" >&2
  exit 1
fi
echo "skill-workflow-boundary-ref-shift selftest: $pass pass, $fail fail"
