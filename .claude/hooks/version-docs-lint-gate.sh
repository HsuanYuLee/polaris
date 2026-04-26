#!/bin/bash
# version-docs-lint-gate.sh — PreToolUse hook for git commit
# Blocks commit when VERSION is staged but readme-lint.py fails.
#
# This is deterministic enforcement of the post-version-bump docs-sync chain.
# Previously behavioral-only (framework-iteration.md), it was missed in v2.12.0
# causing 14 stale doc references to ship.
#
# Hook type: PreToolUse (fires before tool execution)
# Matcher: Bash
# Condition: git commit commands only
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Only intercept git commit
printf '%s' "$command" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Extract repo path from git -C <path> or use project dir
repo_dir=""
if printf '%s' "$command" | grep -qE 'git[[:space:]]+-C[[:space:]]+'; then
  repo_dir=$(printf '%s' "$command" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^ ]+).*/\1/p')
fi
repo_dir="${repo_dir:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

# Only applies to repos with a VERSION file
[[ -f "$repo_dir/VERSION" ]] || exit 0

# Check if VERSION is in staged files
staged=$(git -C "$repo_dir" diff --cached --name-only 2>/dev/null || true)
echo "$staged" | grep -q '^VERSION$' || exit 0

# Bypass
if [[ "${POLARIS_SKIP_DOCS_LINT:-}" == "1" ]]; then
  exit 0
fi

# VERSION is staged — run readme-lint
lint_script="$repo_dir/scripts/readme-lint.py"
[[ -f "$lint_script" ]] || exit 0

lint_output=$(python3 "$lint_script" 2>&1) || {
  cat >&2 <<EOF

BLOCKED: VERSION is staged but docs are out of sync.

readme-lint.py output:
$lint_output

Fix: run /docs-sync to update documentation, then re-stage and commit.
  Or: POLARIS_SKIP_DOCS_LINT=1 to bypass (not recommended).
EOF
  exit 2
}

# ---------------------------------------------------------------------------
# Backlog scan (D11 + BS#20, warn-only v1)
# ---------------------------------------------------------------------------
# Scans .claude/polaris-backlog.md for open items ("- [ ] ...") and emits an
# age report. Items older than 14 days with no park tag ([next-epic],
# [platform], etc.) are highlighted as would-be-blocked in a future v2.
#
# Bypass: POLARIS_SKIP_BACKLOG_SCAN=1
# Exit:   always 0 (warn-only) — docs-lint exit codes above are preserved.

if [[ "${POLARIS_SKIP_BACKLOG_SCAN:-}" != "1" ]]; then
  backlog_file="$repo_dir/.claude/polaris-backlog.md"
  if [[ -f "$backlog_file" ]]; then
    python3 - "$backlog_file" <<'PYEOF' >&2 || true
import re
import sys
from datetime import date

path = sys.argv[1]
today = date.today()

open_re = re.compile(r'^\s*-\s*\[\s\]\s*(.+)$')
date_re = re.compile(r'\((\d{4})-(\d{2})-(\d{2})\)')
park_re = re.compile(r'\[(next-epic|platform)\]')

items = []
in_fence = False
with open(path, 'r', encoding='utf-8') as f:
    for line in f:
        # Skip fenced code blocks (format-example snippets)
        if line.lstrip().startswith('```'):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = open_re.match(line)
        if not m:
            continue
        text = m.group(1).rstrip()
        dm = date_re.search(text)
        if dm:
            try:
                created = date(int(dm.group(1)), int(dm.group(2)), int(dm.group(3)))
                age = (today - created).days
            except ValueError:
                created, age = None, None
        else:
            created, age = None, None
        parked = bool(park_re.search(text))
        items.append((text, created, age, parked))

if not items:
    sys.exit(0)

stale = [i for i in items if i[2] is not None and i[2] > 14 and not i[3]]

print("", file=sys.stderr)
print(f"Polaris backlog scan — {len(items)} open item(s):", file=sys.stderr)
for text, created, age, parked in items:
    tag = ""
    if parked:
        tag = " [parked]"
    elif age is None:
        tag = " [no date]"
    elif age > 14:
        tag = " [STALE > 14d]"
    age_str = f"{age}d" if age is not None else "?"
    # Truncate long titles for readability
    short = text if len(text) <= 100 else text[:97] + "..."
    print(f"  - ({age_str}){tag} {short}", file=sys.stderr)

if stale:
    print("", file=sys.stderr)
    print(f"  {len(stale)} item(s) > 14 days without park tag ([next-epic]/[platform]).", file=sys.stderr)
    print("  These would be blocked in a future v2 backlog gate.", file=sys.stderr)

print("", file=sys.stderr)
print("  v1 is warn-only — no items block. If persistent stale items emerge,", file=sys.stderr)
print("  consider tightening to block-mode in a future iteration.", file=sys.stderr)
print("  Bypass scan: POLARIS_SKIP_BACKLOG_SCAN=1", file=sys.stderr)
print("", file=sys.stderr)
PYEOF
  fi
fi

# Lint passed (and backlog scan is advisory) — allow commit
exit 0
