#!/usr/bin/env bash
# Purpose: assert derive-task-md-from-refinement-json.sh verify-command 契約——
#          有 verify_command 時優先寫入 fence（prose detail 不漏入）；
#          verify_command 為 null + prose detail 時 fail-closed（exit 2 +
#          POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE，不產出 task.md body）。
# Inputs:  無 CLI args；自建 temp refinement.json fixtures。
# Outputs: PASS/FAIL 訊息；exit 0 全過、exit 1 任一 assert 失敗。
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

# Fail-closed contract (DP-311 T6): null verify_command + prose detail must NOT
# fall back into the fence — derive exits 2 with a structured marker and no body.
fail_closed="$TMP/fail-closed.json"
make_refinement "$fail_closed" 'null'
fail_closed_out="$TMP/fail-closed.md"
fail_closed_err="$TMP/fail-closed-err.txt"
fail_closed_rc=0
bash "$SCRIPT" --refinement-json "$fail_closed" --task-id DP-960-T1 \
  >"$fail_closed_out" 2>"$fail_closed_err" || fail_closed_rc=$?
if [[ "$fail_closed_rc" -ne 2 ]]; then
  echo "FAIL: derive must exit 2 when verify_command is null and detail is prose (got rc=$fail_closed_rc)" >&2
  exit 1
fi
if ! grep -q 'POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE' "$fail_closed_err"; then
  echo "FAIL: stderr missing POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE marker for null verify_command + prose detail" >&2
  exit 1
fi
if [[ -s "$fail_closed_out" ]]; then
  echo "FAIL: derive must not emit task.md body when verify_command executability check fails" >&2
  exit 1
fi

echo "PASS: derive task verify_command priority"
