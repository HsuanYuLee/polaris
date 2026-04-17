#!/usr/bin/env bash
# codex-mark-design-plan-implemented.sh
# Codex fallback pre-write gate for design plan status transition.
#
# Runs P1 governance gate:
#  - design-plan-checklist-gate
#
# Usage:
#   codex-mark-design-plan-implemented.sh [--dry-run] <plan_file>
#
# Behavior:
#   - Always runs design-plan-checklist-gate with a synthetic Write payload.
#   - If gate passes and not dry-run, updates frontmatter:
#       status: IMPLEMENTED
#       implemented_at: YYYY-MM-DD (insert/update)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_SCRIPT="$ROOT_DIR/scripts/design-plan-checklist-gate.sh"

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 [--dry-run] <plan_file>" >&2
  exit 1
fi

plan_file="$1"

if [[ ! -f "$plan_file" ]]; then
  echo "Plan file not found: $plan_file" >&2
  exit 1
fi

if [[ "$plan_file" != *"/design-plans/"*"/plan.md" ]]; then
  echo "Unsupported path (must be specs/design-plans/*/plan.md): $plan_file" >&2
  exit 1
fi

payload="$(python3 - "$plan_file" <<'PY'
import json
import sys

plan_file = sys.argv[1]
print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": plan_file,
        "content": "status: IMPLEMENTED"
    }
}))
PY
)"

printf '%s' "$payload" | bash "$GATE_SCRIPT"

if [[ "$dry_run" == true ]]; then
  echo "PASS: design-plan checklist gate passed (dry-run)"
  exit 0
fi

today="$(date +%F)"
tmp_file="$(mktemp)"

awk -v today="$today" '
  BEGIN {
    in_frontmatter = 0
    seen_status = 0
    seen_implemented_at = 0
    done = 0
    line_no = 0
  }
  {
    line_no++
    if (line_no == 1 && $0 == "---") {
      in_frontmatter = 1
      print
      next
    }

    if (in_frontmatter && $0 == "---") {
      if (!seen_status) {
        print "status: IMPLEMENTED"
      }
      if (!seen_implemented_at) {
        print "implemented_at: " today
      }
      in_frontmatter = 0
      done = 1
      print
      next
    }

    if (in_frontmatter && $0 ~ /^status:[[:space:]]*/) {
      print "status: IMPLEMENTED"
      seen_status = 1
      next
    }

    if (in_frontmatter && $0 ~ /^implemented_at:[[:space:]]*/) {
      print "implemented_at: " today
      seen_implemented_at = 1
      next
    }

    print
  }
  END {
    if (!done) {
      # No frontmatter found; leave file unchanged semantics by printing original path content in caller scope.
      # awk cannot rewind original content in END, so rely on standard path having frontmatter.
    }
  }
' "$plan_file" > "$tmp_file"

mv "$tmp_file" "$plan_file"
echo "PASS: marked IMPLEMENTED for $plan_file"
