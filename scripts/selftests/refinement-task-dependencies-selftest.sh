#!/usr/bin/env bash
# DP-231 D45: refinement task dependency semantics selftest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-refinement-json.sh"
TMP="$(mktemp -d -t refinement-task-deps.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/DP-999"
cat >"$TMP/DP-999/index.md" <<'MD'
---
title: "DP-999 fixture"
description: "fixture"
status: LOCKED
---
MD
touch "$TMP/DP-999/refinement.md"

write_fixture() {
  local dep_json="$1"
  local target="$2"
  cat >"$target" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$TMP/DP-999",
    "plan_path": "$TMP/DP-999/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "created_at": "2026-05-27T00:00:00+08:00",
  "schema_version": "1",
  "modules": [
    {"path": "scripts/example.sh", "action": "modify", "complexity": "low", "risk": "low", "reason": "fixture", "references": 0}
  ],
  "dependencies": [],
  "tool_requirements": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "acceptance_criteria": [
    {"id": "AC1", "text": "驗證 task dependency schema。", "category": "functional", "quantifiable": true, "verification": {"method": "unit_test", "detail": "bash scripts/example.sh"}}
  ],
  "tasks": [
    {"id": "DP-999-T1", "kind": "implementation", "title": "範例 task", "scope": "測試", "allowed_files": ["scripts/example.sh"], "modules": ["scripts/example.sh"], "ac_ids": ["AC1"], "dependencies": $dep_json, "estimate_points": 1, "verification": {"method": "unit_test", "detail": "bash scripts/example.sh"}}
  ],
  "adversarial_pass": [
    {"ac_id": "AC1", "attack": "fixture", "enforce": "fixture"}
  ]
}
JSON
}

valid="$TMP/DP-999/refinement.json"
write_fixture '["T2"]' "$valid"
bash "$VALIDATOR" "$valid" >/dev/null

invalid="$TMP/DP-999/refinement.json"
write_fixture '["DP-229"]' "$invalid"
if bash "$VALIDATOR" "$invalid" >"$TMP/invalid.out" 2>&1; then
  echo "FAIL: bare source dependency unexpectedly passed" >&2
  exit 1
fi
grep -q "POLARIS_REFINEMENT_TASK_DEPENDENCY_INVALID" "$TMP/invalid.out" || {
  echo "FAIL: missing dependency invalid token" >&2
  cat "$TMP/invalid.out" >&2
  exit 1
}

echo "PASS: refinement task dependencies selftest"
