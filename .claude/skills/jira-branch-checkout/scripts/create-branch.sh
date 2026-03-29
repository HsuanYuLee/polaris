#!/usr/bin/env bash
set -euo pipefail

# jira-branch-checkout / create-branch.sh
#
# Deterministic branch creation from JIRA ticket info.
# Designed to be called by Claude Code skills — all git logic lives here,
# no AI decision-making inside this script.
#
# Usage:
#   create-branch.sh <TICKET> <DESCRIPTION> [BASE_BRANCH]
#
# Arguments:
#   TICKET       JIRA ticket key, e.g. TASK-123
#   DESCRIPTION  Short kebab-case description, e.g. remove-elapsed-time-log
#   BASE_BRANCH  Base branch to checkout from (default: develop)
#
# Examples:
#   create-branch.sh TASK-123 remove-elapsed-time-log
#   create-branch.sh TASK-123 fix-currency-format master
#   create-branch.sh VM-1186 jp-dx-main rc

# ── Helpers ──────────────────────────────────────────────────────────────

die()  { echo "✗ $*" >&2; exit 1; }
info() { echo "ℹ $*"; }
ok()   { echo "✓ $*"; }

# Sanitise a free-form string into a valid kebab-case git ref fragment.
# Strips non-ASCII, lowercases, collapses separators, trims to 50 chars.
sanitise_kebab() {
  echo "$1" \
    | sed 's/[^a-zA-Z0-9 _-]//g' \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' _' '-' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-//; s/-$//' \
    | cut -c1-50 \
    | sed 's/-$//'
}

# ── Args ─────────────────────────────────────────────────────────────────

TICKET="${1:-}"
DESC="${2:-}"
BASE_BRANCH="${3:-develop}"

[[ -n "$TICKET" ]]  || die "Missing TICKET.  Usage: create-branch.sh <TICKET> <DESCRIPTION> [BASE_BRANCH]"
[[ -n "$DESC" ]]    || die "Missing DESCRIPTION.  Usage: create-branch.sh <TICKET> <DESCRIPTION> [BASE_BRANCH]"

# Validate ticket format (PROJECT-NUMBER)
[[ "$TICKET" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] || die "Invalid ticket format: $TICKET (expected e.g. TASK-123)"

# Sanitise description
DESC=$(sanitise_kebab "$DESC")
[[ -n "$DESC" ]] || die "Description resolved to empty after sanitisation."

BRANCH="task/${TICKET}-${DESC}"

# ── Pre-flight checks ───────────────────────────────────────────────────

CURRENT=$(git branch --show-current 2>/dev/null || echo "")

# Already on the target branch?
if [[ "$CURRENT" == "task/${TICKET}-"* ]]; then
  ok "Already on branch for ${TICKET}: ${CURRENT}"
  exit 0
fi

# Target branch already exists locally?
if git show-ref --verify --quiet "refs/heads/${BRANCH}" 2>/dev/null; then
  info "Branch ${BRANCH} already exists locally. Switching…"
  git checkout "$BRANCH"
  ok "Switched to existing branch: ${BRANCH}"
  exit 0
fi

# ── Create branch ───────────────────────────────────────────────────────

info "Fetching origin…"
git fetch origin

# Verify base branch exists on remote
if ! git show-ref --verify --quiet "refs/remotes/origin/${BASE_BRANCH}" 2>/dev/null; then
  die "Remote branch origin/${BASE_BRANCH} does not exist. Available remotes:"
  git branch -r | grep "origin/" | head -10
fi

info "Creating branch: ${BRANCH} (from origin/${BASE_BRANCH})"
git checkout -b "$BRANCH" "origin/${BASE_BRANCH}"

echo ""
ok "Created and switched to: ${BRANCH}"
