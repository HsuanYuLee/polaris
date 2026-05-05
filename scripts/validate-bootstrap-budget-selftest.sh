#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/validate-bootstrap-budget.sh"

"$SCRIPT" --root "$ROOT" --threshold 999999 --blocking | rg -q "bootstrap_budget_status=PASS"
"$SCRIPT" --root "$ROOT" --threshold 1 --advisory | rg -q "bootstrap_budget_status=WARN"

if "$SCRIPT" --root "$ROOT" --threshold 1 --blocking >/tmp/validate-bootstrap-budget-blocking.out 2>&1; then
  echo "validate-bootstrap-budget-selftest: expected blocking mode to fail" >&2
  cat /tmp/validate-bootstrap-budget-blocking.out >&2
  exit 1
fi
rg -q "bootstrap_budget_status=FAIL" /tmp/validate-bootstrap-budget-blocking.out
rm -f /tmp/validate-bootstrap-budget-blocking.out

echo "validate-bootstrap-budget-selftest: PASS"
