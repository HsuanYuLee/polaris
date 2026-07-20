#!/usr/bin/env bash
set -euo pipefail

# validate-public-onboarding-contract.sh
#
# Ensures public onboarding docs expose the runtime/toolchain contract declared
# by polaris-toolchain.yaml. This catches semantic drift that skill-count docs
# lint cannot see.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_public_onboarding_contract_1.py" "$ROOT"
