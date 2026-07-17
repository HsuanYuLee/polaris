#!/usr/bin/env bash
# Purpose: 證明 verify-cross-llm-parity --help 在 aggregate 與 compiler regeneration 前 fast-exit。
# Inputs: isolated parity script fixture、guarded aggregate/parity/compiler commands 與 dirty sentinel。
# Outputs: --help side-effect-free 時輸出 PASS。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-safe-cli-introspection.sh"

bash "$VALIDATOR" \
  --repo "$ROOT_DIR" \
  --script scripts/verify-cross-llm-parity.sh \
  --guard-repo-command scripts/check-skills-mirror-mode.sh \
  --guard-repo-command scripts/mechanism-parity.sh \
  --guard-repo-command scripts/compile-runtime-instructions.sh \
  --guard-repo-command scripts/polaris-bootstrap.sh \
  --guard-repo-command scripts/run-aggregate-selftests.sh \
  --expect 'Usage:'

echo "verify-cross-llm-parity-selftest: PASS"
