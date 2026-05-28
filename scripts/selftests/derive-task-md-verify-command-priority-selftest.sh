#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/derive-task-md-from-refinement-json.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_refinement() {
  local path="$1"
  local verify_command_json="$2"
  cat >"$path" <<JSON
{
  "source": {"type": "dp", "id": "DP-960"},
  "schema_version": 1,
  "tasks": [
    {
      "id": "DP-960-T1",
      "kind": "implementation",
      "title": "Verify command priority",
      "scope": "Assert verify_command has priority over prose detail.",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "這是不可執行的中文驗證說明",
        "verify_command": $verify_command_json
      }
    }
  ]
}
JSON
}

with_command="$TMP/with-command.json"
make_refinement "$with_command" '"echo PASS_FROM_VERIFY_COMMAND"'
with_command_out="$TMP/with-command.md"
bash "$SCRIPT" --refinement-json "$with_command" --task-id DP-960-T1 >"$with_command_out"
with_command_fence="$TMP/with-command-fence.txt"
awk '/^## Verify Command$/ {capture=1; next} capture && /^```bash$/ {next} capture && /^```$/ {exit} capture {print}' "$with_command_out" >"$with_command_fence"
if ! grep -q 'echo PASS_FROM_VERIFY_COMMAND' "$with_command_fence"; then
  echo "FAIL: verify_command was not emitted in Verify Command fence" >&2
  exit 1
fi
if grep -q '這是不可執行的中文驗證說明' "$with_command_fence"; then
  echo "FAIL: verification.detail leaked into Verify Command fence when verify_command was set" >&2
  exit 1
fi

fallback="$TMP/fallback.json"
make_refinement "$fallback" 'null'
fallback_out="$TMP/fallback.md"
bash "$SCRIPT" --refinement-json "$fallback" --task-id DP-960-T1 >"$fallback_out"
fallback_fence="$TMP/fallback-fence.txt"
awk '/^## Verify Command$/ {capture=1; next} capture && /^```bash$/ {next} capture && /^```$/ {exit} capture {print}' "$fallback_out" >"$fallback_fence"
if ! grep -q '這是不可執行的中文驗證說明' "$fallback_fence"; then
  echo "FAIL: verification.detail fallback missing when verify_command is null" >&2
  exit 1
fi

echo "PASS: derive task verify_command priority"
