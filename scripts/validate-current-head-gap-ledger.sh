#!/usr/bin/env bash
# Purpose: validate current-head gap dispositions and same-source authority.
# Inputs: --ledger PATH --repo PATH --source-container PATH [--source-id ID] [--require-terminal] [--json]
# Outputs: PASS/diagnostics or stable JSON; exits 2 on invalid or stale evidence.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER=""
REPO="$ROOT"
SOURCE_ID=""
SOURCE_CONTAINER=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --require-terminal|--json) ARGS+=("$1"); shift ;;
    -h|--help)
      echo 'usage: scripts/validate-current-head-gap-ledger.sh --ledger PATH [--repo PATH] --source-container PATH [--source-id ID] [--require-terminal] [--json]'
      exit 0
      ;;
    *) echo "validate-current-head-gap-ledger: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$LEDGER" ]] || { echo 'validate-current-head-gap-ledger: --ledger is required' >&2; exit 2; }
[[ -d "$REPO" ]] || { echo "validate-current-head-gap-ledger: repo not found: $REPO" >&2; exit 2; }
[[ -d "$SOURCE_CONTAINER" ]] || { echo "validate-current-head-gap-ledger: source container not found: $SOURCE_CONTAINER" >&2; exit 2; }
CMD=(python3 "$ROOT/scripts/lib/validate_current_head_gap_ledger.py" --ledger "$LEDGER" --repo "$REPO" --source-container "$SOURCE_CONTAINER")
[[ -z "$SOURCE_ID" ]] || CMD+=(--source-id "$SOURCE_ID")
if [[ ${#ARGS[@]} -gt 0 ]]; then
  CMD+=("${ARGS[@]}")
fi
exec "${CMD[@]}"
