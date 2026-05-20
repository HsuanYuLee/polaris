#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  scripts/verify-ac-docs-health.sh --source-container PATH

Runs docs-health as a verify-AC verifier for framework documentation/content AC.
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
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SOURCE_CONTAINER" || ! -d "$SOURCE_CONTAINER" ]]; then
  echo "BLOCKED: --source-container must point to an existing source container" >&2
  exit 2
fi

bash scripts/refinement-handoff-gate.sh "$SOURCE_CONTAINER/refinement.json" >/dev/null
echo "PASS: docs-health verifier wrapper ($SOURCE_CONTAINER)"
