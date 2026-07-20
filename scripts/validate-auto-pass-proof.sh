#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCER_MAP="$REPO_ROOT/scripts/lib/evidence-producers.json"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-auto-pass-proof.sh <marker.json> [marker.json ...]
  scripts/validate-auto-pass-proof.sh --producer-map
USAGE
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_validate_auto_pass_proof_1.py" "$PRODUCER_MAP" "$@"
