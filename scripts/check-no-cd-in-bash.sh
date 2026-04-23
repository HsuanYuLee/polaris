#!/usr/bin/env bash
# scripts/check-no-cd-in-bash.sh
#
# Purpose: Detect `cd` usage in a bash command string and block it. The rule
#          (see rules/bash-command-splitting.md) requires tool path
#          parameters (git -C, pnpm -C, gh --repo) or absolute paths instead.
#
# Canary: no-cd-in-bash (L1 hook primary — tool-use layer, not skill-bound)
#
# Exit codes:
#   0 — PASS (no `cd` command detected)
#   2 — HARD_STOP / block tool call (hook context)
#
# Usage:
#   check-no-cd-in-bash.sh --command "<bash_command_string>"
#   check-no-cd-in-bash.sh "<bash_command_string>"   # positional fallback
#
# Invoked by:
#   - .claude/hooks/no-cd-in-bash.sh (PreToolUse on Bash; passes the
#     tool_input.command extracted from the hook stdin JSON)
#
# Why exit 2 (not 1): this is a L1 hook wrapper. In hook context, exit 2
# blocks the Bash tool call outright; there is no retry concept. The check
# is purely mechanical (regex) — no amount of "retry" would change its
# verdict on the same command string.

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
      # Positional fallback: first non-flag arg is the command
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

# --- Core check ---
# We want to detect `cd ` appearing as a *command token*, not inside a
# quoted string or as part of another word (e.g., grep "cd " or a path
# like `/opt/local/cd-reader`). Practical heuristic:
#
#   - At the start of the command (optionally after leading whitespace):
#         ^\s*cd\s
#   - Or after a command separator:
#         (;|&&|\|\||\||`|\$\(|\() followed by optional whitespace then `cd\s`
#
# We intentionally match `|` too: `foo | cd /tmp && bar` is pathological but
# still a cd-chain. Pure pipes with cd only in payload (like `grep "cd "`)
# fail the regex because the `cd` there is inside quotes; this script does
# not parse quoting — we accept a small false-positive risk for a simple
# regex. If false positives appear in practice, the hook can be narrowed.
#
# Edge cases intentionally allowed (exit 0):
#   - `cd` appearing only inside a quoted argument to grep/sed/awk (we can't
#     reliably detect quoting in pure regex; we accept the false positive
#     risk here — the user can emergency-bypass if needed).

# Test 1: starts with `cd `
if printf '%s' "$command_str" | grep -qE '^[[:space:]]*cd[[:space:]]'; then
  match_reason="command starts with 'cd '"
# Test 2: `cd ` after a shell command separator (&&, ||, ;, |, backtick,
# $(, or open paren)
elif printf '%s' "$command_str" | grep -qE '(&&|\|\||;|\||` |\$\(|\()[[:space:]]*cd[[:space:]]'; then
  match_reason="'cd' found after shell command separator"
else
  exit 0
fi

cat >&2 <<EOF

[no-cd-in-bash] BLOCK: Bash command uses \`cd\` — ${match_reason}.
  Command: ${command_str}

Rule: see rules/bash-command-splitting.md

Use tool path parameters or absolute paths instead:
  git -C /repo status        (instead of: cd /repo && git status)
  pnpm -C /repo test         (instead of: cd /repo && pnpm test)
  gh pr list --repo org/r    (instead of: cd /repo && gh pr list)
  node /repo/script.js       (instead of: cd /repo && node script.js)
  bash /repo/script.sh       (instead of: cd /repo && bash script.sh)

Why: cd-chained commands are compound patterns hard to match in
settings.json permissions.allow globs; atomic commands match simple
glob patterns (git *, pnpm *) and avoid permission prompts.
EOF

exit 2
