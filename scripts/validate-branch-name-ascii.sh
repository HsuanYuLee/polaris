#!/usr/bin/env bash
# Purpose: DP-307 D3 branch-name ASCII gate — fail-closed when a branch name
#   contains any non-ASCII byte (byte >= 0x80). The judgment is byte-level
#   (LC_ALL=C); it deliberately does NOT delegate to `git check-ref-format`,
#   which accepts UTF-8/CJK ref names and therefore cannot serve as the gate
#   (AC-NEG5). No extra character whitelist is applied: legal ASCII branch
#   conventions (`task/` slash, `bundle-DP-NNN-vX.Y.Z` dot, hyphen,
#   underscore) all pass untouched (AC-NEG1).
# Inputs:  $1 = branch name, OR an existing task.md path (auto-detected), OR
#          --task-md <path> to read the Operational Context "Task branch"
#          row explicitly.
# Outputs: stdout PASS line on success; stderr structured marker on violation:
#            POLARIS_BRANCH_NAME_NON_ASCII:{branch}   non-ASCII byte found
#            POLARIS_BRANCH_NAME_FIELD_MISSING:{path} task.md has no usable
#                                                     "Task branch" field
# Exit code: 0 = PASS (pure ASCII), 2 = contract violation / unusable input.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-branch-name-ascii.sh <branch-name>
       validate-branch-name-ascii.sh <task.md>
       validate-branch-name-ascii.sh --task-md <task.md>

Fail-closed branch-name ASCII gate (DP-307 D3): exits 2 with
POLARIS_BRANCH_NAME_NON_ASCII:{branch} when the branch name contains any
non-ASCII byte. ASCII-only names — including `task/` slashes,
`bundle-DP-NNN-vX.Y.Z` dots, hyphens, underscores — exit 0.
EOF
}

# Description: extract the "Task branch" value from a task.md Operational
#   Context table row (`| Task branch | <value> |`), stripping backticks.
# Args:        $1 = task.md absolute or relative path
# Side effects: none (read-only); prints the value (possibly empty) to stdout
task_branch_from_task_md() {
  local task_md="$1" value
  value="$(LC_ALL=C sed -n -E 's/^\|[[:space:]]*Task branch[[:space:]]*\|[[:space:]]*(.*[^[:space:]])[[:space:]]*\|[[:space:]]*$/\1/p' "$task_md" | head -n 1)"
  value="${value#\`}"
  value="${value%\`}"
  printf '%s' "$value"
}

TASK_MD=""
BRANCH=""

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --task-md)
    TASK_MD="${2:-}"
    if [[ -z "$TASK_MD" ]]; then
      usage
      exit 2
    fi
    ;;
  "")
    usage
    exit 2
    ;;
  *)
    if [[ -f "$1" && "$1" == *.md ]]; then
      TASK_MD="$1"
    else
      BRANCH="$1"
    fi
    ;;
esac

if [[ -n "$TASK_MD" ]]; then
  if [[ ! -f "$TASK_MD" ]]; then
    echo "validate-branch-name-ascii: task.md not found: $TASK_MD" >&2
    echo "POLARIS_BRANCH_NAME_FIELD_MISSING:$TASK_MD" >&2
    exit 2
  fi
  BRANCH="$(task_branch_from_task_md "$TASK_MD")"
  case "$(printf '%s' "$BRANCH" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in
    ""|"n/a"|"na"|"-"|"--"|"none")
      # Fail-closed: certifying an absent branch name would be contract misuse.
      echo "validate-branch-name-ascii: no usable 'Task branch' field in $TASK_MD" >&2
      echo "POLARIS_BRANCH_NAME_FIELD_MISSING:$TASK_MD" >&2
      exit 2
      ;;
  esac
fi

# Core judgment (D3): delete every ASCII byte (0x00-0x7F) under the C locale;
# any remaining byte is >= 0x80, i.e. non-ASCII. This is the sole gate — no
# git check-ref-format delegation, no extra character whitelist.
non_ascii_bytes="$(printf '%s' "$BRANCH" | LC_ALL=C tr -d '\000-\177')"
if [[ -n "$non_ascii_bytes" ]]; then
  echo "validate-branch-name-ascii: branch name contains non-ASCII bytes: $BRANCH" >&2
  echo "POLARIS_BRANCH_NAME_NON_ASCII:$BRANCH" >&2
  exit 2
fi

echo "validate-branch-name-ascii PASS - $BRANCH"
