#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMAT="table"

usage() {
  cat <<'USAGE'
Usage: bash scripts/script-ownership-audit.sh [--root <repo>] [--format table|json]

Audits root scripts against textual consumers and scripts/manifest.json to
recommend whether each script should stay root, move to a skill, keep a bridge,
or be reviewed as a sunset candidate.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT_DIR="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$FORMAT" in
  table|json) ;;
  *)
    echo "--format must be table or json" >&2
    exit 2
    ;;
esac

python3 "$SCRIPT_DIR/script-ownership-audit.py" --root "$ROOT_DIR" --format "$FORMAT"
