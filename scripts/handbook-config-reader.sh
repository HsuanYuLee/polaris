#!/usr/bin/env bash
# Read Polaris project handbook config as deterministic JSON.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  handbook-config-reader.sh --config PATH [--field DOTTED_PATH]
  handbook-config-reader.sh --company-dir DIR --project NAME [--field DOTTED_PATH]

Options:
  --config PATH       Direct path to handbook config.yaml.
  --company-dir DIR   Company directory containing polaris-config/.
  --project NAME      Project name under polaris-config/.
  --field PATH        Optional dotted path to emit a single value.
  -h, --help          Show this help.
EOF
}

CONFIG_PATH=""
COMPANY_DIR=""
PROJECT=""
FIELD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --company-dir) COMPANY_DIR="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG_PATH" ]]; then
  if [[ -z "$COMPANY_DIR" || -z "$PROJECT" ]]; then
    echo "Either --config or --company-dir + --project is required" >&2
    usage >&2
    exit 2
  fi
  CONFIG_PATH="$COMPANY_DIR/polaris-config/$PROJECT/handbook/config.yaml"
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "handbook config not found: $CONFIG_PATH" >&2
  exit 1
fi

python3 - "$CONFIG_PATH" "$FIELD" <<'PY'
import json
import sys

try:
    import yaml
except Exception as exc:
    print(f"PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

config_path, field = sys.argv[1], sys.argv[2]

try:
    with open(config_path, encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
except Exception as exc:
    print(f"failed to parse handbook config: {config_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print("handbook config root must be a mapping", file=sys.stderr)
    sys.exit(1)

def select(cur, dotted):
    for part in dotted.split("."):
        if not part:
            continue
        if "[" in part:
            key, idx = part.rstrip("]").split("[", 1)
            if key:
                if not isinstance(cur, dict) or key not in cur:
                    raise KeyError(dotted)
                cur = cur[key]
            if not isinstance(cur, list):
                raise KeyError(dotted)
            cur = cur[int(idx)]
            continue
        if not isinstance(cur, dict) or part not in cur:
            raise KeyError(dotted)
        cur = cur[part]
    return cur

if field:
    try:
        data = select(data, field)
    except Exception:
        print(f"missing field: {field}", file=sys.stderr)
        sys.exit(1)

print(json.dumps(data, ensure_ascii=False, sort_keys=True))
PY
