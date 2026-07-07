#!/usr/bin/env bash
# Purpose: selftest for validate-refinement-json.sh DP-269 jira-only schema rules.
# Inputs:  none (writes fixtures to a tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-269):
#   AC4     : source.type=jira positive fixture (source.repo + source.base_branch
#             + tasks[].jira_key string|null + optional tasks[].repo/base_branch)
#             PASSes.
#   AC-NEG1 : source.type=dp fixture carrying jira-only fields
#             (source.repo / source.base_branch / tasks[].jira_key /
#             tasks[].repo / tasks[].base_branch) FAILs fail-closed with
#             POLARIS_REFINEMENT_JIRA_ONLY_FIELD.
#   AC-NEG2 : the jira-only relaxation does not leak into the dp branch — a dp
#             fixture WITHOUT jira-only fields still PASSes unchanged, and a jira
#             fixture MISSING the required jira-only fields FAILs.
#
# Covers (DP-296 — canonical task schema convergence):
#   AC1     : a canonical dp fixture carrying tasks[].task_shape /
#             tracked_deliverable_hint PASSes (first-class, validated-when-present).
#   AC1/AC-NEG1 (adversarial): a fixture with a top-level planned_tasks[] FAILs
#             fail-closed with POLARIS_REFINEMENT_LEGACY_PLANNED_TASKS — the
#             mandatory negative path, not only the task_shape positive path.
#   AC1     : a canonical dp fixture WITHOUT task_shape/tracked_deliverable_hint
#             AND WITHOUT planned_tasks[] still PASSes (validated-when-present,
#             not mandatory).
#   AC1     : a canonical dp fixture with an out-of-enum task_shape FAILs.
#   AC7     : the tightened validator over a hermetic LOCKED active
#             refinement.json fixture PASSes; live active-set scan is optional
#             when the checkout has local specs available. The optional live scan
#             is differential: every LOCKED file that PASSes must be canonical +
#             intent-only. DP-341 packaging-field failures may make the live
#             passing set empty before the one-time T5 migration, and that is not
#             a regression.
#
# Covers (DP-302 — per-task verification body fields, all source):
#   AC3     : a dp fixture with well-formed per-task verification body fields
#             (behavior_contract / test_environment / verify_command / references)
#             PASSes; the SAME fields on a jira fixture also PASS (all-source,
#             not jira-only); a fixture WITHOUT the fields still PASSes
#             (validated-when-present).
#   AC-NEG1 : when a body field IS present but malformed, the validator fails
#             fail-loud naming the field — behavior_contract missing 'applies',
#             applies=false without 'reason', test_environment out-of-enum level,
#             empty verify_command, non-array references.
#
# AC-NEG2 fixture discipline: DP-296 positive fixtures are produced from a single
# canonical-shaped base (write_dp_canonical) and only mutated at the explicit
# point under test (e.g. add planned_tasks[], drop the optional fields, set an
# out-of-enum task_shape). No hand-rolled shape detached from the canonical
# schema is asserted green.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/validate-refinement-json.sh"

[[ -f "$SCRIPT" ]] || { echo "FAIL: validator not found: $SCRIPT" >&2; exit 1; }

tmpdir="$(mktemp -d -t validate-refinement-json.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# The validator requires source.container to be an existing directory and, for
# jira sources, no plan_path currentness check. Use the tmpdir as container.
container="$tmpdir"

write_jira_positive() {
  cat >"$1" <<JSON
{
  "epic": "PROJ-100",
  "source": {
    "type": "jira",
    "id": "PROJ-100",
    "container": "$container",
    "jira_key": "PROJ-100",
    "repo": "exampleco-web",
    "base_branch": "develop"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "task",
      "jira_key": "PROJ-201",
      "repo": "exampleco-member-ci",
      "base_branch": "release/member-ci",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    },
    {
      "id": "T2",
      "kind": "task",
      "jira_key": null,
      "title": "t2",
      "scope": "s2",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

# write_dp_canonical <dest_dir> — write a canonical-shaped dp refinement.json into
# <dest_dir>/refinement.json. tasks[] carry the first-class task_shape /
# tracked_deliverable_hint fields (DP-296 canonical home) and NO top-level
# planned_tasks[]. DP-296 positive/negative fixtures derive from this base.
write_dp_canonical() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  touch "$dest_dir/index.md"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dest_dir",
    "plan_path": "$dest_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

# --- Case 1 (AC4): jira positive fixture passes (string + null jira_key). ---
jira_pos="$tmpdir/jira-positive.json"
write_jira_positive "$jira_pos"
if ! bash "$SCRIPT" "$jira_pos" >/dev/null 2>"$tmpdir/jira-pos.stderr"; then
  echo "FAIL [case 1 / AC4]: jira positive fixture did not pass" >&2
  cat "$tmpdir/jira-pos.stderr" >&2
  exit 1
fi

# --- Case 2 (AC-NEG1): dp source carrying source.repo fails fail-closed. ---
# dp sources enforce container-currentness: refinement.json must live in the
# container dir. Use a per-case subdir named refinement.json.
dp_repo_dir="$tmpdir/dp-repo"; mkdir -p "$dp_repo_dir"; touch "$dp_repo_dir/index.md"
dp_repo="$dp_repo_dir/refinement.json"
cat >"$dp_repo" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dp_repo_dir",
    "plan_path": "$dp_repo_dir/index.md",
    "jira_key": null,
    "repo": "exampleco-web"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "task",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if bash "$SCRIPT" "$dp_repo" >/dev/null 2>"$tmpdir/dp-repo.stderr"; then
  echo "FAIL [case 2 / AC-NEG1]: dp source with source.repo passed (expected fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-repo.stderr"; then
  echo "FAIL [case 2 / AC-NEG1]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker" >&2
  cat "$tmpdir/dp-repo.stderr" >&2
  exit 1
fi

# --- Case 3 (AC-NEG1): dp source carrying tasks[].jira_key fails fail-closed. ---
dp_taskkey_dir="$tmpdir/dp-taskkey"; mkdir -p "$dp_taskkey_dir"; touch "$dp_taskkey_dir/index.md"
dp_taskkey="$dp_taskkey_dir/refinement.json"
cat >"$dp_taskkey" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dp_taskkey_dir",
    "plan_path": "$dp_taskkey_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "task",
      "jira_key": "PROJ-201",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if bash "$SCRIPT" "$dp_taskkey" >/dev/null 2>"$tmpdir/dp-taskkey.stderr"; then
  echo "FAIL [case 3 / AC-NEG1]: dp source with tasks[].jira_key passed (expected fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-taskkey.stderr"; then
  echo "FAIL [case 3 / AC-NEG1]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker for tasks[].jira_key" >&2
  cat "$tmpdir/dp-taskkey.stderr" >&2
  exit 1
fi

# --- Case 3b (DP-364 D1 / AC-NEG1): dp source carrying tasks[].repo /
# tasks[].base_branch fails fail-closed as jira-only. ---
dp_task_repo_dir="$tmpdir/dp-task-repo"; mkdir -p "$dp_task_repo_dir"; touch "$dp_task_repo_dir/index.md"
dp_task_repo="$dp_task_repo_dir/refinement.json"
cat >"$dp_task_repo" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dp_task_repo_dir",
    "plan_path": "$dp_task_repo_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "task",
      "repo": "exampleco-member-ci",
      "base_branch": "release/member-ci",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if bash "$SCRIPT" "$dp_task_repo" >/dev/null 2>"$tmpdir/dp-task-repo.stderr"; then
  echo "FAIL [case 3b / DP-364 D1]: dp source with tasks[].repo/base_branch passed (expected fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-task-repo.stderr"; then
  echo "FAIL [case 3b / DP-364 D1]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker for tasks[].repo/base_branch" >&2
  cat "$tmpdir/dp-task-repo.stderr" >&2
  exit 1
fi

# --- Case 4 (AC-NEG2): clean dp source (no jira-only fields) still passes —
# the jira-only relaxation does not leak into the dp branch. ---
dp_clean_dir="$tmpdir/dp-clean"; mkdir -p "$dp_clean_dir"; touch "$dp_clean_dir/index.md"
dp_clean="$dp_clean_dir/refinement.json"
cat >"$dp_clean" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dp_clean_dir",
    "plan_path": "$dp_clean_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "task",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if ! bash "$SCRIPT" "$dp_clean" >/dev/null 2>"$tmpdir/dp-clean.stderr"; then
  echo "FAIL [case 4 / AC-NEG2]: clean dp source did not pass (jira-only rules leaked into dp)" >&2
  cat "$tmpdir/dp-clean.stderr" >&2
  exit 1
fi

# --- Case 5 (AC-NEG2): jira source missing source.repo / source.base_branch fails. ---
jira_missing="$tmpdir/jira-missing.json"
cat >"$jira_missing" <<JSON
{
  "epic": "PROJ-100",
  "source": {
    "type": "jira",
    "id": "PROJ-100",
    "container": "$container",
    "jira_key": "PROJ-100"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-02T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "task",
      "jira_key": "PROJ-201",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if bash "$SCRIPT" "$jira_missing" >/dev/null 2>"$tmpdir/jira-missing.stderr"; then
  echo "FAIL [case 5 / AC-NEG2]: jira source missing source.repo/base_branch passed" >&2
  exit 1
fi
if ! grep -q "source.repo is required" "$tmpdir/jira-missing.stderr"; then
  echo "FAIL [case 5 / AC-NEG2]: missing source.repo required marker" >&2
  cat "$tmpdir/jira-missing.stderr" >&2
  exit 1
fi

# --- Case 6 (AC-NEG1): jira source with an invalid (non-key) tasks[].jira_key fails. ---
jira_badkey="$tmpdir/jira-badkey.json"
write_jira_positive "$jira_badkey"
python3 - "$jira_badkey" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["jira_key"] = "not-a-key"
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$jira_badkey" >/dev/null 2>"$tmpdir/jira-badkey.stderr"; then
  echo "FAIL [case 6 / AC-NEG1]: jira source with invalid tasks[].jira_key passed" >&2
  exit 1
fi
if ! grep -q "tasks\[0\].jira_key" "$tmpdir/jira-badkey.stderr"; then
  echo "FAIL [case 6 / AC-NEG1]: missing invalid tasks[].jira_key marker" >&2
  cat "$tmpdir/jira-badkey.stderr" >&2
  exit 1
fi

# =====================================================================
# DP-296 — canonical task schema convergence
# =====================================================================

# --- Case 7 (AC1): canonical dp fixture with tasks[].task_shape /
# tracked_deliverable_hint passes (first-class, validated-when-present). ---
dp_canonical_dir="$tmpdir/dp-canonical"
write_dp_canonical "$dp_canonical_dir"
if ! bash "$SCRIPT" "$dp_canonical_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-canonical.stderr"; then
  echo "FAIL [case 7 / AC1]: canonical dp fixture with task_shape did not pass" >&2
  cat "$tmpdir/dp-canonical.stderr" >&2
  exit 1
fi

# --- Case 8 (AC1 adversarial / AC-NEG1): a fixture carrying a top-level
# planned_tasks[] FAILs fail-closed. This is the MANDATORY negative path —
# the canonical base is mutated only at the deviation point (add planned_tasks[]). ---
dp_planned_dir="$tmpdir/dp-planned"
write_dp_canonical "$dp_planned_dir"
python3 - "$dp_planned_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
# Re-introduce the removed legacy top-level planned_tasks[] (the deviation point).
data["planned_tasks"] = [
    {"task_id": "T1", "task_shape": "implementation", "tracked_deliverable_hint": "tracked"}
]
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_planned_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-planned.stderr"; then
  echo "FAIL [case 8 / AC1-adversarial]: fixture with top-level planned_tasks[] passed (expected fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_LEGACY_PLANNED_TASKS" "$tmpdir/dp-planned.stderr"; then
  echo "FAIL [case 8 / AC1-adversarial]: missing POLARIS_REFINEMENT_LEGACY_PLANNED_TASKS marker" >&2
  cat "$tmpdir/dp-planned.stderr" >&2
  exit 1
fi

# --- Case 9 (AC1): a canonical dp fixture WITHOUT task_shape /
# tracked_deliverable_hint AND WITHOUT planned_tasks[] still passes
# (validated-when-present, not mandatory). ---
dp_no_shape_dir="$tmpdir/dp-no-shape"
write_dp_canonical "$dp_no_shape_dir"
python3 - "$dp_no_shape_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
for task in data["tasks"]:
    task.pop("task_shape", None)
    task.pop("tracked_deliverable_hint", None)
json.dump(data, open(p, "w"))
PY
if ! bash "$SCRIPT" "$dp_no_shape_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-no-shape.stderr"; then
  echo "FAIL [case 9 / AC1]: canonical dp fixture without task_shape/tracked_deliverable_hint did not pass (these are validated-when-present, not mandatory)" >&2
  cat "$tmpdir/dp-no-shape.stderr" >&2
  exit 1
fi

# --- Case 10 (AC1): out-of-enum task_shape FAILs (validated when present). ---
dp_bad_shape_dir="$tmpdir/dp-bad-shape"
write_dp_canonical "$dp_bad_shape_dir"
python3 - "$dp_bad_shape_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["task_shape"] = "not-a-shape"
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_bad_shape_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-bad-shape.stderr"; then
  echo "FAIL [case 10 / AC1]: out-of-enum task_shape passed (expected fail)" >&2
  exit 1
fi
if ! grep -q "task_shape" "$tmpdir/dp-bad-shape.stderr"; then
  echo "FAIL [case 10 / AC1]: missing task_shape violation marker" >&2
  cat "$tmpdir/dp-bad-shape.stderr" >&2
  exit 1
fi

# --- Case 11 (AC1): out-of-enum tracked_deliverable_hint FAILs. ---
dp_bad_hint_dir="$tmpdir/dp-bad-hint"
write_dp_canonical "$dp_bad_hint_dir"
python3 - "$dp_bad_hint_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["tracked_deliverable_hint"] = "maybe"
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_bad_hint_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-bad-hint.stderr"; then
  echo "FAIL [case 11 / AC1]: out-of-enum tracked_deliverable_hint passed (expected fail)" >&2
  exit 1
fi
if ! grep -q "tracked_deliverable_hint" "$tmpdir/dp-bad-hint.stderr"; then
  echo "FAIL [case 11 / AC1]: missing tracked_deliverable_hint violation marker" >&2
  cat "$tmpdir/dp-bad-hint.stderr" >&2
  exit 1
fi

# --- Case 12 (AC7): the tightened validator passes over the active
# refinement.json set.
#
# Active-set scoping (matches how the DP-296 migration scope was drawn):
#   - the governed delivery set is the LOCKED sources (the validator gate fires
#     at LOCK / in-flight delivery via lock-preflight + producer/handoff gates);
#   - exclude archive/ (terminal, not governed);
#   - exclude SUPERSEDED (DP-247): terminal-stale, legitimately still carries
#     legacy planned_tasks[];
#   - exclude DISCUSSION (DP-291): pre-LOCK, will be migrated by the now-canonical
#     producer when it next moves toward LOCK.
#   Running the tightened validator over DP-247/DP-291 and asserting PASS would
#   falsely fail — they legitimately carry legacy planned_tasks[] and are out of
#   the governed active-delivery set.
#
# The assertion is differential: a LOCKED file that PASSES the *current* (this)
# validator must still pass — i.e. the DP-296 tightening introduces ZERO new
# regression on the governed set, and none of the passing LOCKED files carries a
# top-level planned_tasks[]. A handful of LOCKED files are legacy artifacts that
# predate the strong-bound schema (missing schema_version/tasks/adversarial_pass)
# and fail the validator independently of DP-296; they are not in scope of "did
# T2 break them" and are skipped via the current-pass filter.
#
# Keep this case hermetic: task worktrees and fresh clones may not carry the
# gitignored live DP specs. The fixture below is the blocking invariant; the live
# scan is a best-effort regression sweep when local specs happen to be present.
active_fixture_dir="$tmpdir/active-set/DP-999-active"
write_dp_canonical "$active_fixture_dir"
cat >"$active_fixture_dir/index.md" <<'MD'
---
status: LOCKED
---

# DP-999 active fixture
MD
if ! bash "$SCRIPT" "$active_fixture_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/active-fixture.stderr"; then
  echo "FAIL [case 12 / AC7]: hermetic LOCKED active fixture did not pass" >&2
  cat "$tmpdir/active-fixture.stderr" >&2
  exit 1
fi
if grep -q '"planned_tasks"' "$active_fixture_dir/refinement.json"; then
  echo "FAIL [case 12 / AC7]: hermetic LOCKED active fixture carries top-level planned_tasks[]" >&2
  exit 1
fi

specs_root="$ROOT_DIR/docs-manager/src/content/docs/specs"
if [[ -d "$specs_root" ]]; then
  live_asserted=0
  while IFS= read -r f; do
    idx_md="$(dirname "$f")/index.md"
    [[ -f "$idx_md" ]] || continue
    # An index.md without a 'status:' line makes grep exit 1; under
    # `set -euo pipefail` that would abort the whole selftest. Append `|| true`
    # so a missing status yields an empty string and the loop simply continues.
    status="$(grep -m1 '^status:' "$idx_md" 2>/dev/null | sed 's/^status:[[:space:]]*//' | tr -d '[:space:]' || true)"
    [[ "$status" == "LOCKED" ]] || continue
    # Differential scope: only assert files that the validator currently passes;
    # pre-existing strong-bound legacy failures are out of DP-296 scope.
    #
    # DP-341 teardown: the validator now also fail-closes on tasks[].allowed_files
    # / tasks[].estimate_points (per-task packaging fields, now owned by the
    # breakdown writer path / task.md). LOCKED active files that still carry those
    # fields therefore drop out of the passing set here by design — that is the
    # fail-loud signal that the one-time T5 migration
    # (scripts/migrate-refinement-packaging-fields.sh) has not yet moved them to
    # intent-only. So this case asserts a *differential* invariant only ("a file
    # that passes is intent-only and canonical"), not an absolute count floor: at
    # T1's integrated head, before T5 migrates the live LOCKED set, the passing
    # set is legitimately empty, and that is correct, not a regression.
    bash "$SCRIPT" "$f" >/dev/null 2>&1 || continue
    live_asserted=$((live_asserted + 1))
    # Already passed the validator above, which now rejects planned_tasks[] AND
    # packaging fields; this re-assert + explicit checks document the invariant.
    if ! bash "$SCRIPT" "$f" >/dev/null 2>"$tmpdir/active-set.stderr"; then
      echo "FAIL [case 12 / AC7]: tightened validator regressed a LOCKED active file: $f" >&2
      cat "$tmpdir/active-set.stderr" >&2
      exit 1
    fi
    if grep -q '"planned_tasks"' "$f"; then
      echo "FAIL [case 12 / AC7]: LOCKED active file still carries top-level planned_tasks[]: $f" >&2
      exit 1
    fi
    # DP-341 invariant: a LOCKED file that PASSES must be intent-only — it must
    # NOT carry per-task packaging fields. (Carriers fail the validator above and
    # never reach here; this guards against a future regression that relaxes the
    # negative gate.)
    if grep -qE '"(allowed_files|estimate_points)"' "$f"; then
      echo "FAIL [case 12 / AC7]: LOCKED active file passed the validator yet still carries per-task packaging fields: $f" >&2
      exit 1
    fi
  done < <(
    find "$specs_root" \
      \( -path '*/archive/*' -o -path '*/.git/*' \) -prune \
      -o -type f -name 'refinement.json' -print 2>/dev/null | sort
  )
  # DP-341: no absolute count floor. Pre-T5-migration, the passing LOCKED set is
  # legitimately empty (all live LOCKED files still carry packaging fields and
  # fail the negative gate fail-loud); post-T5-migration it repopulates. The
  # invariant under test is differential (any passing file is intent-only +
  # canonical), enforced per-file in the loop above.
  echo "INFO [case 12 / AC7]: hermetic LOCKED active fixture asserted PASS; optional live LOCKED active assertions=$live_asserted (canonical, intent-only: no planned_tasks[], no packaging fields)" >&2
else
  echo "INFO [case 12 / AC7]: hermetic LOCKED active fixture asserted PASS; specs root not found ($specs_root), skipping optional live active-set scan" >&2
fi

# =====================================================================
# DP-302 — per-task verification body fields (all source, validated-when-present)
#
# T1 adds the per-task body schema under tasks[].verification:
#   behavior_contract / test_environment / verify_command / references
# These are field-driven inputs the derive (T2) reads to build task.md body.
# They are validated-when-present (mirroring the DP-296 task_shape pattern) so
# existing active refinement.json that predate the fields still PASS; when a body
# field IS present its shape is enforced fail-loud (AC-NEG1).
# =====================================================================

# write_jira_with_body <dest_file> — jira positive fixture with well-formed
# per-task verification body fields on the first task. Proves the body schema is
# all-source (not jira-only): a jira source carrying the body fields PASSes.
write_jira_with_body() {
  cat >"$1" <<JSON
{
  "epic": "PROJ-100",
  "source": {
    "type": "jira",
    "id": "PROJ-100",
    "container": "$container",
    "jira_key": "PROJ-100",
    "repo": "exampleco-web",
    "base_branch": "develop"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-09T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "task",
      "jira_key": "PROJ-201",
      "title": "t",
      "scope": "s",
      "modules": ["src/sample.ts"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "d",
        "behavior_contract": { "applies": true, "mode": "parity" },
        "test_environment": { "level": "component" },
        "verify_command": "pnpm vitest run src/sample.test.ts",
        "references": ["src/sample.ts"]
      }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

# --- Case 13 (AC3): canonical dp fixture with well-formed per-task body fields
# PASSes (validated-when-present, all-source). ---
dp_body_dir="$tmpdir/dp-body"
write_dp_canonical "$dp_body_dir"
python3 - "$dp_body_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"].update({
    "behavior_contract": {"applies": False, "reason": "framework infra; no runtime behavior"},
    "test_environment": {"level": "static"},
    "verify_command": "bash scripts/selftests/sample-selftest.sh",
    "references": ["scripts/sample.sh"],
})
json.dump(data, open(p, "w"))
PY
if ! bash "$SCRIPT" "$dp_body_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-body.stderr"; then
  echo "FAIL [case 13 / AC3]: canonical dp fixture with well-formed per-task body fields did not pass" >&2
  cat "$tmpdir/dp-body.stderr" >&2
  exit 1
fi

# --- Case 14 (AC3): jira fixture with the SAME body fields also PASSes —
# the body schema is all-source, not jira-only. ---
jira_body="$tmpdir/jira-body.json"
write_jira_with_body "$jira_body"
if ! bash "$SCRIPT" "$jira_body" >/dev/null 2>"$tmpdir/jira-body.stderr"; then
  echo "FAIL [case 14 / AC3]: jira fixture with per-task body fields did not pass (body schema must be all-source)" >&2
  cat "$tmpdir/jira-body.stderr" >&2
  exit 1
fi

# --- Case 15 (AC3 / back-compat): a dp fixture WITHOUT any per-task body fields
# still PASSes (validated-when-present, not mandatory at schema level). ---
dp_no_body_dir="$tmpdir/dp-no-body"
write_dp_canonical "$dp_no_body_dir"
if ! bash "$SCRIPT" "$dp_no_body_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-no-body.stderr"; then
  echo "FAIL [case 15 / AC3]: dp fixture without per-task body fields did not pass (body fields are validated-when-present)" >&2
  cat "$tmpdir/dp-no-body.stderr" >&2
  exit 1
fi

# --- Case 16 (AC-NEG1): behavior_contract present but missing 'applies' →
# fail-loud naming the field. ---
dp_bc_missing_dir="$tmpdir/dp-bc-missing"
write_dp_canonical "$dp_bc_missing_dir"
python3 - "$dp_bc_missing_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["behavior_contract"] = {"mode": "parity"}
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_bc_missing_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-bc-missing.stderr"; then
  echo "FAIL [case 16 / AC-NEG1]: behavior_contract without 'applies' passed (expected fail-loud)" >&2
  exit 1
fi
if ! grep -q "behavior_contract" "$tmpdir/dp-bc-missing.stderr"; then
  echo "FAIL [case 16 / AC-NEG1]: missing behavior_contract violation marker" >&2
  cat "$tmpdir/dp-bc-missing.stderr" >&2
  exit 1
fi

# --- Case 17 (AC-NEG1): behavior_contract.applies=false without 'reason' →
# fail-loud (applies=false must justify why). ---
dp_bc_noreason_dir="$tmpdir/dp-bc-noreason"
write_dp_canonical "$dp_bc_noreason_dir"
python3 - "$dp_bc_noreason_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["behavior_contract"] = {"applies": False}
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_bc_noreason_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-bc-noreason.stderr"; then
  echo "FAIL [case 17 / AC-NEG1]: behavior_contract.applies=false without reason passed (expected fail-loud)" >&2
  exit 1
fi
if ! grep -q "behavior_contract" "$tmpdir/dp-bc-noreason.stderr"; then
  echo "FAIL [case 17 / AC-NEG1]: missing behavior_contract.reason violation marker" >&2
  cat "$tmpdir/dp-bc-noreason.stderr" >&2
  exit 1
fi

# --- Case 18 (AC-NEG1): test_environment present but with out-of-enum 'level' →
# fail-loud. ---
dp_te_bad_dir="$tmpdir/dp-te-bad"
write_dp_canonical "$dp_te_bad_dir"
python3 - "$dp_te_bad_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["test_environment"] = {"level": "not-a-level"}
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_te_bad_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-te-bad.stderr"; then
  echo "FAIL [case 18 / AC-NEG1]: test_environment with out-of-enum level passed (expected fail-loud)" >&2
  exit 1
fi
if ! grep -q "test_environment" "$tmpdir/dp-te-bad.stderr"; then
  echo "FAIL [case 18 / AC-NEG1]: missing test_environment violation marker" >&2
  cat "$tmpdir/dp-te-bad.stderr" >&2
  exit 1
fi

# --- Case 19 (AC-NEG1): verify_command present but empty string → fail-loud. ---
dp_vc_empty_dir="$tmpdir/dp-vc-empty"
write_dp_canonical "$dp_vc_empty_dir"
python3 - "$dp_vc_empty_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["verify_command"] = "   "
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_vc_empty_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-vc-empty.stderr"; then
  echo "FAIL [case 19 / AC-NEG1]: verify_command empty string passed (expected fail-loud)" >&2
  exit 1
fi
if ! grep -q "verify_command" "$tmpdir/dp-vc-empty.stderr"; then
  echo "FAIL [case 19 / AC-NEG1]: missing verify_command violation marker" >&2
  cat "$tmpdir/dp-vc-empty.stderr" >&2
  exit 1
fi

# --- Case 20 (AC-NEG1): references present but not an array → fail-loud. ---
dp_refs_bad_dir="$tmpdir/dp-refs-bad"
write_dp_canonical "$dp_refs_bad_dir"
python3 - "$dp_refs_bad_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["references"] = "scripts/sample.sh"
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_refs_bad_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-refs-bad.stderr"; then
  echo "FAIL [case 20 / AC-NEG1]: references as non-array passed (expected fail-loud)" >&2
  exit 1
fi
if ! grep -q "references" "$tmpdir/dp-refs-bad.stderr"; then
  echo "FAIL [case 20 / AC-NEG1]: missing references violation marker" >&2
  cat "$tmpdir/dp-refs-bad.stderr" >&2
  exit 1
fi

# =====================================================================
# DP-337 — base_branch graduated to a universal field (dp + jira), with a
# dp feat/{source.id} format gate.
#
# Before DP-337, source.base_branch was jira-only: any dp source carrying it
# fail-closed with POLARIS_REFINEMENT_JIRA_ONLY_FIELD (DP-269 AC-NEG1). DP-337
# graduates base_branch to a universal field. For a dp source:
#   - base_branch absent      → PASS  (schema-optional; ~230 historical dp
#                                       refinement.json all carry base_branch=None
#                                       and must not be retroactively broken)
#   - base_branch=feat/{id}   → PASS  (format == feat/<source.id>)
#   - base_branch other value → FAIL  (POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID)
# source.repo / tasks[].jira_key stay jira-only (the relaxation must not leak to
# those two fields) — already asserted by cases 2/3 above; case 24 re-asserts
# the source.repo prohibition stands AFTER base_branch is graduated.
# =====================================================================

# write_dp_with_base_branch <dest_dir> <base_branch_value> — write a canonical dp
# fixture whose source.id is DP-337 and source.base_branch is the given value.
write_dp_with_base_branch() {
  local dest_dir="$1"
  local base_branch="$2"
  mkdir -p "$dest_dir"
  touch "$dest_dir/index.md"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-337",
    "container": "$dest_dir",
    "plan_path": "$dest_dir/index.md",
    "jira_key": null,
    "base_branch": "$base_branch"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-18T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-337-T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

# --- Case 21 (AC1): dp source carrying source.base_branch=feat/{source.id}
# PASSes — base_branch is no longer rejected as jira-only, and the format
# matches feat/DP-337. ---
dp_feat_ok_dir="$tmpdir/dp-feat-ok"
write_dp_with_base_branch "$dp_feat_ok_dir" "feat/DP-337"
if ! bash "$SCRIPT" "$dp_feat_ok_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-feat-ok.stderr"; then
  echo "FAIL [case 21 / AC1]: dp source with base_branch=feat/DP-337 did not pass (base_branch must be a universal field)" >&2
  cat "$tmpdir/dp-feat-ok.stderr" >&2
  exit 1
fi
if grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-feat-ok.stderr"; then
  echo "FAIL [case 21 / AC1]: dp source with base_branch still flagged jira-only (DP-337 graduation incomplete)" >&2
  cat "$tmpdir/dp-feat-ok.stderr" >&2
  exit 1
fi

# --- Case 22 (AC2): dp source with base_branch=main (not feat/{id}) FAILs
# fail-closed with POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID. ---
dp_base_main_dir="$tmpdir/dp-base-main"
write_dp_with_base_branch "$dp_base_main_dir" "main"
if bash "$SCRIPT" "$dp_base_main_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-base-main.stderr"; then
  echo "FAIL [case 22 / AC2]: dp source with base_branch=main passed (expected feat/{id} format gate fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID" "$tmpdir/dp-base-main.stderr"; then
  echo "FAIL [case 22 / AC2]: missing POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID marker for base_branch=main" >&2
  cat "$tmpdir/dp-base-main.stderr" >&2
  exit 1
fi

# --- Case 23 (AC2): dp source with base_branch=feat/DP-999 (a DIFFERENT DP's
# feat branch, not feat/<source.id>) FAILs — the format gate compares against
# source.id, not just the "feat/" prefix. ---
dp_base_wrong_dir="$tmpdir/dp-base-wrong"
write_dp_with_base_branch "$dp_base_wrong_dir" "feat/DP-999"
if bash "$SCRIPT" "$dp_base_wrong_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-base-wrong.stderr"; then
  echo "FAIL [case 23 / AC2]: dp source with mismatched feat/DP-999 passed (expected == feat/<source.id> gate)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID" "$tmpdir/dp-base-wrong.stderr"; then
  echo "FAIL [case 23 / AC2]: missing POLARIS_REFINEMENT_DP_BASE_BRANCH_INVALID marker for mismatched feat branch" >&2
  cat "$tmpdir/dp-base-wrong.stderr" >&2
  exit 1
fi

# --- Case 24 (AC-NEG1): dp source WITHOUT base_branch still PASSes
# (schema-optional; historical dp refinement.json carry base_branch=None and
# must not be retroactively broken). The clean dp fixture (case 4) already omits
# base_branch and passes; this case re-asserts the invariant explicitly under
# the DP-337 graduation (a dp source with source.id=DP-337 and no base_branch). ---
dp_no_base_dir="$tmpdir/dp-no-base-337"
mkdir -p "$dp_no_base_dir"; touch "$dp_no_base_dir/index.md"
cat >"$dp_no_base_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-337",
    "container": "$dp_no_base_dir",
    "plan_path": "$dp_no_base_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-18T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-337-T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if ! bash "$SCRIPT" "$dp_no_base_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-no-base-337.stderr"; then
  echo "FAIL [case 24 / AC-NEG1]: dp source without base_branch did not pass (must stay schema-optional)" >&2
  cat "$tmpdir/dp-no-base-337.stderr" >&2
  exit 1
fi

# --- Case 25 (AC-NEG2): the base_branch graduation must NOT leak to source.repo
# — a dp source carrying source.repo (and a valid base_branch=feat/{id}) still
# FAILs fail-closed with POLARIS_REFINEMENT_JIRA_ONLY_FIELD. This proves the
# relaxation is scoped to base_branch only; source.repo stays jira-only. ---
dp_repo_after_dir="$tmpdir/dp-repo-after-grad"
write_dp_with_base_branch "$dp_repo_after_dir" "feat/DP-337"
python3 - "$dp_repo_after_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["source"]["repo"] = "exampleco-web"
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_repo_after_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-repo-after.stderr"; then
  echo "FAIL [case 25 / AC-NEG2]: dp source with source.repo passed after base_branch graduation (source.repo must stay jira-only)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-repo-after.stderr"; then
  echo "FAIL [case 25 / AC-NEG2]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker for source.repo after graduation" >&2
  cat "$tmpdir/dp-repo-after.stderr" >&2
  exit 1
fi

# --- Case 26 (AC-NEG2 / no-leak): the base_branch graduation must not leak to a
# non-dp/non-jira source type (topic). A topic source carrying base_branch still
# FAILs fail-closed with POLARIS_REFINEMENT_JIRA_ONLY_FIELD — only dp gets the
# format-gated graduation. ---
topic_base_dir="$tmpdir/topic-base"; mkdir -p "$topic_base_dir"; touch "$topic_base_dir/index.md"
cat >"$topic_base_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "topic",
    "id": "some-topic",
    "container": "$topic_base_dir",
    "jira_key": null,
    "base_branch": "feat/some-topic"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-18T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "task",
      "title": "t",
      "scope": "s",
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
if bash "$SCRIPT" "$topic_base_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/topic-base.stderr"; then
  echo "FAIL [case 26 / AC-NEG2]: topic source with base_branch passed (graduation must be dp-scoped)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/topic-base.stderr"; then
  echo "FAIL [case 26 / AC-NEG2]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker for topic source base_branch" >&2
  cat "$tmpdir/topic-base.stderr" >&2
  exit 1
fi

# =====================================================================
# DP-359 — SCSS-removal verify_command curated-token subset gate (AC2 / AC-NF1 /
# AC-NEG1).
#
# T2 adds a fail-closed gate to validate-refinement-json.sh: when a task's
# verification.verify_command contains an SCSS-removal clause — a negative
# assertion `! rg ... <class-token> ...` scanning assets/style/css OR *.scss OR
# *.css — the scanned class-token(s) must be a SUBSET of the curated-token set
# declared on the AC entries the task references (task.ac_ids ->
# acceptance_criteria[*].verification.curated_tokens). Over-scope (a scanned token
# not in the curated set) OR an un-anchored over-broad family pattern (a bare
# `\.modal` / `\.btn` regex not tied to the curated-token list) is fail-closed
# exit 2 + POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE.
#
# curated_tokens is the single source of truth (AC-NF1): it lives ONLY on the AC
# entry's verification block; the verify_command gate reads the same source — no
# second token definition path.
#
# write_dp_scss <dest_dir> <curated_tokens_json> <verify_command> — write a
# canonical dp fixture whose single AC carries verification.curated_tokens and
# whose single task's verify_command is the given SCSS-removal command (ac_ids
# already points at AC1, the curated source).
# =====================================================================
write_dp_scss() {
  local dest_dir="$1"
  local curated_json="$2"
  local verify_command="$3"
  mkdir -p "$dest_dir"
  touch "$dest_dir/index.md"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "$dest_dir",
    "plan_path": "$dest_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-24T00:00:00Z",
  "modules": [{ "path": "assets/style/css/sample.scss", "action": "modify" }],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "t",
      "verification": {
        "method": "unit_test",
        "detail": "d",
        "curated_tokens": $curated_json
      }
    }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-999-T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "t",
      "scope": "s",
      "modules": ["assets/style/css/sample.scss"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "d",
        "verify_command": "$verify_command"
      }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

# --- Case 27 (AC2): SCSS-removal clause whose scanned token is NOT in the AC
# curated_tokens FAILs fail-closed exit 2 + POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE.
# curated = [form-input]; verify scans 'modal' (out of scope). ---
dp_scss_over_dir="$tmpdir/dp-scss-over"
write_dp_scss "$dp_scss_over_dir" '["form-input"]' \
  "! rg '\\\\.modal' assets/style/css"
set +e
bash "$SCRIPT" "$dp_scss_over_dir/refinement.json" >/dev/null 2>"$tmpdir/dp-scss-over.stderr"
scss_over_rc=$?
set -e
if [[ "$scss_over_rc" -ne 2 ]]; then
  echo "FAIL [case 27 / AC2]: SCSS over-scope token expected exit 2, got $scss_over_rc" >&2
  cat "$tmpdir/dp-scss-over.stderr" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE" "$tmpdir/dp-scss-over.stderr"; then
  echo "FAIL [case 27 / AC2]: missing POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE marker" >&2
  cat "$tmpdir/dp-scss-over.stderr" >&2
  exit 1
fi

# --- Case 28 (AC2): SCSS-removal clause whose scanned tokens are ALL in the AC
# curated_tokens PASSes. curated = [form-input, form-select]; verify scans both. ---
dp_scss_in_dir="$tmpdir/dp-scss-in"
write_dp_scss "$dp_scss_in_dir" '["form-input", "form-select"]' \
  "! rg '\\\\.form-input|\\\\.form-select' assets/style/css"
if ! bash "$SCRIPT" "$dp_scss_in_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-scss-in.stderr"; then
  echo "FAIL [case 28 / AC2]: SCSS in-scope subset clause did not pass" >&2
  cat "$tmpdir/dp-scss-in.stderr" >&2
  exit 1
fi

# --- Case 29 (AC2): a bare over-broad family pattern (`\.modal`) with NO matching
# curated token (curated lists only ExampleCo-own form selectors) is rejected as
# over-broad — the un-anchored family pattern is not tied to the curated-token
# list. exit 2 + marker. ---
dp_scss_family_dir="$tmpdir/dp-scss-family"
write_dp_scss "$dp_scss_family_dir" '["form-input"]' \
  "! rg '\\\\.btn' assets/style/css/_buttons.scss"
set +e
bash "$SCRIPT" "$dp_scss_family_dir/refinement.json" >/dev/null 2>"$tmpdir/dp-scss-family.stderr"
scss_family_rc=$?
set -e
if [[ "$scss_family_rc" -ne 2 ]]; then
  echo "FAIL [case 29 / AC2]: bare over-broad family pattern expected exit 2, got $scss_family_rc" >&2
  cat "$tmpdir/dp-scss-family.stderr" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE" "$tmpdir/dp-scss-family.stderr"; then
  echo "FAIL [case 29 / AC2]: missing POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE marker for family pattern" >&2
  cat "$tmpdir/dp-scss-family.stderr" >&2
  exit 1
fi

# --- Case 30 (AC-NEG1): a verify_command WITHOUT any SCSS-removal clause (a
# normal selftest command) is a no-op PASS — not falsely flagged even when the AC
# carries no curated_tokens. ---
dp_scss_noop_dir="$tmpdir/dp-scss-noop"
write_dp_canonical "$dp_scss_noop_dir"
python3 - "$dp_scss_noop_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["tasks"][0]["verification"]["verify_command"] = "bash scripts/selftests/foo-selftest.sh"
json.dump(data, open(p, "w"))
PY
if ! bash "$SCRIPT" "$dp_scss_noop_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-scss-noop.stderr"; then
  echo "FAIL [case 30 / AC-NEG1]: non-SCSS verify_command falsely flagged (expected no-op PASS)" >&2
  cat "$tmpdir/dp-scss-noop.stderr" >&2
  exit 1
fi

# --- Case 31 (AC-NF1 / single source of truth): curated_tokens lives ONLY on the
# AC entry. Mutating the AC curated_tokens alone flips the verify_command gate
# verdict — proving the gate reads the same single source (no second token def).
# Start from the in-scope fixture (PASS); shrink the AC curated set so the scanned
# token is no longer covered → the SAME verify_command now FAILs over-scope. ---
dp_scss_single_dir="$tmpdir/dp-scss-single"
write_dp_scss "$dp_scss_single_dir" '["form-input", "form-select"]' \
  "! rg '\\\\.form-input|\\\\.form-select' assets/style/css"
# Sanity: passes while both tokens are curated.
if ! bash "$SCRIPT" "$dp_scss_single_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-scss-single-before.stderr"; then
  echo "FAIL [case 31 / AC-NF1]: pre-mutation in-scope fixture did not pass" >&2
  cat "$tmpdir/dp-scss-single-before.stderr" >&2
  exit 1
fi
# Mutate ONLY the AC curated_tokens (the single source); verify_command untouched.
python3 - "$dp_scss_single_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["acceptance_criteria"][0]["verification"]["curated_tokens"] = ["form-input"]
json.dump(data, open(p, "w"))
PY
set +e
bash "$SCRIPT" "$dp_scss_single_dir/refinement.json" >/dev/null 2>"$tmpdir/dp-scss-single-after.stderr"
scss_single_rc=$?
set -e
if [[ "$scss_single_rc" -ne 2 ]]; then
  echo "FAIL [case 31 / AC-NF1]: shrinking AC curated_tokens did not flip verify_command gate to fail (single-source not enforced), got $scss_single_rc" >&2
  cat "$tmpdir/dp-scss-single-after.stderr" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_SCSS_VERIFY_TOKEN_OVERSCOPE" "$tmpdir/dp-scss-single-after.stderr"; then
  echo "FAIL [case 31 / AC-NF1]: missing over-scope marker after AC curated_tokens shrink" >&2
  cat "$tmpdir/dp-scss-single-after.stderr" >&2
  exit 1
fi

# --- Case 32 (DP-379 AC1): handoff_advisories[] positive fixture PASSes. ---
dp_advisory_ok_dir="$tmpdir/dp-advisory-ok"
write_dp_canonical "$dp_advisory_ok_dir"
python3 - "$dp_advisory_ok_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["handoff_advisories"] = [
    {
        "id": "framework-release-surface-missing",
        "producer": "refinement-release-surface-advisory",
        "severity": "actionable",
        "recommended_action": "Absorb the release-surface advisory into T1.",
        "disposition": "absorbed_by_task",
        "task_ids": ["DP-999-T1"],
    }
]
json.dump(data, open(p, "w"))
PY
if ! bash "$SCRIPT" "$dp_advisory_ok_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-advisory-ok.stderr"; then
  echo "FAIL [case 32 / DP-379 AC1]: valid handoff_advisories[] fixture did not pass" >&2
  cat "$tmpdir/dp-advisory-ok.stderr" >&2
  exit 1
fi

# --- Case 33 (DP-379 AC1): missing required advisory fields FAIL. ---
dp_advisory_missing_dir="$tmpdir/dp-advisory-missing"
write_dp_canonical "$dp_advisory_missing_dir"
python3 - "$dp_advisory_missing_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["handoff_advisories"] = [
    {
        "id": "",
        "severity": "actionable",
        "recommended_action": "route back",
        "task_ids": ["T1"],
    }
]
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_advisory_missing_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-advisory-missing.stderr"; then
  echo "FAIL [case 33 / DP-379 AC1]: advisory missing id/producer/disposition passed" >&2
  exit 1
fi
if ! grep -q "handoff_advisories\\[0\\].id" "$tmpdir/dp-advisory-missing.stderr" \
  || ! grep -q "handoff_advisories\\[0\\].producer" "$tmpdir/dp-advisory-missing.stderr" \
  || ! grep -q "handoff_advisories\\[0\\].disposition" "$tmpdir/dp-advisory-missing.stderr"; then
  echo "FAIL [case 33 / DP-379 AC1]: missing-field errors not reported" >&2
  cat "$tmpdir/dp-advisory-missing.stderr" >&2
  exit 1
fi

# --- Case 34 (DP-379 AC-NEG2): waived disposition requires reason. ---
dp_advisory_waived_dir="$tmpdir/dp-advisory-waived"
write_dp_canonical "$dp_advisory_waived_dir"
python3 - "$dp_advisory_waived_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["handoff_advisories"] = [
    {
        "id": "waived-without-reason",
        "producer": "refinement-release-surface-advisory",
        "severity": "actionable",
        "recommended_action": "waive only with an explicit reason",
        "disposition": "waived",
        "reason": "   ",
    }
]
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_advisory_waived_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-advisory-waived.stderr"; then
  echo "FAIL [case 34 / DP-379 AC-NEG2]: waived advisory without reason passed" >&2
  exit 1
fi
if ! grep -q "waived requires a non-empty reason" "$tmpdir/dp-advisory-waived.stderr"; then
  echo "FAIL [case 34 / DP-379 AC-NEG2]: missing waived reason error" >&2
  cat "$tmpdir/dp-advisory-waived.stderr" >&2
  exit 1
fi

# --- Case 35 (DP-379 AC1): absorbed_by_task task_ids must point at existing tasks. ---
dp_advisory_task_dir="$tmpdir/dp-advisory-task"
write_dp_canonical "$dp_advisory_task_dir"
python3 - "$dp_advisory_task_dir/refinement.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["handoff_advisories"] = [
    {
        "id": "bad-task-binding",
        "producer": "refinement-release-surface-advisory",
        "severity": "actionable",
        "recommended_action": "absorb into an existing task",
        "disposition": "absorbed_by_task",
        "task_ids": ["DP-999-T9"],
    }
]
json.dump(data, open(p, "w"))
PY
if bash "$SCRIPT" "$dp_advisory_task_dir/refinement.json" \
    >/dev/null 2>"$tmpdir/dp-advisory-task.stderr"; then
  echo "FAIL [case 35 / DP-379 AC1]: advisory with unknown task binding passed" >&2
  exit 1
fi
if ! grep -q "task_ids\\[0\\].*does not match an existing task" "$tmpdir/dp-advisory-task.stderr"; then
  echo "FAIL [case 35 / DP-379 AC1]: missing task binding error" >&2
  cat "$tmpdir/dp-advisory-task.stderr" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/selftests/refinement-json-bug-fields-selftest.sh"

echo "PASS: validate-refinement-json selftest"
