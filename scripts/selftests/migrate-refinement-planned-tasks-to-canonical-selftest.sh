#!/usr/bin/env bash
# Purpose: DP-296 T1 selftest for scripts/migrate-refinement-planned-tasks-to-canonical.sh.
# Inputs:  none (builds synthetic refinement.json fixtures under a tmpdir).
# Outputs: stdout PASS/FAIL lines; exit 0 when every case passes, 1 otherwise.
# Side effects: creates and removes a tmpdir; never touches the live specs tree.
#
# Cases (cover AC1 / AC6 / AC7 / AC-NEG1 / AC-NEG2):
#   1. fold      — planned_tasks[] entry folds into the matching tasks[] entry
#                  (task_shape/tracked_deliverable_hint copied verbatim) and the
#                  top-level planned_tasks[] is deleted (AC1/AC6).
#   2. defaults  — planned_tasks[] entry missing task_shape / tracked_deliverable_hint
#                  defaults to implementation / tracked when folded (AC1).
#   3. fullid    — planned_tasks[].task_id in full form (DP-NNN-T4) folds into the
#                  short-form tasks[].id (T4) (AC1).
#   4. fail-loud — planned_tasks[] entry with NO matching tasks[] entry exits
#                  non-zero and leaves the file unchanged (AC-NEG1).
#   5. no-op     — a file already canonical (no planned_tasks[]) is a clean no-op,
#                  byte-identical after the run (AC7 idempotent).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/migrate-refinement-planned-tasks-to-canonical.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: migration script missing: $SCRIPT" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

note_pass() { echo "PASS: $1"; pass=$((pass + 1)); }
note_fail() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

# field <file> <python-expression-returning-value> — prints the value or empty.
jget() {
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
expr = sys.argv[2]
print(eval(expr, {"d": d}))
PY
}

# ------------------------------------------------------------------
# Case 1: fold + delete planned_tasks[].
# ------------------------------------------------------------------
case1="$tmpdir/case1.json"
cat >"$case1" <<'JSON'
{
  "schema_version": "1.0",
  "source": { "type": "dp", "id": "DP-900" },
  "planned_tasks": [
    { "task_id": "T1", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" }
  ],
  "tasks": [
    { "id": "T1", "kind": "T", "title": "x" }
  ]
}
JSON
if bash "$SCRIPT" "$case1" >/dev/null 2>&1; then
  has_pt="$(jget "$case1" "'planned_tasks' in d")"
  shape="$(jget "$case1" "d['tasks'][0].get('task_shape')")"
  hint="$(jget "$case1" "d['tasks'][0].get('tracked_deliverable_hint')")"
  if [[ "$has_pt" == "False" && "$shape" == "confirmation" && "$hint" == "specs_only" ]]; then
    note_pass "case1 fold: planned_tasks deleted, tasks[0] folded (shape=$shape hint=$hint)"
  else
    note_fail "case1 fold: has_pt=$has_pt shape=$shape hint=$hint"
  fi
else
  note_fail "case1 fold: migration exited non-zero"
fi

# ------------------------------------------------------------------
# Case 2: missing fields default to implementation / tracked.
# ------------------------------------------------------------------
case2="$tmpdir/case2.json"
cat >"$case2" <<'JSON'
{
  "schema_version": "1.0",
  "source": { "type": "dp", "id": "DP-901" },
  "planned_tasks": [
    { "task_id": "T1" }
  ],
  "tasks": [
    { "id": "T1", "kind": "T", "title": "x" }
  ]
}
JSON
if bash "$SCRIPT" "$case2" >/dev/null 2>&1; then
  shape="$(jget "$case2" "d['tasks'][0].get('task_shape')")"
  hint="$(jget "$case2" "d['tasks'][0].get('tracked_deliverable_hint')")"
  has_pt="$(jget "$case2" "'planned_tasks' in d")"
  if [[ "$has_pt" == "False" && "$shape" == "implementation" && "$hint" == "tracked" ]]; then
    note_pass "case2 defaults: shape=$shape hint=$hint"
  else
    note_fail "case2 defaults: has_pt=$has_pt shape=$shape hint=$hint"
  fi
else
  note_fail "case2 defaults: migration exited non-zero"
fi

# ------------------------------------------------------------------
# Case 3: full-form planned task_id folds into short-form tasks[].id.
# ------------------------------------------------------------------
case3="$tmpdir/case3.json"
cat >"$case3" <<'JSON'
{
  "schema_version": "1.0",
  "source": { "type": "dp", "id": "DP-902" },
  "planned_tasks": [
    { "task_id": "DP-902-T4", "task_shape": "confirmation", "tracked_deliverable_hint": "specs_only" }
  ],
  "tasks": [
    { "id": "T4", "kind": "T", "title": "x" }
  ]
}
JSON
if bash "$SCRIPT" "$case3" >/dev/null 2>&1; then
  shape="$(jget "$case3" "d['tasks'][0].get('task_shape')")"
  hint="$(jget "$case3" "d['tasks'][0].get('tracked_deliverable_hint')")"
  if [[ "$shape" == "confirmation" && "$hint" == "specs_only" ]]; then
    note_pass "case3 fullid: DP-902-T4 folded into short T4 (shape=$shape hint=$hint)"
  else
    note_fail "case3 fullid: shape=$shape hint=$hint"
  fi
else
  note_fail "case3 fullid: migration exited non-zero"
fi

# ------------------------------------------------------------------
# Case 4: planned task with no matching tasks[] entry -> fail-loud, no write.
# ------------------------------------------------------------------
case4="$tmpdir/case4.json"
cat >"$case4" <<'JSON'
{
  "schema_version": "1.0",
  "source": { "type": "dp", "id": "DP-903" },
  "planned_tasks": [
    { "task_id": "T9", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ],
  "tasks": [
    { "id": "T1", "kind": "T", "title": "x" }
  ]
}
JSON
before_hash="$(shasum "$case4" | cut -d' ' -f1)"
if bash "$SCRIPT" "$case4" >/dev/null 2>&1; then
  note_fail "case4 fail-loud: migration unexpectedly exited 0 for orphan planned task"
else
  after_hash="$(shasum "$case4" | cut -d' ' -f1)"
  if [[ "$before_hash" == "$after_hash" ]]; then
    note_pass "case4 fail-loud: non-zero exit, file unchanged"
  else
    note_fail "case4 fail-loud: file mutated despite fail-loud exit"
  fi
fi

# ------------------------------------------------------------------
# Case 5: already-canonical file (no planned_tasks[]) -> clean no-op.
# ------------------------------------------------------------------
case5="$tmpdir/case5.json"
cat >"$case5" <<'JSON'
{
  "schema_version": "1.0",
  "source": { "type": "dp", "id": "DP-904" },
  "tasks": [
    { "id": "T1", "kind": "T", "title": "x", "task_shape": "implementation", "tracked_deliverable_hint": "tracked" }
  ]
}
JSON
before_hash="$(shasum "$case5" | cut -d' ' -f1)"
if bash "$SCRIPT" "$case5" >/dev/null 2>&1; then
  after_hash="$(shasum "$case5" | cut -d' ' -f1)"
  if [[ "$before_hash" == "$after_hash" ]]; then
    note_pass "case5 no-op: already-canonical file byte-identical"
  else
    note_fail "case5 no-op: file mutated (expected byte-identical no-op)"
  fi
else
  note_fail "case5 no-op: migration exited non-zero on canonical file"
fi

echo "----"
echo "selftest summary: pass=$pass fail=$fail"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
echo "PASS: migrate-refinement-planned-tasks-to-canonical-selftest"
