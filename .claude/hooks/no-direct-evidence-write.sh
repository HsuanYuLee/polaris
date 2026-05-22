#!/usr/bin/env bash
# no-direct-evidence-write.sh — PreToolUse hook for Write / Edit / MultiEdit
# Blocks direct writes to evidence JSON files and specs-bound Markdown. These
# files must be produced through designated producer scripts/flows.
#
# DP-226: auto-pass ledger / resume JSON paths under
# docs-manager/src/content/docs/specs/**/artifacts/auto-pass/*-{ledger,resume}.json
# are added to protected globs. POLARIS_PRODUCER env token recognition is added
# with token-first lookup: bypass requires (a) token present in some producer
# entry's producer_tokens[] AND (b) file_path matching that same entry's
# path_globs[]. Token uniqueness across producer_tokens[] is invariant.

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

# Determine if file_path is in any protected scope (existing BLOCKED globs plus
# DP-226 auto-pass ledger/resume globs).
in_protected_scope=0
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
  docs-manager/src/content/docs/specs/**/*.md|*/docs-manager/src/content/docs/specs/**/*.md|\
  docs-manager/src/content/docs/specs/**/artifacts/auto-pass/*-ledger.json|*/docs-manager/src/content/docs/specs/**/artifacts/auto-pass/*-ledger.json|\
  docs-manager/src/content/docs/specs/**/artifacts/auto-pass/*-resume.json|*/docs-manager/src/content/docs/specs/**/artifacts/auto-pass/*-resume.json)
    in_protected_scope=1
    ;;
esac

if [[ "$in_protected_scope" -ne 1 ]]; then
  exit 0
fi

# DP-226 POLARIS_PRODUCER token recognition. Bypass requires token+glob match
# against scripts/lib/evidence-producers.json. Token uniqueness across all
# producer_tokens[] entries is an invariant — token appearing in >1 entry is
# treated as fail-closed (no bypass).
if [[ -n "${POLARIS_PRODUCER:-}" ]]; then
  script_dir_nd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  workspace_root_nd="$(cd "$script_dir_nd/../.." && pwd)"
  producers_json_nd="$workspace_root_nd/scripts/lib/evidence-producers.json"
  decision_nd="NO_TABLE"
  if [[ -f "$producers_json_nd" ]]; then
    decision_nd=$(POLARIS_PRODUCER_VAL="$POLARIS_PRODUCER" FILE_PATH_VAL="$file_path" \
      PRODUCERS_JSON_VAL="$producers_json_nd" python3 - <<'PY' 2>/dev/null || true
import fnmatch
import json
import os
import sys

token = os.environ.get("POLARIS_PRODUCER_VAL", "")
file_path = os.environ.get("FILE_PATH_VAL", "")
producers_json = os.environ.get("PRODUCERS_JSON_VAL", "")

try:
    with open(producers_json, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("NO_TABLE")
    sys.exit(0)

producers = data.get("producers", []) or []
matching = [p for p in producers if token in (p.get("producer_tokens") or [])]
if len(matching) > 1:
    print("TOKEN_NOT_UNIQUE")
    sys.exit(0)
if len(matching) == 0:
    print("TOKEN_UNKNOWN")
    sys.exit(0)

entry = matching[0]
globs = entry.get("path_globs", []) or []

def match_any(path, globs):
    for g in globs:
        if fnmatch.fnmatch(path, g):
            return True
        parts = path.split("/")
        for i in range(len(parts)):
            tail = "/".join(parts[i:])
            if fnmatch.fnmatch(tail, g):
                return True
        g_alt = g.replace("**/", "*/").replace("/**", "/*")
        if fnmatch.fnmatch(path, g_alt):
            return True
    return False

if match_any(file_path, globs):
    print("BYPASS_TOKEN")
else:
    print("PATH_OUT_OF_GLOBS")
PY
)
  fi
  case "$decision_nd" in
    BYPASS_TOKEN)
      echo "[no-direct-evidence-write] producer=$POLARIS_PRODUCER path=$file_path (DP-226 token+glob bypass)" >&2
      exit 0
      ;;
    PATH_OUT_OF_GLOBS)
      echo "[no-direct-evidence-write] DENIED token+path mismatch producer=$POLARIS_PRODUCER path=$file_path (DP-226 strict)" >&2
      ;;
    TOKEN_NOT_UNIQUE)
      echo "[no-direct-evidence-write] DENIED token uniqueness violated producer=$POLARIS_PRODUCER (DP-226)" >&2
      ;;
    TOKEN_UNKNOWN|NO_TABLE|"")
      echo "[no-direct-evidence-write] DENIED token not in producer_tokens[] producer=$POLARIS_PRODUCER path=$file_path (DP-226 strict)" >&2
      ;;
  esac
fi

# Fall through to BLOCKED — protected scope, no valid producer bypass.
echo "BLOCKED: evidence/specs-bound files may only be written by designated producer flows." >&2
echo "Allowed producers are declared in scripts/lib/evidence-producers.json." >&2
echo "Debug the producing script or emit contract; do not patch protected artifacts directly." >&2
exit 2
