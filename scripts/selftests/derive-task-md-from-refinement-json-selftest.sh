#!/usr/bin/env bash
# Purpose: selftest for derive-task-md-from-refinement-json.sh — the deterministic
#   task.md body derivation. Covers source.type-free output parity (DP-302),
#   field-driven body, references-by-container, fail-loud, and constructability.
# Inputs:  none (constructs refinement.json fixtures in a tmpdir)
# Outputs: stdout PASS line on success; non-zero exit + stderr on failure
# Exit code: 0 = pass, non-zero = fail
#
# History / AC coverage:
# - DP-230-T10 (AC28 / AC-NEG9): structured tasks[] fields deterministically derive
#   a task.md body that passes validate-task-md.sh; missing field -> fail-loud.
# - DP-231 D45: V tasks derive the V-mode schema (Implementation tasks / 驗收項目).
# - DP-260 AC-NEG1: CLI --task-id must be canonical full form.
# - DP-296 T3 / AC2 / AC-NEG1: tasks[].task_shape passthrough (T only); no removed
#   planned_tasks read.
# - DP-307 T1: slugify is ASCII-only (drop non-[a-z0-9], collapse hyphens); the
#   case-1 Task branch anchor asserts the ASCII-only expectation for a CJK title.
# - DP-302 (this task):
#     AC1     : same refinement.json content fed as dp vs jira derives a task.md
#               whose STRUCTURE (frontmatter keys, section headings, table shapes)
#               is identical -- diff falls only on field values, never on structure
#               or framework literals.
#     AC2     : derive source has no source_type== branch affecting
#               identity/body/references/gate; jira_key cell renders `jira_key or
#               N/A` via one field-driven path.
#     AC3     : body fields (behavior_contract / test_environment / verify_command /
#               references) come from refinement.json; references are generated from
#               the resolved container (jira -> companies/, dp -> design-plans/); the
#               Verify Command has no unconditional framework tail.
#     AC4     : derived dp/jira task.md run through validate-breakdown-ready.sh; a
#               synthesized test-runner + static/N/A env body must be judged FAIL.
#     AC-NEG1 : a task partially declaring body fields fails fail-loud naming the
#               missing field (no silent framework default).
#     AC-NEG2 : an existing dp work order, after backfilling equivalent body fields,
#               derives equivalent output; the no-body legacy path is unchanged.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
VALIDATE_TASK_MD="$ROOT_DIR/scripts/validate-task-md.sh"
VALIDATE_BREAKDOWN_READY="$ROOT_DIR/scripts/validate-breakdown-ready.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: derive script not executable: $SCRIPT" >&2; exit 1; }
[[ -x "$VALIDATE_TASK_MD" ]] || { echo "FAIL: validate-task-md.sh not executable" >&2; exit 1; }
[[ -x "$VALIDATE_BREAKDOWN_READY" ]] || { echo "FAIL: validate-breakdown-ready.sh not executable" >&2; exit 1; }

tmpdir="$(mktemp -d -t derive-task-md.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# Body fields populate the field-driven path. A fully-populated task.md is the
# DP-302 steady state; the no-body legacy path is exercised separately (case 16).
BODY_BC='"behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" }'
BODY_TE='"test_environment": { "level": "static" }'
BODY_REFS='"references": ["scripts/sample.sh"]'

# ---------------------------------------------------------------------------
# Case 1 (AC28): positive -- full refinement.json `tasks[]` entry with per-task
# body fields derives a valid task.md body that passes validate-task-md.sh.
# ---------------------------------------------------------------------------
positive_json="$tmpdir/refinement-positive.json"
cat >"$positive_json" <<JSON
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-999-sample",
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
        "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"
      ],
      "modules": [
        "scripts/sample.sh"
      ],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh",
        $BODY_BC,
        $BODY_TE,
        $BODY_REFS
      }
    }
  ]
}
JSON

positive_preserve="$tmpdir/positive-preserve.md"
cat >"$positive_preserve" <<'MD'
# T1: preserve packaging fixture (2 pt)

## Allowed Files

- `scripts/sample.sh`
- `scripts/selftests/derive-task-md-from-refinement-json-selftest.sh`
MD

positive_out="$tmpdir/positive-task.md"
bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-T1" --preserve-from "$positive_preserve" > "$positive_out"

# Anchors come straight from refinement.json fields, not from any LLM step or
# hardcoded framework literal.
required_anchors=(
  "# T1: 範例 deterministic derivation (2 pt)"
  "task_kind: T"
  "> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: polaris-framework"
  "| Source type | dp |"
  "| Source ID | DP-999 |"
  "| Task ID | DP-999-T1 |"
  "| Base branch | main |"
  "| Task branch | task/DP-999-T1-deterministic-derivation |"
  "## Allowed Files"
  "- \`scripts/sample.sh\`"
  "- \`scripts/selftests/derive-task-md-from-refinement-json-selftest.sh\`"
  "## Scope Trace Matrix"
  "| AC1 | \`scripts/sample.sh\`"
  "## Gate Closure Matrix"
  "bash scripts/validate-config-driven-authoring.sh"
  "## Verify Command"
)
for anchor in "${required_anchors[@]}"; do
  if ! grep -qF -- "$anchor" "$positive_out"; then
    echo "FAIL [case 1 / AC28]: anchor not found in derived task.md: $anchor" >&2
    echo "--- derived output ---" >&2
    cat "$positive_out" >&2
    exit 1
  fi
done

# References come from the resolved container (design-plans/), not a hardcoded
# `DP-999-*` glob literal (AC3).
if ! grep -qF -- "docs-manager/src/content/docs/specs/design-plans/DP-999-sample/refinement.json" "$positive_out"; then
  echo "FAIL [case 1 / AC3]: references not derived from container path" >&2
  cat "$positive_out" >&2
  exit 1
fi

bash "$VALIDATE_TASK_MD" "$positive_out" >/dev/null 2>&1 || {
  echo "FAIL [case 1 / AC28]: derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$positive_out" >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# Case 2 (AC28): determinism -- running twice is byte-identical.
# ---------------------------------------------------------------------------
positive_out_b="$tmpdir/positive-task-b.md"
bash "$SCRIPT" --refinement-json "$positive_json" --task-id "DP-999-T1" --preserve-from "$positive_preserve" > "$positive_out_b"
if ! cmp -s "$positive_out" "$positive_out_b"; then
  echo "FAIL [case 2 / AC28]: derive script output is not deterministic" >&2
  diff "$positive_out" "$positive_out_b" | head -40 >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 3 (AC-NEG9 / DP-341 T2): missing required structural field -> fail-loud.
#
# DP-341 contract change: allowed_files / estimate_points are NO LONGER required
# intent fields (refinement.json is intent-only; packaging is breakdown-owned in
# task.md). So an intent-only refinement.json that OMITS allowed_files must now
# SUCCEED (regime 3 initial-create), NOT fail-loud. The negative AC-NEG9 contract
# (a genuinely-missing required field fail-louds + names the field) is preserved
# against a field that is STILL required (scope).
# ---------------------------------------------------------------------------

# Sub-case 3a (DP-341 T2): omitting allowed_files is now the intent-only target
# shape -> derive succeeds (regime 3), it is not a missing-required-field error.
intent_only_json="$tmpdir/refinement-intent-only-no-allowed.json"
cat >"$intent_only_json" <<'JSON'
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
      "title": "Intent only, no allowed_files",
      "scope": "Intent-only shape -- allowed_files omitted; packaging is task.md-owned.",
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

if ! bash "$SCRIPT" --refinement-json "$intent_only_json" --task-id "DP-999-T2" >/dev/null 2>"$tmpdir/intent-only.stderr"; then
  echo "FAIL [case 3a / DP-341 T2]: derive rejected intent-only refinement.json missing allowed_files (regime 3 must succeed)" >&2
  cat "$tmpdir/intent-only.stderr" >&2
  exit 1
fi

# Sub-case 3b (AC-NEG9): a genuinely-still-required structural field (scope)
# omitted -> fail-loud + names the missing field.
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
      "title": "Missing scope",
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
  echo "FAIL [case 3b / AC-NEG9]: script accepted refinement.json missing required field scope" >&2
  exit 1
fi
if ! grep -q "scope" "$tmpdir/neg.stderr"; then
  echo "FAIL [case 3b / AC-NEG9]: script did not surface the missing field name" >&2
  cat "$tmpdir/neg.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 4 (AC-NEG9): unknown task id -> fail-loud.
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
# Case 5 (AC-NEG9): missing refinement.json file -> fail-loud.
# ---------------------------------------------------------------------------
if bash "$SCRIPT" --refinement-json "$tmpdir/does-not-exist.json" --task-id "DP-999-T1" >/dev/null 2>"$tmpdir/missing.stderr"; then
  echo "FAIL [case 5 / AC-NEG9]: script accepted missing refinement.json" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 6 (DP-231 D45): V tasks derive the V-mode schema.
# ---------------------------------------------------------------------------
v_json="$tmpdir/refinement-v.json"
cat >"$v_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-999-sample",
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
        "detail": "bash scripts/validate-config-driven-authoring.sh"
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
        "detail": "bash scripts/validate-config-driven-authoring.sh"
      }
    },
    {
      "id": "DP-999-V1",
      "kind": "verification",
      "title": "範例 umbrella 驗收",
      "scope": "驗收 T task 的 AC。",
      "allowed_files": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["DP-999-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh"
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
# V references are container-derived too (AC3 / AC2 -- no hardcoded design-plans literal).
if ! grep -qF -- "docs-manager/src/content/docs/specs/design-plans/DP-999-sample/refinement.json" "$v_out"; then
  echo "FAIL [case 6 / AC3]: V references not derived from container path" >&2
  cat "$v_out" >&2
  exit 1
fi
bash "$VALIDATE_TASK_MD" "$v_out" >/dev/null 2>&1 || {
  echo "FAIL [case 6 / D45]: derived V task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$v_out" >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# Case 7 (DP-260 AC-NEG1): CLI --task-id must be canonical full form.
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

# ===========================================================================
# DP-302 -- source.type-free derive: parity, field-driven body, references-by-
# container, constructability, fail-loud, back-compat.
# ===========================================================================

# write_refinement <dest> <type> <jira_key_cell:null|"KEY"> <repo:null|"slug"> \
#   <base_branch:null|"branch"> <container>
# Emits a refinement.json whose tasks[].T1 carries the SAME body fields for every
# call. Only the source/identity values differ between calls, so a structural diff
# of two derived task.md must come out empty (AC1).
write_refinement() {
  local dest="$1" stype="$2" jkey="$3" repo="$4" base="$5" container="$6"
  local repo_line="" base_line="" task_jkey_line=""
  [[ "$repo" != "null" ]] && repo_line="\"repo\": \"$repo\","
  [[ "$base" != "null" ]] && base_line="\"base_branch\": \"$base\","
  [[ "$jkey" != "null" ]] && task_jkey_line="\"jira_key\": \"$jkey\","
  cat >"$dest" <<JSON
{
  "source": {
    "type": "$stype",
    "id": "DP-500",
    $repo_line
    $base_line
    "container": "$container",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      $task_jkey_line
      "title": "parity task",
      "scope": "驗證 source.type-free parity。",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" },
        "test_environment": { "level": "static" },
        "references": ["scripts/sample.sh"]
      }
    }
  ]
}
JSON
}

# structural_skeleton <task.md> -- reduce a task.md to its STRUCTURE: frontmatter
# keys (left of ':'), section headings, and table-row column COUNT (cell content
# blanked). Two task.md with the same structure but different values normalize to
# the same skeleton.
structural_skeleton() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
out = []
in_fm = False
fm_seen = 0
for line in text.splitlines():
    if line.strip() == "---":
        fm_seen += 1
        in_fm = fm_seen == 1
        out.append("FM_DELIM")
        continue
    if in_fm:
        m = re.match(r"^(\s*)([A-Za-z_][\w-]*):", line)
        if m:
            out.append(f"FM_KEY {m.group(1)}{m.group(2)}")
        elif line.strip() == "":
            out.append("FM_BLANK")
        else:
            out.append("FM_OTHER")
        continue
    if line.startswith("#"):
        out.append("HEAD " + line.strip())
        continue
    if line.lstrip().startswith("|"):
        out.append(f"ROW cols={line.count('|')}")
        continue
    if line.startswith("```"):
        out.append("FENCE")
        continue
    if line.strip() == "":
        out.append("BLANK")
        continue
    out.append("TEXT")
print("\n".join(out))
PY
}

# --- Case 8 (AC1 / AC2): same content fed dp vs jira -> identical STRUCTURE. ---
dp_parity="$tmpdir/parity-dp.json"
jira_parity="$tmpdir/parity-jira.json"
write_refinement "$dp_parity" "dp" "null" "null" "null" \
  "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-500-sample"
write_refinement "$jira_parity" "jira" "PROJ-201" "exampleco-web" "develop" \
  "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/PROJ-500"

dp_parity_out="$tmpdir/parity-dp.md"
jira_parity_out="$tmpdir/parity-jira.md"
bash "$SCRIPT" --refinement-json "$dp_parity" --task-id "DP-500-T1" > "$dp_parity_out"
bash "$SCRIPT" --refinement-json "$jira_parity" --task-id "DP-500-T1" > "$jira_parity_out"

bash "$VALIDATE_TASK_MD" "$dp_parity_out" >/dev/null 2>&1 || {
  echo "FAIL [case 8 / AC1]: dp parity task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$dp_parity_out" >&2 || true
  exit 1
}
bash "$VALIDATE_TASK_MD" "$jira_parity_out" >/dev/null 2>&1 || {
  echo "FAIL [case 8 / AC1]: jira parity task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$jira_parity_out" >&2 || true
  exit 1
}

structural_skeleton "$dp_parity_out" > "$tmpdir/skel-dp.txt"
structural_skeleton "$jira_parity_out" > "$tmpdir/skel-jira.txt"
if ! cmp -s "$tmpdir/skel-dp.txt" "$tmpdir/skel-jira.txt"; then
  echo "FAIL [case 8 / AC1]: dp vs jira derived task.md differ in STRUCTURE, not just values" >&2
  diff "$tmpdir/skel-dp.txt" "$tmpdir/skel-jira.txt" | head -40 >&2
  exit 1
fi

# Structures match; values still differ on the expected cells (AC2: field-driven).
grep -qF "| JIRA key | N/A |" "$dp_parity_out" || {
  echo "FAIL [case 8 / AC2]: dp jira_key cell did not render N/A" >&2; cat "$dp_parity_out" >&2; exit 1; }
grep -qF "| Task ID | DP-500-T1 |" "$dp_parity_out" || {
  echo "FAIL [case 8 / AC2]: dp identity not local task id" >&2; exit 1; }
grep -qF "| Base branch | main |" "$dp_parity_out" || {
  echo "FAIL [case 8 / AC2]: dp base branch not main" >&2; exit 1; }
grep -qF "| Repo: polaris-framework" "$dp_parity_out" || {
  echo "FAIL [case 8 / AC2]: dp repo not polaris-framework default" >&2; exit 1; }

grep -qF "| JIRA key | PROJ-201 |" "$jira_parity_out" || {
  echo "FAIL [case 8 / AC2]: jira jira_key cell did not render the real key" >&2; cat "$jira_parity_out" >&2; exit 1; }
grep -qF "| Task ID | PROJ-201 |" "$jira_parity_out" || {
  echo "FAIL [case 8 / AC2]: jira identity not the per-task jira_key" >&2; exit 1; }
grep -qF "| Base branch | develop |" "$jira_parity_out" || {
  echo "FAIL [case 8 / AC2]: jira base branch not source.base_branch" >&2; exit 1; }
grep -qF "| Repo: exampleco-web" "$jira_parity_out" || {
  echo "FAIL [case 8 / AC2]: jira repo not source.repo" >&2; exit 1; }

# --- Case 8b (DP-364 D1): per-task repo/base_branch override source-level
# repo/base, and changeset detection uses the per-task repo root.
task_repo_root="$tmpdir/task-repo"
mkdir -p "$task_repo_root/.changeset"
printf '{"changelog": false}\n' > "$task_repo_root/.changeset/config.json"
per_task_repo_json="$tmpdir/refinement-per-task-repo.json"
cat >"$per_task_repo_json" <<JSON
{
  "source": {
    "type": "jira",
    "id": "PROJ-777",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/PROJ-777",
    "repo": "source-repo",
    "base_branch": "develop"
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "jira_key": "PROJ-778",
      "repo": "$task_repo_root",
      "base_branch": "release/task-repo",
      "title": "per task repo override",
      "scope": "驗證 per-task repo/base_branch override 會覆蓋 source-level 欄位。",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/sample.sh",
        "verify_command": "bash scripts/sample.sh",
        $BODY_BC,
        $BODY_TE,
        $BODY_REFS
      }
    }
  ]
}
JSON
per_task_repo_out="$tmpdir/per-task-repo.md"
bash "$SCRIPT" --refinement-json "$per_task_repo_json" --task-id "PROJ-777-T1" > "$per_task_repo_out"
grep -qF "| Base branch | release/task-repo |" "$per_task_repo_out" || {
  echo "FAIL [case 8b / DP-364 D1]: Base branch did not use tasks[].base_branch" >&2
  cat "$per_task_repo_out" >&2
  exit 1
}
grep -qF "| Repo: $task_repo_root" "$per_task_repo_out" || {
  echo "FAIL [case 8b / DP-364 D1]: Repo did not use tasks[].repo" >&2
  cat "$per_task_repo_out" >&2
  exit 1
}
if grep -qF -- "- \`.changeset/" "$per_task_repo_out"; then
  echo "FAIL [case 8b / DP-423 AC17]: per-task repo leaked exact changeset path" >&2
  cat "$per_task_repo_out" >&2
  exit 1
fi

# --- Case 9 (AC2): zero source_type== branch in the derive CODE. The only allowed
# use is reading source.type for the rendered "Source type" cell value. Strip
# python comment lines first so documentation prose mentioning the old pattern
# does not false-positive; the assertion is about executable code. ---
if grep -vE '^[[:space:]]*#' "$SCRIPT" | grep -nE 'source_type[[:space:]]*=='; then
  echo "FAIL [case 9 / AC2]: derive still contains a source_type== branch in code" >&2
  exit 1
fi

# --- Case 10 (AC3): references track the container type. jira -> companies/. ---
if ! grep -qF -- "docs-manager/src/content/docs/specs/companies/exampleco/PROJ-500/refinement.json" "$jira_parity_out"; then
  echo "FAIL [case 10 / AC3]: jira references not derived from companies/ container" >&2
  cat "$jira_parity_out" >&2
  exit 1
fi
if grep -qF -- "design-plans/" "$jira_parity_out"; then
  echo "FAIL [case 10 / AC3]: jira task.md leaked a design-plans/ literal" >&2
  cat "$jira_parity_out" >&2
  exit 1
fi

# --- Case 11 (AC3): the Verify Command fence has NO unconditional framework tail
# (no check-script-manifest, no echo PASS) -- body is the field-driven command. ---
verify_fence="$tmpdir/verify-fence.txt"
awk '/^## Verify Command$/ {capture=1; next} capture && /^```bash$/ {next} capture && /^```$/ {exit} capture {print}' "$jira_parity_out" >"$verify_fence"
if grep -q 'check-script-manifest' "$verify_fence"; then
  echo "FAIL [case 11 / AC3]: Verify Command still emits the unconditional framework manifest tail" >&2
  cat "$verify_fence" >&2
  exit 1
fi
if grep -qE 'echo "PASS:' "$verify_fence"; then
  echo "FAIL [case 11 / AC3]: Verify Command still emits the unconditional framework echo PASS tail" >&2
  cat "$verify_fence" >&2
  exit 1
fi
if ! grep -q 'bash scripts/validate-config-driven-authoring.sh' "$verify_fence"; then
  echo "FAIL [case 11 / AC3]: Verify Command fence missing the field-driven verify_command" >&2
  cat "$verify_fence" >&2
  exit 1
fi

# --- Case 11b (DP-386 bootstrap): multiline verify_command must not be inlined
# into the Gate Closure Matrix table cell. The complete command remains in the
# fenced Verify Command block, while the table row uses a stable one-line pass
# condition that validate-task-md.sh can parse. ---
multiline_cmd_json="$tmpdir/multiline-command.json"
cat >"$multiline_cmd_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-501", "container": "/tmp/dp-501", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-501-T1",
      "kind": "implementation",
      "title": "multiline verify command",
      "scope": "驗證多行 verify_command 不會破壞 Gate Closure Matrix table。",
      "allowed_files": ["scripts/derive-task-md-from-refinement-json.sh"],
      "modules": ["scripts/derive-task-md-from-refinement-json.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "multiline verify command fixture",
        "verify_command": "echo PASS\nprintf '%s\\n' PASS",
        "behavior_contract": { "applies": false, "reason": "framework renderer fixture；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "references": []
      }
    }
  ]
}
JSON
mkdir -p "$tmpdir/multiline/T1"
multiline_cmd_out="$tmpdir/multiline/T1/index.md"
bash "$SCRIPT" --refinement-json "$multiline_cmd_json" --task-id "DP-501-T1" > "$multiline_cmd_out"
gate_matrix="$tmpdir/multiline-gate-matrix.txt"
awk '/^## Gate Closure Matrix$/ {capture=1; next} capture && /^## / {exit} capture {print}' "$multiline_cmd_out" >"$gate_matrix"
if ! grep -qF -- "| verify | yes | Verify Command exits 0 | engineering |" "$gate_matrix"; then
  echo "FAIL [case 11b / DP-386]: multiline verify_command did not render as a stable one-line gate summary" >&2
  cat "$gate_matrix" >&2
  exit 1
fi
if grep -qF -- "printf '%s\\n' PASS" "$gate_matrix"; then
  echo "FAIL [case 11b / DP-386]: raw multiline verify_command leaked into Gate Closure Matrix" >&2
  cat "$gate_matrix" >&2
  exit 1
fi
awk '/^## Verify Command$/ {capture=1; next} capture && /^```bash$/ {next} capture && /^```$/ {exit} capture {print}' "$multiline_cmd_out" >"$verify_fence"
if ! grep -qF -- "echo PASS" "$verify_fence" || ! grep -qF -- "printf '%s\\n' PASS" "$verify_fence"; then
  echo "FAIL [case 11b / DP-386]: Verify Command fence did not preserve the full multiline command" >&2
  cat "$verify_fence" >&2
  exit 1
fi
bash "$VALIDATE_BREAKDOWN_READY" "$multiline_cmd_out" >/tmp/derive-multiline-breakdown-ready.out 2>&1 || {
  echo "FAIL [case 11b / DP-386]: multiline-derived task.md should be breakdown-ready" >&2
  cat /tmp/derive-multiline-breakdown-ready.out >&2
  exit 1
}

# --- Case 12 (AC3): behavior_contract / test_environment come from the fields.
# Flip the field values and assert the output tracks them (no hardcoded default). ---
bc_true_json="$tmpdir/bc-true.json"
cat >"$bc_true_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "runtime task",
      "scope": "驗證 behavior_contract / test_environment 由欄位驅動。",
      "allowed_files": ["src/app.ts", "src/app.test.ts"],
      "modules": ["src/app.ts"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "pnpm vitest run src/app.test.ts",
        "verify_command": "pnpm vitest run src/app.test.ts",
        "behavior_contract": { "applies": true, "mode": "parity", "source_of_truth": "existing_behavior", "fixture_policy": "live_allowed", "flow": "載入頁面並比對既有行為", "assertions": ["回應結構不變", "互動行為一致"] },
        "test_environment": { "level": "integration", "env_bootstrap_command": "pnpm install" },
        "references": []
      }
    }
  ]
}
JSON
bc_true_out="$tmpdir/bc-true.md"
bash "$SCRIPT" --refinement-json "$bc_true_json" --task-id "DP-500-T1" > "$bc_true_out"
if ! grep -qE '^[[:space:]]+applies: true$' "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.applies=true not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if ! grep -qE '^[[:space:]]+mode: parity$' "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.mode not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
# DP-302 revision: applies=true must render the FULL sub-field set that
# validate-task-md.sh requires (source_of_truth / fixture_policy / flow /
# assertions), not just applies+mode.
if ! grep -qE '^[[:space:]]+source_of_truth: existing_behavior$' "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.source_of_truth not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if ! grep -qE '^[[:space:]]+fixture_policy: live_allowed$' "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.fixture_policy not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if ! grep -qF -- "    flow: 載入頁面並比對既有行為" "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.flow not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if ! grep -qE '^[[:space:]]+assertions:$' "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.assertions list not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if ! grep -qF -- "      - 回應結構不變" "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: behavior_contract.assertions entry not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
# An applies=true derived task.md must itself pass validate-task-md.sh (the
# pre-existing validator requires the full sub-field set when applies=true).
bash "$VALIDATE_TASK_MD" "$bc_true_out" >/dev/null 2>&1 || {
  echo "FAIL [case 12 / AC3]: applies=true derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$bc_true_out" >&2 || true
  exit 1
}
if ! grep -qF -- "- **Level**: build" "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: test_environment.level not rendered from field" >&2
  cat "$bc_true_out" >&2
  exit 1
fi
if grep -qF -- "framework deterministic gate / selftest / helper" "$bc_true_out"; then
  echo "FAIL [case 12 / AC3]: field-driven task leaked the hardcoded framework behavior_contract reason" >&2
  cat "$bc_true_out" >&2
  exit 1
fi

# --- Case 13 (AC4): constructability bar -- a body that declares a test runner
# verify_command/Test Command but a static Test Environment must be judged FAIL by
# validate-breakdown-ready.sh (the DP-269 false-completion path). ---
construct_json="$tmpdir/construct.json"
cat >"$construct_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "constructability contradiction",
      "scope": "驗證 test runner + static env 的合成 case 被 validate-breakdown-ready 判 FAIL。",
      "allowed_files": ["src/app.ts", "src/app.test.ts"],
      "modules": ["src/app.ts"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "pnpm vitest run src/app.test.ts",
        "verify_command": "pnpm vitest run src/app.test.ts",
        "behavior_contract": { "applies": false, "reason": "no runtime behavior" },
        "test_environment": { "level": "static" },
        "references": []
      }
    }
  ]
}
JSON
# validate-breakdown-ready resolves a task id only from a real task path
# (`.../T<n>.md` or `.../T<n>/index.md`); a loose tmp filename yields a vacuous
# PASS. Materialize the derived body at a canonical task path so the gate runs.
mkdir -p "$tmpdir/construct/T1"
construct_out="$tmpdir/construct/T1/index.md"
bash "$SCRIPT" --refinement-json "$construct_json" --task-id "DP-500-T1" > "$construct_out"
if bash "$VALIDATE_BREAKDOWN_READY" "$construct_out" >"$tmpdir/construct.ready" 2>&1; then
  echo "FAIL [case 13 / AC4]: test-runner + static env task.md wrongly passed validate-breakdown-ready.sh" >&2
  cat "$tmpdir/construct.ready" >&2
  echo "--- derived task.md ---" >&2
  cat "$construct_out" >&2
  exit 1
fi

# --- Case 14 (AC4): a coherent dp task.md (static env + non-runner Verify) passes
# validate-breakdown-ready.sh -- the bar only trips on the contradiction. The
# derived body is materialized at a canonical task path for the same reason. ---
mkdir -p "$tmpdir/coherent/T1"
coherent_out="$tmpdir/coherent/T1/index.md"
bash "$SCRIPT" --refinement-json "$dp_parity" --task-id "DP-500-T1" > "$coherent_out"
if ! bash "$VALIDATE_BREAKDOWN_READY" "$coherent_out" >"$tmpdir/dp-ready.out" 2>&1; then
  echo "FAIL [case 14 / AC4]: coherent dp task.md did not pass validate-breakdown-ready.sh" >&2
  cat "$tmpdir/dp-ready.out" >&2
  cat "$coherent_out" >&2
  exit 1
fi

# --- Case 15 (AC-NEG1): a task declaring SOME body fields but omitting a required
# one fails fail-loud naming the missing field -- no silent framework default. ---
partial_json="$tmpdir/partial.json"
cat >"$partial_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "partial body fields",
      "scope": "Negative -- declares test_environment but drops behavior_contract.",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "test_environment": { "level": "static" }
      }
    }
  ]
}
JSON
if bash "$SCRIPT" --refinement-json "$partial_json" --task-id "DP-500-T1" >/dev/null 2>"$tmpdir/partial.stderr"; then
  echo "FAIL [case 15 / AC-NEG1]: derive silently accepted a partial body-field task" >&2
  exit 1
fi
if ! grep -q "behavior_contract" "$tmpdir/partial.stderr"; then
  echo "FAIL [case 15 / AC-NEG1]: fail-loud did not name the missing body field" >&2
  cat "$tmpdir/partial.stderr" >&2
  exit 1
fi

# --- Case 15b (AC-NEG1): behavior_contract.applies=false WITHOUT reason ->
# fail-loud (no framework default reason injected). ---
noreason_json="$tmpdir/noreason.json"
cat >"$noreason_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "missing reason",
      "scope": "Negative -- applies=false but no reason.",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "behavior_contract": { "applies": false },
        "test_environment": { "level": "static" }
      }
    }
  ]
}
JSON
if bash "$SCRIPT" --refinement-json "$noreason_json" --task-id "DP-500-T1" >/dev/null 2>"$tmpdir/noreason.stderr"; then
  echo "FAIL [case 15b / AC-NEG1]: derive accepted applies=false with no reason" >&2
  exit 1
fi
if ! grep -q "reason" "$tmpdir/noreason.stderr"; then
  echo "FAIL [case 15b / AC-NEG1]: fail-loud did not name the missing reason" >&2
  cat "$tmpdir/noreason.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 16 (AC-NEG2 / back-compat): a dp task with NO body fields still derives a
# valid task.md via the legacy framework-infra default path (existing work orders
# predate the fields). It must pass validate-task-md.sh and be deterministic.
# ---------------------------------------------------------------------------
nobody_json="$tmpdir/nobody.json"
cat >"$nobody_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "legacy no-body task",
      "scope": "Back-compat -- no per-task body fields declared.",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh"
      }
    }
  ]
}
JSON
nobody_out="$tmpdir/nobody.md"
bash "$SCRIPT" --refinement-json "$nobody_json" --task-id "DP-500-T1" > "$nobody_out"
bash "$VALIDATE_TASK_MD" "$nobody_out" >/dev/null 2>&1 || {
  echo "FAIL [case 16 / AC-NEG2]: legacy no-body derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$nobody_out" >&2 || true
  exit 1
}
nobody_out_b="$tmpdir/nobody-b.md"
bash "$SCRIPT" --refinement-json "$nobody_json" --task-id "DP-500-T1" > "$nobody_out_b"
cmp -s "$nobody_out" "$nobody_out_b" || {
  echo "FAIL [case 16 / AC-NEG2]: legacy no-body derive is not deterministic" >&2; exit 1; }

# --- Case 16b (AC-NEG2): backfilling the equivalent legacy framework defaults as
# explicit fields reproduces the legacy frontmatter behavior_contract + Test
# Environment Level / Fixtures (equivalent output). ---
backfill_json="$tmpdir/backfill.json"
cat >"$backfill_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "legacy no-body task",
      "scope": "Back-compat -- no per-task body fields declared.",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh",
        "behavior_contract": { "applies": false, "reason": "framework deterministic gate / selftest / helper；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static", "fixtures": "tmpdir + repo-tracked selftest fixtures" },
        "references": []
      }
    }
  ]
}
JSON
backfill_out="$tmpdir/backfill.md"
bash "$SCRIPT" --refinement-json "$backfill_json" --task-id "DP-500-T1" > "$backfill_out"
for anchor in \
  '    applies: false' \
  "framework deterministic gate / selftest / helper；無 runtime / UI 行為變更" \
  "- **Level**: static" \
  "- **Fixtures**: tmpdir + repo-tracked selftest fixtures"; do
  if ! grep -qF -- "$anchor" "$backfill_out"; then
    echo "FAIL [case 16b / AC-NEG2]: backfilled body did not reproduce the legacy default anchor: $anchor" >&2
    cat "$backfill_out" >&2
    exit 1
  fi
  if ! grep -qF -- "$anchor" "$nobody_out"; then
    echo "FAIL [case 16b / AC-NEG2]: legacy no-body output missing expected anchor: $anchor" >&2
    cat "$nobody_out" >&2
    exit 1
  fi
done

# ===========================================================================
# DP-302 revision (V1 drift fix): an applies=true (runtime/product, PROJ-700-
# style) refinement.json with a COMPLETE behavior_contract must derive a task.md
# that the pre-existing validate-task-md.sh / validate-breakdown-ready.sh accept,
# i.e. the applies=true (jira/product) derive output must be CONSTRUCTIBLE. The
# previous applies=true branch rendered only applies+mode, dropping the sub-fields
# validate-task-md.sh requires (source_of_truth / fixture_policy / flow /
# assertions), so the output was not constructible. These cases close that gap.
# ===========================================================================

# --- Case 22 (DP-302 V1 / AC4): applies=true runtime/product task with a complete
# behavior_contract + coherent runtime env -> derive -> validate-breakdown-ready
# PASS (exit 0). Materialize at a real tasks/T*/index.md path (a loose tmp path
# vacuous-PASSes validate-breakdown-ready, so it would not exercise the gate). ---
applies_true_json="$tmpdir/applies-true.json"
cat >"$applies_true_json" <<'JSON'
{
  "source": { "type": "jira", "id": "DP-302", "repo": "exampleco-web", "base_branch": "develop", "container": "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/PROJ-700", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-302-T1",
      "kind": "implementation",
      "jira_key": "PROJ-701",
      "title": "runtime product task",
      "scope": "驗證 applies=true 的 runtime/product task 可被 derive 並通過 validate-breakdown-ready。",
      "allowed_files": ["src/components/Card.vue", "src/components/Card.test.ts"],
      "modules": ["src/components/Card.vue"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 3,
      "verification": {
        "method": "component_test",
        "detail": "pnpm vitest run src/components/Card.test.ts",
        "verify_command": "pnpm vitest run src/components/Card.test.ts",
        "behavior_contract": {
          "applies": true,
          "mode": "parity",
          "source_of_truth": "existing_behavior",
          "fixture_policy": "live_allowed",
          "flow": "載入卡片元件並比對既有渲染行為",
          "assertions": ["卡片標題與既有版本一致", "點擊事件行為不變"]
        },
        "test_environment": { "level": "integration", "env_bootstrap_command": "pnpm install" },
        "references": []
      }
    }
  ]
}
JSON
mkdir -p "$tmpdir/applies-true/T1"
applies_true_out="$tmpdir/applies-true/T1/index.md"
bash "$SCRIPT" --refinement-json "$applies_true_json" --task-id "DP-302-T1" > "$applies_true_out"
# Pre-existing validate-task-md.sh must accept the applies=true frontmatter.
bash "$VALIDATE_TASK_MD" "$applies_true_out" >/dev/null 2>&1 || {
  echo "FAIL [case 22 / DP-302 AC4]: applies=true derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$applies_true_out" >&2 || true
  cat "$applies_true_out" >&2
  exit 1
}
# Constructability: the derived task.md must pass validate-breakdown-ready (exit 0).
if ! bash "$VALIDATE_BREAKDOWN_READY" "$applies_true_out" >"$tmpdir/applies-true.ready" 2>&1; then
  echo "FAIL [case 22 / DP-302 AC4]: applies=true derived task.md did not pass validate-breakdown-ready.sh" >&2
  cat "$tmpdir/applies-true.ready" >&2
  echo "--- derived task.md ---" >&2
  cat "$applies_true_out" >&2
  exit 1
fi

# --- Case 23 (DP-302 V1 / AC-NEG1): applies=true missing a required sub-field
# (source_of_truth) -> fail-loud naming the missing field. No framework default. ---
applies_true_partial_json="$tmpdir/applies-true-partial.json"
cat >"$applies_true_partial_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-302", "container": "/tmp/dp-302", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-302-T1",
      "kind": "implementation",
      "title": "incomplete runtime contract",
      "scope": "Negative -- applies=true but source_of_truth omitted; derive must fail-loud.",
      "allowed_files": ["src/components/Card.vue", "src/components/Card.test.ts"],
      "modules": ["src/components/Card.vue"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 3,
      "verification": {
        "method": "component_test",
        "detail": "pnpm vitest run src/components/Card.test.ts",
        "verify_command": "pnpm vitest run src/components/Card.test.ts",
        "behavior_contract": {
          "applies": true,
          "mode": "parity",
          "flow": "載入卡片元件",
          "assertions": ["標題一致"]
        },
        "test_environment": { "level": "integration", "env_bootstrap_command": "pnpm install" },
        "references": []
      }
    }
  ]
}
JSON
if bash "$SCRIPT" --refinement-json "$applies_true_partial_json" --task-id "DP-302-T1" >/dev/null 2>"$tmpdir/applies-true-partial.stderr"; then
  echo "FAIL [case 23 / DP-302 AC-NEG1]: derive accepted applies=true missing source_of_truth" >&2
  exit 1
fi
if ! grep -q "source_of_truth" "$tmpdir/applies-true-partial.stderr"; then
  echo "FAIL [case 23 / DP-302 AC-NEG1]: fail-loud did not name the missing source_of_truth field" >&2
  cat "$tmpdir/applies-true-partial.stderr" >&2
  exit 1
fi
if ! grep -q "applies=true" "$tmpdir/applies-true-partial.stderr"; then
  echo "FAIL [case 23 / DP-302 AC-NEG1]: fail-loud message did not anchor on applies=true" >&2
  cat "$tmpdir/applies-true-partial.stderr" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 17 (DP-296 T3 / AC2): tasks[].task_shape propagates into T-task frontmatter.
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
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "task_shape": "confirmation",
      "title": "確認型 task",
      "scope": "驗證 canonical tasks[].task_shape 注入 T-task frontmatter。",
      "allowed_files": ["docs-manager/src/content/docs/specs/design-plans/DP-999-x/index.md"],
      "modules": ["docs-manager/src/content/docs/specs/design-plans/DP-999-x/index.md"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh"
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
        "detail": "bash scripts/validate-config-driven-authoring.sh"
      }
    }
  ]
}
JSON

shape_t1_out="$tmpdir/shape-t1.md"
bash "$SCRIPT" --refinement-json "$shape_json" --task-id "DP-999-T1" > "$shape_t1_out"
shape_t1_count=$(grep -c '^task_shape: confirmation$' "$shape_t1_out" || true)
if [[ "$shape_t1_count" -ne 1 ]]; then
  echo "FAIL [case 17 / DP-296 AC2]: expected exactly one 'task_shape: confirmation' line, got $shape_t1_count" >&2
  cat "$shape_t1_out" >&2
  exit 1
fi
if ! awk '/^task_kind: T$/{k=NR} /^task_shape: confirmation$/{if(NR==k+1){found=1}} END{exit found?0:1}' "$shape_t1_out"; then
  echo "FAIL [case 17 / DP-296 AC2]: task_shape line not directly after task_kind" >&2
  cat "$shape_t1_out" >&2
  exit 1
fi
shape_t2_out="$tmpdir/shape-t2.md"
bash "$SCRIPT" --refinement-json "$shape_json" --task-id "DP-999-T2" > "$shape_t2_out"
shape_t2_count=$(grep -c '^task_shape:' "$shape_t2_out" || true)
if [[ "$shape_t2_count" -ne 0 ]]; then
  echo "FAIL [case 17 / DP-296 AC2]: expected no task_shape line for T2 (absent), got $shape_t2_count" >&2
  cat "$shape_t2_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 18 (DP-296 T3 / AC2): V tasks must NEVER receive a task_shape line.
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
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "驗收 V task 不帶 task_shape。",
      "category": "functional",
      "quantifiable": true,
      "verification": { "method": "unit_test", "detail": "bash scripts/validate-config-driven-authoring.sh" }
    }
  ],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "task_shape": "confirmation",
      "title": "確認型 task",
      "scope": "驗證 T task。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/validate-config-driven-authoring.sh" }
    },
    {
      "id": "DP-999-V1",
      "kind": "verification",
      "task_shape": "audit",
      "title": "範例 umbrella 驗收",
      "scope": "驗收 T task。",
      "allowed_files": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["DP-999-T1"],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/validate-config-driven-authoring.sh" }
    }
  ]
}
JSON

mkdir -p "$tmpdir/V1-shape"
v_shape_out="$tmpdir/V1-shape/index.md"
bash "$SCRIPT" --refinement-json "$v_shape_json" --task-id "DP-999-V1" > "$v_shape_out"
v_shape_count=$(grep -c '^task_shape:' "$v_shape_out" || true)
if [[ "$v_shape_count" -ne 0 ]]; then
  echo "FAIL [case 18 / DP-296 AC2]: V task must never carry task_shape, got $v_shape_count line(s)" >&2
  cat "$v_shape_out" >&2
  exit 1
fi
if ! grep -qF 'depends_on: [DP-999-T1]' "$v_shape_out"; then
  echo "FAIL [case 18 / DP-412 AC1]: V task dependency did not reach frontmatter" >&2
  cat "$v_shape_out" >&2
  exit 1
fi
if ! grep -qF '| Depends on | DP-999-T1 |' "$v_shape_out"; then
  echo "FAIL [case 18 / DP-412 AC2]: V task dependency did not reach Operational Context" >&2
  cat "$v_shape_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 19 (DP-296 T3 / AC2): derive is passthrough-only; a typo'd task_shape is
# emitted verbatim and rejected by the single classifier validate-task-md.sh.
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
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "task_shape": "confirmaton",
      "title": "typo shape task",
      "scope": "驗證 derive passthrough 不做 enum 驗證。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": { "method": "unit_test", "detail": "bash scripts/validate-config-driven-authoring.sh" }
    }
  ]
}
JSON

typo_out="$tmpdir/typo-t1.md"
bash "$SCRIPT" --refinement-json "$typo_json" --task-id "DP-999-T1" > "$typo_out"
if ! grep -q '^task_shape: confirmaton$' "$typo_out"; then
  echo "FAIL [case 19 / DP-296 AC2]: derive must passthrough typo'd task_shape verbatim" >&2
  cat "$typo_out" >&2
  exit 1
fi
if bash "$VALIDATE_TASK_MD" "$typo_out" >/dev/null 2>&1; then
  echo "FAIL [case 19 / DP-296 AC2]: validate-task-md.sh accepted invalid task_shape enum" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 20 (DP-296 AC-NEG1): the production derive script no longer reads the
# removed top-level planned_tasks[] key.
# ---------------------------------------------------------------------------
if grep -q 'planned_tasks' "$SCRIPT"; then
  echo "FAIL [case 20 / AC-NEG1]: production derive script still references planned_tasks[]" >&2
  grep -n 'planned_tasks' "$SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 21 (DP-269 AC5, retained): derive remains pure stdlib python3.
# ---------------------------------------------------------------------------
if ! head -1 "$SCRIPT" | grep -q 'env bash'; then
  echo "FAIL [case 21 / DP-269 AC5]: derive script shebang changed" >&2
  exit 1
fi
# subprocess joined the allowlist with DP-311 T6: derive delegates the verify
# command executability verdict to the shared helper via subprocess (stdlib).
if grep -E '^[[:space:]]*(import|from)[[:space:]]' "$SCRIPT" | grep -vqE '^[[:space:]]*(import|from)[[:space:]]+(json|re|subprocess|sys|unicodedata|pathlib|hashlib|datetime)'; then
  echo "FAIL [case 21 / DP-269 AC5]: derive script imports a non-stdlib module" >&2
  grep -E '^[[:space:]]*(import|from)[[:space:]]' "$SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 22 (DP-311 AC8): the DP-252-T1 original prose detail (no verify_command)
# must fail-close — exit 2, POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker, and
# NO task.md body on stdout (the prose fallback is removed).
# ---------------------------------------------------------------------------
prose_json="$tmpdir/refinement-dp252-prose.json"
cat >"$prose_json" <<'JSON'
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
      "title": "prose verify command task",
      "scope": "驗證 prose Verify Command 會被 derive fail-closed 攔下。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "set -euo pipefail\n檔案 existence + frontmatter assert + 5 H2 sections grep + language table 4 rows + 每 row code block fence\n+ Don't/Do >= 2 對 + grandfather/new-modified/modified-邊界 wording + advisory/reviewer-signoff/mechanism-registry\npointer wording + wc -l <= 500 + 2 個 gate replay"
      }
    }
  ]
}
JSON

prose_out="$tmpdir/prose-t1.md"
prose_err="$tmpdir/prose-t1.err"
set +e
bash "$SCRIPT" --refinement-json "$prose_json" --task-id "DP-999-T1" >"$prose_out" 2>"$prose_err"
prose_rc=$?
set -e
if [[ "$prose_rc" -ne 2 ]]; then
  echo "FAIL [case 22 / DP-311 AC8]: derive must exit 2 on DP-252-T1 prose verify command (got rc=$prose_rc)" >&2
  cat "$prose_err" >&2
  exit 1
fi
if ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$prose_err"; then
  echo "FAIL [case 22 / DP-311 AC8]: derive stderr missing POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker" >&2
  cat "$prose_err" >&2
  exit 1
fi
if [[ -s "$prose_out" ]]; then
  echo "FAIL [case 22 / DP-311 AC8]: derive emitted a task.md body despite the executability violation" >&2
  cat "$prose_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 23 (DP-311 AC8 / EC11): CJK prose that bash -n happily parses (a CJK
# bare word becomes a command name) must still fail-close — the outside-quote
# CJK check is the primary interceptor, applied to verify_command too.
# ---------------------------------------------------------------------------
cjk_cmd_json="$tmpdir/refinement-cjk-command.json"
cat >"$cjk_cmd_json" <<'JSON'
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
      "title": "cjk bare word verify command task",
      "scope": "驗證 bash -n 可 parse 的 CJK prose 仍被 quote 外 CJK 檢查攔下。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "檔案 existence + frontmatter assert"
      }
    }
  ]
}
JSON

cjk_cmd_err="$tmpdir/cjk-cmd.err"
set +e
bash "$SCRIPT" --refinement-json "$cjk_cmd_json" --task-id "DP-999-T1" >/dev/null 2>"$cjk_cmd_err"
cjk_cmd_rc=$?
set -e
if [[ "$cjk_cmd_rc" -ne 2 ]] || ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$cjk_cmd_err"; then
  echo "FAIL [case 23 / DP-311 AC8]: bash-parseable CJK prose verify_command must exit 2 with marker (got rc=$cjk_cmd_rc)" >&2
  cat "$cjk_cmd_err" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 24 (DP-311 AC-NEG7): a verify_command with a quoted CJK grep pattern is
# legal — derive must succeed and render the pattern verbatim in the fences.
# ---------------------------------------------------------------------------
quoted_cjk_json="$tmpdir/refinement-quoted-cjk.json"
cat >"$quoted_cjk_json" <<'JSON'
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
      "title": "quoted cjk verify command task",
      "scope": "驗證 quoted CJK grep pattern 是合法可執行命令、零誤擋。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "grep -q '既有未動' .claude/rules/handbook/code-documentation-conventions.md && bash scripts/validate-config-driven-authoring.sh"
      }
    }
  ]
}
JSON

quoted_cjk_out="$tmpdir/quoted-cjk-t1.md"
bash "$SCRIPT" --refinement-json "$quoted_cjk_json" --task-id "DP-999-T1" >"$quoted_cjk_out" || {
  echo "FAIL [case 24 / DP-311 AC-NEG7]: quoted CJK grep pattern verify_command was falsely blocked" >&2
  exit 1
}
if ! grep -qF -- "grep -q '既有未動'" "$quoted_cjk_out"; then
  echo "FAIL [case 24 / DP-311 AC-NEG7]: quoted CJK pattern not rendered verbatim in derived task.md" >&2
  cat "$quoted_cjk_out" >&2
  exit 1
fi

# ===========================================================================
# DP-423 — repo-native changeset policy removes task Allowed-Files injection.
# Repo config presence, product/framework routing, and CJK titles must not change
# task packaging. Re-derive remains byte-idempotent.
# ===========================================================================

# A minimal refinement.json reused by the repo-policy cases. The task title carries
# a CJK segment to ensure no hidden filename ceremony returns. Body fields are present so
# the derived task.md is a complete, valid work order.
make_dp344_refinement() {
  # Args: $1 = output json path, $2 = task title
  local out="$1" title="$2"
  cat >"$out" <<JSON
{
  "source": {
    "type": "dp",
    "id": "DP-344",
    "container": "/tmp/dp-344",
    "plan_path": "/tmp/dp-344/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-344-T1",
      "kind": "implementation",
      "title": "$title",
      "scope": "changeset derive injection scope.",
      "allowed_files": ["scripts/derive-task-md-from-refinement-json.sh"],
      "modules": ["scripts/derive-task-md-from-refinement-json.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      $BODY_BC,
      $BODY_TE,
      $BODY_REFS,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh"
      }
    }
  ]
}
JSON
}

# Build a hermetic changeset-config repo-root fixture (just needs the marker file).
cs_repo="$tmpdir/dp344-changeset-repo"
mkdir -p "$cs_repo/.changeset"
echo '{ "changelog": "@changesets/cli/changelog" }' >"$cs_repo/.changeset/config.json"

# A non-changeset repo-root fixture (no .changeset/config.json).
nocs_repo="$tmpdir/dp344-plain-repo"
mkdir -p "$nocs_repo"

# ---------------------------------------------------------------------------
# Case 25 (DP-423 AC17): changeset-enabled repos do not alter task packaging.
# Exact changeset filenames are repo-native producer output, not Allowed Files.
# ---------------------------------------------------------------------------
dp344_title_ascii="changeset allowed files derive injection"
dp344_ref_ascii="$tmpdir/dp344-ascii.json"
make_dp344_refinement "$dp344_ref_ascii" "$dp344_title_ascii"

dp344_out_ascii="$tmpdir/dp344-ascii.md"
bash "$SCRIPT" --refinement-json "$dp344_ref_ascii" --task-id "DP-344-T1" \
  --repo-root "$cs_repo" >"$dp344_out_ascii" || {
  echo "FAIL [case 25 / DP-344 AC1]: derive failed on changeset repo fixture" >&2
  exit 1
}

allowed_section_ascii="$(awk '/^## Allowed Files/{f=1;next} /^## /{f=0} f' "$dp344_out_ascii")"
if printf '%s\n' "$allowed_section_ascii" | grep -qF -- '.changeset/'; then
  echo "FAIL [case 25 / DP-423 AC17]: changeset repo injected exact path into Allowed Files" >&2
  cat "$dp344_out_ascii" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 26: CJK title does not reintroduce a hidden exact-path field or entry.
# ---------------------------------------------------------------------------
dp344_title_cjk="changeset 注入 derive 移除 carve-out"
dp344_ref_cjk="$tmpdir/dp344-cjk.json"
make_dp344_refinement "$dp344_ref_cjk" "$dp344_title_cjk"

dp344_out_cjk="$tmpdir/dp344-cjk.md"
bash "$SCRIPT" --refinement-json "$dp344_ref_cjk" --task-id "DP-344-T1" \
  --repo-root "$cs_repo" >"$dp344_out_cjk" || {
  echo "FAIL [case 26 / DP-344 AC4]: derive failed on CJK-title changeset fixture" >&2
  exit 1
}

allowed_section_cjk="$(awk '/^## Allowed Files/{f=1;next} /^## /{f=0} f' "$dp344_out_cjk")"
if printf '%s\n' "$allowed_section_cjk" | grep -qF -- '.changeset/'; then
  echo "FAIL [case 26 / DP-423 AC17]: CJK title injected changeset path" >&2
  cat "$dp344_out_cjk" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 27: repo config presence has no task-shape effect.
# ---------------------------------------------------------------------------
dp344_out_nocs="$tmpdir/dp344-nocs.md"
bash "$SCRIPT" --refinement-json "$dp344_ref_ascii" --task-id "DP-344-T1" \
  --repo-root "$nocs_repo" >"$dp344_out_nocs" || {
  echo "FAIL [case 27 / DP-344 AC-NEG1]: derive failed on non-changeset repo fixture" >&2
  exit 1
}
if ! cmp -s "$dp344_out_ascii" "$dp344_out_nocs"; then
  echo "FAIL [case 27 / DP-423 AC17]: repo config changed task packaging" >&2
  diff "$dp344_out_ascii" "$dp344_out_nocs" >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 28: re-derive remains byte-idempotent after ceremony retirement.
# ---------------------------------------------------------------------------
dp344_out_redo="$tmpdir/dp344-ascii-redo.md"
bash "$SCRIPT" --refinement-json "$dp344_ref_ascii" --task-id "DP-344-T1" \
  --repo-root "$cs_repo" >"$dp344_out_redo" || {
  echo "FAIL [case 28 / DP-344 AC-NEG2]: re-derive failed on changeset fixture" >&2
  exit 1
}
if ! cmp -s "$dp344_out_ascii" "$dp344_out_redo"; then
  echo "FAIL [case 28 / DP-344 AC-NEG2]: re-derive is not byte-identical (idempotency broken)" >&2
  diff "$dp344_out_ascii" "$dp344_out_redo" >&2 || true
  exit 1
fi
# ===========================================================================
# DP-359 T1 (AC1 / AC-NEG2) — framework-infra default = per-task self-contained.
#
# The framework-infra `## Verification Handoff` branch (applies=false, no
# visual_regression) must NOT emit the phantom umbrella-V1 delegation
# `驗收委派給 {source_id}-V1（umbrella regression）`, and the `## Operational
# Context` table must NOT carry the two hardcoded `N/A - framework work order`
# rows (Test sub-tasks / AC 驗收單). A legacy no-body task must derive without
# failing AND without umbrella prose (AC-NEG2).
# ===========================================================================

DP359_PHANTOM_DELEGATION='V1（umbrella regression）'
DP359_PHANTOM_VERB='驗收委派給'
DP359_DEAD_ROW='Test sub-tasks | N/A - framework work order'

# --- Case 29 (DP-359 AC1): framework-infra task (applies=false, no VR) must NOT
# emit the phantom umbrella delegation in `## Verification Handoff`, and must NOT
# carry the dead `N/A - framework work order` Operational Context rows. ---
dp359_infra_json="$tmpdir/dp359-infra.json"
cat >"$dp359_infra_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/design-plans/DP-999-sample",
    "plan_path": "/tmp/dp-999/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "title": "framework deterministic derive 條件化",
      "scope": "純 framework deterministic gate / selftest；無 runtime / UI 行為變更。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh",
        "behavior_contract": { "applies": false, "reason": "framework infra; no runtime behavior" },
        "test_environment": { "level": "static" },
        "references": ["scripts/sample.sh"]
      }
    }
  ]
}
JSON

dp359_infra_out="$tmpdir/dp359-infra.md"
bash "$SCRIPT" --refinement-json "$dp359_infra_json" --task-id "DP-999-T1" > "$dp359_infra_out"

if grep -qF -- "$DP359_PHANTOM_DELEGATION" "$dp359_infra_out"; then
  echo "FAIL [case 29 / DP-359 AC1]: framework-infra task.md still emits phantom umbrella-V1 delegation '$DP359_PHANTOM_DELEGATION'" >&2
  cat "$dp359_infra_out" >&2
  exit 1
fi
if grep -qF -- "$DP359_PHANTOM_VERB" "$dp359_infra_out"; then
  echo "FAIL [case 29 / DP-359 AC1]: framework-infra task.md still delegates verification to an umbrella V ('$DP359_PHANTOM_VERB')" >&2
  cat "$dp359_infra_out" >&2
  exit 1
fi
if grep -qF -- "$DP359_DEAD_ROW" "$dp359_infra_out"; then
  echo "FAIL [case 29 / DP-359 AC1]: framework-infra task.md still carries the dead '$DP359_DEAD_ROW' Operational Context row" >&2
  cat "$dp359_infra_out" >&2
  exit 1
fi
if grep -qF -- "AC 驗收單 | N/A - framework work order" "$dp359_infra_out"; then
  echo "FAIL [case 29 / DP-359 AC1]: framework-infra task.md still carries the dead 'AC 驗收單 | N/A - framework work order' Operational Context row" >&2
  cat "$dp359_infra_out" >&2
  exit 1
fi
# Positive: the handoff reflects per-task self-contained framework wiring.
dp359_infra_handoff="$(awk '/^## Verification Handoff$/{c=1;next} c&&/^## /{c=0} c' "$dp359_infra_out")"
if ! printf '%s\n' "$dp359_infra_handoff" | grep -qF -- "per-task self-contained"; then
  echo "FAIL [case 29 / DP-359 AC1]: framework-infra handoff does not state per-task self-contained verification" >&2
  cat "$dp359_infra_out" >&2
  exit 1
fi

# --- Case 30 (DP-359 AC-NEG2): a legacy task with NO per-task body fields (no
# behavior_contract present) still derives without failing AND without umbrella
# prose — the framework-infra default path is self-contained, not delegated. ---
dp359_nobody_json="$tmpdir/dp359-nobody.json"
cat >"$dp359_nobody_json" <<'JSON'
{
  "source": { "type": "dp", "id": "DP-500", "container": "/tmp/dp-500", "jira_key": null },
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-500-T1",
      "kind": "implementation",
      "title": "legacy no-body framework task",
      "scope": "AC-NEG2 -- no per-task body fields declared; legacy framework-infra path.",
      "allowed_files": ["scripts/sample.sh", "scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh"
      }
    }
  ]
}
JSON

dp359_nobody_out="$tmpdir/dp359-nobody.md"
bash "$SCRIPT" --refinement-json "$dp359_nobody_json" --task-id "DP-500-T1" > "$dp359_nobody_out" || {
  echo "FAIL [case 30 / DP-359 AC-NEG2]: legacy no-body framework task derive failed" >&2
  exit 1
}
bash "$VALIDATE_TASK_MD" "$dp359_nobody_out" >/dev/null 2>&1 || {
  echo "FAIL [case 30 / DP-359 AC-NEG2]: legacy no-body derived task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$dp359_nobody_out" >&2 || true
  exit 1
}
if grep -qF -- "$DP359_PHANTOM_DELEGATION" "$dp359_nobody_out"; then
  echo "FAIL [case 30 / DP-359 AC-NEG2]: legacy no-body task.md still emits phantom umbrella-V1 delegation" >&2
  cat "$dp359_nobody_out" >&2
  exit 1
fi
if grep -qF -- "$DP359_PHANTOM_VERB" "$dp359_nobody_out"; then
  echo "FAIL [case 30 / DP-359 AC-NEG2]: legacy no-body task.md still delegates verification to an umbrella V" >&2
  cat "$dp359_nobody_out" >&2
  exit 1
fi
if grep -qF -- "$DP359_DEAD_ROW" "$dp359_nobody_out"; then
  echo "FAIL [case 30 / DP-359 AC-NEG2]: legacy no-body task.md still carries the dead Operational Context row" >&2
  cat "$dp359_nobody_out" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Case 31 (DP-231 T8 / AC38): Bug source identity -- derive accepts
# source.type=bug with {BUG_KEY}-Tn work_item_id and renders JIRA key N/A.
# ---------------------------------------------------------------------------
bug_source_json="$tmpdir/bug-source-refinement.json"
cat >"$bug_source_json" <<'JSON'
{
  "source": {
    "type": "bug",
    "id": "BUG-321",
    "container": "/Users/x/work/docs-manager/src/content/docs/specs/companies/exampleco/BUG-321",
    "repo": "exampleco-b2c-web",
    "base_branch": "main"
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "BUG-321-T1",
      "kind": "implementation",
      "title": "修正 Bug source identity",
      "scope": "驗證 Bug source work item identity。",
      "allowed_files": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "modules": ["scripts/selftests/derive-task-md-from-refinement-json-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/validate-config-driven-authoring.sh",
        "verify_command": "bash scripts/validate-config-driven-authoring.sh",
        "behavior_contract": {"applies": false, "reason": "static identity fixture"},
        "test_environment": {"level": "static"}
      }
    }
  ]
}
JSON

bug_source_out="$tmpdir/bug-source-task.md"
bash "$SCRIPT" --refinement-json "$bug_source_json" --task-id "BUG-321-T1" > "$bug_source_out"
bug_anchors=(
  "> Source: BUG-321 | Task: BUG-321-T1 | JIRA: N/A | Repo: exampleco-b2c-web"
  "| Source type | bug |"
  "| Source ID | BUG-321 |"
  "| Task ID | BUG-321-T1 |"
  "| JIRA key | N/A |"
  "| Task branch | task/BUG-321-T1-bug-source-identity |"
)
for anchor in "${bug_anchors[@]}"; do
  if ! grep -qF -- "$anchor" "$bug_source_out"; then
    echo "FAIL [case 31 / DP-231 T8]: Bug source anchor not found: $anchor" >&2
    cat "$bug_source_out" >&2
    exit 1
  fi
done
bash "$VALIDATE_TASK_MD" "$bug_source_out" >/dev/null 2>&1 || {
  echo "FAIL [case 31 / DP-231 T8]: derived Bug source task.md does not pass validate-task-md.sh" >&2
  bash "$VALIDATE_TASK_MD" "$bug_source_out" >&2 || true
  exit 1
}

echo "PASS: derive-task-md-from-refinement-json selftest"
