#!/usr/bin/env bash
# Source-agnostic primary doc authoring gate. Runs after creating or updating
# a primary doc (DP index.md / legacy plan.md, Epic index.md / refinement.md).
#
# Shared gates: Starlight authoring, sidebar metadata sync/validation, language
# policy, handbook path contract, route-safe specs paths, and (for DP plans)
# duplicate DP number guard.
#
# Source-detection rules:
#   - basename must be one of: index.md, plan.md, refinement.md
#   - path must contain /specs/design-plans/ (DP source) or /specs/epics/ (Epic source)
#   - DP-specific guards (validate-dp-metadata.sh, validate-dp-number-uniqueness.sh)
#     only fire for DP sources.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-spec-primary-doc-authoring.sh <path/to/index.md|plan.md|refinement.md>...

Source-agnostic primary doc authoring wrapper. Accepts DP / Epic primary docs:
  - DP index.md / legacy plan.md under .../specs/design-plans/<DP-ID>/
  - Epic index.md / refinement.md under .../specs/epics/<EPIC-ID>/

Runs deterministic authoring checks shared by DP / Epic primary docs:
Starlight authoring, sidebar metadata sync/validation, language policy,
handbook path contract, route-safe specs paths. Adds DP metadata and
duplicate DP number guard when the input is a DP primary doc.
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

primary_docs=("$@")
dp_docs=()
for doc in "${primary_docs[@]}"; do
  if [[ ! -f "$doc" ]]; then
    echo "error: primary doc not found: $doc" >&2
    exit 2
  fi
  case "$(basename "$doc")" in
    index.md|plan.md|refinement.md) ;;
    *)
      echo "error: expected index.md / plan.md / refinement.md path, got: $doc" >&2
      exit 2
      ;;
  esac
  doc_dir="$(dirname "$doc")"
  case "$doc_dir" in
    */design-plans/*)
      dp_docs+=("$doc")
      ;;
    */epics/*)
      ;;
    *)
      echo "error: expected design-plans/ or epics/ primary doc path, got: $doc" >&2
      exit 2
      ;;
  esac
done

bash scripts/sync-spec-sidebar-metadata.sh --apply "${primary_docs[@]}"
bash scripts/validate-starlight-authoring.sh check "${primary_docs[@]}"
if [[ ${#dp_docs[@]} -gt 0 ]]; then
  bash scripts/validate-dp-metadata.sh "${dp_docs[@]}"
fi
bash scripts/validate-language-policy.sh --blocking --mode artifact "${primary_docs[@]}"
bash scripts/validate-handbook-path-contract.sh

containers=()
for doc in "${primary_docs[@]}"; do
  containers+=("$(dirname "$doc")")
done
bash scripts/validate-route-safe-spec-paths.sh "${containers[@]}"

if [[ ${#dp_docs[@]} -gt 0 ]] && [[ -x scripts/validate-dp-number-uniqueness.sh ]]; then
  for doc in "${dp_docs[@]}"; do
    bash scripts/validate-dp-number-uniqueness.sh --plan "$doc"
  done
fi

echo "PASS: spec primary doc authoring wrapper"
