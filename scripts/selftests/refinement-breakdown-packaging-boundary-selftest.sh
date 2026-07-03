#!/usr/bin/env bash
# Purpose: DP-341 shared selftest for the refinement.json -> breakdown task.md
#          per-task packaging-field ownership boundary. refinement.json tasks[]
#          is the INTENT layer and must NOT carry per-task packaging fields
#          (allowed_files / estimate_points); those are owned by the breakdown
#          writer path (task.md). This file is shared across DP-341 T1-T5; each
#          task owns its own section. T1 owns the refinement.json schema cases
#          (negative fail-closed gate, dp+jira parity); T2-T5 sections are TODO
#          stubs filled in by their owning tasks.
# Inputs:  none (writes fixtures to a hermetic tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFINEMENT_VALIDATOR="$ROOT_DIR/scripts/validate-refinement-json.sh"

[[ -f "$REFINEMENT_VALIDATOR" ]] || {
  echo "FAIL: validator not found: $REFINEMENT_VALIDATOR" >&2
  exit 1
}

tmpdir="$(mktemp -d -t refinement-packaging-boundary.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# PACKAGING_MARKER — the fail-closed marker the T1 negative gate must emit when a
# refinement.json tasks[] entry carries a per-task packaging field.
PACKAGING_MARKER="POLARIS_REFINEMENT_PACKAGING_FIELD_FORBIDDEN"

# run_refinement_validator <refinement.json> <stderr_capture> — spawn the
# refinement.json validator hermetically (env -u so a leaked POLARIS_WORKSPACE_ROOT
# / POLARIS_SPECS_ROOT cannot short-circuit it to the live workspace). Returns the
# validator exit code; never aborts the selftest under set -e.
run_refinement_validator() {
  local fixture="$1"
  local stderr_capture="$2"
  local rc=0
  env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
    bash "$REFINEMENT_VALIDATOR" "$fixture" >/dev/null 2>"$stderr_capture" || rc=$?
  return "$rc"
}

# write_intent_only_dp <dest_dir> — write a canonical INTENT-ONLY dp
# refinement.json (tasks[] carries id/kind/title/scope/modules/ac_ids/
# dependencies/verification but NO packaging fields). This is the post-DP-341
# target shape and must PASS.
write_intent_only_dp() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  touch "$dest_dir/index.md"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-341",
    "container": "$dest_dir",
    "plan_path": "$dest_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-29T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "DP-341-T1",
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

# write_intent_only_jira <dest_dir> — INTENT-ONLY jira refinement.json (carries
# the jira-required source.repo / source.base_branch and tasks[].jira_key, but NO
# per-task packaging fields). Used to assert the negative gate fires for jira too
# (dp+jira parity — the gate must NOT branch on source.type).
write_intent_only_jira() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": "PROJ-100",
  "source": {
    "type": "jira",
    "id": "PROJ-100",
    "container": "$dest_dir",
    "jira_key": "PROJ-100",
    "repo": "exampleco-web",
    "base_branch": "develop"
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-29T00:00:00Z",
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
}

# add_packaging_field <refinement.json> <field> — mutate the fixture so its first
# task carries the given per-task packaging field (allowed_files / estimate_points).
add_packaging_field() {
  local fixture="$1"
  local field="$2"
  python3 - "$fixture" "$field" <<'PY'
import json, sys
path, field = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if field == "allowed_files":
    data["tasks"][0]["allowed_files"] = ["scripts/sample.sh"]
elif field == "estimate_points":
    data["tasks"][0]["estimate_points"] = 2
else:
    raise SystemExit(f"unknown packaging field: {field}")
json.dump(data, open(path, "w"))
PY
}

# =====================================================================
# DP-341 T1 — refinement.json schema: per-task packaging fields are FORBIDDEN.
#
# AC-NEG1 (negative gate): a refinement.json tasks[] entry carrying allowed_files
#   OR estimate_points fail-closes exit 2 + POLARIS_*; the gate fires for BOTH
#   source.type=dp AND source.type=jira (parity — no source-type fast path).
# AC4 (intent-only target): an intent-only tasks[] (no packaging fields) PASSes.
# =====================================================================

# --- T1 case 1 (AC-NEG1, dp): dp tasks[] with allowed_files fails fail-closed
# exit 2 + PACKAGING_MARKER. ---
t1_dp_af_dir="$tmpdir/t1-dp-allowed-files"
write_intent_only_dp "$t1_dp_af_dir"
add_packaging_field "$t1_dp_af_dir/refinement.json" "allowed_files"
t1_dp_af_rc=0
run_refinement_validator "$t1_dp_af_dir/refinement.json" "$tmpdir/t1-dp-af.stderr" \
  || t1_dp_af_rc=$?
if [[ "$t1_dp_af_rc" -ne 2 ]]; then
  echo "FAIL [T1 case 1 / AC-NEG1]: dp tasks[].allowed_files expected exit 2, got $t1_dp_af_rc" >&2
  cat "$tmpdir/t1-dp-af.stderr" >&2
  exit 1
fi
if ! grep -q "$PACKAGING_MARKER" "$tmpdir/t1-dp-af.stderr"; then
  echo "FAIL [T1 case 1 / AC-NEG1]: missing $PACKAGING_MARKER for dp tasks[].allowed_files" >&2
  cat "$tmpdir/t1-dp-af.stderr" >&2
  exit 1
fi

# --- T1 case 2 (AC-NEG1, dp): dp tasks[] with estimate_points fails fail-closed
# exit 2 + PACKAGING_MARKER. ---
t1_dp_ep_dir="$tmpdir/t1-dp-estimate-points"
write_intent_only_dp "$t1_dp_ep_dir"
add_packaging_field "$t1_dp_ep_dir/refinement.json" "estimate_points"
t1_dp_ep_rc=0
run_refinement_validator "$t1_dp_ep_dir/refinement.json" "$tmpdir/t1-dp-ep.stderr" \
  || t1_dp_ep_rc=$?
if [[ "$t1_dp_ep_rc" -ne 2 ]]; then
  echo "FAIL [T1 case 2 / AC-NEG1]: dp tasks[].estimate_points expected exit 2, got $t1_dp_ep_rc" >&2
  cat "$tmpdir/t1-dp-ep.stderr" >&2
  exit 1
fi
if ! grep -q "$PACKAGING_MARKER" "$tmpdir/t1-dp-ep.stderr"; then
  echo "FAIL [T1 case 2 / AC-NEG1]: missing $PACKAGING_MARKER for dp tasks[].estimate_points" >&2
  cat "$tmpdir/t1-dp-ep.stderr" >&2
  exit 1
fi

# --- T1 case 3 (AC-NEG1, jira PARITY): jira tasks[] with allowed_files fails
# fail-closed exit 2 + PACKAGING_MARKER — the gate is NOT dp-only. This is the
# adversarial-pass enforcement: an implementation that only checks dp would miss
# this. ---
t1_jira_af_dir="$tmpdir/t1-jira-allowed-files"
write_intent_only_jira "$t1_jira_af_dir"
add_packaging_field "$t1_jira_af_dir/refinement.json" "allowed_files"
t1_jira_af_rc=0
run_refinement_validator "$t1_jira_af_dir/refinement.json" "$tmpdir/t1-jira-af.stderr" \
  || t1_jira_af_rc=$?
if [[ "$t1_jira_af_rc" -ne 2 ]]; then
  echo "FAIL [T1 case 3 / AC-NEG1 parity]: jira tasks[].allowed_files expected exit 2, got $t1_jira_af_rc (gate must fire for jira too)" >&2
  cat "$tmpdir/t1-jira-af.stderr" >&2
  exit 1
fi
if ! grep -q "$PACKAGING_MARKER" "$tmpdir/t1-jira-af.stderr"; then
  echo "FAIL [T1 case 3 / AC-NEG1 parity]: missing $PACKAGING_MARKER for jira tasks[].allowed_files (dp+jira parity broken)" >&2
  cat "$tmpdir/t1-jira-af.stderr" >&2
  exit 1
fi

# --- T1 case 4 (AC-NEG1, jira PARITY): jira tasks[] with estimate_points also
# fails fail-closed exit 2 + PACKAGING_MARKER. ---
t1_jira_ep_dir="$tmpdir/t1-jira-estimate-points"
write_intent_only_jira "$t1_jira_ep_dir"
add_packaging_field "$t1_jira_ep_dir/refinement.json" "estimate_points"
t1_jira_ep_rc=0
run_refinement_validator "$t1_jira_ep_dir/refinement.json" "$tmpdir/t1-jira-ep.stderr" \
  || t1_jira_ep_rc=$?
if [[ "$t1_jira_ep_rc" -ne 2 ]]; then
  echo "FAIL [T1 case 4 / AC-NEG1 parity]: jira tasks[].estimate_points expected exit 2, got $t1_jira_ep_rc" >&2
  cat "$tmpdir/t1-jira-ep.stderr" >&2
  exit 1
fi
if ! grep -q "$PACKAGING_MARKER" "$tmpdir/t1-jira-ep.stderr"; then
  echo "FAIL [T1 case 4 / AC-NEG1 parity]: missing $PACKAGING_MARKER for jira tasks[].estimate_points" >&2
  cat "$tmpdir/t1-jira-ep.stderr" >&2
  exit 1
fi

# --- T1 case 5 (AC4, dp intent-only): an intent-only dp tasks[] (NO packaging
# fields) PASSes — allowed_files / estimate_points are removed from task_required
# and the negative gate does not false-positive on their absence. ---
t1_dp_clean_dir="$tmpdir/t1-dp-intent-only"
write_intent_only_dp "$t1_dp_clean_dir"
t1_dp_clean_rc=0
run_refinement_validator "$t1_dp_clean_dir/refinement.json" "$tmpdir/t1-dp-clean.stderr" \
  || t1_dp_clean_rc=$?
if [[ "$t1_dp_clean_rc" -ne 0 ]]; then
  echo "FAIL [T1 case 5 / AC4]: intent-only dp refinement.json did not pass (got $t1_dp_clean_rc; packaging fields must be optional/forbidden, not required)" >&2
  cat "$tmpdir/t1-dp-clean.stderr" >&2
  exit 1
fi

# --- T1 case 6 (AC4, jira intent-only): an intent-only jira tasks[] (NO packaging
# fields) PASSes too — parity on the positive side as well. ---
t1_jira_clean_dir="$tmpdir/t1-jira-intent-only"
write_intent_only_jira "$t1_jira_clean_dir"
t1_jira_clean_rc=0
run_refinement_validator "$t1_jira_clean_dir/refinement.json" "$tmpdir/t1-jira-clean.stderr" \
  || t1_jira_clean_rc=$?
if [[ "$t1_jira_clean_rc" -ne 0 ]]; then
  echo "FAIL [T1 case 6 / AC4]: intent-only jira refinement.json did not pass (got $t1_jira_clean_rc)" >&2
  cat "$tmpdir/t1-jira-clean.stderr" >&2
  exit 1
fi

# =====================================================================
# DP-341 T2 — derive-task-md is intent-regenerate + packaging-preserve, NOT a
# destructive full regenerate that reads packaging from refinement.json tasks[].
#
# The derive script resolves per-task packaging (Allowed Files + estimate points)
# with this precedence:
#   Regime 1 (legacy back-compat): refinement.json tasks[] still carries
#     allowed_files / estimate_points -> use those (covered by the existing
#     derive-task-md selftest's regime-1 fixtures; not re-asserted here).
#   Regime 2 (preserve, AC3 idempotency): NO refinement packaging, but a target
#     task.md exists and carries authored packaging (## Allowed Files block +
#     points-in-title) passed via --preserve-from -> PRESERVE those. A same-intent
#     re-derive must NOT clobber the breakdown-authored Allowed Files; the block
#     stays byte-identical even when an INTENT field (scope/title) is re-derived.
#   Regime 3 (initial-create, adversarial_pass): no refinement packaging AND no
#     task.md -> emit intent-only (empty/absent ## Allowed Files, default points)
#     and must NOT crash.
#
# AC3 (idempotency): same-intent re-derive --preserve-from an authored task.md
#   keeps ## Allowed Files BYTE-IDENTICAL and points preserved, even when an intent
#   field changed in refinement.json.
# adversarial_pass: regime 3 (no task.md, no refinement packaging) must not crash
#   on the empty Allowed Files list (owning-anchor / block build).
# =====================================================================

DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
[[ -f "$DERIVE" ]] || {
  echo "FAIL: derive script not found: $DERIVE" >&2
  exit 1
}

# run_derive <refinement.json> <task-id> <stdout_capture> <stderr_capture> [--preserve-from <task.md>]
# — spawn derive hermetically (env -u so a leaked POLARIS_WORKSPACE_ROOT /
# POLARIS_SPECS_ROOT cannot redirect resolution to the live workspace). Returns the
# derive exit code; never aborts the selftest under set -e.
run_derive() {
  local refinement="$1" task_id="$2" stdout_capture="$3" stderr_capture="$4"
  shift 4
  local rc=0
  env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT \
    bash "$DERIVE" --refinement-json "$refinement" --task-id "$task_id" \
    --repo polaris-framework --repo-root "$(dirname "$refinement")" "$@" \
    >"$stdout_capture" 2>"$stderr_capture" || rc=$?
  return "$rc"
}

# extract_allowed_files_block <task.md> — print the body of the `## Allowed Files`
# section (lines until the next `## ` heading), used for byte-identical comparison.
extract_allowed_files_block() {
  awk '
    /^## Allowed Files[[:space:]]*$/ { inblk=1; next }
    inblk && /^## / { inblk=0 }
    inblk { print }
  ' "$1"
}

# write_authored_task_md <dest_path> — a breakdown-authored task.md carrying
# packaging (## Allowed Files block + a `(N pt)` title), representing the post-T1
# target where packaging lives in task.md (not refinement.json tasks[]).
write_authored_task_md() {
  local dest="$1"
  cat >"$dest" <<'TASKMD'
---
title: "DP-341 T1: authored intent (3 pt)"
status: IN_PROGRESS
task_kind: T
---

# T1: authored intent (3 pt)

## Allowed Files

- `scripts/sample.sh`
- `scripts/other-authored.sh`

## 目標

authored scope
TASKMD
}

# --- T2 case 1 (AC3 regime-2 preserve): intent-only refinement.json + an authored
# task.md via --preserve-from. derive must PRESERVE the authored ## Allowed Files
# (byte-identical) and the authored points (3 pt), regenerating only INTENT. ---
t2_preserve_dir="$tmpdir/t2-preserve"
write_intent_only_dp "$t2_preserve_dir"
t2_authored_task="$t2_preserve_dir/authored-task.md"
write_authored_task_md "$t2_authored_task"
t2_preserve_rc=0
run_derive "$t2_preserve_dir/refinement.json" "DP-341-T1" \
  "$tmpdir/t2-preserve.stdout" "$tmpdir/t2-preserve.stderr" \
  --preserve-from "$t2_authored_task" || t2_preserve_rc=$?
if [[ "$t2_preserve_rc" -ne 0 ]]; then
  echo "FAIL [T2 case 1 / AC3 preserve]: derive --preserve-from expected exit 0, got $t2_preserve_rc" >&2
  cat "$tmpdir/t2-preserve.stderr" >&2
  exit 1
fi
# Authored Allowed Files must survive byte-identical into the derived body.
authored_block="$(extract_allowed_files_block "$t2_authored_task")"
derived_block="$(extract_allowed_files_block "$tmpdir/t2-preserve.stdout")"
if [[ "$authored_block" != "$derived_block" ]]; then
  echo "FAIL [T2 case 1 / AC3 preserve]: ## Allowed Files not preserved byte-identical" >&2
  echo "--- authored ---" >&2; printf '%s\n' "$authored_block" >&2
  echo "--- derived ---" >&2; printf '%s\n' "$derived_block" >&2
  exit 1
fi
# The second authored file proves the preserve is real (not just re-deriving the
# single module path); the refinement modules[] only mentions scripts/sample.sh.
if ! grep -qF 'scripts/other-authored.sh' "$tmpdir/t2-preserve.stdout"; then
  echo "FAIL [T2 case 1 / AC3 preserve]: authored-only file scripts/other-authored.sh was clobbered" >&2
  cat "$tmpdir/t2-preserve.stdout" >&2
  exit 1
fi
# Authored points (3 pt) must be preserved into the derived title/heading.
if ! grep -qF '(3 pt)' "$tmpdir/t2-preserve.stdout"; then
  echo "FAIL [T2 case 1 / AC3 preserve]: authored points (3 pt) not preserved" >&2
  cat "$tmpdir/t2-preserve.stdout" >&2
  exit 1
fi

# --- T2 case 2 (AC3 same-intent idempotency): same inputs derived twice must be
# byte-identical. ---
t2_preserve_rc2=0
run_derive "$t2_preserve_dir/refinement.json" "DP-341-T1" \
  "$tmpdir/t2-preserve2.stdout" "$tmpdir/t2-preserve2.stderr" \
  --preserve-from "$t2_authored_task" || t2_preserve_rc2=$?
if [[ "$t2_preserve_rc2" -ne 0 ]]; then
  echo "FAIL [T2 case 2 / AC3 idempotency]: second derive expected exit 0, got $t2_preserve_rc2" >&2
  cat "$tmpdir/t2-preserve2.stderr" >&2
  exit 1
fi
if ! cmp -s "$tmpdir/t2-preserve.stdout" "$tmpdir/t2-preserve2.stdout"; then
  echo "FAIL [T2 case 2 / AC3 idempotency]: same-intent re-derive not byte-identical" >&2
  exit 1
fi

# --- T2 case 3 (adversarial_pass regime-3 initial-create): intent-only
# refinement.json, NO --preserve-from, NO task.md. derive must NOT crash and must
# emit intent-only (no authored Allowed Files entries). ---
t2_initial_dir="$tmpdir/t2-initial"
write_intent_only_dp "$t2_initial_dir"
t2_initial_rc=0
run_derive "$t2_initial_dir/refinement.json" "DP-341-T1" \
  "$tmpdir/t2-initial.stdout" "$tmpdir/t2-initial.stderr" || t2_initial_rc=$?
if [[ "$t2_initial_rc" -ne 0 ]]; then
  echo "FAIL [T2 case 3 / adversarial_pass regime-3]: initial-create derive expected exit 0, got $t2_initial_rc (empty Allowed Files must not crash)" >&2
  cat "$tmpdir/t2-initial.stderr" >&2
  exit 1
fi
# Regime 3 emits no authored Allowed Files entries (the authored-only file from
# case 1 must NOT leak in; the block is empty/absent).
if grep -qF 'scripts/other-authored.sh' "$tmpdir/t2-initial.stdout"; then
  echo "FAIL [T2 case 3 / adversarial_pass regime-3]: regime-3 leaked authored Allowed Files" >&2
  cat "$tmpdir/t2-initial.stdout" >&2
  exit 1
fi

# =====================================================================
# DP-341 T3 — producer registry + no-direct-evidence-write: the per-task
# packaging WRITE lands in the breakdown task.md writer path, NOT refinement.json.
#
# AC4 (producer registry single-writer): the task.md packaging write path
#   (tasks/T*/index.md) resolves to the breakdown task.md writer (owning_skill
#   "breakdown"); the refinement.json design-doc producer must NOT carry any
#   task packaging glob. Each writer maps to a single declared producer.
# AC-NEG2 (no-direct-evidence-write DENY/ALLOW): breakdown writing refinement.json
#   intent stays fail-closed DENY (refinement.json is JSON, excluded from the
#   skill-writer markdown bypass); breakdown writing the task.md packaging section
#   goes through the existing task.md (.md) skill-writer bypass -> ALLOW.
# =====================================================================

PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
NO_DIRECT_HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"

[[ -f "$PRODUCERS_JSON" ]] || {
  echo "FAIL [T3]: producer registry not found: $PRODUCERS_JSON" >&2
  exit 1
}
[[ -f "$NO_DIRECT_HOOK" ]] || {
  echo "FAIL [T3]: no-direct-evidence-write hook not found: $NO_DIRECT_HOOK" >&2
  exit 1
}

# resolve_producer_owning_skill <registry.json> <file_path> — resolve the SINGLE
# producer that owns a specs-bound markdown write, FAITHFULLY MIRRORING the real
# PR-gate resolver in scripts/validate-specs-bound-write-contract.sh:
#   1. pre-filter producers to specs-bound artifact_kind values
#      (specs_markdown / verify_evidence_layout / docs_page / sidecar / d2_transport);
#   2. select the FIRST producer whose any path_glob naive-fnmatch-matches the
#      full path (plain fnmatch, where "*" crosses "/") — array order decides
#      among overlapping globs.
# This is intentionally the resolver that actually runs at PR-gate time, NOT the
# aspirational token-first lookup used by the write-side producer helper. AC4
# asserts the breakdown task.md packaging write resolves to a single breakdown
# writer; if registry array order lets the refinement container-index producer
# win the tasks/**/index.md path first, that is a genuine single-producer
# violation this helper must surface.
# Prints the single owning_skill of the first matching producer, or "NONE".
resolve_producer_owning_skill() {
  local registry="$1"
  local file_path="$2"
  REGISTRY_VAL="$registry" FILE_PATH_VAL="$file_path" python3 - <<'PY'
import fnmatch
import json
import os

registry = os.environ["REGISTRY_VAL"]
file_path = os.environ["FILE_PATH_VAL"]

with open(registry, "r", encoding="utf-8") as fh:
    data = json.load(fh)

# Mirror validate-specs-bound-write-contract.sh: same artifact_kind pre-filter.
SPECS_BOUND_KINDS = {
    "specs_markdown",
    "verify_evidence_layout",
    "docs_page",
    "sidecar",
    "d2_transport",
}
producers = [
    p for p in (data.get("producers", []) or [])
    if p.get("artifact_kind") in SPECS_BOUND_KINDS
]

# Naive first-match over the full path (plain fnmatch, "*" crosses "/"), exactly
# as the PR-gate resolver does. Array order is decisive among overlapping globs.
producer = next(
    (
        p
        for p in producers
        if any(fnmatch.fnmatch(file_path, glob) for glob in p.get("path_globs", []))
    ),
    None,
)

print(producer.get("owning_skill") if producer else "NONE")
PY
}

# refinement_producer_carries_packaging <registry.json> — exit 0 (true) if any
# producer whose path_globs include a refinement.json path ALSO declares a task
# packaging glob (tasks/T*/index.md or tasks/V*/index.md). The DP-341 boundary
# requires the refinement.json producer to NOT carry packaging.
refinement_producer_carries_packaging() {
  local registry="$1"
  REGISTRY_VAL="$registry" python3 - <<'PY'
import json
import os
import sys

registry = os.environ["REGISTRY_VAL"]
with open(registry, "r", encoding="utf-8") as fh:
    data = json.load(fh)

for entry in data.get("producers", []) or []:
    globs = entry.get("path_globs") or []
    owns_refinement = any(g.endswith("refinement.json") for g in globs)
    owns_packaging = any(
        g.endswith("tasks/T*/index.md") or g.endswith("tasks/V*/index.md")
        for g in globs
    )
    if owns_refinement and owns_packaging:
        sys.exit(0)
sys.exit(1)
PY
}

# run_no_direct_hook <file_path> <skill_writer> <stderr_capture> — feed a Write
# tool payload to the hook; returns its exit code (0 ALLOW, 2 BLOCKED). Empty
# skill_writer => no POLARIS_SKILL_WRITER bypass requested.
run_no_direct_hook() {
  local file_path="$1"
  local skill_writer="$2"
  local stderr_capture="$3"
  local payload
  payload=$(FILE_PATH_VAL="$file_path" python3 -c \
    'import json,os;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":os.environ["FILE_PATH_VAL"]}}))')
  local rc=0
  if [[ -n "$skill_writer" ]]; then
    printf '%s' "$payload" | env -u POLARIS_PRODUCER POLARIS_SKILL_WRITER="$skill_writer" \
      bash "$NO_DIRECT_HOOK" >/dev/null 2>"$stderr_capture" || rc=$?
  else
    printf '%s' "$payload" | env -u POLARIS_PRODUCER -u POLARIS_SKILL_WRITER \
      bash "$NO_DIRECT_HOOK" >/dev/null 2>"$stderr_capture" || rc=$?
  fi
  return "$rc"
}

# Representative specs-bound paths for the boundary.
T3_TASK_MD_PATH="docs-manager/src/content/docs/specs/design-plans/DP-341-x/tasks/T1/index.md"
T3_REFINEMENT_JSON_PATH="docs-manager/src/content/docs/specs/design-plans/DP-341-x/refinement.json"

# --- T3 case 1 / AC4: task.md packaging path resolves to the breakdown writer. ---
t3_owning_skill="$(resolve_producer_owning_skill "$PRODUCERS_JSON" "$T3_TASK_MD_PATH")"
if [[ "$t3_owning_skill" != "breakdown" ]]; then
  echo "FAIL [T3 case 1 / AC4]: task.md packaging path must resolve to a single breakdown writer, got: $t3_owning_skill" >&2
  echo "  path=$T3_TASK_MD_PATH" >&2
  exit 1
fi

# --- T3 case 2 / AC4: refinement.json producer must NOT carry a packaging glob. ---
if refinement_producer_carries_packaging "$PRODUCERS_JSON"; then
  echo "FAIL [T3 case 2 / AC4]: a refinement.json producer also declares a task packaging glob (tasks/T*|V*/index.md); the refinement.json design-doc entry must not carry packaging" >&2
  exit 1
fi

# --- T3 case 3 / AC-NEG2: breakdown writing refinement.json intent -> DENY. ---
t3_refinement_stderr="$tmpdir/t3-refinement.stderr"
t3_refinement_rc=0
run_no_direct_hook "$T3_REFINEMENT_JSON_PATH" "breakdown" "$t3_refinement_stderr" || t3_refinement_rc=$?
if [[ "$t3_refinement_rc" -ne 2 ]]; then
  echo "FAIL [T3 case 3 / AC-NEG2]: breakdown writing refinement.json must fail-closed DENY (exit 2), got exit $t3_refinement_rc" >&2
  cat "$t3_refinement_stderr" >&2
  exit 1
fi
if ! grep -qF 'BLOCKED' "$t3_refinement_stderr"; then
  echo "FAIL [T3 case 3 / AC-NEG2]: breakdown writing refinement.json DENY did not emit a BLOCKED line" >&2
  cat "$t3_refinement_stderr" >&2
  exit 1
fi

# --- T3 case 4 / AC-NEG2: breakdown writing task.md packaging section -> ALLOW. ---
t3_taskmd_stderr="$tmpdir/t3-taskmd.stderr"
t3_taskmd_rc=0
run_no_direct_hook "$T3_TASK_MD_PATH" "breakdown" "$t3_taskmd_stderr" || t3_taskmd_rc=$?
if [[ "$t3_taskmd_rc" -ne 0 ]]; then
  echo "FAIL [T3 case 4 / AC-NEG2]: breakdown writing task.md packaging (.md) must ALLOW (exit 0) via the skill-writer markdown bypass, got exit $t3_taskmd_rc" >&2
  cat "$t3_taskmd_stderr" >&2
  exit 1
fi

# =====================================================================
# DP-341 T4 — escalation-intake routing: packaging-only plan-defect →
# route=task_update (NOT bounced to route=refinement), NO refinement-inbox
# record, and escalation_count NOT incremented (one-line packaging backfill
# must not consume the loop cap). AC1 covers allowed_files; AC2 covers
# estimate_points — both share the SAME task_update lane (each verified once).
# =====================================================================

ESCALATION_VALIDATOR="$ROOT_DIR/scripts/validate-breakdown-escalation-intake.sh"
[[ -f "$ESCALATION_VALIDATOR" ]] || {
  echo "FAIL [T4]: escalation validator not found: $ESCALATION_VALIDATOR" >&2
  exit 1
}

# The PASS-line token the validator must emit for a packaging-scope plan-defect
# task_update, signalling the deterministic AC1/AC2 invariant: the loop-cap
# counter is NOT consumed by a packaging-only backfill.
T4_NO_COUNT_TOKEN="escalation_count_delta=0"

# write_packaging_plan_defect_sidecar <dest_file> — a plan-defect escalation
# whose closure forecast is POSITIVE (the packaging backfill closes the gap)
# so the task_update negative-forecast guard does not require --closes-gate.
write_packaging_plan_defect_sidecar() {
  local dest="$1"
  cat >"$dest" <<'EOF'
---
skill: engineering
ticket: TASK-9001
epic: EPIC-341
flavor: plan-defect
escalation_count: 1
timestamp: 2026-06-29T00:00:00Z
truncated: false
scrubbed: true
---

## Summary

The task.md packaging fields are too narrow; only the per-task packaging needs a backfill.

## Closure Forecast

Yes — once the packaging field is widened, the Verify Command passes and the task can resume.

## Required Planner Decisions

1. Widen the per-task packaging field so the colocated change is in scope.
EOF
}

# run_escalation_intake <stdout_capture> <stderr_capture> <args...> — spawn the
# escalation-intake validator with POLARIS_WORKSPACE_ROOT bound to ROOT_DIR so
# any task_update side effect resolves within this tree. Returns the exit code;
# never aborts the selftest under set -e.
run_escalation_intake() {
  local stdout_capture="$1"
  local stderr_capture="$2"
  shift 2
  local rc=0
  POLARIS_WORKSPACE_ROOT="$ROOT_DIR" \
    bash "$ESCALATION_VALIDATOR" "$@" >"$stdout_capture" 2>"$stderr_capture" || rc=$?
  return "$rc"
}

# --- T4 case 1 / AC1: packaging plan-defect (allowed_files) → route=task_update,
# NO refinement-inbox record, escalation_count NOT incremented. ---
t4_inbox_dir="$tmpdir/t4-refinement-inbox"
mkdir -p "$t4_inbox_dir"
t4_sidecar_af="$tmpdir/t4-allowed-files.md"
write_packaging_plan_defect_sidecar "$t4_sidecar_af"
t4_af_out="$tmpdir/t4-af.stdout"
t4_af_err="$tmpdir/t4-af.stderr"
t4_af_rc=0
run_escalation_intake "$t4_af_out" "$t4_af_err" \
  --sidecar "$t4_sidecar_af" \
  --route task_update \
  --closes-gate true \
  --flavor plan-defect \
  --scope packaging \
  --disposition "accepted flavor: plan-defect" \
  --decision "widen the per-task Allowed Files glob so the colocated change is in scope" \
  --inbox-dir "$t4_inbox_dir" || t4_af_rc=$?
if [[ "$t4_af_rc" -ne 0 ]]; then
  echo "FAIL [T4 case 1 / AC1]: packaging plan-defect (allowed_files) must PASS route=task_update, got exit $t4_af_rc" >&2
  cat "$t4_af_err" >&2
  exit 1
fi
if ! grep -qF "$T4_NO_COUNT_TOKEN" "$t4_af_out"; then
  echo "FAIL [T4 case 1 / AC1]: packaging task_update PASS line must emit '$T4_NO_COUNT_TOKEN' (loop cap not consumed)" >&2
  cat "$t4_af_out" >&2
  exit 1
fi
if [[ -n "$(find "$t4_inbox_dir" -type f 2>/dev/null)" ]]; then
  echo "FAIL [T4 case 1 / AC1]: packaging plan-defect must NOT write a refinement-inbox record; found:" >&2
  find "$t4_inbox_dir" -type f >&2
  exit 1
fi

# --- T4 case 2 / AC2: packaging plan-defect (estimate_points) → SAME
# task_update lane (not bounced to route=refinement), same no-increment token. ---
t4_inbox_dir_est="$tmpdir/t4-refinement-inbox-est"
mkdir -p "$t4_inbox_dir_est"
t4_sidecar_est="$tmpdir/t4-estimate.md"
write_packaging_plan_defect_sidecar "$t4_sidecar_est"
t4_est_out="$tmpdir/t4-est.stdout"
t4_est_err="$tmpdir/t4-est.stderr"
t4_est_rc=0
run_escalation_intake "$t4_est_out" "$t4_est_err" \
  --sidecar "$t4_sidecar_est" \
  --route task_update \
  --closes-gate true \
  --flavor plan-defect \
  --scope packaging \
  --disposition "accepted flavor: plan-defect" \
  --decision "correct the per-task estimate_points to match the widened scope" \
  --inbox-dir "$t4_inbox_dir_est" || t4_est_rc=$?
if [[ "$t4_est_rc" -ne 0 ]]; then
  echo "FAIL [T4 case 2 / AC2]: packaging plan-defect (estimate_points) must PASS the SAME task_update lane, got exit $t4_est_rc" >&2
  cat "$t4_est_err" >&2
  exit 1
fi
if ! grep -qF "$T4_NO_COUNT_TOKEN" "$t4_est_out"; then
  echo "FAIL [T4 case 2 / AC2]: estimate_points task_update PASS line must emit '$T4_NO_COUNT_TOKEN' (same lane as allowed_files)" >&2
  cat "$t4_est_out" >&2
  exit 1
fi
if grep -qiE 'route=refinement|refinement-inbox' "$t4_est_out"; then
  echo "FAIL [T4 case 2 / AC2]: estimate-only plan-defect must NOT be bounced to route=refinement" >&2
  cat "$t4_est_out" >&2
  exit 1
fi
if [[ -n "$(find "$t4_inbox_dir_est" -type f 2>/dev/null)" ]]; then
  echo "FAIL [T4 case 2 / AC2]: estimate_points plan-defect must NOT write a refinement-inbox record; found:" >&2
  find "$t4_inbox_dir_est" -type f >&2
  exit 1
fi

# =====================================================================
# DP-341 T5 — end-to-end boundary (refinement intent-only -> breakdown packages).
# Existing active refinement.json files that still carry per-task packaging fields
# are migrated exactly once. If a task.md already exists, it is the packaging
# authority; stale refinement-vs-task.md differences are reported explicitly and
# then removed from refinement.json. Archive history and hard exclusions remain
# untouched.
# =====================================================================

MIGRATION="$ROOT_DIR/scripts/migrate-refinement-packaging-fields.sh"
[[ -f "$MIGRATION" ]] || {
  echo "FAIL [T5]: migration script not found: $MIGRATION" >&2
  exit 1
}

write_legacy_packaging_refinement() {
  local dest_dir="$1"
  local source_id="$2"
  local task_id="$3"
  mkdir -p "$dest_dir"
  dest_dir="$(cd "$dest_dir" && pwd -P)"
  touch "$dest_dir/index.md"
  cat >"$dest_dir/refinement.json" <<JSON
{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "$source_id",
    "container": "$dest_dir",
    "plan_path": "$dest_dir/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "schema_version": "1.0",
  "created_at": "2026-06-29T00:00:00Z",
  "modules": [{ "path": "scripts/sample.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "t", "verification": { "method": "unit_test", "detail": "d" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "$task_id",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "t",
      "scope": "s",
      "allowed_files": ["scripts/sample.sh", "scripts/extra.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": { "method": "unit_test", "detail": "d" }
    }
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "a", "enforce": "e" }]
}
JSON
}

write_compact_legacy_packaging_refinement() {
  local dest_dir="$1"
  mkdir -p "$dest_dir"
  dest_dir="$(cd "$dest_dir" && pwd -P)"
  touch "$dest_dir/index.md"
  printf '%s\n' '{"epic":null,"source":{"type":"dp","id":"DP-998","container":"'"$dest_dir"'","plan_path":"'"$dest_dir"'/index.md","jira_key":null},"version":"1.0","schema_version":"1.0","created_at":"2026-06-29T00:00:00Z","modules":[{"path":"scripts/sample.sh","action":"modify"}],"acceptance_criteria":[{"id":"AC1","text":"t","verification":{"method":"unit_test","detail":"d"}}],"dependencies":[],"edge_cases":[],"predecessor_audit":[],"tasks":[{"id":"T1","kind":"implementation","title":"t","scope":"s","allowed_files":["scripts/sample.sh"],"modules":["scripts/sample.sh"],"ac_ids":["AC1"],"dependencies":[],"estimate_points":1,"verification":{"method":"unit_test","detail":"d"}}],"adversarial_pass":[{"ac_id":"AC1","attack":"a","enforce":"e"}]}' >"$dest_dir/refinement.json"
}

write_t5_packaged_task_md() {
  local dest="$1"
  local second_file="${2:-scripts/extra.sh}"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<TASKMD
---
title: "DP test task (2 pt)"
status: IN_PROGRESS
task_kind: T
---

# T1: DP test task (2 pt)

## Allowed Files

- \`scripts/sample.sh\`
- \`$second_file\`

## 目標

fixture
TASKMD
}

assert_refinement_packaging_absent() {
  local fixture="$1"
  python3 - "$fixture" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for idx, task in enumerate(data.get("tasks") or []):
    for field in ("allowed_files", "estimate_points"):
        if field in task:
            raise SystemExit(f"{sys.argv[1]} tasks[{idx}].{field} still present")
PY
}

assert_refinement_packaging_present() {
  local fixture="$1"
  python3 - "$fixture" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
tasks = data.get("tasks") or []
if not tasks or "allowed_files" not in tasks[0] or "estimate_points" not in tasks[0]:
    raise SystemExit(f"{sys.argv[1]} packaging fields were unexpectedly removed")
PY
}

# --- T5 case 1 / AC-NEG3: active broken-down + active not-yet-broken-down
# sources migrate to intent-only, archive and hard exclusions remain untouched. ---
t5_ws="$tmpdir/t5-workspace"
t5_design_plans="$t5_ws/docs-manager/src/content/docs/specs/design-plans"
t5_active_stale="$t5_design_plans/DP-999-active"
write_legacy_packaging_refinement "$t5_active_stale" "DP-999" "T1"
write_t5_packaged_task_md "$t5_active_stale/tasks/T1/index.md" "scripts/taskmd-extra.sh"

t5_active_pending="$t5_design_plans/DP-998-pending"
write_compact_legacy_packaging_refinement "$t5_active_pending"

t5_archive="$t5_design_plans/archive/DP-997-archived"
write_legacy_packaging_refinement "$t5_archive" "DP-997" "T1"

t5_dp231="$t5_design_plans/DP-231-concurrent"
write_legacy_packaging_refinement "$t5_dp231" "DP-231" "T1"

t5_dp375="$t5_design_plans/DP-375-halted"
write_legacy_packaging_refinement "$t5_dp375" "DP-375" "T1"

t5_out="$tmpdir/t5-migration.stdout"
t5_err="$tmpdir/t5-migration.stderr"
t5_rc=0
bash "$MIGRATION" --workspace-root "$t5_ws" >"$t5_out" 2>"$t5_err" || t5_rc=$?
if [[ "$t5_rc" -ne 0 ]]; then
  echo "FAIL [T5 case 1 / AC-NEG3]: migration expected exit 0, got $t5_rc" >&2
  cat "$t5_err" >&2
  exit 1
fi
assert_refinement_packaging_absent "$t5_active_stale/refinement.json"
assert_refinement_packaging_absent "$t5_active_pending/refinement.json"
assert_refinement_packaging_present "$t5_archive/refinement.json"
assert_refinement_packaging_present "$t5_dp231/refinement.json"
assert_refinement_packaging_present "$t5_dp375/refinement.json"
if ! grep -qF "STALE_REFINEMENT_PACKAGING_REMOVED: DP-999:T1:allowed_files" "$t5_out"; then
  echo "FAIL [T5 case 1 / AC-NEG3]: stale task.md-authority mismatch must be explicit, not silent" >&2
  cat "$t5_out" >&2
  exit 1
fi
if ! grep -qF "REMOVE_DRAFT_PACKAGING: DP-998:T1: no task.md" "$t5_out"; then
  echo "FAIL [T5 case 1 / AC-NEG3]: unbroken-down draft packaging removal must be explicit" >&2
  cat "$t5_out" >&2
  exit 1
fi
if ! grep -qF "DEFERRED: DP-231" "$t5_out" || ! grep -qF "DEFERRED: DP-375" "$t5_out"; then
  echo "FAIL [T5 case 1 / AC-NEG3]: hard exclusions must be logged as DEFERRED" >&2
  cat "$t5_out" >&2
  exit 1
fi

# --- T5 case 2 / idempotency: running migration again is a clean no-op for the
# migrated files and still leaves archive/exclusions untouched. ---
t5_second_out="$tmpdir/t5-migration-second.stdout"
bash "$MIGRATION" --workspace-root "$t5_ws" >"$t5_second_out" 2>"$tmpdir/t5-migration-second.stderr"
assert_refinement_packaging_absent "$t5_active_stale/refinement.json"
assert_refinement_packaging_absent "$t5_active_pending/refinement.json"
assert_refinement_packaging_present "$t5_archive/refinement.json"
assert_refinement_packaging_present "$t5_dp231/refinement.json"
assert_refinement_packaging_present "$t5_dp375/refinement.json"
if ! grep -qF "DP-999-active/refinement.json (intent-only)" "$t5_second_out"; then
  echo "FAIL [T5 case 2 / idempotency]: migrated active file should become intent-only no-op" >&2
  cat "$t5_second_out" >&2
  exit 1
fi

echo "PASS: refinement-breakdown packaging-boundary selftest (T1 schema cases + T2 derive intent/preserve cases + T3 producer registry cases + T4 escalation packaging task_update lane + T5 migration cases)"
