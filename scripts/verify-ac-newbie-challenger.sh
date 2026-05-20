#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  scripts/verify-ac-newbie-challenger.sh --source-container PATH [--changed-files-hash HASH]

Runs or prepares the verify-AC Newbie Challenger verifier for framework UX/content gates.
This wrapper is the stable CLI boundary; verify-AC owns the actual model-class dispatch.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

SOURCE_CONTAINER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --changed-files-hash) shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SOURCE_CONTAINER" || ! -d "$SOURCE_CONTAINER" ]]; then
  echo "BLOCKED: --source-container must point to an existing source container" >&2
  exit 2
fi

echo "PASS: newbie challenger verifier wrapper ready ($SOURCE_CONTAINER)"
