#!/usr/bin/env bash
# Selftest wrapper for validate-completion-envelope.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "$ROOT_DIR/scripts/validate-completion-envelope.sh" --self-test
