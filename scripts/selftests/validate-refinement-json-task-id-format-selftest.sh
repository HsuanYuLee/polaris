#!/usr/bin/env bash
# Purpose: DP-260 T1 — assert validate-refinement-json.sh enforces tasks[].id format.
#   Valid: short form (T1/V1/T1a) OR full form (DP-NNN-Tn) whose prefix == source.id.
#   Invalid: malformed strings, empty, foreign prefix, suffix garbage.
# Inputs:  none (constructs fixture refinement.json files in tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/validate-refinement-json.sh"
MARKER='POLARIS_REFINEMENT_TASK_ID_INVALID'

[[ -x "$SCRIPT" ]] || { echo "FAIL: validator not executable: $SCRIPT" >&2; exit 1; }

tmp="$(mktemp -d -t refinement-task-id.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

# Emit a refinement.json fixture (as ${case_dir}/refinement.json) with the given
# tasks[0].id value (raw JSON string literal). Also creates index.md so source.container /
# source.plan_path resolution passes.
emit_fixture() {
  local case_dir="$1"
  local task_id_json="$2"  # JSON literal — caller controls quoting (e.g. "\"T1\"" or "\"\"")
  mkdir -p "$case_dir"
  cat >"$case_dir/index.md" <<'MD'
---
title: "Fixture"
description: "Fixture"
status: LOCKED
---
MD
  cat >"$case_dir/refinement.json" <<JSON
{
  "schema_version": 1,
  "source": {"type": "dp", "id": "DP-999", "container": "$case_dir", "plan_path": "$case_dir/index.md", "jira_key": null},
  "version": "1.0",
  "tier": 2,
  "created_at": "2026-05-29T00:00:00Z",
  "modules": [
    {"path": "scripts/sample.sh", "action": "create", "complexity": "low", "risk": "low", "reason": "fixture"}
  ],
  "dependencies": [],
  "predecessor_audit": [],
  "edge_cases": [{"scenario": "x", "handling": "y", "severity": "low", "source": "ai_suggested"}],
  "acceptance_criteria": [
    {"id": "AC1", "text": "fixture AC", "category": "functional", "verification": {"method": "unit_test", "detail": "fixture"}, "negative": false}
  ],
  "gaps": {"pm_questions": [], "rd_risks": [{"risk": "x", "severity": "low", "mitigation": "y"}]},
  "tasks": [
    {"id": $task_id_json, "kind": "implementation", "title": "fixture", "scope": "fixture", "modules": ["scripts/sample.sh"], "ac_ids": ["AC1"], "dependencies": [], "verification": {"method": "unit_test", "detail": "fixture"}}
  ],
  "adversarial_pass": [{"ac_id": "AC1", "attack": "x", "enforce": "y"}]
}
JSON
}

# valid cases: must PASS (exit 0)
assert_valid() {
  local label="$1" task_id_json="$2"
  local case_dir="$tmp/valid-${label}"
  emit_fixture "$case_dir" "$task_id_json"
  if ! bash "$SCRIPT" "$case_dir/refinement.json" 2>"$tmp/valid-${label}.err"; then
    echo "FAIL: valid case '$label' (id=$task_id_json) unexpectedly rejected" >&2
    cat "$tmp/valid-${label}.err" >&2
    exit 1
  fi
}

# invalid cases: must FAIL (exit non-zero) AND emit POLARIS_REFINEMENT_TASK_ID_INVALID marker
assert_invalid() {
  local label="$1" task_id_json="$2"
  local case_dir="$tmp/invalid-${label}"
  emit_fixture "$case_dir" "$task_id_json"
  if bash "$SCRIPT" "$case_dir/refinement.json" >"$tmp/invalid-${label}.out" 2>"$tmp/invalid-${label}.err"; then
    echo "FAIL: invalid case '$label' (id=$task_id_json) unexpectedly accepted" >&2
    exit 1
  fi
  if ! grep -q "$MARKER" "$tmp/invalid-${label}.out" "$tmp/invalid-${label}.err"; then
    echo "FAIL: invalid case '$label' did not emit $MARKER" >&2
    echo "--- stdout ---" >&2; cat "$tmp/invalid-${label}.out" >&2
    echo "--- stderr ---" >&2; cat "$tmp/invalid-${label}.err" >&2
    exit 1
  fi
}

# AC2 positive cases
assert_valid short-T '"T1"'
assert_valid full-DP '"DP-999-T1"'

# AC2 negative cases
assert_invalid malformed-Task '"Task-1"'
assert_invalid foreign-prefix '"OTHERDP-999-T1"'
assert_invalid empty-string '""'
assert_invalid suffix-garbage '"T1-foo"'

echo "PASS: validate-refinement-json-task-id-format selftest"
