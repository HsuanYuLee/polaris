#!/usr/bin/env bash
# Purpose: 證明 polaris-bootstrap --help 在 sourcing toolchain/bootstrap side effects 前 fast-exit。
# Inputs: isolated bootstrap fixture、tool-resolution dependency 與 dirty sentinel。
# Outputs: --help side-effect-free 時輸出 PASS。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT_DIR/scripts/validate-safe-cli-introspection.sh" \
  --repo "$ROOT_DIR" \
  --script scripts/polaris-bootstrap.sh \
  --copy-dependency scripts/lib/tool-resolution.sh \
  --expect 'Usage:'

echo "polaris-bootstrap-help-selftest: PASS"
