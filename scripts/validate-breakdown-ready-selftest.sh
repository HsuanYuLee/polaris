#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-breakdown-ready.sh"

case "${1:-}" in
  -h|--help)
    echo "usage: validate-breakdown-ready-selftest.sh"
    echo "Runs the validate-breakdown-ready.sh self-test fixture."
    exit 0
    ;;
esac

if [[ ! -x "$VALIDATOR" ]]; then
  chmod +x "$VALIDATOR" 2>/dev/null || true
fi

bash "$VALIDATOR" --self-test
