#!/usr/bin/env bash
# Single DP plan authoring gate used after creating or updating plan.md.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-plan-authoring.sh <path/to/plan.md>...

Runs the deterministic authoring checks required for Design Plan plan.md files:
Starlight authoring, sidebar metadata sync/validation, language policy,
handbook path contract, route-safe specs paths, and duplicate DP number guard
for each supplied plan number.
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

plans=("$@")
for plan in "${plans[@]}"; do
  if [[ ! -f "$plan" ]]; then
    echo "error: plan not found: $plan" >&2
    exit 2
  fi
  if [[ "$(basename "$plan")" != "plan.md" ]]; then
    echo "error: expected plan.md path, got: $plan" >&2
    exit 2
  fi
done

bash scripts/sync-spec-sidebar-metadata.sh --apply "${plans[@]}"
bash scripts/validate-starlight-authoring.sh check "${plans[@]}"
bash scripts/validate-dp-metadata.sh "${plans[@]}"
bash scripts/validate-language-policy.sh --blocking --mode artifact "${plans[@]}"
bash scripts/validate-handbook-path-contract.sh

containers=()
for plan in "${plans[@]}"; do
  containers+=("$(dirname "$plan")")
done
bash scripts/validate-route-safe-spec-paths.sh "${containers[@]}"

if [[ -x scripts/validate-dp-number-uniqueness.sh ]]; then
  for plan in "${plans[@]}"; do
    bash scripts/validate-dp-number-uniqueness.sh --plan "$plan"
  done
fi

echo "PASS: DP plan authoring wrapper"
