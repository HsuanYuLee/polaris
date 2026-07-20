#!/usr/bin/env bash
# Validate specs source paths that must map cleanly to Starlight routes.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-route-safe-spec-paths.sh [file-or-directory...]

Default path:
  docs-manager/src/content/docs/specs

Fails when a specs markdown path segment contains characters that commonly
produce missing Starlight routes, such as extra dots, spaces, or punctuation.
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
  paths=("docs-manager/src/content/docs/specs")
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_route_safe_spec_paths_1.py" "${paths[@]}"
