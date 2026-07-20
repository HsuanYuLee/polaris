#!/usr/bin/env bash
# Purpose: validate script-layer semantic coverage and owner terminality queries.
# Inputs: --ledger PATH [--owner DP-NNN-Tn --require-terminal]
# Outputs: PASS or POLARIS_SCRIPT_LAYER_COVERAGE diagnostics.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER=""
OWNER=""
REQUIRE_TERMINAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --require-terminal) REQUIRE_TERMINAL=1; shift ;;
    -h|--help) echo 'usage: scripts/validate-script-layer-migration-coverage.sh --ledger PATH [--owner OWNER --require-terminal]'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$LEDGER" ]] || { echo '--ledger is required' >&2; exit 2; }
args=(--ledger "$LEDGER")
[[ -z "$OWNER" ]] || args+=(--owner "$OWNER")
[[ "$REQUIRE_TERMINAL" -eq 0 ]] || args+=(--require-terminal)
python3 "$ROOT/scripts/lib/validate_script_layer_migration_coverage.py" "${args[@]}"
