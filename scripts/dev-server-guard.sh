#!/usr/bin/env bash
# dev-server-guard.sh — PreToolUse hook
# Blocks direct dev server startup commands. Forces use of polaris-env.sh.
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Allow polaris-env.sh itself
if printf '%s' "$command" | grep -q 'polaris-env\.sh'; then
  exit 0
fi

# Block direct dev server commands
block() {
  local pattern="$1"
  local msg="$2"
  if printf '%s' "$command" | grep -qiE "$pattern"; then
    echo "BLOCKED: $msg" >&2
    echo "Use polaris-env.sh to start dev environments. It handles Docker, requires, and health checks." >&2
    echo "Command was: $command" >&2
    exit 2
  fi
}

block 'pnpm\b.*\b(dev|dev:main|dev:trans|dev:demo|hot)\b' 'Direct pnpm dev server startup — use polaris-env.sh'
block 'npm\b.*\brun[[:space:]]+(dev|start|serve)\b' 'Direct npm dev server startup — use polaris-env.sh'
block 'docker-compose\b.*\bup\b' 'Direct docker-compose up — use polaris-env.sh'
block 'docker[[:space:]]+compose\b.*\bup\b' 'Direct docker compose up — use polaris-env.sh'

exit 0
