#!/usr/bin/env bash
# Purpose: prove the review external-write transition is registry-bound and blocking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/scripts/selftests/polaris-external-write-gate-selftest.sh" >/dev/null
bash "$ROOT/scripts/selftests/submit-pr-review-selftest.sh" >/dev/null
bash "$ROOT/scripts/validate-skill-flow-transition-registry.sh" >/dev/null

resolved="$(bash "$ROOT/scripts/resolve-skill-flow-transition.sh" \
  --id review_pr.external_write_submission --field callable_interface.path)"
[[ "$resolved" == "scripts/submit-pr-review.sh" ]] || {
  echo "FAIL: transition resolver returned $resolved" >&2
  exit 1
}

echo "PASS: external-write review chain is registry-bound"
