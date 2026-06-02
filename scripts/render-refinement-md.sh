#!/usr/bin/env bash
# Purpose: render refinement.json into the human-facing refinement.md derived view.
# Inputs:  <refinement.json> [--check]
# Outputs: writes <dir>/refinement.md (or --check compares without writing).
#
# DP-269: the jira-only schema fields (source.repo / source.base_branch /
# tasks[].jira_key) are machine-consumed by derive-task-md-from-refinement-json.sh
# and intentionally NOT surfaced in the rendered refinement.md. The generator
# (lib/refinement-md-generator.py) ignores unknown source/task fields, so the
# additive schema does not break the existing render output.
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
