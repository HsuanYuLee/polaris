#!/usr/bin/env bash
# Purpose: enforce production script language-fit and draining migration debt.
# Inputs: --ledger PATH --manifest PATH [--base-ref REF]
# Outputs: PASS or fail-closed POLARIS_SCRIPT_LANGUAGE_FIT diagnostics.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo 'POLARIS_TOOL_MISSING:python3 — run `mise install` to restore the Polaris runtime toolchain' >&2
  exit 2
}
exec python3 "$ROOT/scripts/lib/lint_script_language_fit.py" "$@"
