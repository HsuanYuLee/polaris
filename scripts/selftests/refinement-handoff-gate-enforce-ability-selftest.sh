#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$ROOT/scripts/selftests/refinement-decision-ac-coverage-selftest.sh" >/dev/null
bash "$ROOT/scripts/selftests/refinement-module-ac-coverage-selftest.sh" >/dev/null
bash "$ROOT/scripts/selftests/refinement-section-presence-advisory-selftest.sh" >/dev/null
bash "$ROOT/scripts/selftests/refinement-intra-dp-consistency-selftest.sh" >/dev/null
bash "$ROOT/scripts/selftests/refinement-ac-id-shape-selftest.sh" >/dev/null
echo "PASS: refinement handoff gate enforce-ability"
