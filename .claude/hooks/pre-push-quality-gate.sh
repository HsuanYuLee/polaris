#!/bin/bash
# Pre-push Quality Gate
# Intercepts git push and verifies that quality checks have passed
#
# Mechanism: quality-check-flow writes a marker file on pass; this hook checks the marker
# Marker: /tmp/.quality-gate-passed-{branch}
#
# This hook only fires on `git push*` commands via the `if` field in settings.json.
# Environment variables (provided by Claude Code hooks):
#   CLAUDE_TOOL_INPUT — JSON input of the Bash tool call

# 取得專案目錄（從 CLAUDE_PROJECT_DIR 或 fallback）
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 從 tool input 提取實際操作的 repo（支援 git -C /path push）
REPO_PATH=$(echo "$CLAUDE_TOOL_INPUT" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //')
if [ -n "$REPO_PATH" ]; then
  PROJECT_DIR="$REPO_PATH"
fi

# 取得 branch 名稱
BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# 主要 branch 不攔截（通常不會直接 push）
case "$BRANCH" in
  main|master|develop) exit 0 ;;
esac

# 檢查 marker file
MARKER="/tmp/.quality-gate-passed-${BRANCH}"

if [ -f "$MARKER" ]; then
  # Marker 存在，檢查是否過期（超過 24 小時視為過期）
  if [ "$(uname)" = "Darwin" ]; then
    MARKER_AGE=$(( $(date +%s) - $(stat -f %m "$MARKER") ))
  else
    MARKER_AGE=$(( $(date +%s) - $(stat -c %Y "$MARKER") ))
  fi

  if [ "$MARKER_AGE" -lt 86400 ]; then
    exit 0  # 有效 marker，放行
  else
    rm -f "$MARKER"  # 過期，刪除
  fi
fi

# No valid marker — check if this is the user's first push ever (no markers exist)
FIRST_PUSH=true
for existing_marker in /tmp/.quality-gate-passed-*; do
  [ -e "$existing_marker" ] && FIRST_PUSH=false && break
done

if [ "$FIRST_PUSH" = true ]; then
  cat >&2 <<'EOF'
ℹ️  First push detected — quality gate is skipping this time.

In future pushes, run "quality check" (or 「品質檢查」) before pushing.
The quality gate ensures lint, tests, and coverage pass before code is pushed.
EOF
  exit 0
fi

# Not first push — block and explain
cat >&2 <<'EOF'
⚠️ Quality gate not passed — run quality-check-flow first

Push requires passing quality checks (lint + test + coverage).
After the check passes, a marker file is created and push will proceed.

Tip: say "quality check" or "品質檢查" to trigger it.
EOF
exit 2
