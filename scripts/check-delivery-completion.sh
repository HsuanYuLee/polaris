#!/usr/bin/env bash
set -euo pipefail

# check-delivery-completion.sh — Completion-time hard gate for engineering.
# Prevents "mouth-only completion" by requiring the same delivery evidence gates
# before the agent reports task completion to the user.
#
# Usage:
#   bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]
#
# Exit: 0 = pass, 2 = block, 64 = usage error

PREFIX="[polaris completion-gate]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
TICKET=""
MODE="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_ROOT="${2:-}"
      shift 2
      ;;
    --ticket)
      TICKET="${2:-}"
      shift 2
      ;;
    --admin)
      MODE="admin"
      shift
      ;;
    -h|--help)
      echo "Usage: bash scripts/check-delivery-completion.sh [--repo <path>] [--ticket <KEY>] [--admin]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>  JIRA ticket key for verification evidence gate"
      echo "  --admin         Skip ticket-bound verification evidence gate"
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi

if [[ -z "$REPO_ROOT" ]]; then
  echo "$PREFIX unable to resolve repo root" >&2
  exit 64
fi

if [[ "$MODE" == "auto" && -z "$TICKET" ]]; then
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
  fi
fi

echo "$PREFIX checking completion gates for ${REPO_ROOT}" >&2

# Layer A: repo-level Local CI Mirror. Existing script must be treated as
# authoritative regardless of git tracking state (tracked/untracked/generated).
bash "${SCRIPT_DIR}/gates/gate-ci-local.sh" --repo "$REPO_ROOT"

# Layer B: ticket-bound verify evidence for Developer flows.
if [[ "$MODE" != "admin" && -n "$TICKET" ]]; then
  bash "${SCRIPT_DIR}/gates/gate-evidence.sh" --repo "$REPO_ROOT" --ticket "$TICKET"
fi

echo "$PREFIX ✅ completion gates satisfied." >&2
