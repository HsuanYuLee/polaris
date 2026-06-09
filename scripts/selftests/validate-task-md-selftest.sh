#!/usr/bin/env bash
# Purpose: DP-296 T5 — folder-native (scripts/selftests/) entrypoint for the
#          validate-task-md.sh selftest. The canonical implementation lives at the
#          manifest-bound path scripts/validate-task-md-selftest.sh (single source
#          of truth, no second writer path); this wrapper exists so DP-296-T5's
#          Verify Command can reference the conventional scripts/selftests/ location
#          without forking the test body.
# Inputs:  none.
# Outputs: delegates stdout/stderr/exit code from the canonical selftest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$SCRIPT_DIR/validate-task-md-selftest.sh" "$@"
