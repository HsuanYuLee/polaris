#!/usr/bin/env bash
# DP-230-T10: derive-task-md-from-refinement-json selftest
#
# AC28 (positive): refinement.json structured `tasks[]` fields are sufficient to
#   deterministically derive a task.md body that passes `validate-task-md.sh`.
#   No LLM-judgment text is required.
# AC-NEG9 (negative): when `tasks[]` entry is missing required deterministic
#   fields (id / title / scope / allowed_files / verification.detail), the
#   derive script must fail-loud and refuse to emit a task.md body. There is
#   NO LLM-judgment fallback.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
VALIDATE_TASK_MD="$ROOT_DIR/scripts/validate-task-md.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-task-md.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Case 1 (AC28): positive — full refinement.json `tasks[]` entry derives a
# valid task.md body. No LLM judgment in the derivation pipeline.
# ---------------------------------------------------------------------------
positive_json="$tmpdir/refinement-positive.json"
cat >"$positive_json" <<'JSON'
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
      "title": "範例 deterministic derivation",
      "scope": "驗證 derive script 會從 refinement.json structured fields 產出 canonical task.md body。",
      "allowed_files": [
        "scripts/sample.sh",
        "scripts/selftests/sample-selftest.sh"
      ],
      "modules": [
        "scripts/sample.sh"
      ],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ]
}
JSON

positive_out="$tmpdir/positive-task.md"
bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-T1" > "$positive_out"

# Required deterministic anchors — these come straight from refinement.json
# fields, not from any LLM reasoning step.
required_anchors=(
  "# T1: 範例 deterministic derivation (2 pt)"
  "> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework"
  "| Source type | dp |"
  "| Source ID | DP-999 |"
  "| Task ID | DP-999-T1 |"
  "| Base branch | main |"
  "| Task branch | task/DP-999-T1-範例-deterministic-derivation |"
  "## Allowed Files"
  "- \`scripts/sample.sh\`"
  "- \`scripts/selftests/sample-selftest.sh\`"
  "## Scope Trace Matrix"
  "| AC1 | \`scripts/sample.sh\`"
  "## Gate Closure Matrix"
  "bash scripts/selftests/sample-selftest.sh"
  "## Verify Command"
  "echo \"PASS: DP-999-T1\""
)
for anchor in "${required_anchors[@]}"; do
  if ! grep -qF -- "$anchor" "$positive_out"; then
    echo "FAIL [case 1 / AC28]: anchor not found in derived task.md: $anchor" >&2
    echo "--- derived output ---" >&2
    cat "$positive_out" >&2
    exit 1
  fi
done

# Derived body must pass `validate-task-md.sh` without any post-edit.
bash "$VALIDATE_TASK_MD" "$positive_out" >/dev/null 2>&1 || {
  echo "FAIL [case 1 / AC28]: derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$positive_out" >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# Case 2 (AC28): determinism — running the script twice yields byte-identical
# output. There is no time-dependent / random-seeded behavior.
# ---------------------------------------------------------------------------
positive_out_b="$tmpdir/positive-task-b.md"
bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-T1" > "$positive_out_b"
if ! cmp -s "$positive_out" "$positive_out_b"; then
  echo "FAIL [case 2 / AC28]: derive script output is not deterministic" >&2
  diff "$positive_out" "$positive_out_b" | head -40 >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG9): negative — missing required field must fail-loud. No
# LLM-judgment fallback that fills the gap.
# ---------------------------------------------------------------------------
negative_json="$tmpdir/refinement-negative.json"
cat >"$negative_json" <<'JSON'
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
      "id": "DP-999-T2",
      "kind": "implementation",
      "title": "Missing allowed_files",
      "scope": "Negative case — allowed_files intentionally omitted to assert fail-loud.",
      "ac_ids": ["AC2"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/missing-selftest.sh"
      }
    }
  ]
}
JSON

if bash "$SCRIPT" --refinement-json "$negative_json" --task-id "DP-999-T2" >/dev/null 2>"$tmpdir/neg.stderr"; then
  echo "FAIL [case 3 / AC-NEG9]: script accepted refinement.json missing allowed_files" >&2
  exit 1
fi
if ! grep -q "allowed_files" "$tmpdir/neg.stderr"; then
  echo "FAIL [case 3 / AC-NEG9]: script did not surface the missing field name" >&2
  cat "$tmpdir/neg.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 4 (AC-NEG9): unknown task id must fail-loud.
# ---------------------------------------------------------------------------
if bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-TX" >/dev/null 2>"$tmpdir/unknown.stderr"; then
  echo "FAIL [case 4 / AC-NEG9]: script accepted unknown task id" >&2
  exit 1
fi
if ! grep -q "DP-999-TX" "$tmpdir/unknown.stderr"; then
  echo "FAIL [case 4 / AC-NEG9]: stderr did not name the unresolved task id" >&2
  cat "$tmpdir/unknown.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 5 (AC-NEG9): missing refinement.json file must fail-loud.
# ---------------------------------------------------------------------------
if bash "$SCRIPT" --refinement-json "$tmpdir/does-not-exist.json" --task-id "DP-999-T1" >/dev/null 2>"$tmpdir/missing.stderr"; then
  echo "FAIL [case 5 / AC-NEG9]: script accepted missing refinement.json" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 6 (DP-231 D45): V tasks derive a V-mode schema body with
# Implementation tasks and 驗收項目, not the T-mode sections.
# ---------------------------------------------------------------------------
v_json="$tmpdir/refinement-v.json"
cat >"$v_json" <<'JSON'
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
      "text": "驗收 deterministic V task schema。",
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
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "範例 implementation",
      "scope": "驗證 T task。",
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
      "id": "DP-999-V1",
      "kind": "verification",
      "title": "範例 umbrella 驗收",
      "scope": "驗收 T task 的 AC。",
      "allowed_files": ["scripts/selftests/sample-selftest.sh"],
      "modules": ["scripts/selftests/sample-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["DP-999-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    }
  ]
}
JSON

mkdir -p "$tmpdir/V1"
v_out="$tmpdir/V1/index.md"
bash "$SCRIPT" --refinement-json "$v_json" --task-id "DP-999-V1" > "$v_out"
v_anchors=(
  "# V1: 範例 umbrella 驗收 (1 pt)"
  "| Implementation tasks | T1 |"
  "## 驗收項目"
  "| AC1 | 驗收 deterministic V task schema。 | T1 | unit_test |"
  "## 驗收計畫（AC level）"
)
for anchor in "${v_anchors[@]}"; do
  if ! grep -qF -- "$anchor" "$v_out"; then
    echo "FAIL [case 6 / D45]: V anchor not found: $anchor" >&2
    cat "$v_out" >&2
    exit 1
  fi
done
bash "$VALIDATE_TASK_MD" "$v_out" >/dev/null 2>&1 || {
  echo "FAIL [case 6 / D45]: derived V task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$v_out" >&2 || true
  exit 1
}

echo "PASS: derive-task-md-from-refinement-json selftest"
