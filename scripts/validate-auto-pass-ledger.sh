#!/usr/bin/env bash
# Purpose: Validate an auto-pass source-scoped ledger.json against the contract
#          (schema_version, source/refinement-hash, consent enum, terminal enum,
#          loop_counters cap incl. engineering_revision_rounds, pause/friction shape).
# Inputs:  ledger path (absolute) + optional --source-container/--source-id/--task-write-at.
# Outputs: stdout PASS line; exit 0 PASS, 1 validation failure, 2 usage error.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-ledger.sh /absolute/path/to/ledger.json
    [--source-container /absolute/path/to/DP-NNN-container]
    [--source-id DP-NNN]
    [--task-write-at ISO8601]
    [--print-refinement-hash]
USAGE
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

LEDGER=""
SOURCE_CONTAINER=""
SOURCE_ID=""
TASK_WRITE_AT=""
PRINT_HASH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-container)
      SOURCE_CONTAINER="${2:-}"
      shift 2
      ;;
    --source-id)
      SOURCE_ID="${2:-}"
      shift 2
      ;;
    --task-write-at)
      TASK_WRITE_AT="${2:-}"
      shift 2
      ;;
    --print-refinement-hash)
      PRINT_HASH=1
      shift
      ;;
    --help|-h)
      usage
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$LEDGER" ]]; then
        echo "ERROR: unexpected argument: $1" >&2
        usage
      fi
      LEDGER="$1"
      shift
      ;;
  esac
done

if [[ -z "$LEDGER" ]]; then
  usage
fi

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_validate_auto_pass_ledger_1.py" "$LEDGER" "$SOURCE_CONTAINER" "$SOURCE_ID" "$TASK_WRITE_AT" "$PRINT_HASH" "$SCRIPT_ROOT"
