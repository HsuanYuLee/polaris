#!/usr/bin/env bash
# Validate root polaris-toolchain.yaml.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${1:-$WORKSPACE_ROOT/polaris-toolchain.yaml}"

python3 "$WORKSPACE_ROOT/scripts/lib/polaris_toolchain_manifest.py" "$MANIFEST" >/dev/null
echo "PASS: Polaris toolchain manifest"
