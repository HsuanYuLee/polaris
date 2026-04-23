#!/usr/bin/env bash
# scripts/check-no-independent-cmd-chaining.sh
#
# Purpose: Block Bash commands that chain multiple commands with `&&`.
#          Rule (rules/bash-command-splitting.md § Do Not Chain Independent
#          Commands) says: split into separate Bash tool calls instead.
#
# Canary: no-independent-cmd-chaining (L1 hook primary — tool-use layer, not
#         skill-bound)
#
# Exit codes:
#   0 — PASS (no `&&` chain detected outside quotes)
#   2 — HARD_STOP / block tool call (hook context — no retry concept)
#
# Usage:
#   check-no-independent-cmd-chaining.sh --command "<bash_command_string>"
#   check-no-independent-cmd-chaining.sh "<bash_command_string>"   # positional
#
# Invoked by:
#   - .claude/hooks/no-independent-cmd-chaining.sh (PreToolUse on Bash)
#
# Quote-awareness: `&&` inside single/double-quoted arguments is allowed.
#                  Detection uses python3 `shlex.split(posix=True)` so that
#                  `git commit -m "wip: foo && bar"` passes but
#                  `git status && git diff` is blocked.

set -u

# --- Arg parsing ---
command_str=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)
      command_str="${2:-}"
      shift 2
      ;;
    --command=*)
      command_str="${1#--command=}"
      shift
      ;;
    -h|--help)
      sed -n '2,30p' "$0" >&2
      exit 0
      ;;
    *)
      if [[ -z "$command_str" ]]; then
        command_str="$1"
      fi
      shift
      ;;
  esac
done

# Empty command → nothing to check → PASS.
if [[ -z "$command_str" ]]; then
  exit 0
fi

# --- Core check via python shlex ---
# shlex.split with posix=True tokenizes the command respecting quote rules.
# Shell operators like `&&` appear as their own token at top level but are
# swallowed into a larger token when they appear inside a quoted argument.
#
# - `echo hi && cat foo`           → ['echo', 'hi', '&&', 'cat', 'foo']
# - `echo "hi && cat foo"`         → ['echo', 'hi && cat foo']
# - `git commit -m "feat: a && b"` → ['git', 'commit', '-m', 'feat: a && b']
#
# We block if any token equals "&&" exactly.
result=$(
  COMMAND_STR="$command_str" python3 - <<'PY' 2>/dev/null || echo ERROR
import os, shlex, sys
cmd = os.environ.get("COMMAND_STR", "")
try:
    tokens = shlex.split(cmd, posix=True)
except ValueError:
    # Malformed quoting (e.g., unterminated quote). Fail-open to PASS — the
    # shell would reject this command anyway.
    print("PASS")
    sys.exit(0)
for t in tokens:
    if t == "&&":
        print("BLOCK")
        sys.exit(0)
print("PASS")
PY
)

if [[ "$result" != "BLOCK" ]]; then
  exit 0
fi

cat >&2 <<EOF

[no-independent-cmd-chaining] BLOCK: Bash command chains with \`&&\`.
  Command: ${command_str}

Rule: see rules/bash-command-splitting.md § Do Not Chain Independent Commands

Use multiple Bash tool calls instead (in the same message for parallelism):

  ✅ Bash: git -C /repo log --oneline -5
     Bash: git -C /repo status
     Bash: git -C /repo diff --name-only

  ❌ Bash: git -C /repo log --oneline -5 && git -C /repo status

Pipes (\`|\`) are allowed and count as a single command.
Quoted \`&&\` inside args (e.g., \`git commit -m "a && b"\`) is also allowed.
EOF

exit 2
