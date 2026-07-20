#!/usr/bin/env bash
# Purpose: validate source-neutral refinement.json verification_strategy semantics.
# Inputs:  <path/to/refinement.json>
# Outputs: PASS line on success; fail-closed POLARIS_* markers on contract drift.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-verification-strategy.sh <path/to/refinement.json>

Validates refinement.json verification_strategy:
- mode enum: per_task_self_verify | source_level_v_required | external_ac_ticket
- reason / authority are non-empty strings
- source_level_v_required requires at least one V task
- per_task_self_verify requires T tasks to carry non-empty verification.verify_command
- external_ac_ticket requires a ticket identity

The gate is source-neutral: it does not branch on source.type.
EOF
  exit 2
}

[[ $# -eq 1 ]] || usage
REFINEMENT_JSON="$1"
[[ -f "$REFINEMENT_JSON" ]] || { echo "validate-verification-strategy: file not found: $REFINEMENT_JSON" >&2; exit 2; }

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_verification_strategy_1.py" "$REFINEMENT_JSON"
