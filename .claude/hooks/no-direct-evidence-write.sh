#!/usr/bin/env bash
# no-direct-evidence-write.sh — PreToolUse hook for Write / Edit / MultiEdit
# Blocks direct writes to evidence JSON files and specs-bound Markdown. These
# files must be produced through designated producer scripts/flows.

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

case "$file_path" in
  /tmp/polaris-verified-*.json|/tmp/polaris-ci-local-*.json|/tmp/polaris-vr-*.json|\
  .polaris/evidence/task-snapshot/*.json|*/.polaris/evidence/task-snapshot/*.json|\
  .polaris/evidence/validation-fail/*.json|*/.polaris/evidence/validation-fail/*.json|\
  .polaris/evidence/missing-v-task/*.json|*/.polaris/evidence/missing-v-task/*.json|\
  .polaris/evidence/completion-gate/*.json|*/.polaris/evidence/completion-gate/*.json|\
  .polaris/evidence/blocked-conflict/*.json|*/.polaris/evidence/blocked-conflict/*.json|\
  .polaris/evidence/unsupported-mutation/*.json|*/.polaris/evidence/unsupported-mutation/*.json|\
  .polaris/evidence/ci-local/*.json|*/.polaris/evidence/ci-local/*.json|\
  .polaris/evidence/verify/*.json|*/.polaris/evidence/verify/*.json|\
  .polaris/evidence/ac-verification/*.json|*/.polaris/evidence/ac-verification/*.json|\
  .polaris/evidence/auto-pass/audit/*.json|*/.polaris/evidence/auto-pass/audit/*.json|\
  docs-manager/src/content/docs/specs/**/*.md|*/docs-manager/src/content/docs/specs/**/*.md)
    echo "BLOCKED: evidence/specs-bound files may only be written by designated producer flows." >&2
    echo "Allowed producers are declared in scripts/lib/evidence-producers.json." >&2
    echo "Debug the producing script or emit contract; do not patch protected artifacts directly." >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
