#!/usr/bin/env bash
# ci-contract-discover.sh — Discover repo CI strategy and normalize into a local contract
#
# Usage:
#   scripts/ci-contract-discover.sh --repo <path>
#
# Output:
#   JSON contract to stdout

set -euo pipefail

REPO_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: ci-contract-discover.sh --repo <path>" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ci_ci_contract_discover_1.py" "$REPO_DIR"
