#!/usr/bin/env bash
set -euo pipefail

# polaris-pr-create.sh — PR creation wrapper with pre-flight gates (DP-032 Wave δ)
# Replaces bare `gh pr create` in Polaris engineering flows.
# Runs base-check + evidence + ci-local + PR metadata gates before PR creation.
#
# Usage:
#   bash scripts/polaris-pr-create.sh [--repo <path>] [--skip-gates] -- <gh pr create args...>
#   bash scripts/polaris-pr-create.sh --base develop --title "feat: X" --body "..."
#
# All unrecognized flags are passed through to `gh pr create`.
# Gates that fail with exit 2 abort PR creation.
#
# Bypass: --skip-gates (or POLARIS_SKIP_PR_GATES=1)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATES_DIR="$SCRIPT_DIR/gates"

PREFIX="[polaris-pr-create]"
REPO_PATH=""
SKIP_GATES="${POLARIS_SKIP_PR_GATES:-0}"
GH_ARGS=()

usage() {
  cat <<EOF
Usage: polaris-pr-create.sh [--repo <path>] [--skip-gates] [--] <gh pr create args...>

Wrapper for 'gh pr create' that runs pre-flight gates before PR creation.

Options:
  --repo <path>     Repository path (default: cwd)
  --skip-gates      Skip all gates (emergency bypass)
  -h, --help        Show this help

All other arguments are passed verbatim to 'gh pr create'.
EOF
  exit 0
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage ;;
    --repo)          REPO_PATH="$2"; shift 2 ;;
    --repo=*)        REPO_PATH="${1#--repo=}"; shift ;;
    --skip-gates)    SKIP_GATES=1; shift ;;
    --)              shift; GH_ARGS+=("$@"); break ;;
    *)               GH_ARGS+=("$1"); shift ;;
  esac
done

REPO_PATH="${REPO_PATH:-$(pwd)}"

# --- Extract --base from GH_ARGS ---
BASE_BRANCH=""
PR_TITLE=""
PR_BODY=""
PR_BODY_FILE=""
PR_BODY_SOURCE=""
for (( i=0; i<${#GH_ARGS[@]}; i++ )); do
  case "${GH_ARGS[$i]}" in
    --base=*) BASE_BRANCH="${GH_ARGS[$i]#--base=}" ;;
    --title=*) PR_TITLE="${GH_ARGS[$i]#--title=}" ;;
    --body=*) PR_BODY="${GH_ARGS[$i]#--body=}"; PR_BODY_SOURCE="body" ;;
    --body-file=*) PR_BODY_FILE="${GH_ARGS[$i]#--body-file=}"; PR_BODY_SOURCE="file" ;;
    --base)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        BASE_BRANCH="${GH_ARGS[$(( i + 1 ))]}"
      fi
      ;;
    --title)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_TITLE="${GH_ARGS[$(( i + 1 ))]}"
      fi
      ;;
    --body)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_BODY="${GH_ARGS[$(( i + 1 ))]}"
        PR_BODY_SOURCE="body"
      fi
      ;;
    --body-file)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_BODY_FILE="${GH_ARGS[$(( i + 1 ))]}"
        PR_BODY_SOURCE="file"
      fi
      ;;
  esac
done

# --- Detect non-ticket branch (skip evidence gate) ---
CURRENT_BRANCH="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
IS_TICKET_BRANCH=1
[[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" =~ ^(main|master|develop|release/) ]] && IS_TICKET_BRANCH=0

# --- Gate runner ---
run_gate() {
  local name="$1"; shift
  local script="$GATES_DIR/$name"

  if [[ ! -x "$script" ]]; then
    echo "$PREFIX ⊘ $name not found, skipping"
    return 0
  fi

  if "$script" "$@"; then
    echo "$PREFIX ✓ ${name%.sh} passed"
  else
    local rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "$PREFIX ✗ ${name%.sh} FAILED (exit 2)"
      echo "$PREFIX PR creation aborted. Fix the issue above and retry."
      exit 2
    else
      echo "$PREFIX ⚠ ${name%.sh} warning (exit $rc), continuing"
    fi
  fi
}

# --- Skip gates ---
if [[ "$SKIP_GATES" == "1" ]]; then
  echo "$PREFIX ⚠ --skip-gates: all gates bypassed"
  exec gh pr create "${GH_ARGS[@]}"
fi

# --- Run gates ---
echo "$PREFIX Running pre-flight gates..."

# Gate 1: base-check (only if --base provided)
if [[ -n "$BASE_BRANCH" ]]; then
  run_gate gate-base-check.sh --repo "$REPO_PATH" --base "$BASE_BRANCH"
fi

# Gate 2: evidence (skip for non-ticket branches)
if [[ "$IS_TICKET_BRANCH" -eq 1 ]]; then
  run_gate gate-evidence.sh --repo "$REPO_PATH"
fi

# Gate 3: ci-local (always)
run_gate gate-ci-local.sh --repo "$REPO_PATH"

# Gate 4: local-only docs-manager specs must not be tracked.
run_gate gate-no-tracked-specs.sh --repo "$REPO_PATH"

# Gate 5: Developer PR title (managed task branches only)
if [[ "$IS_TICKET_BRANCH" -eq 1 && -n "$PR_TITLE" ]]; then
  run_gate gate-pr-title.sh --repo "$REPO_PATH" --title "$PR_TITLE"
fi

# Gate 6: PR body preserves repo pull request template headings.
if [[ "$PR_BODY_SOURCE" == "file" ]]; then
  run_gate gate-pr-body-template.sh --repo "$REPO_PATH" --body-file "$PR_BODY_FILE"
elif [[ "$PR_BODY_SOURCE" == "body" ]]; then
  run_gate gate-pr-body-template.sh --repo "$REPO_PATH" --body "$PR_BODY"
fi

# Gate 7: PR title/body language policy via gate-pr-language.sh
# (central wrapper around validate-language-policy.sh).
if [[ -n "$PR_TITLE" || "$PR_BODY_SOURCE" == "file" || "$PR_BODY_SOURCE" == "body" ]]; then
  if [[ "$PR_BODY_SOURCE" == "file" ]]; then
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE" --body-file "$PR_BODY_FILE"
  elif [[ "$PR_BODY_SOURCE" == "body" ]]; then
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE" --body "$PR_BODY"
  else
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE"
  fi
fi

# Gate 8: task changeset (managed task branches in changeset repos)
if [[ "$IS_TICKET_BRANCH" -eq 1 ]]; then
  run_gate gate-changeset.sh --repo "$REPO_PATH"
fi

echo "$PREFIX All gates passed — creating PR..."
exec gh pr create "${GH_ARGS[@]}"
