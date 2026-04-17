#!/usr/bin/env bash
# gate-hook-adapter.sh
# Execute a Claude-style gate script by feeding synthetic hook JSON.
#
# Usage:
#   gate-hook-adapter.sh <gate_script> <command_string>
#
# Env:
#   GATE_PROJECT_DIR=<path>  Optional project dir; defaults to git root or cwd.
#
# Exit code follows gate script exit code (0 allow, 2 block).

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <gate_script> <command_string>" >&2
  exit 1
fi

gate_script="$1"
shift
command_string="$*"

if [[ ! -f "$gate_script" ]]; then
  echo "Gate script not found: $gate_script" >&2
  exit 1
fi

if [[ -n "${GATE_PROJECT_DIR:-}" ]]; then
  project_dir="$GATE_PROJECT_DIR"
elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  project_dir="$git_root"
else
  project_dir="$(pwd)"
fi

payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command_string")"

printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$project_dir" bash "$gate_script"
