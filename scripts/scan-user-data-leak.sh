#!/usr/bin/env bash
# Scan .claude/rules/ for hardcoded user-specific data that would leak to other framework users.
# Reads user identity from workspace-config.yaml and checks for those values in shared files.
#
# Usage: scan-user-data-leak.sh [workspace_root]
# Exit: 0 = clean, 1 = leaks found

set -euo pipefail

WORKSPACE_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIG="$WORKSPACE_ROOT/workspace-config.yaml"
RULES_DIR="$WORKSPACE_ROOT/.claude/rules"
FOUND=0

# --- Extract user fields from config ---

if [ ! -f "$CONFIG" ]; then
  echo "⚠ workspace-config.yaml not found — skipping user data leak scan"
  exit 0
fi

GITHUB_USER=$(python3 -c "
import yaml, sys
try:
    cfg = yaml.safe_load(open('$CONFIG'))
    u = cfg.get('user', {}).get('github_username', '')
    if u: print(u)
except: pass
" 2>/dev/null)

# --- Scan rules/ for leaked values ---

scan_pattern() {
  local label="$1" pattern="$2"
  [ -z "$pattern" ] && return

  local matches
  matches=$(grep -rn --include='*.md' "$pattern" "$RULES_DIR" 2>/dev/null || true)

  if [ -n "$matches" ]; then
    echo "🔴 $label found in shared rules:"
    echo "$matches" | while IFS= read -r line; do
      echo "   $line"
    done
    FOUND=1
  fi
}

echo "Scanning .claude/rules/ for user-specific data leaks..."
echo ""

# Check each known user field
scan_pattern "GitHub username ($GITHUB_USER)" "$GITHUB_USER"

# Generic PII patterns (email-like strings that aren't example.com)
EMAIL_MATCHES=$(grep -rnoE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$RULES_DIR" \
  --include='*.md' 2>/dev/null \
  | grep -v '@example\.com' \
  | grep -v '@anthropic\.com' \
  | grep -v '@kkday\.com' || true)

# Filter: @kkday.com in handbook is company-level (org domain), not user-specific.
# But a specific person's email (john@kkday.com) IS user-specific.
# For now, flag all non-generic emails for human review.

if [ -n "$EMAIL_MATCHES" ]; then
  echo "🟡 Email addresses found in shared rules (review for user-specific data):"
  echo "$EMAIL_MATCHES" | while IFS= read -r line; do
    echo "   $line"
  done
  echo ""
fi

if [ "$FOUND" -eq 0 ]; then
  echo "✅ No user-specific data leaks found"
else
  echo ""
  echo "Fix: move user-specific values to workspace-config.yaml user: section"
  echo "See: DP-007 (specs/design-plans/DP-007-user-config-isolation/)"
fi

exit "$FOUND"
