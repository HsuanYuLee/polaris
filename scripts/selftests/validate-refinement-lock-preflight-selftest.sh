#!/usr/bin/env bash
# Purpose: Selftest for validate-refinement-lock-preflight.sh (DP-262 T4 / DP-369 T2).
#          DP-369 T2 reworks the preflight to FULL-DERIVE the real task.md per
#          planned task via derive-task-md-from-refinement-json.sh, then run the
#          real validate-breakdown-ready.sh against each derived task.md (no more
#          hardcoded-clean placeholder). This selftest therefore drives full
#          canonical refinement.json fixtures and asserts:
#            - AC3: a planned runtime task with a PROSE env_bootstrap value makes
#                   the preflight fail-stop (exit 2) — the real env_bootstrap value
#                   is now validated (T1's env_bootstrap executability gate), not
#                   shadowed by a hardcoded `echo bootstrap`.
#            - AC4: a planned runtime task with a LEGAL pipe-free missing-binary
#                   env_bootstrap chain PASSes (no false-FAIL on absent host bins).
#            - AC-NF1: the preflight reuses derive-task-md-from-refinement-json.sh
#                   (full-derive) + validate-breakdown-ready.sh; no second
#                   synthesis / validation path lives in it (the hardcoded
#                   write_placeholder_task body is removed).
#            - AC-NEG2: the DP-262 carve-out (confirmation/audit specs-only legal,
#                   implementation specs-only illegal) and DP-274 delivery-unit
#                   shape gate (research-unit / dispatch-theme illegal) keep their
#                   behavior under full-derive; the legacy ok/bad/empty smoke is
#                   upgraded to full canonical tasks[].
# Inputs:  none (builds tmpdir refinement.json fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$ROOT_DIR/scripts/validate-refinement-lock-preflight.sh"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

tmpdir="$(mktemp -d -t validate-refinement-lock-preflight-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Runtime fixture probe host: a non-8080 local port so validate-task-md treats it
# as a generic runtime target (not the docs-manager viewer). Target host and the
# Verify Command host must match (DP-023). The host:port is a fixture constant.
RUNTIME_PROBE_URL="http://127.0.0.1:9999/dp369-lock-preflight-probe"

# run_preflight <label> <fixture.json> -> captures exit code into $LAST_RC, stderr
# into $tmpdir/<label>.err
LAST_RC=0
run_preflight() {
  local label="$1"
  local fixture="$2"
  set +e
  bash "$PREFLIGHT" "$fixture" >/dev/null 2>"$tmpdir/$label.err"
  LAST_RC=$?
  set -e
}

expect_pass() {
  local label="$1"
  local fixture="$2"
  run_preflight "$label" "$fixture"
  if [[ "$LAST_RC" -ne 0 ]]; then
    echo "FAIL: expected preflight PASS (exit 0) for $label, got $LAST_RC"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

expect_exit2_contains() {
  local label="$1"
  local fixture="$2"
  local pattern="$3"
  run_preflight "$label" "$fixture"
  if [[ "$LAST_RC" -ne 2 ]]; then
    echo "FAIL: expected preflight exit 2 for $label, got $LAST_RC"
    cat "$tmpdir/$label.err"
    exit 1
  fi
  if ! grep -q "$pattern" "$tmpdir/$label.err"; then
    echo "FAIL: expected '$pattern' in stderr for $label"
    cat "$tmpdir/$label.err"
    exit 1
  fi
}

# canonical_impl_task — emit a fully-derivable implementation T-task object (with
# behavior_contract + test_environment so derive takes the field-driven path).
# Args: $1=id $2=title $3=level $4=env_bootstrap $5=runtime_target $6=verify_command
canonical_impl_task() {
  local id="$1" title="$2" level="$3" bootstrap="$4" runtime_target="$5" verify_command="$6"
  cat <<JSON
    {
      "id": "${id}",
      "kind": "implementation",
      "title": "${title}",
      "scope": "DP-369 lock-preflight full-derive fixture for ${id}",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/${id}-dp369-fixture.sh"],
      "modules": ["scripts/${id}-dp369-fixture.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "${verify_command}",
        "behavior_contract": { "applies": false, "reason": "framework lock-preflight full-derive fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "${level}", "runtime_verify_target": "${runtime_target}", "env_bootstrap_command": "${bootstrap}" },
        "verify_command": "${verify_command}",
        "references": []
      }
    }
JSON
}

# canonical_specs_only_task — emit a fully-derivable confirmation/audit specs-only
# task object (DP-262 carve-out). These plan a specs-only deliverable and pass.
# Args: $1=id $2=shape (confirmation|audit)
canonical_specs_only_task() {
  local id="$1" shape="$2"
  cat <<JSON
    {
      "id": "${id}",
      "kind": "${shape}",
      "title": "DP-369 specs-only carve-out fixture ${id}",
      "scope": "DP-369 lock-preflight specs-only carve-out fixture for ${id}",
      "task_shape": "${shape}",
      "tracked_deliverable_hint": "specs_only",
      "allowed_files": ["docs-manager/src/content/docs/specs/design-plans/DP-262-example/index.md"],
      "modules": [],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "framework specs-only carve-out fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      }
    }
JSON
}

# ---------------------------------------------------------------------------
# AC4 — a fully-legal, fully-derivable refinement.json (a runtime task with a
# legal missing-binary env_bootstrap chain + a specs-only confirmation carve-out
# task) PASSes. The runtime env_bootstrap references colima / docker-compose /
# pnpm which are absent from the gate host, but the smoke is a command-shape
# check, not a binary-existence check (AC2 family / DP-369), so it passes.
# ---------------------------------------------------------------------------
cat >"$tmpdir/legal-full-derive.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight full-derive" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T1" "DP-369 runtime task legal env bootstrap" "runtime" \
    "colima start; docker-compose up -d nginx; pkill -f 'b2c dev'; pnpm dev --port 3001" \
    "$RUNTIME_PROBE_URL" "curl -fsS $RUNTIME_PROBE_URL"),
$(canonical_specs_only_task "T2" "confirmation")
  ]
}
JSON
expect_pass "legal-full-derive-runtime-and-carveout" "$tmpdir/legal-full-derive.json"

# ---------------------------------------------------------------------------
# AC3 — a planned runtime task whose env_bootstrap is PROSE (the DEMO-646 original
# value, CJK prose with no parseable command) makes the preflight fail-stop
# (exit 2). With the old hardcoded-clean placeholder (te_bootstrap="echo
# bootstrap") this prose value was never validated; full-derive emits the REAL
# prose into the task.md so T1's env_bootstrap executability gate catches it.
# ---------------------------------------------------------------------------
cat >"$tmpdir/prose-env-bootstrap.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight prose env bootstrap" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T1" "DP-369 runtime task prose env bootstrap" "runtime" \
    "啟動 app.example.test 三層 stack 並把 dev server 釘在 3001" \
    "$RUNTIME_PROBE_URL" "curl -fsS $RUNTIME_PROBE_URL")
  ]
}
JSON
expect_exit2_contains "prose-env-bootstrap-runtime" "$tmpdir/prose-env-bootstrap.json" \
  "POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED"

# ---------------------------------------------------------------------------
# AC-NEG2 — the upgraded legal/illegal/empty smoke uses full canonical tasks[].
#
# Legal: confirmation/audit specs-only + implementation tracked -> PASS.
# (The legacy minimal-field ok.json is upgraded to full canonical tasks so it is
# derivable; it must still PASS.)
# ---------------------------------------------------------------------------
cat >"$tmpdir/ok.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-262", "base_branch": "feat/DP-262" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight ok" } ],
  "modules": [],
  "tasks": [
$(canonical_specs_only_task "T1" "confirmation"),
$(canonical_specs_only_task "T2" "audit"),
$(canonical_impl_task "T3" "DP-262 implementation tracked task" "static" "N/A" "N/A" "echo PASS")
  ]
}
JSON
expect_pass "ok-canonical-tasks" "$tmpdir/ok.json"

# DP-386 bootstrap — multiline verify_command stays breakdown-ready after the
# full-derive lock preflight path. This guards the producer-generated task.md
# shape that previously broke Gate Closure Matrix parsing.
cat >"$tmpdir/multiline-verify-command.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-386", "base_branch": "feat/DP-386" },
  "acceptance_criteria": [ { "id": "AC10", "text": "multiline verify command remains derivable" } ],
  "modules": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "DP-386 multiline verify command",
      "scope": "DP-386 lock-preflight multiline verify command fixture",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/derive-task-md-from-refinement-json.sh"],
      "modules": ["scripts/derive-task-md-from-refinement-json.sh"],
      "ac_ids": ["AC10"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "multiline verify command fixture",
        "behavior_contract": { "applies": false, "reason": "framework lock-preflight fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static", "runtime_verify_target": "N/A", "env_bootstrap_command": "N/A" },
        "verify_command": "echo PASS\nprintf '%s\\n' PASS",
        "references": []
      }
    }
  ]
}
JSON
expect_pass "multiline-verify-command" "$tmpdir/multiline-verify-command.json"

# Illegal (full-derive-reproducible) — a runtime implementation task whose
# Env bootstrap command is PROSE fail-stops, naming the offending task. Under
# full-derive this is the realistic illegitimate-implementation signal (the
# real env_bootstrap value reaches the task.md and T1's executability gate
# rejects it). Changeset policy is repo-native and does not alter Allowed Files.
cat >"$tmpdir/bad-prose-named.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight bad named" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T9" "DP-369 runtime task prose env bootstrap named" "runtime" \
    "啟動 app.example.test 三層 stack 並把 dev server 釘在 3001" \
    "$RUNTIME_PROBE_URL" "curl -fsS $RUNTIME_PROBE_URL")
  ]
}
JSON
expect_exit2_contains "implementation-prose-named" "$tmpdir/bad-prose-named.json" \
  "task 'T9'"

# A mixed batch where only one task is illegal still fails (exit 2) and names the
# offending one. The legal sibling is a confirmation specs-only carve-out task;
# the illegal one is a runtime task with prose env_bootstrap.
cat >"$tmpdir/mixed.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "acceptance_criteria": [ { "id": "AC1", "text": "lock preflight mixed" } ],
  "modules": [],
  "tasks": [
$(canonical_specs_only_task "T1" "confirmation"),
$(canonical_impl_task "T2" "DP-369 runtime task prose env bootstrap mixed" "runtime" \
    "啟動 app.example.test 三層 stack 並把 dev server 釘在 3001" \
    "$RUNTIME_PROBE_URL" "curl -fsS $RUNTIME_PROBE_URL")
  ]
}
JSON
expect_exit2_contains "mixed-batch" "$tmpdir/mixed.json" "task 'T2'"

# Zero migration shim — refinement.json without tasks[] is a no-op PASS.
cat >"$tmpdir/no-tasks.json" <<'JSON'
{ "source": { "type": "dp", "id": "DP-262", "base_branch": "feat/DP-262" } }
JSON
expect_pass "no-tasks" "$tmpdir/no-tasks.json"

# ---------------------------------------------------------------------------
# AC-NEG2 (DP-274 delivery-unit shape gate parity under full-derive) — a source
# whose only tasks are audit (研究單) or confirmation-only (轉發/theme 單), with no
# implementation task, still fail-stops at LOCK time via the directory-mode
# delivery-unit shape gate that validate-breakdown-ready owns.
# ---------------------------------------------------------------------------
cat >"$tmpdir/research-unit.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-274", "base_branch": "feat/DP-274" },
  "acceptance_criteria": [ { "id": "AC1", "text": "research unit" } ],
  "modules": [],
  "tasks": [
$(canonical_specs_only_task "T1" "audit"),
$(canonical_specs_only_task "T2" "audit")
  ]
}
JSON
expect_exit2_contains "research-unit" "$tmpdir/research-unit.json" \
  "POLARIS_RESEARCH_UNIT_NO_IMPLEMENTATION"

cat >"$tmpdir/dispatch-theme-unit.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-274", "base_branch": "feat/DP-274" },
  "acceptance_criteria": [ { "id": "AC1", "text": "dispatch theme unit" } ],
  "modules": [],
  "tasks": [
$(canonical_specs_only_task "T1" "confirmation"),
$(canonical_specs_only_task "T2" "audit")
  ]
}
JSON
expect_exit2_contains "dispatch-theme-unit" "$tmpdir/dispatch-theme-unit.json" \
  "POLARIS_DISPATCH_THEME_UNIT_NO_IMPLEMENTATION"

# ---------------------------------------------------------------------------
# AC-NEG2 — refinement.json missing per-task body fields makes derive fail-loud,
# and the preflight surfaces it as a fail-stop (an incomplete spec must not pass
# LOCK). A minimal task (only id + task_shape + hint, the OLD placeholder fixture
# shape) is no longer derivable, so the preflight must NOT silently pass it.
# ---------------------------------------------------------------------------
cat >"$tmpdir/incomplete-task.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-369", "base_branch": "feat/DP-369" },
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
run_preflight "incomplete-task" "$tmpdir/incomplete-task.json"
if [[ "$LAST_RC" -eq 0 ]]; then
  echo "FAIL: incomplete (non-derivable) task.json must not PASS LOCK; got exit 0"
  cat "$tmpdir/incomplete-task.err"
  exit 1
fi

# ---------------------------------------------------------------------------
# AC-NF1 — the production preflight reuses derive-task-md-from-refinement-json.sh
# (full-derive) and validate-breakdown-ready.sh; no second synthesis/validation
# path lives in it. Assert both canonical helpers are invoked and that the
# removed hardcoded placeholder body / executability copy is gone.
# ---------------------------------------------------------------------------
if ! grep -q 'derive-task-md-from-refinement-json.sh' "$PREFLIGHT"; then
  echo "FAIL [AC-NF1]: preflight no longer references the canonical derive bridge"
  exit 1
fi
if ! grep -q 'validate-breakdown-ready.sh' "$PREFLIGHT"; then
  echo "FAIL [AC-NF1]: preflight no longer references validate-breakdown-ready.sh"
  exit 1
fi
# The hardcoded-clean placeholder body writer is removed (no second synthesis path).
if grep -q 'write_placeholder_task' "$PREFLIGHT"; then
  echo "FAIL [AC-NF1]: preflight still contains the removed write_placeholder_task synthesis path"
  grep -n 'write_placeholder_task' "$PREFLIGHT"
  exit 1
fi
# No hardcoded env_bootstrap shadow (the old `te_bootstrap="echo bootstrap"`).
if grep -q 'echo bootstrap' "$PREFLIGHT"; then
  echo "FAIL [AC-NF1]: preflight still hardcodes an env_bootstrap value (shadows the real one)"
  grep -n 'echo bootstrap' "$PREFLIGHT"
  exit 1
fi

# DP-296 AC-NEG1 carry-over — the production preflight does not read the removed
# top-level planned_tasks[] key (canonical tasks[] is the sole shape source).
if grep -q 'planned_tasks' "$PREFLIGHT"; then
  echo "FAIL [DP-296 AC-NEG1]: production preflight still references the removed planned_tasks[] key"
  grep -n 'planned_tasks' "$PREFLIGHT"
  exit 1
fi

# ---------------------------------------------------------------------------
# AC-NEG2 (DP-316 single level projection parity) — the derived task.md Level is
# projected through the SAME single canonical projection that
# derive-task-md-from-refinement-json.sh applies. An unknown refinement level
# fail-louds in the real derive; the preflight must likewise fail-stop (no silent
# fallback to static). Assert the real derive precondition then the preflight.
# ---------------------------------------------------------------------------
cat >"$tmpdir/unknown-level.json" <<JSON
{
  "source": { "type": "dp", "id": "DP-316", "base_branch": "feat/DP-316" },
  "acceptance_criteria": [ { "id": "AC1", "text": "unknown level" } ],
  "modules": [],
  "tasks": [
$(canonical_impl_task "T1" "DP-316 unknown level task" "bogus" "N/A" "N/A" "echo PASS")
  ]
}
JSON
set +e
bash "$DERIVE" --refinement-json "$tmpdir/unknown-level.json" --task-id "DP-316-T1" \
  >/dev/null 2>"$tmpdir/unknown-derive.err"
derive_rc=$?
set -e
if [[ "$derive_rc" -eq 0 ]]; then
  echo "FAIL [DP-316 parity]: real derive unexpectedly accepted unknown level (precondition broken)"
  exit 1
fi
run_preflight "unknown-level" "$tmpdir/unknown-level.json"
if [[ "$LAST_RC" -eq 0 ]]; then
  echo "FAIL [DP-316 parity]: preflight PASSed an unknown level; must fail-stop like real derive"
  cat "$tmpdir/unknown-level.err"
  exit 1
fi

# Embedded smoke test must also pass.
if ! bash "$PREFLIGHT" --self-test >/dev/null 2>"$tmpdir/embedded.err"; then
  echo "FAIL: embedded --self-test did not pass"
  cat "$tmpdir/embedded.err"
  exit 1
fi

echo "PASS: validate-refinement-lock-preflight selftest"
