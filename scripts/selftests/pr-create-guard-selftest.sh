#!/usr/bin/env bash
# Purpose: DP-231 T9 regression for the direct gh pr create PreToolUse guard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/scripts/pr-create-guard.sh"
TMP="$(mktemp -d -t pr-create-guard.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

payload() {
  local command="$1"
  python3 - "$command" <<'PY'
import json
import sys

print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
PY
}

if payload "gh pr create --base main --title 測試 --body 測試" | POLARIS_PR_WORKFLOW=1 "$GUARD" >/dev/null 2>"$TMP/direct.err"; then
  echo "FAIL: direct gh pr create passed with POLARIS_PR_WORKFLOW=1" >&2
  exit 1
fi
grep -Fq "BLOCKED: Direct gh pr create" "$TMP/direct.err" || {
  echo "FAIL: missing direct-create block message" >&2
  cat "$TMP/direct.err" >&2
  exit 1
}

payload "bash scripts/polaris-pr-create.sh --base main --title 測試 --body 測試" | "$GUARD" >/dev/null
payload "echo gh pr create --base main" | "$GUARD" >/dev/null

if grep -Fq "POLARIS_PR_WORKFLOW" "$GUARD"; then
  echo "FAIL: legacy POLARIS_PR_WORKFLOW bypass remains in guard" >&2
  exit 1
fi

echo "PASS: pr-create guard selftest"
