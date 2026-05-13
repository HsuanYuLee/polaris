#!/usr/bin/env bash
set -euo pipefail

# DP-154 V1 convergence selftest.
# Keeps the captured product-delivery failure shape as a sanitized fixture, then
# delegates each closed gap to the deterministic selftest that owns the contract.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE="$SCRIPT_DIR/fixtures/delivery-contract-gap-convergence/generic-product-delivery.json"

assert_fixture_safe() {
  python3 - "$FIXTURE" "$0" <<'PY'
import json
import re
import sys
from pathlib import Path

fixture_path = Path(sys.argv[1])
script_path = Path(sys.argv[2])
data = json.loads(fixture_path.read_text(encoding="utf-8"))

required = {
    "deliverable_writeback",
    "task_verify_report",
    "behavior_assertion_results",
    "changeset_allowed_files_contract",
    "pending_ci_readiness_reason",
}
actual = set(data.get("expected_mechanisms") or [])
missing = sorted(required - actual)
if missing:
    raise SystemExit(f"fixture missing expected mechanisms: {', '.join(missing)}")

assertions = {item.get("status") for item in data.get("behavior_assertions") or []}
if "PASS" not in assertions or "NOT_COVERED" not in assertions:
    raise SystemExit("fixture must include both covered and not-covered behavior assertions")

changeset = data.get("changeset") or {}
expected_path = str(changeset.get("expected_path") or "")
slug = str(changeset.get("filename_slug") or "")
if expected_path != f".changeset/{slug}.md":
    raise SystemExit("fixture changeset path must mechanically derive from filename_slug")

text = fixture_path.read_text(encoding="utf-8") + "\n" + script_path.read_text(encoding="utf-8")
company = "kk" + "day"
for pattern in (
    r"\bGT-[0-9]+\b",
    r"\bKB2CW-[0-9]+\b",
    company,
    r"atlassian[.]net",
    r"www[.](?:stage[.]|sit[.])?" + company + r"[.]com",
):
    if re.search(pattern, text, re.I):
        raise SystemExit(f"template-unsafe fixture content matched: {pattern}")

print("fixture safety PASS")
PY
}

run_step() {
  local label="$1"
  shift
  echo "=== ${label} ==="
  "$@"
}

assert_fixture_safe
run_step "deliverable writeback + verify report" bash "$ROOT_DIR/scripts/selftests/polaris-pr-create-selftest.sh"
run_step "finalize generated verify report" bash "$ROOT_DIR/scripts/selftests/finalize-engineering-delivery-selftest.sh"
run_step "behavior assertion coverage" bash "$ROOT_DIR/scripts/selftests/run-behavior-contract-selftest.sh"
run_step "changeset scope contract" bash "$ROOT_DIR/scripts/validate-breakdown-ready.sh" --self-test
run_step "PR readiness classification" bash "$ROOT_DIR/scripts/selftests/check-delivery-completion-selftest.sh"

echo "delivery-contract-gap-convergence selftest PASS"
