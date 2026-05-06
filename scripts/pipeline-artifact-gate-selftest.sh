#!/usr/bin/env bash
set -euo pipefail

# scripts/pipeline-artifact-gate-selftest.sh — coverage for pipeline artifact routing guards.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/pipeline-artifact-gate.sh"
TMPROOT="$(mktemp -d -t pipeline-artifact-gate-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
  fi
}

json_input() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import json
import sys

path = sys.argv[1]
print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": path,
        "content": "---\ntitle: Fixture\n---\n\n# Fixture\n"
    },
}))
PY
}

legacy_task="$TMPROOT/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks/T1.md"
folder_task="$TMPROOT/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks/T1/index.md"
mkdir -p "$(dirname "$legacy_task")" "$(dirname "$folder_task")"

set +e
out="$(json_input "$legacy_task" | CLAUDE_PROJECT_DIR="$TMPROOT" POLARIS_LEGACY_TASK_LAYOUT_GATE=block "$GATE" 2>&1)"
rc=$?
set -e
assert_rc "legacy new task blocks when rollout flag is block" "$rc" "2"
assert_contains "legacy blocker explains folder-native target" "$out" "legacy task layout is deprecated for new files; use tasks/T1/index.md"

set +e
out="$(json_input "$folder_task" | CLAUDE_PROJECT_DIR="$TMPROOT" POLARIS_LEGACY_TASK_LAYOUT_GATE=block "$GATE" 2>&1)"
rc=$?
set -e
if [[ "$out" == *"legacy task layout is deprecated"* ]]; then
  assert_rc "folder-native task does not trigger legacy blocker" "1" "0"
else
  assert_rc "folder-native task does not trigger legacy blocker" "0" "0"
fi

printf '\n=== pipeline-artifact-gate selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
