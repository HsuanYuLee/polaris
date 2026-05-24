#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  migrate-refinement-json.sh --manifest <manifest-file>
  migrate-refinement-json.sh <refinement.json> [...]

Manifest format: one refinement.json path per line; blank lines and # comments ignored.
USAGE
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE="$SCRIPT_DIR/lib/migrate-refinement-json-to-strong-bound.py"
VALIDATOR="$SCRIPT_DIR/validate-refinement-json.sh"

paths=()
if [[ $# -eq 0 ]]; then
  usage
fi
if [[ "${1:-}" == "--manifest" ]]; then
  [[ $# -eq 2 ]] || usage
  [[ -f "$2" ]] || { echo "manifest not found: $2" >&2; exit 2; }
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && paths+=("$line")
  done < "$2"
else
  paths=("$@")
fi

[[ "${#paths[@]}" -gt 0 ]] || { echo "no refinement.json paths" >&2; exit 2; }
python3 "$CORE" "${paths[@]}"
for path in "${paths[@]}"; do
  bash "$VALIDATOR" "$path"
done
