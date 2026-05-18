#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT_DIR/scripts/tool-direct-call-inventory.txt"
CHECK=false

usage() {
  cat <<'USAGE'
Usage: bash scripts/tool-direct-call-inventory.sh [--check] [--output <path>]

Scans Tier A Polaris scripts for direct tool calls and emits a TSV baseline:
path, line, tool, owner, install_authority, runtime_profile, goes_to_mise.
USAGE
}

OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "tool-direct-call-inventory: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

export PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
# shellcheck source=lib/tool-attribution.sh
source "$ROOT_DIR/scripts/lib/tool-attribution.sh"

field() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json
import sys
value = json.loads(sys.argv[1]).get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

emit_inventory() {
  local files=(
    "scripts/polaris-bootstrap.sh"
    "scripts/polaris-doctor.sh"
    "scripts/doctor-mise-check.sh"
    "scripts/polaris-pr-create.sh"
    "scripts/run-governed-script-tests.sh"
  )
  local tools=(mise gh node pnpm jq rg python3)
  local file line_no line tool attr owner authority profile goes

  printf 'path\tline\ttool\towner\tinstall_authority\truntime_profile\tgoes_to_mise\n'
  for file in "${files[@]}"; do
    [[ -f "$ROOT_DIR/$file" ]] || continue
    line_no=0
    while IFS= read -r line; do
      line_no=$((line_no + 1))
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      for tool in "${tools[@]}"; do
        if [[ "$line" =~ (^|[^A-Za-z0-9_-])${tool}([^A-Za-z0-9_-]|$) ]]; then
          attr="$(polaris_classify_tool "$tool")"
          owner="$(field "$attr" owner)"
          authority="$(field "$attr" install_authority)"
          profile="$(field "$attr" runtime_profile)"
          goes="$(field "$attr" goes_to_mise)"
          printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$file" "$line_no" "$tool" "$owner" "$authority" "$profile" "$goes"
        fi
      done
    done < "$ROOT_DIR/$file"
  done
}

if [[ -n "$OUTPUT" ]]; then
  emit_inventory > "$OUTPUT"
  exit 0
fi

if [[ "$CHECK" == true ]]; then
  tmp="$(mktemp -t polaris-tool-inventory-XXXXXX)"
  trap 'rm -f "$tmp"' EXIT
  emit_inventory > "$tmp"
  if ! cmp -s "$tmp" "$BASELINE"; then
    echo "tool-direct-call-inventory: baseline drift detected" >&2
    diff -u "$BASELINE" "$tmp" >&2 || true
    exit 1
  fi
  echo "tool-direct-call-inventory PASS"
  exit 0
fi

emit_inventory
