#!/usr/bin/env bash
# Purpose: Transparent-pipe gate for memory-hygiene dry-run plan artifacts.
# Inputs:  plan JSON via --input PATH or stdin; --format text|json selects the
#          verdict representation written to stderr.
# Outputs: On PASS, the validated plan JSON is re-emitted verbatim to stdout
#          (so it can be piped to apply) and the verdict goes to stderr (exit 0).
#          On FAIL, stdout is empty and the verdict + issues go to stderr (exit 1).

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-memory-hygiene-plan.sh [--input PATH] [--format text|json]

Defaults:
  --input   stdin
  --format  text

On PASS the plan JSON is passed through verbatim on stdout; the verdict
(--format text|json) is written to stderr. On FAIL stdout is empty.
EOF
  exit 2
}

input_path=""
format="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_path="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ "$format" != "text" && "$format" != "json" ]]; then
  echo "error: --format must be text or json" >&2
  exit 2
fi

tmp_input=""
if [[ -z "$input_path" ]]; then
  tmp_input="$(mktemp -t memory-hygiene-plan.XXXXXX.json)"
  cat >"$tmp_input"
  input_path="$tmp_input"
fi
trap '[[ -n "${tmp_input:-}" ]] && rm -f "$tmp_input"' EXIT

if [[ -n "$input_path" && ! -f "$input_path" ]]; then
  echo "error: input file not found: $input_path" >&2
  exit 1
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_memory_hygiene_plan_1.py" "$format" "$input_path"
