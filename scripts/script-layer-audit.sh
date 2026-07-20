#!/usr/bin/env bash
# Purpose: enumerate the governed production/test script union into a semantic ledger.
# Inputs: --workspace PATH --output PATH
# Outputs: deterministic JSON governance ledger; exit 0 on success.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) echo 'usage: scripts/script-layer-audit.sh --workspace PATH --output PATH'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$WORKSPACE" && -n "$OUTPUT" ]] || { echo '--workspace and --output are required' >&2; exit 2; }
python3 "$ROOT/scripts/lib/script_layer_audit.py" --workspace "$WORKSPACE" --output "$OUTPUT"
