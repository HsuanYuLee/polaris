#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THRESHOLD="30000"
MODE="advisory"
MEMORY_INDEX=""

usage() {
  cat >&2 <<'EOF'
usage: validate-bootstrap-budget.sh [options]

Options:
  --root <path>          Workspace root (default: script parent)
  --memory-index <path>  Explicit MEMORY.md path for measurement
  --threshold <tokens>   Shared Polaris token threshold (default: 30000)
  --advisory             Report over-budget as WARN with exit 0 (default)
  --blocking             Report over-budget as FAIL with exit 1
  -h, --help             Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --memory-index) MEMORY_INDEX="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    --advisory) MODE="advisory"; shift ;;
    --blocking) MODE="blocking"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "validate-bootstrap-budget: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "validate-bootstrap-budget: threshold must be an integer" >&2
  exit 2
fi

MEASURE_ARGS=(--root "$ROOT" --json)
if [[ -n "$MEMORY_INDEX" ]]; then
  MEASURE_ARGS+=(--memory-index "$MEMORY_INDEX")
fi

JSON_OUTPUT="$("$ROOT/scripts/measure-bootstrap-tokens.sh" "${MEASURE_ARGS[@]}")"

JSON_OUTPUT="$JSON_OUTPUT" python3 - "$THRESHOLD" "$MODE" <<'PY'
import json
import os
import sys

threshold = int(sys.argv[1])
mode = sys.argv[2]
data = json.loads(os.environ["JSON_OUTPUT"])
tokens = int(data["shared_polaris_estimated_tokens"])
status = "PASS" if tokens <= threshold else ("WARN" if mode == "advisory" else "FAIL")

print(f"bootstrap_budget_status={status}")
print(f"shared_polaris_estimated_tokens={tokens}")
print(f"threshold={threshold}")
print(f"mode={mode}")
print(f"estimator={data.get('estimator', '')}")

if status == "FAIL":
    sys.exit(1)
PY
