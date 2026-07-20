#!/usr/bin/env bash
# Selftest for scripts/skill-workflow-boundary-gate.sh
#
# Coverage matrix (per AC40 / AC-NEG16):
#   - 4 skills × {scope-only pass | out-of-scope fail | pre-existing dirty
#     baseline carve-out}
#   - /auto-pass orchestrator cross-skill transition fixture (refinement
#     baseline + breakdown baseline coexist independently)
#   - bypass env (POLARIS_LANGUAGE_POLICY_BYPASS, POLARIS_SKILL_BOUNDARY_BYPASS)
#     must NOT silence the gate (AC-NEG16)

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

run_gate() {
  # Print exit code on stdout (line 1), stderr capture follows on stdout
  # so the caller can assert on both. Returns the gate's exit code via $?.
  local out err rc
  out="$tmp_root/.out"
  err="$tmp_root/.err"
  set +e
  "$gate" "$@" >"$out" 2>"$err"
  rc=$?
  set -e
  printf '%s\n' "$rc"
  cat "$out"
  printf '\n--STDERR--\n'
  cat "$err"
}

# Build an isolated repo + DP-backed container.
make_repo() {
  local label="$1"
  local repo="$tmp_root/repo-$label"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@local
  git -C "$repo" config user.name selftest

  local container="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-skill-boundary-fixture"
  mkdir -p "$container"
  mkdir -p "$container/artifacts"
  mkdir -p "$container/jira-comments"
  mkdir -p "$container/refinement-inbox"
  mkdir -p "$container/tasks/T1"
  mkdir -p "$container/tasks/V1"
  mkdir -p "$container/verification/V1"
  printf '# DP-999\n' > "$container/refinement.md"
  printf '{}\n' > "$container/refinement.json"
  printf '# DP-999 index\n' > "$container/index.md"
  printf '# T1: boundary fixture (1 pt)\n> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: fixture\n## Allowed Files\n- `src/foo.py`\n- `scripts/bar.sh`\n' > "$container/tasks/T1/index.md"
  printf '# V1\n' > "$container/tasks/V1/index.md"
  mkdir -p "$repo/src" "$repo/scripts" "$repo/other" "$repo/.changeset"
  printf '{"$schema":"https://unpkg.com/@changesets/config@3.1.1/schema.json"}\n' > "$repo/.changeset/config.json"
  printf '# repo\n' > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "init"

  printf '%s\n%s\n' "$repo" "$container"
}

# ---- 1. refinement: scope-only pass -----------------------------------------
{
  out="$(make_repo "refn-pass")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# updated\n' > "$container/refinement.md"
  printf '{"x":1}\n' > "$container/refinement.json"
  printf '# new artifact\n' > "$container/artifacts/note.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill refinement --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "refinement scope-only pass"
  else
    record_fail "refinement scope-only pass"
  fi
}

# ---- 2. refinement: out-of-scope fail ---------------------------------------
{
  out="$(make_repo "refn-fail")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# updated\n' > "$container/refinement.md"
  printf 'x\n' > "$repo/src/forbidden.py"           # out of refinement scope
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill refinement --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement' <<< "$err_out"; then
    record_pass "refinement out-of-scope fail (exit 1 + stderr marker)"
  else
    record_fail "refinement out-of-scope fail (rc=$rc, err=$err_out)"
  fi
}

# ---- 3. refinement: pre-existing dirty baseline carve-out -------------------
{
  out="$(make_repo "refn-carve")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  # Dirty file before --start, outside refinement scope
  printf 'pre-existing\n' > "$repo/src/legacy.py"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null
  # Refinement-owned change
  printf '# updated\n' > "$container/refinement.md"
  # Pre-existing dirty file remains dirty — should be carved out
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill refinement --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "refinement pre-existing dirty baseline carve-out"
  else
    record_fail "refinement pre-existing dirty baseline carve-out"
  fi
}

# ---- 4. breakdown: scope-only pass ------------------------------------------
{
  out="$(make_repo "brk-pass")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill breakdown --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# updated T1\n## Allowed Files\n- `src/foo.py`\n' > "$container/tasks/T1/index.md"
  mkdir -p "$container/tasks/T2"
  printf '# new T2\n## Allowed Files\n' > "$container/tasks/T2/index.md"
  printf '# inbox\n' > "$container/refinement-inbox/2026-05-25-issue.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "breakdown scope-only pass"
  else
    record_fail "breakdown scope-only pass"
  fi
}

# ---- 5. breakdown: out-of-scope fail ----------------------------------------
{
  out="$(make_repo "brk-fail")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill breakdown --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# updated\n' > "$container/refinement.md"   # refinement-owned, not breakdown
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:breakdown' <<< "$err_out"; then
    record_pass "breakdown out-of-scope fail"
  else
    record_fail "breakdown out-of-scope fail (rc=$rc, err=$err_out)"
  fi
}

# ---- 6. breakdown: pre-existing dirty baseline carve-out --------------------
{
  out="$(make_repo "brk-carve")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  printf 'stale\n' > "$repo/other/scratch.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill breakdown --start --source-container "$container" --repo "$repo" >/dev/null
  mkdir -p "$container/tasks/T2"
  printf '# new T2\n## Allowed Files\n' > "$container/tasks/T2/index.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "breakdown pre-existing dirty baseline carve-out"
  else
    record_fail "breakdown pre-existing dirty baseline carve-out"
  fi
}

# ---- 7. engineering: scope-only pass ----------------------------------------
{
  out="$(make_repo "eng-pass")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf 'foo\n' > "$repo/src/foo.py"
  printf '#!/bin/bash\n' > "$repo/scripts/bar.sh"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null 2>&1; then
    record_pass "engineering scope-only pass (Allowed Files)"
  else
    record_fail "engineering scope-only pass (Allowed Files)"
  fi
}

# ---- 7a. engineering: canonical producer-owned changeset pass ---------------
{
  out="$(make_repo "eng-changeset-pass")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf '%s\n' '---' > "$repo/.changeset/dp-999-t1-boundary-fixture.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null 2>&1; then
    record_pass "engineering canonical changeset pass"
  else
    record_fail "engineering canonical changeset pass"
  fi
}

# ---- 7b. engineering: arbitrary changeset remains blocked ------------------
{
  out="$(make_repo "eng-changeset-fail")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf '%s\n' '---' > "$repo/.changeset/arbitrary.md"
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q '.changeset/arbitrary.md' <<< "$err_out"; then
    record_pass "engineering arbitrary changeset blocked"
  else
    record_fail "engineering arbitrary changeset blocked (rc=$rc, err=$err_out)"
  fi
}

# ---- 7c. engineering: wildcard task identity fails closed -------------------
{
  out="$(make_repo "eng-changeset-wildcard")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  sed 's/DP-999-T1/*/g' "$task_md" > "$task_md.wildcard"
  task_md="$task_md.wildcard"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf '%s\n' '---' > "$repo/.changeset/anything-boundary-fixture.md"
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 2 ]] && grep -q 'failed to derive canonical changeset path' <<< "$err_out"; then
    record_pass "engineering wildcard task identity fails closed"
  else
    record_fail "engineering wildcard task identity fails closed (rc=$rc, err=$err_out)"
  fi
}

# ---- 8. engineering: out-of-scope fail --------------------------------------
{
  out="$(make_repo "eng-fail")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf 'foo\n' > "$repo/src/foo.py"
  printf 'x\n' > "$repo/other/not-allowed.txt"   # outside Allowed Files
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:engineering' <<< "$err_out"; then
    record_pass "engineering out-of-scope fail"
  else
    record_fail "engineering out-of-scope fail (rc=$rc, err=$err_out)"
  fi
}

# ---- 9. engineering: pre-existing dirty baseline carve-out ------------------
{
  out="$(make_repo "eng-carve")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  printf 'wip\n' > "$repo/other/pre-dirty.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf 'foo\n' > "$repo/src/foo.py"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null 2>&1; then
    record_pass "engineering pre-existing dirty baseline carve-out"
  else
    record_fail "engineering pre-existing dirty baseline carve-out"
  fi
}

# ---- 10. verify-AC: scope-only pass -----------------------------------------
{
  out="$(make_repo "vac-pass")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# verify\n' > "$container/verification/V1/verify-report.md"
  printf '{}\n' > "$container/verification/V1/links.json"
  printf '# V1 update\n' > "$container/tasks/V1/index.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "verify-AC scope-only pass"
  else
    record_fail "verify-AC scope-only pass"
  fi
}

# ---- 11. verify-AC: out-of-scope fail ---------------------------------------
{
  out="$(make_repo "vac-fail")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# verify\n' > "$container/verification/V1/verify-report.md"
  printf 'x\n' > "$repo/scripts/bar.sh"     # outside verify-AC scope
  set +e
  err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:verify-AC' <<< "$err_out"; then
    record_pass "verify-AC out-of-scope fail"
  else
    record_fail "verify-AC out-of-scope fail (rc=$rc, err=$err_out)"
  fi
}

# ---- 12. verify-AC: pre-existing dirty baseline carve-out -------------------
{
  out="$(make_repo "vac-carve")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  printf 'wip\n' > "$repo/scripts/bar.sh"     # pre-existing dirty outside scope
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# verify\n' > "$container/verification/V1/verify-report.md"
  if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
       "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_pass "verify-AC pre-existing dirty baseline carve-out"
  else
    record_fail "verify-AC pre-existing dirty baseline carve-out"
  fi
}

# ---- 13. AC-NEG16: bypass env must NOT silence the gate ---------------------
{
  out="$(make_repo "ac-neg16-lp")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null
  printf 'x\n' > "$repo/src/forbidden.py"
  set +e
  err_out="$(POLARIS_LANGUAGE_POLICY_BYPASS=1 \
              POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill refinement --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:refinement' <<< "$err_out"; then
    record_pass "AC-NEG16: POLARIS_LANGUAGE_POLICY_BYPASS ignored (refinement)"
  else
    record_fail "AC-NEG16: POLARIS_LANGUAGE_POLICY_BYPASS bypass (rc=$rc, err=$err_out)"
  fi
}
{
  out="$(make_repo "ac-neg16-sb")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill breakdown --start --source-container "$container" --repo "$repo" >/dev/null
  printf 'x\n' > "$repo/src/forbidden.py"
  set +e
  err_out="$(POLARIS_SKILL_BOUNDARY_BYPASS=1 \
              POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:breakdown' <<< "$err_out"; then
    record_pass "AC-NEG16: POLARIS_SKILL_BOUNDARY_BYPASS ignored (breakdown)"
  else
    record_fail "AC-NEG16: POLARIS_SKILL_BOUNDARY_BYPASS bypass (rc=$rc, err=$err_out)"
  fi
}
{
  out="$(make_repo "ac-neg16-eng")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  task_md="$container/tasks/T1/index.md"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill engineering --start --source-container "$container" --repo "$repo" --task-md "$task_md" >/dev/null
  printf 'x\n' > "$repo/other/not-allowed.txt"
  set +e
  err_out="$(POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 \
              POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill engineering --check --source-container "$container" --repo "$repo" --task-md "$task_md" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:engineering' <<< "$err_out"; then
    record_pass "AC-NEG16: bypass envs ignored (engineering)"
  else
    record_fail "AC-NEG16: bypass envs (engineering) (rc=$rc, err=$err_out)"
  fi
}
{
  out="$(make_repo "ac-neg16-vac")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill verify-AC --start --source-container "$container" --repo "$repo" >/dev/null
  printf 'x\n' > "$repo/scripts/bar.sh"
  set +e
  err_out="$(POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 \
              POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
              "$gate" --skill verify-AC --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:verify-AC' <<< "$err_out"; then
    record_pass "AC-NEG16: bypass envs ignored (verify-AC)"
  else
    record_fail "AC-NEG16: bypass envs (verify-AC) (rc=$rc, err=$err_out)"
  fi
}

# ---- 14. /auto-pass orchestrator cross-skill transition fixture -------------
# refinement baseline must coexist with a fresh breakdown baseline so the
# orchestrator can dispatch refinement -> breakdown without poisoning each
# skill's own scope view.
{
  out="$(make_repo "autopass-xfer")"
  repo="$(printf '%s\n' "$out" | sed -n '1p')"
  container="$(printf '%s\n' "$out" | sed -n '2p')"

  # Stage refinement session
  POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
    "$gate" --skill refinement --start --source-container "$container" --repo "$repo" >/dev/null
  printf '# refn\n' > "$container/refinement.md"

  # Commit refinement output between transitions
  git -C "$repo" add -A
  git -C "$repo" -c commit.gpgsign=false commit -q -m "refinement update"

  # Refinement check should still pass (only refinement.md changed)
  if ! POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
         "$gate" --skill refinement --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
    record_fail "auto-pass xfer: refinement check (before transition)"
  else
    # Now /auto-pass transitions to breakdown; start a fresh breakdown baseline
    POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
      "$gate" --skill breakdown --start --source-container "$container" --repo "$repo" >/dev/null
    # breakdown phase writes a new task
    mkdir -p "$container/tasks/T9"
    printf '# T9\n## Allowed Files\n' > "$container/tasks/T9/index.md"
    if POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
         "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" >/dev/null 2>&1; then
      # Negative: if breakdown ALSO touches refinement.md, it should fail
      printf '# illegal cross-write\n' > "$container/refinement.md"
      set +e
      err_out="$(POLARIS_RUNTIME_DIR="$repo/.polaris/runtime" \
                  "$gate" --skill breakdown --check --source-container "$container" --repo "$repo" 2>&1 1>/dev/null)"
      rc=$?
      set -e
      if [[ "$rc" -eq 1 ]] && grep -q 'POLARIS_SKILL_WORKFLOW_BOUNDARY_BLOCKED:breakdown' <<< "$err_out"; then
        record_pass "auto-pass cross-skill transition (refinement -> breakdown, breakdown writes refn = fail)"
      else
        record_fail "auto-pass cross-skill transition (breakdown writes refn should fail; rc=$rc, err=$err_out)"
      fi
    else
      record_fail "auto-pass xfer: breakdown check (legit write)"
    fi
  fi
}

if [[ "$fail" -ne 0 ]]; then
  echo "skill-workflow-boundary-gate selftest: $pass pass, $fail fail" >&2
  exit 1
fi
echo "skill-workflow-boundary-gate selftest: $pass pass, $fail fail"
