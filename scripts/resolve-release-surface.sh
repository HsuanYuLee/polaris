#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris release-surface]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"

TASK_MD=""
FORMAT="text"
FIELD=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/resolve-release-surface.sh --task-md <path> [--format text|json|field] [--field <name>]

Output:
  text   SURFACE class=<none|developer_pr|package_release|local_extension|ambiguous> release_required=<true|false>
  json   { "class": "...", "release_required": true|false, "surface_signals": [...], "ambiguity_reasons": [...] }
  field  one of: class, release_required

Exit:
  0   success
  64  invalid usage / parse failure
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$TASK_MD" ]] || { echo "$PREFIX --task-md is required" >&2; usage; exit 64; }
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ "$FORMAT" == "text" || "$FORMAT" == "json" || "$FORMAT" == "field" ]] || {
  echo "$PREFIX --format must be text, json, or field" >&2
  exit 64
}
if [[ "$FORMAT" == "field" ]]; then
  [[ "$FIELD" == "class" || "$FIELD" == "release_required" ]] || {
    echo "$PREFIX --field must be class or release_required" >&2
    exit 64
  }
fi

task_json="$(bash "$PARSE_TASK_MD" "$TASK_MD" --no-resolve 2>/dev/null)" || {
  echo "$PREFIX failed to parse task.md: $TASK_MD" >&2
  exit 64
}

python3 "$SCRIPT_DIR/lib/release_closeout_helpers.py" resolve-surface \
  "$FORMAT" "$FIELD" "$task_json"
