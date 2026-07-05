#!/usr/bin/env bash
# Purpose: DP-231 T8 regression — Bug source task identity uses
#          source_type=bug and {BUG_KEY}-Tn/Vn work_item_id.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT/scripts/derive-task-md-from-refinement-json.sh"
VALIDATE="$ROOT/scripts/validate-task-md.sh"
RESOLVE="$ROOT/scripts/resolve-task-md.sh"
TMP="$(mktemp -d -t bug-source-task-identity.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

BUG_DIR="$TMP/docs-manager/src/content/docs/specs/companies/exampleco/BUG-321"
mkdir -p "$BUG_DIR/tasks/T1" "$BUG_DIR/tasks/V1"

cat >"$BUG_DIR/refinement.json" <<JSON
{
  "source": {
    "type": "bug",
    "id": "BUG-321",
    "container": "$BUG_DIR",
    "repo": "exampleco-b2c-web",
    "base_branch": "main"
  },
  "schema_version": 1,
  "acceptance_criteria": [
    {
      "id": "AC1",
      "description": "Bug source work item identity remains source-neutral.",
      "category": "functional",
      "quantifiable": true,
      "verification": {"method": "unit_test", "detail": "bash scripts/selftests/bug-source-task-identity-selftest.sh"}
    }
  ],
  "tasks": [
    {
      "id": "BUG-321-T1",
      "kind": "implementation",
      "title": "修正 Bug source identity",
      "scope": "驗證 Bug source T task 使用 BUG-321-T1 work_item_id，且 JIRA key 可以是 N/A。",
      "allowed_files": ["scripts/bug-source.sh"],
      "modules": ["scripts/bug-source.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/bug-source-task-identity-selftest.sh",
        "verify_command": "bash scripts/selftests/bug-source-task-identity-selftest.sh",
        "behavior_contract": {"applies": false, "reason": "static identity fixture"},
        "test_environment": {"level": "static"}
      }
    },
    {
      "id": "BUG-321-V1",
      "kind": "verification",
      "title": "驗收 Bug source identity",
      "scope": "驗收 Bug source V task 使用 BUG-321-V1 work_item_id。",
      "allowed_files": ["scripts/selftests/bug-source-task-identity-selftest.sh"],
      "modules": ["scripts/selftests/bug-source-task-identity-selftest.sh"],
      "ac_ids": ["AC1"],
      "dependencies": ["BUG-321-T1"],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "bash scripts/selftests/bug-source-task-identity-selftest.sh",
        "verify_command": "bash scripts/selftests/bug-source-task-identity-selftest.sh",
        "behavior_contract": {"applies": false, "reason": "static identity fixture"},
        "test_environment": {"level": "static"}
      }
    }
  ]
}
JSON

bash "$DERIVE" --refinement-json "$BUG_DIR/refinement.json" --task-id BUG-321-T1 >"$BUG_DIR/tasks/T1/index.md"
bash "$DERIVE" --refinement-json "$BUG_DIR/refinement.json" --task-id BUG-321-V1 >"$BUG_DIR/tasks/V1/index.md"

for task in T1 V1; do
  file="$BUG_DIR/tasks/$task/index.md"
  grep -Fq "| Source type | bug |" "$file" || { echo "FAIL: $task missing source_type=bug" >&2; cat "$file" >&2; exit 1; }
  grep -Fq "| Source ID | BUG-321 |" "$file" || { echo "FAIL: $task missing source id" >&2; cat "$file" >&2; exit 1; }
  grep -Fq "| Task ID | BUG-321-$task |" "$file" || { echo "FAIL: $task missing source work_item_id" >&2; cat "$file" >&2; exit 1; }
  grep -Fq "| JIRA key | N/A |" "$file" || { echo "FAIL: $task should allow JIRA key N/A" >&2; cat "$file" >&2; exit 1; }
  bash "$VALIDATE" "$file" >/dev/null 2>"$TMP/validate-$task.err" || {
    echo "FAIL: validate-task-md rejected Bug source $task" >&2
    cat "$TMP/validate-$task.err" >&2
    exit 1
  }
done

out="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "$RESOLVE" --scan-root "$TMP" BUG-321-T1)"
[[ "$out" == "$BUG_DIR/tasks/T1/index.md" ]] || {
  echo "FAIL: BUG-321-T1 resolver output mismatch: $out" >&2
  exit 1
}

out="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "$RESOLVE" --scan-root "$TMP" --from-input "請做 BUG-321-T1")"
[[ "$out" == "$BUG_DIR/tasks/T1/index.md" ]] || {
  echo "FAIL: from-input BUG-321-T1 resolver output mismatch: $out" >&2
  exit 1
}

out="$(env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "$RESOLVE" --scan-root "$TMP" BUG-321-V1)"
[[ "$out" == "$BUG_DIR/tasks/V1/index.md" ]] || {
  echo "FAIL: BUG-321-V1 resolver output mismatch: $out" >&2
  exit 1
}

if env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "$RESOLVE" --scan-root "$TMP" BUG-321 >/dev/null 2>"$TMP/short.err"; then
  echo "FAIL: BUG-321 bare JIRA lookup unexpectedly resolved a source work item" >&2
  exit 1
fi

echo "PASS: bug source task identity selftest"
