#!/usr/bin/env bash
# Purpose: enforce DP-420 selftest corpus debt, latency, and quality budgets.
# Inputs: --ledger PATH --manifest PATH [--base-ref REF] [--metrics PATH ...]
# Outputs: PASS or fail-closed POLARIS_CORPUS_BUDGET diagnostics.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || {
  echo 'POLARIS_TOOL_MISSING:python3 — run `mise install` to restore the Polaris runtime toolchain' >&2
  exit 2
}
exec python3 "$ROOT/scripts/lib/lint_selftest_corpus_budget.py" "$@"
