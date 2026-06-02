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
  "task_kind: T"
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
  "task_kind: V"
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

# ---------------------------------------------------------------------------
# Case 7 (DP-260 AC-NEG1): --task-id CLI argument must be canonical full form
# (EPIC-NNN-Tn). Passing a short form (e.g. "T1") must fail-loud; the dual-form
# support is for refinement.json `tasks[].id` only, never for the CLI handoff.
# ---------------------------------------------------------------------------
if bash "$SCRIPT" --refinement-json "$positive_json" --task-id "T1" >/dev/null 2>"$tmpdir/cli-short.stderr"; then
  echo "FAIL [case 7 / DP-260 AC-NEG1]: derive accepted short-form CLI --task-id" >&2
  exit 1
fi
if ! grep -q "canonical pattern" "$tmpdir/cli-short.stderr"; then
  echo "FAIL [case 7 / DP-260 AC-NEG1]: stderr missing canonical-pattern hint" >&2
  cat "$tmpdir/cli-short.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 8 (DP-272 T1 / AC1): planned_tasks[Tn].task_shape propagates into the
# T-task frontmatter as `task_shape: <value>`. The value source is
# planned_tasks[] joined by short task_id, NOT tasks[]. When the matched
# planned_tasks entry has no task_shape (or is absent), the line is omitted.
# ---------------------------------------------------------------------------
shape_json="$tmpdir/refinement-shape.json"
cat >"$shape_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "planned_tasks": [
    { "task_id": "T1", "task_shape": "confirmation" },
    { "task_id": "T2" }
  ],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "確認型 task",
      "scope": "驗證 planned_tasks task_shape 注入 T-task frontmatter。",
      "allowed_files": ["docs-manager/src/content/docs/specs/design-plans/DP-999-x/index.md"],
      "modules": ["docs-manager/src/content/docs/specs/design-plans/DP-999-x/index.md"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/sample-selftest.sh"
      }
    },
    {
      "id": "DP-999-T2",
      "kind": "implementation",
      "title": "一般型 task",
      "scope": "驗證缺 task_shape 時不注入。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC2"],
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

shape_t1_out="$tmpdir/shape-t1.md"
bash "$SCRIPT" --refinement-json "$shape_json" --task-id "DP-999-T1" > "$shape_t1_out"
shape_t1_count=$(grep -c '^task_shape: confirmation$' "$shape_t1_out" || true)
if [[ "$shape_t1_count" -ne 1 ]]; then
  echo "FAIL [case 8 / DP-272 AC1]: expected exactly one 'task_shape: confirmation' line, got $shape_t1_count" >&2
  cat "$shape_t1_out" >&2
  exit 1
fi
# task_shape must sit immediately after task_kind in the frontmatter.
if ! grep -Pzoq 'task_kind: T\ntask_shape: confirmation\n' "$shape_t1_out" 2>/dev/null; then
  # grep -P may be unavailable; fall back to awk adjacency check.
  if ! awk '/^task_kind: T$/{k=NR} /^task_shape: confirmation$/{if(NR==k+1){found=1}} END{exit found?0:1}' "$shape_t1_out"; then
    echo "FAIL [case 8 / DP-272 AC1]: task_shape line not directly after task_kind" >&2
    cat "$shape_t1_out" >&2
    exit 1
  fi
fi

# AC1 absent half: T2 has no task_shape in planned_tasks → no task_shape line.
shape_t2_out="$tmpdir/shape-t2.md"
bash "$SCRIPT" --refinement-json "$shape_json" --task-id "DP-999-T2" > "$shape_t2_out"
shape_t2_count=$(grep -c '^task_shape:' "$shape_t2_out" || true)
if [[ "$shape_t2_count" -ne 0 ]]; then
  echo "FAIL [case 8 / DP-272 AC1]: expected no task_shape line for T2 (absent), got $shape_t2_count" >&2
  cat "$shape_t2_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 9 (DP-272 T1 / AC2): V tasks must NEVER receive a task_shape line, even
# when planned_tasks declares one for the V id.
# ---------------------------------------------------------------------------
v_shape_json="$tmpdir/refinement-v-shape.json"
cat >"$v_shape_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "planned_tasks": [
    { "task_id": "T1", "task_shape": "confirmation" },
    { "task_id": "V1", "task_shape": "audit" }
  ],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "驗收 V task 不帶 task_shape。",
      "category": "functional",
      "quantifiable": true,
      "verification": { "method": "unit_test", "detail": "bash scripts/selftests/sample-selftest.sh" }
    }
  ],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "確認型 task",
      "scope": "驗證 T task。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/selftests/sample-selftest.sh" }
    },
    {
      "id": "DP-999-V1",
      "kind": "verification",
      "title": "範例 umbrella 驗收",
      "scope": "驗收 T task。",
      "allowed_files": ["scripts/selftests/sample-selftest.sh"],
      "modules": ["scripts/selftests/sample-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["DP-999-T1"],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/selftests/sample-selftest.sh" }
    }
  ]
}
JSON

mkdir -p "$tmpdir/V1-shape"
v_shape_out="$tmpdir/V1-shape/index.md"
bash "$SCRIPT" --refinement-json "$v_shape_json" --task-id "DP-999-V1" > "$v_shape_out"
v_shape_count=$(grep -c '^task_shape:' "$v_shape_out" || true)
if [[ "$v_shape_count" -ne 0 ]]; then
  echo "FAIL [case 9 / DP-272 AC2]: V task must never carry task_shape, got $v_shape_count line(s)" >&2
  cat "$v_shape_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 10 (DP-272 T1 / AC3): a derived task.md with task_shape=confirmation +
# specs-only allowed_files must pass validate-breakdown-ready.sh (exit 0). This
# is the end-to-end carve-out the DP-262 docs promised but never wired up.
# ---------------------------------------------------------------------------
VALIDATE_BREAKDOWN_READY="$ROOT_DIR/scripts/validate-breakdown-ready.sh"
if [[ ! -x "$VALIDATE_BREAKDOWN_READY" ]]; then
  echo "FAIL [case 10 / DP-272 AC3]: validate-breakdown-ready.sh not executable: $VALIDATE_BREAKDOWN_READY" >&2
  exit 1
fi
if ! bash "$VALIDATE_BREAKDOWN_READY" "$shape_t1_out" >"$tmpdir/breakdown-ready.out" 2>&1; then
  echo "FAIL [case 10 / DP-272 AC3]: derived confirmation task.md did not pass validate-breakdown-ready.sh" >&2
  cat "$tmpdir/breakdown-ready.out" >&2
  echo "--- derived task.md ---" >&2
  cat "$shape_t1_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 11 (DP-272 T1 / AC-NEG1): derive is passthrough-only and does NOT
# validate the enum. A typo'd task_shape is emitted verbatim, and the single
# classifier (validate-task-md.sh) rejects it.
# ---------------------------------------------------------------------------
typo_json="$tmpdir/refinement-typo.json"
cat >"$typo_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/dp-999",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "planned_tasks": [
    { "task_id": "T1", "task_shape": "confirmaton" }
  ],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "typo shape task",
      "scope": "驗證 derive passthrough 不做 enum 驗證。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/selftests/sample-selftest.sh" }
    }
  ]
}
JSON

typo_out="$tmpdir/typo-t1.md"
bash "$SCRIPT" --refinement-json "$typo_json" --task-id "DP-999-T1" > "$typo_out"
if ! grep -q '^task_shape: confirmaton$' "$typo_out"; then
  echo "FAIL [case 11 / DP-272 AC-NEG1]: derive must passthrough typo'd task_shape verbatim" >&2
  cat "$typo_out" >&2
  exit 1
fi
if bash "$VALIDATE_TASK_MD" "$typo_out" >/dev/null 2>&1; then
  echo "FAIL [case 11 / DP-272 AC-NEG1]: validate-task-md.sh accepted invalid task_shape enum" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 12 (DP-272 T1 / AC8 zero-shim): refinement.json with no planned_tasks
# at all derives byte-identical output to before this feature. We assert this
# against the existing positive fixture, whose output already passed all
# earlier anchors and validate-task-md.sh — re-deriving must not regress and
# must contain no task_shape line.
# ---------------------------------------------------------------------------
zero_shim_out="$tmpdir/zero-shim.md"
bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-T1" > "$zero_shim_out"
if ! cmp -s "$positive_out" "$zero_shim_out"; then
  echo "FAIL [case 12 / DP-272 AC8]: no-planned_tasks output drifted from baseline derive" >&2
  diff "$positive_out" "$zero_shim_out" | head -40 >&2
  exit 1
fi
if grep -q '^task_shape:' "$zero_shim_out"; then
  echo "FAIL [case 12 / DP-272 AC8]: no-planned_tasks output must not contain task_shape" >&2
  exit 1
fi

echo "PASS: derive-task-md-from-refinement-json selftest"
