#!/usr/bin/env bash
# Purpose: DP-264 T1 — assert derive-task-md-from-refinement-json.sh derives a
#   stacked task's `Base branch` / branch chain from the dependency entry's real
#   title slug, regardless of whether tasks[].id is short form (T1) or full form
#   (DP-NNN-Tn). Regression for the L161 task_by_id lookup that used raw entry.id
#   as key while the L199-200 dependency title lookup used the full id, missing on
#   short-form ids and falling back to a `task/DP-NNN-T1-dp-nnn-t1` literal.
# Inputs:  none (constructs fixtures in tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-stacked-base.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# --- AC1: short-form tasks[].id, T2 depends on T1 (both T tasks). -------------
# The dependency base branch must use T1's real title slug, NOT the full-id
# literal fallback `task/DP-700-T1-dp-700-t1`.
short_json="$tmpdir/refinement-short.json"
cat >"$short_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-700",
    "container": "/tmp/dp-700",
    "plan_path": "/tmp/dp-700/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "Foundation helper extraction",
      "scope": "Base task for stacked base-branch fixture.",
      "allowed_files": ["scripts/foundation.sh"],
      "modules": ["scripts/foundation.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/foundation-selftest.sh"
      }
    },
    {
      "id": "T2",
      "kind": "implementation",
      "title": "Stacked consumer wiring",
      "scope": "Dependent task stacked on T1 for base-branch derivation.",
      "allowed_files": ["scripts/consumer.sh"],
      "modules": ["scripts/consumer.sh"],
      "ac_ids": ["AC2"],
      "dependencies": ["T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/consumer-selftest.sh"
      }
    }
  ]
}
JSON

short_out="$tmpdir/short-task.md"
bash "$SCRIPT" --refinement-json "$short_json" --task-id "DP-700-T2" > "$short_out" 2>"$tmpdir/short.stderr" || {
  echo "FAIL: derive failed on short-form stacked fixture (--task-id='DP-700-T2')" >&2
  cat "$tmpdir/short.stderr" >&2
  exit 1
}

# Expected: base branch uses T1's real title slug.
expected_base="task/DP-700-T1-foundation-helper-extraction"
if ! grep -qF "| Base branch | ${expected_base} |" "$short_out"; then
  echo "FAIL: short-form stacked base branch did not resolve to T1's real title slug" >&2
  echo "       expected: | Base branch | ${expected_base} |" >&2
  grep -F '| Base branch |' "$short_out" >&2 || true
  exit 1
fi
# Negative assertion: must NOT be the full-id literal fallback.
if grep -qF "| Base branch | task/DP-700-T1-dp-700-t1 |" "$short_out"; then
  echo "FAIL: short-form stacked base branch fell back to full-id literal slug" >&2
  cat "$short_out" >&2
  exit 1
fi

# --- AC2 regression: full-form tasks[].id must still resolve real title slug. -
full_json="$tmpdir/refinement-full.json"
cat >"$full_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-700",
    "container": "/tmp/dp-700",
    "plan_path": "/tmp/dp-700/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-700-T1",
      "kind": "implementation",
      "title": "Foundation helper extraction",
      "scope": "Base task for stacked base-branch fixture.",
      "allowed_files": ["scripts/foundation.sh"],
      "modules": ["scripts/foundation.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/foundation-selftest.sh"
      }
    },
    {
      "id": "DP-700-T2",
      "kind": "implementation",
      "title": "Stacked consumer wiring",
      "scope": "Dependent task stacked on T1 for base-branch derivation.",
      "allowed_files": ["scripts/consumer.sh"],
      "modules": ["scripts/consumer.sh"],
      "ac_ids": ["AC2"],
      "dependencies": ["DP-700-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/consumer-selftest.sh"
      }
    }
  ]
}
JSON

full_out="$tmpdir/full-task.md"
bash "$SCRIPT" --refinement-json "$full_json" --task-id "DP-700-T2" > "$full_out" 2>"$tmpdir/full.stderr" || {
  echo "FAIL: derive failed on full-form stacked fixture (--task-id='DP-700-T2')" >&2
  cat "$tmpdir/full.stderr" >&2
  exit 1
}

if ! grep -qF "| Base branch | ${expected_base} |" "$full_out"; then
  echo "FAIL: full-form stacked base branch regressed away from T1's real title slug" >&2
  echo "       expected: | Base branch | ${expected_base} |" >&2
  grep -F '| Base branch |' "$full_out" >&2 || true
  exit 1
fi

# --- AC-NEG1: foreign-prefix external dep must NOT become a local base branch. -
foreign_json="$tmpdir/refinement-foreign.json"
cat >"$foreign_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-700",
    "container": "/tmp/dp-700",
    "plan_path": "/tmp/dp-700/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "title": "Local task with external source reference",
      "scope": "Depends on a cross-source full-form work item.",
      "allowed_files": ["scripts/local.sh"],
      "modules": ["scripts/local.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["OTHERDP-999-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/local-selftest.sh"
      }
    }
  ]
}
JSON

foreign_out="$tmpdir/foreign-task.md"
bash "$SCRIPT" --refinement-json "$foreign_json" --task-id "DP-700-T1" > "$foreign_out" 2>"$tmpdir/foreign.stderr" || {
  echo "FAIL: derive failed on foreign-prefix external dep fixture (--task-id='DP-700-T1')" >&2
  cat "$tmpdir/foreign.stderr" >&2
  exit 1
}

# External dep is excluded from local base-branch derivation → base stays main.
if ! grep -qF "| Base branch | main |" "$foreign_out"; then
  echo "FAIL: foreign-prefix external dep did not keep base branch = main" >&2
  grep -F '| Base branch |' "$foreign_out" >&2 || true
  exit 1
fi
# Must not turn the external work item into a local task branch.
if grep -qF "task/OTHERDP-999-T1" "$foreign_out"; then
  echo "FAIL: foreign-prefix external dep was converted into a local base branch" >&2
  cat "$foreign_out" >&2
  exit 1
fi

echo "PASS: derive-task-md-stacked-base-branch selftest"
