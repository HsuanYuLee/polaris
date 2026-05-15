#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

script_test_expect_pass \
  "polaris bootstrap dry-run" \
  bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile runtime --dry-run

echo "polaris-bootstrap self-test PASS"
