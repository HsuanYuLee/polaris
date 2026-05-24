#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: render-refinement-md.sh <refinement.json> [--check]
USAGE
  exit 2
}

[[ $# -ge 1 ]] || usage
JSON_PATH="$1"
CHECK=0
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$(dirname "$JSON_PATH")/refinement.md"
TMP="$(mktemp -t refinement-md.XXXXXX)"
python3 "$SCRIPT_DIR/lib/refinement-md-generator.py" "$JSON_PATH" > "$TMP"
if [[ "$CHECK" -eq 1 ]]; then
  cmp -s "$TMP" "$OUT" || {
    echo "POLARIS_REFINEMENT_MD_HAND_EDIT_DETECTED" >&2
    rm -f "$TMP"
    exit 2
  }
  rm -f "$TMP"
  exit 0
fi
mv "$TMP" "$OUT"
