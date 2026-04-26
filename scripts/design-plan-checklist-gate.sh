#!/usr/bin/env bash
# design-plan-checklist-gate.sh — PreToolUse hook for Edit/Write
# Blocks marking a design plan as IMPLEMENTED when Implementation Checklist
# has unchecked items ([ ]).
#
# Trigger: only fires when the edit/write actually transitions the YAML
# frontmatter `status:` field to IMPLEMENTED. Body text mentioning the
# string "status: IMPLEMENTED" (lifecycle docs, archive rules,
# self-referential checklist items) does not trigger the gate.
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# Only check Edit and Write
if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
  exit 0
fi

# Extract file_path
file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

# Only care about design plan files
if [[ "$file_path" != *"/design-plans/"*"/plan.md" ]]; then
  exit 0
fi

# Determine post-edit frontmatter status by simulating the edit:
#   - Write: post-content == tool_input.content
#   - Edit:  post-content == on-disk content with old_string → new_string
# Then parse YAML frontmatter from post-content and check `status:` field.
post_status=$(printf '%s' "$input" | python3 -c "
import sys, json, re

def extract_frontmatter_status(content: str) -> str:
    if not content.startswith('---'):
        return ''
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return ''
    end_idx = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == '---':
            end_idx = i
            break
    if end_idx is None:
        return ''
    fm_block = '\n'.join(lines[1:end_idx])
    m = re.search(r'^status:\s*(\S+)\s*$', fm_block, re.MULTILINE)
    return m.group(1) if m else ''

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

ti = d.get('tool_input', {}) or {}
tool = d.get('tool_name', '')
file_path = ti.get('file_path', '')

post_content = ''
if tool == 'Write':
    post_content = ti.get('content', '') or ''
elif tool == 'Edit':
    old = ti.get('old_string', '') or ''
    new = ti.get('new_string', '') or ''
    replace_all = bool(ti.get('replace_all', False))
    try:
        with open(file_path, 'r', encoding='utf-8') as fh:
            on_disk = fh.read()
    except Exception:
        on_disk = ''
    if not on_disk:
        post_content = ''
    elif replace_all:
        post_content = on_disk.replace(old, new)
    else:
        post_content = on_disk.replace(old, new, 1)

print(extract_frontmatter_status(post_content))
" 2>/dev/null || true)

# Only fire when post-edit frontmatter status is exactly IMPLEMENTED.
if [[ "$post_status" != "IMPLEMENTED" ]]; then
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
