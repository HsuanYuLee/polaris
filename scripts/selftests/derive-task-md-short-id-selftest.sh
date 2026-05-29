#!/usr/bin/env bash
# Purpose: DP-260 T1 — assert derive-task-md-from-refinement-json.sh accepts both
#   short form (T1/V1) and full form (DP-NNN-Tn/Vn) for tasks[].id and produces
#   byte-identical task.md staged body for either input.
# Inputs:  none (constructs fixture in tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-short-id.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Fixture with `id: "T1"` (short form).
short_json="$tmpdir/refinement-short.json"
cat >"$short_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "Short form derive parity",
      "scope": "驗證 derive 對 short form id 的雙形 fallback。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ]
}
JSON

# Fixture with `id: "DP-999-T1"` (full form) — same content otherwise.
full_json="$tmpdir/refinement-full.json"
cat >"$full_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "Short form derive parity",
      "scope": "驗證 derive 對 short form id 的雙形 fallback。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ]
}
JSON

short_out="$tmpdir/short-task.md"
full_out="$tmpdir/full-task.md"

bash "$SCRIPT" --refinement-json "$short_json" --task-id "DP-999-T1" > "$short_out" 2>"$tmpdir/short.stderr" || {
  echo "FAIL: derive failed on short-form id (entry.id='T1', --task-id='DP-999-T1')" >&2
  cat "$tmpdir/short.stderr" >&2
  exit 1
}

bash "$SCRIPT" --refinement-json "$full_json" --task-id "DP-999-T1" > "$full_out" 2>"$tmpdir/full.stderr" || {
  echo "FAIL: derive failed on full-form id (entry.id='DP-999-T1')" >&2
  cat "$tmpdir/full.stderr" >&2
  exit 1
}

if ! cmp -s "$short_out" "$full_out"; then
  echo "FAIL: short-form vs full-form derive output is not byte-identical" >&2
  diff "$short_out" "$full_out" | head -40 >&2
  exit 1
fi

# Sanity: derived body must contain canonical full-form id in frontmatter.
if ! grep -q "Task ID | DP-999-T1" "$short_out"; then
  echo "FAIL: short-form derive did not emit canonical task id in body" >&2
  cat "$short_out" >&2
  exit 1
fi

# V-mode short form must also work (acceptance_criteria required for V tasks).
v_short_json="$tmpdir/refinement-v-short.json"
cat >"$v_short_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "驗收 V mode short-id 雙形支援。",
      "category": "functional",
      "quantifiable": true,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ],
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "Short form V derive parity T",
      "scope": "T task baseline。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    },
    {
      "id": "V1",
      "kind": "verification",
      "title": "Short form V derive parity",
      "scope": "驗證 V mode 雙形支援。",
      "allowed_files": ["scripts/selftests/sample-selftest.sh"],
      "modules": ["scripts/selftests/sample-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ]
}
JSON

v_short_out="$tmpdir/v-short.md"
bash "$SCRIPT" --refinement-json "$v_short_json" --task-id "DP-999-V1" > "$v_short_out" 2>"$tmpdir/v.stderr" || {
  echo "FAIL: derive failed on V-mode short-form id (entry.id='V1', --task-id='DP-999-V1')" >&2
  cat "$tmpdir/v.stderr" >&2
  exit 1
}

if ! grep -q "Task ID | DP-999-V1" "$v_short_out"; then
  echo "FAIL: V-mode short-form derive did not emit canonical task id in body" >&2
  cat "$v_short_out" >&2
  exit 1
fi

echo "PASS: derive-task-md-short-id selftest"
