#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-resume.sh --ledger /abs/ledger.json --resume-artifact PATH [--source-id DP-NNN]

Validates auto-pass session_handoff resume artifact against its ledger pause.
USAGE
  exit 2
}

LEDGER=""
RESUME_ARTIFACT=""
SOURCE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --resume-artifact) RESUME_ARTIFACT="${2:-}"; shift 2 ;;
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$LEDGER" && -n "$RESUME_ARTIFACT" ]] || usage

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_validate_auto_pass_resume_1.py" "$LEDGER" "$RESUME_ARTIFACT" "$SOURCE_ID"
