#!/usr/bin/env bash
# Single DP plan authoring gate used after creating or updating a DP primary doc.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-plan-authoring.sh <path/to/index.md|plan.md>...

Runs the deterministic authoring checks required for Design Plan primary docs:
Starlight authoring, sidebar metadata sync/validation, language policy,
handbook path contract, route-safe specs paths, and duplicate DP number guard
for each supplied DP container.
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

primary_docs=("$@")
for doc in "${primary_docs[@]}"; do
  if [[ ! -f "$doc" ]]; then
    echo "error: primary doc not found: $doc" >&2
    exit 2
  fi
  case "$(basename "$doc")" in
    index.md|plan.md) ;;
    *)
      echo "error: expected index.md or plan.md path, got: $doc" >&2
      exit 2
      ;;
  esac
  if [[ "$(dirname "$doc")" != */design-plans/* ]]; then
    echo "error: expected design-plan primary doc path, got: $doc" >&2
    exit 2
  fi
done

bash scripts/sync-spec-sidebar-metadata.sh --apply "${primary_docs[@]}"
bash scripts/validate-starlight-authoring.sh check "${primary_docs[@]}"
bash scripts/validate-dp-metadata.sh "${primary_docs[@]}"
bash scripts/validate-language-policy.sh --blocking --mode artifact "${primary_docs[@]}"
bash scripts/validate-handbook-path-contract.sh

containers=()
for doc in "${primary_docs[@]}"; do
  containers+=("$(dirname "$doc")")
done
bash scripts/validate-route-safe-spec-paths.sh "${containers[@]}"

if [[ -x scripts/validate-dp-number-uniqueness.sh ]]; then
  for doc in "${primary_docs[@]}"; do
    bash scripts/validate-dp-number-uniqueness.sh --plan "$doc"
  done
fi

echo "PASS: DP plan authoring wrapper"
