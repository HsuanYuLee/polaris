#!/usr/bin/env bash
# Purpose: DP-364 T2 selftest for source-neutral verification_strategy gates.
# Inputs: none (writes hermetic refinement.json fixtures to a tmpdir).
# Outputs: PASS line on success; non-zero FAIL on contract regression.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE_STRATEGY="$ROOT_DIR/scripts/validate-verification-strategy.sh"
VALIDATE_JSON="$ROOT_DIR/scripts/validate-refinement-json.sh"
LOCK_PREFLIGHT="$ROOT_DIR/scripts/validate-refinement-lock-preflight.sh"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"

tmpdir="$(mktemp -d -t validate-verification-strategy.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

write_fixture() {
  local dest="$1" source_type="$2" mode="$3" include_v="$4"
  local source_extra=""
  local epic_value="null"
  if [[ "$source_type" == "jira" ]]; then
    source_extra=', "jira_key": "PROJ-100", "repo": "exampleco-web", "base_branch": "develop"'
    epic_value='"PROJ-100"'
  else
    local container
    container="$(cd "$(dirname "$dest")" && pwd)"
    touch "$container/index.md"
    source_extra=', "container": "'"$container"'", "plan_path": "'"$container"'/index.md", "jira_key": null, "base_branch": "feat/DP-999"'
  fi
  cat >"$dest" <<JSON
{
  "epic": $epic_value,
  "source": {
    "type": "$source_type",
    "id": "DP-999"$source_extra
  },
  "schema_version": "1.0",
  "version": "1.0",
  "created_at": "2026-07-06T00:00:00Z",
  "verification_strategy": {
    "mode": "$mode",
    "reason": "selftest reason",
    "authority": "DP-364 selftest"
  },
  "modules": [{ "path": "scripts/selftest-target.sh", "action": "modify" }],
  "acceptance_criteria": [
    { "id": "AC1", "text": "strategy selftest AC", "verification": { "method": "unit_test", "detail": "echo PASS" } }
  ],
  "dependencies": [],
  "edge_cases": [],
  "predecessor_audit": [],
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "tracked_deliverable_hint": "tracked",
      "title": "strategy selftest implementation task",
      "scope": "strategy selftest implementation task with self verify command",
      "modules": ["scripts/selftest-target.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS",
        "behavior_contract": { "applies": false, "reason": "selftest deterministic gate；無 runtime / UI 行為變更" },
        "test_environment": { "level": "static" },
        "verify_command": "echo PASS",
        "references": []
      }
    }
JSON
  if [[ "$include_v" == "yes" ]]; then
    cat >>"$dest" <<JSON
    ,
    {
      "id": "V1",
      "kind": "verification",
      "title": "strategy selftest verification task",
      "scope": "strategy selftest source-level verification envelope",
      "modules": [],
      "ac_ids": ["AC1"],
      "dependencies": ["T1"],
      "verification": { "method": "unit_test", "detail": "echo PASS" }
    }
JSON
  fi
  cat >>"$dest" <<'JSON'
  ],
  "adversarial_pass": [{ "ac_id": "AC1", "attack": "source type branch", "enforce": "mode only" }]
}
JSON
}

mkdir -p "$tmpdir/per-task"
per_task="$tmpdir/per-task/refinement.json"
write_fixture "$per_task" "dp" "per_task_self_verify" "no"
bash "$VALIDATE_JSON" "$per_task" >/dev/null
bash "$VALIDATE_STRATEGY" "$per_task" >/dev/null
bash "$LOCK_PREFLIGHT" "$per_task" >/dev/null
derive_out="$tmpdir/per-task-T1.md"
bash "$DERIVE" --refinement-json "$per_task" --task-id "DP-999-T1" >"$derive_out"
if grep -q "驗收委派給 .*V1" "$derive_out"; then
  echo "FAIL [AC7]: per_task_self_verify derive still emits hardcoded V1 delegation" >&2
  exit 1
fi
grep -q "per-task self-contained" "$derive_out" || {
  echo "FAIL [AC7]: per_task_self_verify derive missing self-contained handoff" >&2
  exit 1
}

mkdir -p "$tmpdir/source-level-missing-v"
missing_v="$tmpdir/source-level-missing-v/refinement.json"
write_fixture "$missing_v" "dp" "source_level_v_required" "no"
if bash "$LOCK_PREFLIGHT" "$missing_v" >/dev/null 2>"$tmpdir/missing-v.err"; then
  echo "FAIL [AC5]: source_level_v_required without V task passed" >&2
  exit 1
fi
grep -q "POLARIS_VERIFICATION_STRATEGY_MISSING_V_TASK" "$tmpdir/missing-v.err" || {
  echo "FAIL [AC5]: missing V failure did not emit expected marker" >&2
  cat "$tmpdir/missing-v.err" >&2
  exit 1
}

mkdir -p "$tmpdir/source-level-with-v"
with_v="$tmpdir/source-level-with-v/refinement.json"
write_fixture "$with_v" "dp" "source_level_v_required" "yes"
bash "$LOCK_PREFLIGHT" "$with_v" >/dev/null 2>"$tmpdir/with-v.err" || {
  echo "FAIL [AC5]: source_level_v_required with V task did not pass V-specific readiness" >&2
  cat "$tmpdir/with-v.err" >&2
  exit 1
}
source_level_out="$tmpdir/source-level-T1.md"
bash "$DERIVE" --refinement-json "$with_v" --task-id "DP-999-T1" >"$source_level_out"
grep -q "verification_strategy.mode=source_level_v_required" "$source_level_out" || {
  echo "FAIL [AC7]: source_level_v_required derive did not mention strategy mode" >&2
  exit 1
}

for source_type in dp jira; do
  if [[ "$source_type" == "dp" ]]; then
    mkdir -p "$tmpdir/parity-$source_type"
    parity="$tmpdir/parity-$source_type/refinement.json"
  else
    parity="$tmpdir/parity-$source_type.json"
  fi
  write_fixture "$parity" "$source_type" "source_level_v_required" "no"
  if bash "$VALIDATE_STRATEGY" "$parity" >/dev/null 2>"$tmpdir/parity-$source_type.err"; then
    echo "FAIL [AC-NEG2]: $source_type source_level_v_required without V unexpectedly passed" >&2
    exit 1
  fi
  grep -q "POLARIS_VERIFICATION_STRATEGY_MISSING_V_TASK" "$tmpdir/parity-$source_type.err" || {
    echo "FAIL [AC-NEG2]: $source_type missing V marker mismatch" >&2
    cat "$tmpdir/parity-$source_type.err" >&2
    exit 1
  }
done

mkdir -p "$tmpdir/bad-strategy"
bad_strategy="$tmpdir/bad-strategy/refinement.json"
write_fixture "$bad_strategy" "dp" "per_task_self_verify" "no"
python3 - "$bad_strategy" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["verification_strategy"]["reason"] = ""
json.dump(data, open(p, "w"))
PY
if bash "$VALIDATE_JSON" "$bad_strategy" >/dev/null 2>"$tmpdir/bad-json.err"; then
  echo "FAIL [schema]: invalid verification_strategy passed validate-refinement-json" >&2
  exit 1
fi
grep -q "POLARIS_REFINEMENT_VERIFICATION_STRATEGY_INVALID" "$tmpdir/bad-json.err" || {
  echo "FAIL [schema]: missing refinement-json strategy marker" >&2
  cat "$tmpdir/bad-json.err" >&2
  exit 1
}

grep -q "verification_strategy.mode" "$ROOT_DIR/.claude/skills/references/refinement-artifact.md" || {
  echo "FAIL [AC6]: refinement-artifact missing verification_strategy.mode contract" >&2
  exit 1
}
grep -q "Breakdown 只消費 structured field" "$ROOT_DIR/.claude/skills/references/breakdown-planning-flow.md" || {
  echo "FAIL [AC6]: breakdown-planning-flow missing structured-field consumption contract" >&2
  exit 1
}
grep -q "verification-strategy-source-neutral" "$ROOT_DIR/.claude/rules/mechanism-registry.md" || {
  echo "FAIL [registry]: mechanism registry missing verification strategy canary" >&2
  exit 1
}

echo "PASS: validate-verification-strategy selftest"
