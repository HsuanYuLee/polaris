#!/usr/bin/env bash
# design-plan-checklist-gate.sh — PreToolUse hook for Edit/Write
# Blocks marking a design plan as IMPLEMENTED when Implementation Checklist
# has unchecked items ([ ]).
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Only check Edit and Write
if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
  exit 0
fi

# Extract file_path and new content separately
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

# Only care about design plan files
if [[ "$file_path" != *"/design-plans/"*"/plan.md" ]]; then
  exit 0
fi

# For Edit: new_string; for Write: content
new_content=$(printf '%s' "$input" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('new_string', '') or ti.get('content', ''))
" 2>/dev/null || true)

# Only care if the edit introduces "status: IMPLEMENTED"
if [[ "$new_content" != *"status: IMPLEMENTED"* ]]; then
  exit 0
fi

# Read the current file and count unchecked items in Implementation Checklist
if [[ ! -f "$file_path" ]]; then
  exit 0
fi

# Extract from "## Implementation Checklist" to end-of-file or next ## heading
unchecked=$(awk '
  /^## Implementation Checklist/ { in_section=1; next }
  in_section && /^## / { exit }
  in_section && /^- \[ \]/ { count++ }
  END { print count+0 }
' "$file_path")

if [[ "$unchecked" -gt 0 ]]; then
  echo "BLOCKED: design plan has $unchecked unchecked item(s) in Implementation Checklist." >&2
  echo "Complete or drop all checklist items before marking status: IMPLEMENTED." >&2
  echo "File: $file_path" >&2
  exit 2
fi

exit 0
