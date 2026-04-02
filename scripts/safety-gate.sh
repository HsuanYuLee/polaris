#!/usr/bin/env bash
# safety-gate.sh — PreToolUse hook for Polaris sub-agents
# Reads Claude Code hook JSON from stdin, blocks dangerous operations.
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# --- Edit / Write: enforce directory allowlist ---
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  if [[ -n "${POLARIS_SAFE_DIRS:-}" ]]; then
    file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

    if [[ -n "$file_path" ]]; then
      allowed=false
      IFS=':' read -ra dirs <<< "$POLARIS_SAFE_DIRS"
      for dir in "${dirs[@]}"; do
        # Normalize: strip trailing slash
        dir="${dir%/}"
        if [[ "$file_path" == "$dir" || "$file_path" == "$dir/"* ]]; then
          allowed=true
          break
        fi
      done

      if [[ "$allowed" == "false" ]]; then
        echo "[safety-gate] BLOCKED $tool_name: '$file_path' is outside allowed directories." >&2
        echo "Allowed: $POLARIS_SAFE_DIRS" >&2
        exit 2
      fi
    fi
  fi
  exit 0
fi

# --- Bash: block dangerous command patterns ---
if [[ "$tool_name" == "Bash" ]]; then
  command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

  check() {
    local pattern="$1"
    local reason="$2"
    if printf '%s' "$command" | grep -qiE "$pattern"; then
      echo "[safety-gate] BLOCKED Bash: $reason" >&2
      echo "Command: $command" >&2
      exit 2
    fi
  }

  check 'rm\s+-rf\s+(/|~|/\*)' 'recursive delete of root or home'
  check 'git\s+push\s+.*--force\s+.*(main|master)|git\s+push\s+.*-f\s+.*(main|master)' 'force-push to main/master'
  check 'DROP\s+(TABLE|DATABASE)' 'destructive SQL operation'
  check 'chmod\s+777' 'overly permissive chmod 777'
  check '>\s*/dev/sd[a-z]' 'write to block device'

  exit 0
fi

# All other tools: allow
exit 0
