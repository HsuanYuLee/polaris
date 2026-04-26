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

# Build a synthetic Write payload to feed the checklist gate for validation.
# The 2099-12-31 placeholder is never written to disk. The real file rewrite
# below uses today's date; the gate only needs a structurally valid post-write
# payload with status: IMPLEMENTED so it can inspect checklist completeness.
payload="$(python3 - "$plan_file" <<'PY'
import json
import sys

plan_file = sys.argv[1]
with open(plan_file, "r", encoding="utf-8") as fh:
    content = fh.read()

if content.startswith("---\n"):
    parts = content.split("\n---\n", 1)
    if len(parts) == 2:
        frontmatter, body = parts
        fm_lines = frontmatter.splitlines()
        seen_status = False
        seen_implemented_at = False
        out = []
        for line in fm_lines:
            if line.startswith("status:"):
                out.append("status: IMPLEMENTED")
                seen_status = True
            elif line.startswith("implemented_at:"):
                out.append("implemented_at: 2099-12-31")
                seen_implemented_at = True
            else:
                out.append(line)
        if not seen_status:
            out.append("status: IMPLEMENTED")
        if not seen_implemented_at:
            out.append("implemented_at: 2099-12-31")
        content = "\n".join(out) + "\n---\n" + body

print(json.dumps({
    "tool_name": "Write",
    "tool_input": {
        "file_path": plan_file,
        "content": content
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

# Keep docs-viewer sidebar in sync for Codex/bash-driven status transitions.
sync_hook="$ROOT_DIR/scripts/docs-viewer-sync-hook.sh"
if [[ -x "$sync_hook" ]]; then
  "$sync_hook" "$ROOT_DIR" "$plan_file" >/dev/null 2>&1 || true
fi

echo "PASS: marked IMPLEMENTED for $plan_file"
