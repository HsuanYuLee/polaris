#!/usr/bin/env bash
# Purpose: Selftest for validate-refinement-lock-preflight.sh (DP-262 T4).
#          Covers AC5 (legal planned tasks pass; the preflight delegates to the
#          real validate-breakdown-ready.sh) and AC-NEG3 (a planned
#          implementation task that declares a specs-only deliverable fail-stops
#          with exit 2 — the preflight is a real gate, not an advisory).
# Inputs:  none (builds tmpdir refinement.json fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$ROOT_DIR/scripts/validate-refinement-lock-preflight.sh"

tmpdir="$(mktemp -d -t validate-refinement-lock-preflight-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# run_preflight <fixture.json> -> captures exit code into $LAST_RC, stderr into
# $tmpdir/<label>.err
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

# ---------------------------------------------------------------------------
# DP-296 T3 / AC2 — the preflight reads canonical tasks[] (task_shape /
# tracked_deliverable_hint are first-class tasks[] fields, NOT a removed
# top-level shape array). All fixtures below use canonical tasks[].
#
# AC5 — legal tasks pass. confirmation/audit may plan specs-only deliverables;
# implementation may plan a tracked deliverable. The preflight delegates the
# verdict to validate-breakdown-ready.sh (no second classifier).
# ---------------------------------------------------------------------------

cat >"$tmpdir/legal.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T1", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" },
    { "id": "T2", "task_shape": "audit", "tracked_deliverable_hint": "specs_only" },
    { "id": "T3", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
expect_pass "legal-canonical-tasks" "$tmpdir/legal.json"

# AC2 — full-form tasks[].id (DP-NNN-Tn) must also resolve to the short work-item
# id and be read off canonical tasks[]. Mixed full/short ids in one source.
cat >"$tmpdir/legal-fullform-id.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "DP-262-T1", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" },
    { "id": "T2", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
expect_pass "legal-fullform-id" "$tmpdir/legal-fullform-id.json"

# AC5 default task_shape (missing field defaults to implementation) with a
# tracked deliverable is also legal.
cat >"$tmpdir/legal-default.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T1", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
expect_pass "legal-default-implementation-tracked" "$tmpdir/legal-default.json"

# ---------------------------------------------------------------------------
# AC-NEG3 — an implementation task that declares a specs-only deliverable must
# fail-stop (exit 2), naming the offending task. The preflight must not pass
# just because it runs as a dry-run.
# ---------------------------------------------------------------------------

cat >"$tmpdir/bad-impl-specs-only.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T9", "task_shape": "implementation", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
expect_exit2_contains "implementation-specs-only" "$tmpdir/bad-impl-specs-only.json" \
  "task 'T9'"

# AC-NEG3 default task_shape (missing field = implementation) + specs-only
# deliverable must also fail-stop.
cat >"$tmpdir/bad-default-specs-only.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T8", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
expect_exit2_contains "default-implementation-specs-only" "$tmpdir/bad-default-specs-only.json" \
  "POLARIS_REFINEMENT_LOCK_PREFLIGHT_FAILED"

# A mixed batch where only one task is illegal still fails (exit 2) and names the
# offending one.
cat >"$tmpdir/mixed.json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-262" },
  "tasks": [
    { "id": "T1", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" },
    { "id": "T2", "task_shape": "implementation", "tracked_deliverable_hint": "specs_only" }
  ]
}
JSON
expect_exit2_contains "mixed-batch" "$tmpdir/mixed.json" "task 'T2'"

# ---------------------------------------------------------------------------
# Zero migration shim — refinement.json without tasks[] is a no-op PASS.
# ---------------------------------------------------------------------------

cat >"$tmpdir/no-tasks.json" <<'JSON'
{ "source": { "type": "dp", "id": "DP-262" } }
JSON
expect_pass "no-tasks" "$tmpdir/no-tasks.json"

# ---------------------------------------------------------------------------
# DP-296 AC-NEG1 — the production preflight no longer reads the removed
# top-level shape array. Assert rg 'planned_tasks' has zero hits in the
# production script (canonical tasks[] is the sole shape source).
# ---------------------------------------------------------------------------
if grep -q 'planned_tasks' "$PREFLIGHT"; then
  echo "FAIL [AC-NEG1]: production preflight still references the removed planned_tasks[] key"
  grep -n 'planned_tasks' "$PREFLIGHT"
  exit 1
fi

# Embedded smoke test must also pass.
if ! bash "$PREFLIGHT" --self-test >/dev/null 2>"$tmpdir/embedded.err"; then
  echo "FAIL: embedded --self-test did not pass"
  cat "$tmpdir/embedded.err"
  exit 1
fi

echo "PASS: validate-refinement-lock-preflight selftest"
