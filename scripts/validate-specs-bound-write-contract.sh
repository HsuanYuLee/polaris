#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/validate-specs-bound-write-contract.sh --files PATH [PATH ...]
  scripts/validate-specs-bound-write-contract.sh --diff-range BASE..HEAD [--repo PATH]

Validates specs-bound Markdown against scripts/lib/evidence-producers.json.
USAGE
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PRODUCER_MAP="$ROOT_DIR/scripts/lib/evidence-producers.json"
REPO="$ROOT_DIR"
MODE=""
DIFF_RANGE=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --diff-range) MODE="diff"; DIFF_RANGE="${2:-}"; shift 2 ;;
    --files) MODE="files"; shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$MODE" ]] || usage

if [[ "$MODE" == "diff" ]]; then
  [[ -n "$DIFF_RANGE" ]] || usage
  mapfile -t FILES < <(git -C "$REPO" diff --name-only "$DIFF_RANGE" -- 'docs-manager/src/content/docs/specs/**/*.md')
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_specs_bound_write_contract_1.py" "$REPO" "$PRODUCER_MAP" "${FILES[@]}"
