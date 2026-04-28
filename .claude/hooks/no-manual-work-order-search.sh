#!/usr/bin/env bash
# no-manual-work-order-search.sh — PreToolUse hook for Bash
# After resolve-task-md.sh establishes an authoritative work-order lock,
# block ad-hoc find/rg/grep searches over specs/tasks that could override
# the resolver result with a human-crafted fallback.

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)
[[ -n "$command" ]] || exit 0

# Allow the authoritative resolver itself and explicit lock clearing.
if printf '%s' "$command" | grep -qE 'resolve-task-md\.sh|resolve-task-md-by-branch\.sh'; then
  exit 0
fi

# Only care about ad-hoc search commands over specs/tasks.
if ! printf '%s' "$command" | grep -qE '^(find|rg|grep|fd)\b'; then
  exit 0
fi
if ! printf '%s' "$command" | grep -qE 'specs/.*/tasks|specs|tasks/pr-release|plan\.md|T[0-9]+[a-z]?\.md'; then
  exit 0
fi

state="$(python3 - "$command" <<'PY'
import json
import glob
import sys
from datetime import datetime, timezone

command = sys.argv[1]
now = datetime.now(timezone.utc)
fresh = []

for path in glob.glob("/tmp/polaris-work-order-lock-*.json"):
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        at = datetime.fromisoformat(d["at"])
        if at.tzinfo is None:
            at = at.replace(tzinfo=timezone.utc)
        age = (now - at).total_seconds()
        if age <= 7200:
            fresh.append(d)
    except Exception:
        continue

if not fresh:
    print("")
    raise SystemExit(0)

# Prefer a lock whose root path is mentioned in the command.
for d in fresh:
    root = d.get("root", "")
    if root and root in command:
        print(d.get("resolved_path", ""))
        raise SystemExit(0)

# Otherwise if there is exactly one fresh lock, treat it as authoritative.
if len(fresh) == 1:
    print(fresh[0].get("resolved_path", ""))
    raise SystemExit(0)

print("")
PY
)"

case "$state" in
  stale|invalid|"")
    exit 0
    ;;
esac

echo "BLOCKED: manual work-order search after authoritative resolver lock." >&2
echo "Use scripts/resolve-task-md.sh as the sole work-order authority for this session." >&2
echo "Resolved work order: $state" >&2
echo "If you intentionally need to discard the lock, run: bash scripts/resolve-task-md.sh --clear-lock" >&2
exit 2
