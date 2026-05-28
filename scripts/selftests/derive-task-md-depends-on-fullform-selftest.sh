#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/derive-task-md-from-refinement-json.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REF="$TMP/refinement.json"
cat >"$REF" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-961"},
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-961-T1",
      "kind": "implementation",
      "title": "Base task",
      "scope": "Base task for dependency fixture.",
      "allowed_files": ["scripts/base.sh"],
      "modules": ["scripts/base.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo base"
      }
    },
    {
      "id": "DP-961-T2",
      "kind": "implementation",
      "title": "Dependent task",
      "scope": "Dependent task for full-form dependency fixture.",
      "allowed_files": ["scripts/dependent.sh"],
      "modules": ["scripts/dependent.sh"],
      "ac_ids": ["AC2"],
      "dependencies": ["T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo dependent"
      }
    },
    {
      "id": "DP-961-T3",
      "kind": "implementation",
      "title": "Full-form dependent task",
      "scope": "Dependent task with already full-form dependency.",
      "allowed_files": ["scripts/fullform.sh"],
      "modules": ["scripts/fullform.sh"],
      "ac_ids": ["AC3"],
      "dependencies": ["DP-961-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo fullform"
      }
    }
  ]
}
JSON

short_out="$TMP/short.md"
bash "$SCRIPT" --refinement-json "$REF" --task-id DP-961-T2 >"$short_out"
if ! grep -qF 'depends_on: [DP-961-T1]' "$short_out"; then
  echo "FAIL: short dependency did not become full-form frontmatter" >&2
  cat "$short_out" >&2
  exit 1
fi
if ! grep -qF '| Depends on | DP-961-T1 |' "$short_out"; then
  echo "FAIL: short dependency did not become full-form table cell" >&2
  cat "$short_out" >&2
  exit 1
fi

full_out="$TMP/full.md"
bash "$SCRIPT" --refinement-json "$REF" --task-id DP-961-T3 >"$full_out"
if ! grep -qF 'depends_on: [DP-961-T1]' "$full_out"; then
  echo "FAIL: full-form dependency did not stay full-form frontmatter" >&2
  cat "$full_out" >&2
  exit 1
fi

echo "PASS: derive task depends_on full-form"
