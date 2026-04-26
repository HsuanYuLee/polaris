#!/usr/bin/env bash
# scripts/changeset-clean-inherited.sh — DP-032 Wave β D24
#
# Mechanically removes inherited changeset files left over from a parent
# task branch after rebase (e.g., when task/CURRENT-TICKET branched off
# task/PARENT-TICKET, .changeset/parent-*.md files are inherited and must
# be cleaned before opening the PR — see kkday handbook
# development-workflow.md § Changeset Convention).
#
# This script is purely git-state hygiene — it does NOT create new changesets.
# Pair with scripts/polaris-changeset.sh for the create side.
#
# Contract:
#   changeset-clean-inherited.sh --repo PATH --current-ticket KEY [--base BRANCH]
#
# Behavior:
#   1. --base inferred from `git config init.defaultBranch` or "main" if absent
#   2. Diff origin/<base> ↔ HEAD limited to .changeset/ → list changeset files
#   3. For each file: parse slug → extract ticket key (regex `[a-z]+[0-9a-z]*-[0-9]+`)
#   4. Ticket key (uppercased) != --current-ticket → `git -C <repo> rm <file>`
#   5. File without parseable ticket key → leave alone (conservative)
#   6. Print summary: "Cleaned N inherited changeset(s): a, b, c" or
#      "No inherited changesets found"
#
# Exit codes:
#   0  Success (cleanup done or no-op)
#   1  System error (git diff fails, etc.)
#   2  Usage error

set -uo pipefail

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") --repo PATH --current-ticket KEY [--base BRANCH]

Removes inherited .changeset/*.md files (from a parent task branch's PR-merge
inheritance) that don't match --current-ticket. Conservative: files with no
parseable ticket key in slug are left alone.

Exit:  0 = success / no-op, 1 = system error, 2 = usage error.
EOF
}

# --- Args -------------------------------------------------------------------
REPO=""
CURRENT_TICKET=""
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)            REPO="${2:-}";           shift 2 ;;
    --current-ticket)  CURRENT_TICKET="${2:-}"; shift 2 ;;
    --base)            BASE="${2:-}";           shift 2 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "changeset-clean-inherited: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "changeset-clean-inherited: --repo is required" >&2
  usage; exit 2
fi
if [[ -z "$CURRENT_TICKET" ]]; then
  echo "changeset-clean-inherited: --current-ticket is required" >&2
  usage; exit 2
fi
if [[ ! -d "$REPO" ]]; then
  echo "changeset-clean-inherited: --repo path not a directory: $REPO" >&2
  exit 1
fi

# --- Resolve base branch ----------------------------------------------------
if [[ -z "$BASE" ]]; then
  BASE="$(git -C "$REPO" config --get init.defaultBranch 2>/dev/null || true)"
fi
if [[ -z "$BASE" ]]; then
  BASE="main"
fi

# --- No-op if .changeset/ doesn't exist ------------------------------------
if [[ ! -d "$REPO/.changeset" ]]; then
  echo "changeset-clean-inherited: .changeset/ not present in $REPO — no-op" >&2
  exit 0
fi

# --- Diff base...HEAD limited to .changeset/ ------------------------------
# Try origin/<BASE> first (covers fetched remote branches); fall back to local
# <BASE> if origin reference is unavailable (e.g., in selftest sandboxes).
diff_base="origin/${BASE}"
if ! git -C "$REPO" rev-parse --verify --quiet "$diff_base" >/dev/null 2>&1; then
  diff_base="$BASE"
  if ! git -C "$REPO" rev-parse --verify --quiet "$diff_base" >/dev/null 2>&1; then
    echo "changeset-clean-inherited: neither origin/$BASE nor $BASE resolvable in $REPO" >&2
    exit 1
  fi
fi

CHANGED_FILES="$(git -C "$REPO" diff "$diff_base" --name-only -- '.changeset/' 2>/dev/null || true)"

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No inherited changesets found"
  exit 0
fi

# --- Iterate, parse slug, remove if ticket mismatch ------------------------
CURRENT_TICKET_UPPER="$(printf '%s' "$CURRENT_TICKET" | tr '[:lower:]' '[:upper:]')"
removed=()

# Use a heredoc to avoid pipe-subshell array scoping issues in bash 3.2.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # Skip removed-side diff entries that no longer exist
  [[ ! -f "$REPO/$f" ]] && continue

  base_name="$(basename "$f" .md)"
  # Extract ticket prefix: e.g., kb2cw-3788-foo → KB2CW-3788
  # Regex: ^([a-z]+[0-9a-z]*)-([0-9]+)-
  if [[ "$base_name" =~ ^([a-z]+[0-9a-z]*)-([0-9]+)(-|$) ]]; then
    proj="${BASH_REMATCH[1]}"
    num="${BASH_REMATCH[2]}"
    ticket_key="$(printf '%s' "$proj" | tr '[:lower:]' '[:upper:]')-${num}"
  else
    # No parseable ticket → leave alone (conservative)
    continue
  fi

  if [[ "$ticket_key" != "$CURRENT_TICKET_UPPER" ]]; then
    if git -C "$REPO" rm -q -- "$f" >/dev/null 2>&1; then
      removed+=("$f")
    else
      # If `git rm` fails (e.g., file never tracked), fall back to plain rm.
      rm -f "$REPO/$f" 2>/dev/null || true
      removed+=("$f")
    fi
  fi
done <<EOF
$CHANGED_FILES
EOF

if [[ ${#removed[@]} -eq 0 ]]; then
  echo "No inherited changesets found"
  exit 0
fi

# Comma-join for summary
joined=""
for x in "${removed[@]}"; do
  if [[ -z "$joined" ]]; then
    joined="$x"
  else
    joined="$joined, $x"
  fi
done

echo "Cleaned ${#removed[@]} inherited changeset(s): $joined"
exit 0
