#!/usr/bin/env bash
# Deterministic Starlight authoring validator for specs Markdown sources.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-starlight-authoring.sh <check|legacy-report> <file-or-directory>...

Modes:
  check          Blocking validation for explicit create/update/move-in paths.
  legacy-report  Non-blocking report for legacy trees; exits 0 after classifying drift.
EOF
  exit 2
}

if [[ $# -lt 2 ]]; then
  usage
fi

mode="$1"
shift

case "$mode" in
  check|legacy-report) ;;
  *) usage ;;
esac

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_starlight_authoring_1.py" "$mode" "$@"
