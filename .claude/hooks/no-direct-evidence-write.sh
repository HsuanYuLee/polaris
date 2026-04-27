#!/usr/bin/env bash
# no-direct-evidence-write.sh — PreToolUse hook for Write / Edit
# Blocks direct writes to evidence JSON files. These files must be produced
# by their designated scripts, not fabricated through editor tools.

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

case "$file_path" in
  /tmp/polaris-verified-*.json|/tmp/polaris-ci-local-*.json|/tmp/polaris-vr-*.json)
    echo "BLOCKED: evidence files may only be written by designated scripts." >&2
    echo "Allowed producers: run-verify-command.sh / ci-local.sh / run-visual-snapshot.sh" >&2
    echo "Debug the producing script; do not patch evidence JSON directly." >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
