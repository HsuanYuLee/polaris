#!/usr/bin/env bash
# Purpose: DP-296 T4 / AC3 selftest for validate-refinement-consumer-schema-binding.sh.
#   Exercises the schema-binding gate against hermetic fixture repos:
#     1. positive — declared consumers read only canonical-whitelist tasks[] fields → exit 0
#     2. negative — a declared consumer reads a schema-EXTERNAL field → exit 2 + marker
#     3. registration — an unregistered tasks[] consumer → exit 2 + marker
#     4. SoT-coupling — the whitelist is derived from the schema validator source, so
#        a field becomes legal only when the schema validator declares it (proves the
#        gate is NOT a static literal grep but binds to the canonical schema field set)
#     5. live-repo — the gate PASSes against the real workspace (AC7: no self-block)
# Inputs:  none (builds hermetic fixtures in a tmpdir).
# Outputs: PASS/FAIL lines per case; exit 0 if all pass, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/validate-refinement-consumer-schema-binding.sh"

if [[ ! -f "$GATE" ]]; then
  echo "FAIL: gate missing: $GATE" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_stderr_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label (stderr contains '$needle')"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (stderr missing '$needle')" >&2
    cat "$file" >&2
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Fixture builder. Writes a fake repo whose schema validator declares the given
# whitelist fields. The registered consumers mirror the real declared consumers
# (derive / lock-preflight / md-generator / module-ac-coverage). Optional extra
# arguments inject additional consumer files (path::body) so cases can add a
# schema-external read or an unregistered consumer.
# ---------------------------------------------------------------------------
build_fixture() {
  local fixdir="$1"; shift
  mkdir -p "$fixdir/scripts/lib"

  # Schema validator stub — the SINGLE SOURCE OF TRUTH for the whitelist. The gate
  # extracts `task_required = { ... }` plus every `if "X" in task:` field. The
  # canonical set here mirrors the real schema after DP-296 T2/T3.
  cat >"$fixdir/scripts/validate-refinement-json.sh" <<'EOF'
#!/usr/bin/env bash
: <<'PY'
    task_required = {
        "id",
        "kind",
        "title",
        "scope",
        "allowed_files",
        "modules",
        "ac_ids",
        "dependencies",
        "estimate_points",
        "verification",
    }
        if "task_shape" in task:
        if "tracked_deliverable_hint" in task:
        if "jira_key" in task:
PY
EOF

  # Registered consumer: derive (reads via match[...] / match.get / entry.get +
  # a required_fields tuple). All reads are in-whitelist.
  cat >"$fixdir/scripts/derive-task-md-from-refinement-json.sh" <<'EOF'
#!/usr/bin/env bash
: <<'PY'
tasks = data.get("tasks") or []
required_fields = ("id", "title", "scope", "allowed_files", "verification", "estimate_points")
title = str(match["title"])
ac_ids = list(match.get("ac_ids") or [])
shape = match.get("task_shape")
key = match.get("jira_key")
for entry in tasks:
    eid = entry.get("id")
PY
EOF

  # Registered consumer: lock-preflight (reads via entry.get).
  cat >"$fixdir/scripts/validate-refinement-lock-preflight.sh" <<'EOF'
#!/usr/bin/env bash
: <<'PY'
tasks = data.get("tasks")
for entry in tasks or []:
    task_shape = entry.get("task_shape")
    hint = entry.get("tracked_deliverable_hint")
    title = entry.get("title")
    tid = entry.get("id")
PY
EOF

  # Registered consumer: md-generator (reads via task.get).
  cat >"$fixdir/scripts/lib/refinement-md-generator.py" <<'EOF'
# reads refinement.json
for task in data.get("tasks") or []:
    line = f"{task.get('id')} {task.get('title')} {task.get('scope')}"
EOF

  # Registered consumer: module-ac-coverage (reads via task.get).
  cat >"$fixdir/scripts/lib/refinement-module-ac-coverage.py" <<'EOF'
# reads refinement.json
for task in data.get("tasks") or []:
    mods = (task.get("modules") or []) + (task.get("allowed_files") or [])
EOF

  # Optional extra consumer files: each arg is "<rel-path>::<body>".
  local spec rel body
  for spec in "$@"; do
    rel="${spec%%::*}"
    body="${spec#*::}"
    mkdir -p "$fixdir/$(dirname "$rel")"
    printf '%s\n' "$body" >"$fixdir/$rel"
  done
}

# ---------------------------------------------------------------------------
# Case 1 (positive): all declared consumers read only canonical-whitelist fields.
# ---------------------------------------------------------------------------
fix1="$tmpdir/case1"
build_fixture "$fix1"
set +e
out1="$(bash "$GATE" --root "$fix1" 2>"$tmpdir/case1.err")"; rc1=$?
set -e
assert_exit "case1 positive (all reads in-whitelist)" 0 "$rc1"
if [[ "$out1" != *"PASS: refinement consumer schema binding"* ]]; then
  echo "FAIL: case1 missing PASS line (got: $out1)" >&2
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Case 2 (negative): a declared consumer reads a schema-EXTERNAL field. The field
# `planned_shape` is NOT in the schema validator whitelist, so the gate must fail.
# This proves the gate is not a literal `grep planned_tasks` scan: an arbitrary
# out-of-schema field (not the legacy literal) is caught.
# ---------------------------------------------------------------------------
fix2="$tmpdir/case2"
build_fixture "$fix2"
# overwrite the derive consumer to add a schema-external read
cat >"$fix2/scripts/derive-task-md-from-refinement-json.sh" <<'EOF'
#!/usr/bin/env bash
: <<'PY'
tasks = data.get("tasks") or []
title = str(match["title"])
bogus = match["planned_shape"]
PY
EOF
set +e
bash "$GATE" --root "$fix2" 2>"$tmpdir/case2.err"; rc2=$?
set -e
assert_exit "case2 negative (schema-external field read)" 2 "$rc2"
assert_stderr_contains "case2 marker" "POLARIS_REFINEMENT_CONSUMER_SCHEMA_BINDING:" "$tmpdir/case2.err"
assert_stderr_contains "case2 names offending field" "planned_shape" "$tmpdir/case2.err"

# ---------------------------------------------------------------------------
# Case 3 (registration): an UNREGISTERED script reads refinement.json tasks[]
# entry fields. The gate's discovery scan must flag it and demand registration.
# ---------------------------------------------------------------------------
fix3="$tmpdir/case3"
build_fixture "$fix3" \
  "scripts/new-orphan-consumer.py::# reads refinement.json
for entry in data.get(\"tasks\") or []:
    z = entry.get(\"scope\")"
set +e
bash "$GATE" --root "$fix3" 2>"$tmpdir/case3.err"; rc3=$?
set -e
assert_exit "case3 registration (unregistered consumer)" 2 "$rc3"
assert_stderr_contains "case3 unregistered marker" "unregistered refinement.json tasks[] consumer" "$tmpdir/case3.err"
assert_stderr_contains "case3 names orphan file" "scripts/new-orphan-consumer.py" "$tmpdir/case3.err"

# ---------------------------------------------------------------------------
# Case 4 (SoT-coupling): a field that a declared consumer reads is legal ONLY when
# the schema validator declares it. We add `jira_key` removed from the schema stub
# while the derive consumer still reads it → out-of-schema → fail. This proves the
# whitelist is genuinely derived from the schema validator source (the SoT), not a
# hardcoded list inside the gate.
# ---------------------------------------------------------------------------
fix4="$tmpdir/case4"
build_fixture "$fix4"
# shrink the schema validator whitelist: drop the `if "jira_key" in task:` anchor
# (the derive consumer still reads match.get("jira_key")).
cat >"$fix4/scripts/validate-refinement-json.sh" <<'EOF'
#!/usr/bin/env bash
: <<'PY'
    task_required = {
        "id",
        "kind",
        "title",
        "scope",
        "allowed_files",
        "modules",
        "ac_ids",
        "dependencies",
        "estimate_points",
        "verification",
    }
        if "task_shape" in task:
        if "tracked_deliverable_hint" in task:
PY
EOF
set +e
bash "$GATE" --root "$fix4" 2>"$tmpdir/case4.err"; rc4=$?
set -e
assert_exit "case4 SoT-coupling (field legal only when schema declares it)" 2 "$rc4"
assert_stderr_contains "case4 names dropped field" "jira_key" "$tmpdir/case4.err"

# ---------------------------------------------------------------------------
# Case 5 (live-repo, AC7): the gate must PASS against the real workspace — DP-296's
# own implementation must not self-block.
# ---------------------------------------------------------------------------
set +e
out5="$(bash "$GATE" --root "$ROOT" 2>"$tmpdir/case5.err")"; rc5=$?
set -e
assert_exit "case5 live-repo (AC7 no self-block)" 0 "$rc5"
if [[ "$out5" != *"PASS: refinement consumer schema binding"* ]]; then
  echo "FAIL: case5 missing PASS line (got: $out5)" >&2
  cat "$tmpdir/case5.err" >&2
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
echo "----------------------------------------"
echo "selftest summary: pass=$pass fail=$fail"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "PASS: validate-refinement-consumer-schema-binding selftest"
