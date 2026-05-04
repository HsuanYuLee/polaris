#!/usr/bin/env bash
# refinement-handoff-gate.sh — hard gate before refinement hands off to breakdown.
#
# Usage:
#   refinement-handoff-gate.sh <spec-container|refinement.md|refinement.json>
#
# Exit:
#   0 = refinement.json exists and passes schema validation
#   1 = handoff blocked (missing or invalid artifact)
#   2 = usage/path error

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: refinement-handoff-gate.sh <spec-container|refinement.md|refinement.json>

Examples:
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495/refinement.md
  refinement-handoff-gate.sh specs/companies/exampleco/EPIC-495/refinement.json
EOF
  exit 2
}

if [[ $# -ne 1 ]]; then
  usage
fi

input="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
validator="$script_dir/validate-refinement-json.sh"

if [[ ! -x "$validator" ]]; then
  echo "BLOCKED: validator not executable: $validator" >&2
  exit 2
fi

json_path=""
case "$input" in
  */refinement.json|refinement.json)
    json_path="$input"
    ;;
  */refinement.md|refinement.md)
    json_path="$(dirname "$input")/refinement.json"
    ;;
  *)
    if [[ -d "$input" ]]; then
      json_path="$input/refinement.json"
    else
      echo "BLOCKED: path is neither a specs directory nor refinement artifact: $input" >&2
      exit 2
    fi
    ;;
esac

if [[ ! -f "$json_path" ]]; then
  cat >&2 <<EOF
BLOCKED: refinement handoff requires a machine-readable artifact.
Missing: $json_path

Run refinement Step 7 first: produce refinement.json from the finalized refinement.md,
then rerun this gate before telling the user to proceed to breakdown.
EOF
  exit 1
fi

if ! "$validator" "$json_path"; then
  cat >&2 <<EOF

BLOCKED: refinement.json exists but does not satisfy the pipeline handoff schema.
Fix the artifact before proceeding to breakdown.
EOF
  exit 1
fi

echo "PASS refinement handoff: $json_path"

