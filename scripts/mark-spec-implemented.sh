#!/usr/bin/env bash
# Mark an Epic/Bug/Task spec as IMPLEMENTED (or ABANDONED) by updating
# the frontmatter status field in refinement.md / plan.md.
#
# Usage:
#   mark-spec-implemented.sh <ticket_key> [--status IMPLEMENTED|ABANDONED] [--workspace <path>]
#
# Examples:
#   mark-spec-implemented.sh GT-521
#   mark-spec-implemented.sh KB2CW-3847 --status IMPLEMENTED
#   mark-spec-implemented.sh GT-483 --status ABANDONED
#
# Behavior:
#   - First tries Epic-level anchor: {workspace}/*/specs/<ticket>/refinement.md or plan.md
#   - Falls back to Task-level anchor: {workspace}/*/specs/*/tasks/T*.md whose header
#     contains "> JIRA: <ticket_key>" (task.md schema from pipeline-handoff.md)
#   - If file has no frontmatter, prepends one with status
#   - If file has frontmatter with status, replaces only the status line
#   - Idempotent: if status is already set to the target value, does nothing
#   - Exit 0 on success (including idempotent no-op); exit 1 on error
#
# Non-goals:
#   - Does NOT sync to JIRA
#   - Does NOT regenerate sidebar (docs-viewer-sync-hook handles that via PostToolUse)

set -euo pipefail

TICKET=""
STATUS="IMPLEMENTED"
WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --status)     STATUS="$2"; shift 2 ;;
    --workspace)  WORKSPACE_ROOT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TICKET" ]; then
        TICKET="$1"
        shift
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TICKET" ]; then
  echo "ERROR: ticket key required (e.g., GT-521)" >&2
  exit 1
fi

case "$STATUS" in
  IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION) ;;
  *)
    echo "ERROR: invalid status '$STATUS' (must be IMPLEMENTED|ABANDONED|LOCKED|DISCUSSION)" >&2
    exit 1
    ;;
esac

# Resolve anchor file — two resolution paths:
#   1) Epic-level: {workspace}/*/specs/<ticket>/refinement.md or plan.md
#   2) Task-level: {workspace}/*/specs/*/tasks/T*.md whose header contains "> JIRA: <ticket>"
ANCHOR=""

# Path 1 — Epic-level
for company_dir in "$WORKSPACE_ROOT"/*/; do
  candidate="${company_dir}specs/${TICKET}"
  if [ -d "$candidate" ]; then
    [ -f "$candidate/refinement.md" ] && ANCHOR="$candidate/refinement.md" && break
    [ -f "$candidate/plan.md" ] && ANCHOR="$candidate/plan.md" && break
  fi
done

# Path 2 — Task-level (only if Path 1 missed)
if [ -z "$ANCHOR" ]; then
  # Match "> JIRA: KEY" with word boundary (space, |, newline, EOF)
  # e.g., "> Epic: GT-478 | JIRA: KB2CW-3821 | Repo: kkday-b2c-web"
  while IFS= read -r f; do
    ANCHOR="$f"
    break
  done < <(grep -lE "^> .*JIRA: ${TICKET}([[:space:]]|\$|\|)" "$WORKSPACE_ROOT"/*/specs/*/tasks/T*.md 2>/dev/null)
fi

if [ -z "$ANCHOR" ]; then
  echo "ERROR: no spec found for $TICKET" >&2
  echo "  Searched:" >&2
  echo "    - $WORKSPACE_ROOT/*/specs/$TICKET/{refinement.md,plan.md}" >&2
  echo "    - $WORKSPACE_ROOT/*/specs/*/tasks/T*.md (by '> JIRA: $TICKET' header)" >&2
  exit 1
fi

# Check existing status (idempotent exit)
existing_status=""
if head -1 "$ANCHOR" | grep -q '^---$'; then
  existing_status=$(sed -n '/^---$/,/^---$/p' "$ANCHOR" | grep '^status:' | head -1 | sed 's/^status:[[:space:]]*//' || true)
fi

if [ "$existing_status" = "$STATUS" ]; then
  echo "NOOP: $ANCHOR already has status: $STATUS"
  exit 0
fi

# Update frontmatter using python (robust for YAML edge cases)
python3 - "$ANCHOR" "$STATUS" <<'PY'
import sys
import re
from pathlib import Path

path = Path(sys.argv[1])
new_status = sys.argv[2]

content = path.read_text(encoding="utf-8")
lines = content.split("\n")

if lines and lines[0] == "---":
    # Has frontmatter — find closing ---
    try:
        close_idx = lines.index("---", 1)
    except ValueError:
        print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
        sys.exit(1)

    fm = lines[1:close_idx]
    status_pattern = re.compile(r"^status:\s*")
    found = False
    for i, line in enumerate(fm):
        if status_pattern.match(line):
            fm[i] = f"status: {new_status}"
            found = True
            break
    if not found:
        fm.append(f"status: {new_status}")

    new_content = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[close_idx+1:])
else:
    # No frontmatter — prepend
    new_content = f"---\nstatus: {new_status}\n---\n\n" + content

path.write_text(new_content, encoding="utf-8")
print(f"OK: {path} → status: {new_status}")
PY
