#!/usr/bin/env bash
# Purpose: selftest for validate-refinement-json.sh DP-269 jira-only schema rules.
# Inputs:  none (writes fixtures to a tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-269):
#   AC4     : source.type=jira positive fixture (source.repo + source.base_branch
#             + tasks[].jira_key string|null) PASSes.
#   AC-NEG1 : source.type=dp fixture carrying jira-only fields
#             (source.repo / source.base_branch / tasks[].jira_key) FAILs
#             fail-closed with POLARIS_REFINEMENT_JIRA_ONLY_FIELD.
#   AC-NEG2 : the jira-only relaxation does not leak into the dp branch — a dp
#             fixture WITHOUT jira-only fields still PASSes unchanged, and a jira
#             fixture MISSING the required jira-only fields FAILs.

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
      "title": "t",
      "scope": "s",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 2,
      "verification": { "method": "unit_test", "detail": "d" }
    },
    {
      "id": "T2",
      "kind": "task",
      "jira_key": null,
      "title": "t2",
      "scope": "s2",
      "allowed_files": ["scripts/sample.sh"],
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
      "allowed_files": ["scripts/sample.sh"],
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
      "allowed_files": ["scripts/sample.sh"],
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
if bash "$SCRIPT" "$dp_taskkey" >/dev/null 2>"$tmpdir/dp-taskkey.stderr"; then
  echo "FAIL [case 3 / AC-NEG1]: dp source with tasks[].jira_key passed (expected fail-closed)" >&2
  exit 1
fi
if ! grep -q "POLARIS_REFINEMENT_JIRA_ONLY_FIELD" "$tmpdir/dp-taskkey.stderr"; then
  echo "FAIL [case 3 / AC-NEG1]: missing POLARIS_REFINEMENT_JIRA_ONLY_FIELD marker for tasks[].jira_key" >&2
  cat "$tmpdir/dp-taskkey.stderr" >&2
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
      "allowed_files": ["scripts/sample.sh"],
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
      "allowed_files": ["scripts/sample.sh"],
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

echo "PASS: validate-refinement-json selftest"
