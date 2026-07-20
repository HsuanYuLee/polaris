#!/usr/bin/env bash
# Validate Design Plan lifecycle and Starlight sidebar metadata.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-dp-metadata.sh [file-or-directory...]

Default path:
  docs-manager/src/content/docs/specs/design-plans

Use scripts/sync-spec-sidebar-metadata.sh --apply to repair deterministic drift.
EOF
  exit 2
}

paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      paths+=("$1")
      shift
      ;;
  esac
done

if [[ ${#paths[@]} -eq 0 ]]; then
  paths=("docs-manager/src/content/docs/specs/design-plans")
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_dp_metadata_1.py" "${paths[@]}"
