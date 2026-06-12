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

# ---------------------------------------------------------------------------
# DP-316 T2 / AC3 / AC4 — the placeholder synthesized by the preflight must
# carry the planned task's REAL test_environment.level, projected through the
# SAME projection that derive-task-md-from-refinement-json.sh applies (single
# source — no second mapping table). For each refinement.json level the
# placeholder Level must equal what the real derive emits for the same input.
#
# The preflight exposes a test-observability seam: when
# POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR points at a writable dir, the synthesized
# placeholders are kept there (instead of an auto-removed mktemp dir) so the
# selftest can read the placeholder Level line. This is the only way to assert
# parity deterministically without re-deriving the projection in the test.
# ---------------------------------------------------------------------------
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

# real_derive_level <refinement.json> <full-form-task-id> -> echoes derived Level
real_derive_level() {
  local fixture="$1"
  local full_id="$2"
  bash "$DERIVE" --refinement-json "$fixture" --task-id "$full_id" \
    | grep -E '^- \*\*Level\*\*:' | head -n 1 | sed -E 's/^- \*\*Level\*\*:[[:space:]]*//'
}

# placeholder_level <kept-tmpdir> <short-task-id> -> echoes placeholder Level
placeholder_level() {
  local kept="$1"
  local task_id="$2"
  grep -E '^- \*\*Level\*\*:' "$kept/$task_id/index.md" | head -n 1 \
    | sed -E 's/^- \*\*Level\*\*:[[:space:]]*//'
}

# A canonical full refinement.json (derive needs the full task schema). One
# implementation task per level so the same source drives both the real derive
# and the preflight placeholder. The level value is templated per case.
write_level_fixture() {
  local out="$1"
  local level="$2"
  cat >"$out" <<JSON
{
  "source": { "type": "dp", "id": "DP-316" },
  "acceptance_criteria": [ { "id": "AC1", "text": "level projection probe" } ],
  "tasks": [
    {
      "id": "T1",
      "kind": "T",
      "title": "level projection parity probe",
      "scope": "probe ${level} projection",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "allowed_files": ["scripts/T1-placeholder.sh"],
      "modules": ["scripts/T1-placeholder.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "probe",
        "behavior_contract": { "applies": false, "reason": "framework probe" },
        "test_environment": { "level": "${level}" },
        "verify_command": "echo PASS",
        "references": []
      }
    }
  ]
}
JSON
}

# AC3 / AC4 — for each mapped level, preflight placeholder Level == real derive Level.
for level in static component integration runtime; do
  fixture="$tmpdir/level-$level.json"
  write_level_fixture "$fixture" "$level"

  expected="$(real_derive_level "$fixture" "DP-316-T1")"
  if [[ -z "$expected" ]]; then
    echo "FAIL [AC4]: real derive produced no Level for input level=$level"
    exit 1
  fi

  kept="$tmpdir/kept-$level"
  mkdir -p "$kept"
  set +e
  POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR="$kept" \
    bash "$PREFLIGHT" "$fixture" >/dev/null 2>"$tmpdir/level-$level.err"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL [AC3]: preflight did not PASS for valid level=$level (exit $rc)"
    cat "$tmpdir/level-$level.err"
    exit 1
  fi

  actual="$(placeholder_level "$kept" "T1")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL [AC3/AC4]: level=$level placeholder Level='$actual' != real derive Level='$expected'"
    exit 1
  fi
done

# AC3 explicit many-to-one assertion: component and integration both project to
# build (not static, not runtime) — the false-PASS gap the hardcoded `static`
# placeholder used to hide.
for level in component integration; do
  fixture="$tmpdir/many2one-$level.json"
  write_level_fixture "$fixture" "$level"
  kept="$tmpdir/m2o-kept-$level"
  mkdir -p "$kept"
  POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR="$kept" \
    bash "$PREFLIGHT" "$fixture" >/dev/null 2>"$tmpdir/m2o-$level.err"
  actual="$(placeholder_level "$kept" "T1")"
  if [[ "$actual" != "build" ]]; then
    echo "FAIL [AC3]: level=$level placeholder Level='$actual', expected 'build' (no longer hardcoded static)"
    exit 1
  fi
done

# AC-NEG (parity) — an unknown level must make the preflight fail-stop, exactly
# as the real derive fail-louds; it must not silently fall back to static.
unknown_fixture="$tmpdir/level-unknown.json"
write_level_fixture "$unknown_fixture" "bogus"
set +e
bash "$DERIVE" --refinement-json "$unknown_fixture" --task-id "DP-316-T1" >/dev/null 2>"$tmpdir/unknown-derive.err"
derive_rc=$?
set -e
if [[ "$derive_rc" -eq 0 ]]; then
  echo "FAIL [AC-NEG parity]: real derive unexpectedly accepted unknown level (precondition broken)"
  exit 1
fi
set +e
bash "$PREFLIGHT" "$unknown_fixture" >/dev/null 2>"$tmpdir/unknown-preflight.err"
preflight_rc=$?
set -e
if [[ "$preflight_rc" -eq 0 ]]; then
  echo "FAIL [AC-NEG parity]: preflight PASSed an unknown level; must fail-stop like real derive"
  cat "$tmpdir/unknown-preflight.err"
  exit 1
fi

# A task that declares no test_environment.level keeps the static placeholder
# (backward compat with the pre-DP-316 fixtures above that omit the field).
no_level_fixture="$tmpdir/no-level.json"
cat >"$no_level_fixture" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-316" },
  "tasks": [
    { "id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
kept_nolevel="$tmpdir/kept-nolevel"
mkdir -p "$kept_nolevel"
POLARIS_LOCK_PREFLIGHT_KEEP_TMPDIR="$kept_nolevel" \
  bash "$PREFLIGHT" "$no_level_fixture" >/dev/null 2>"$tmpdir/no-level.err"
actual="$(placeholder_level "$kept_nolevel" "T1")"
if [[ "$actual" != "static" ]]; then
  echo "FAIL: level-less task placeholder Level='$actual', expected 'static' (backward compat)"
  exit 1
fi

# Embedded smoke test must also pass.
if ! bash "$PREFLIGHT" --self-test >/dev/null 2>"$tmpdir/embedded.err"; then
  echo "FAIL: embedded --self-test did not pass"
  cat "$tmpdir/embedded.err"
  exit 1
fi

echo "PASS: validate-refinement-lock-preflight selftest"
