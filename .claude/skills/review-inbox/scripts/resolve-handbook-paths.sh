#!/usr/bin/env bash
# resolve-handbook-paths.sh — Resolve Polaris project handbook markdown paths.

set -euo pipefail

WORKSPACE=""
COMPANY=""
PROJECT=""

usage() {
  cat >&2 <<'EOF'
usage: resolve-handbook-paths.sh --workspace PATH --company KEY --project KEY

Prints a JSON array of existing absolute markdown paths under:
  {workspace}/{company}/polaris-config/{project}/handbook/**/*.md

Missing or empty handbook directories return [].
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --company) COMPANY="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$WORKSPACE" || -z "$COMPANY" || -z "$PROJECT" ]]; then
  usage
fi

python3 - "$WORKSPACE" "$COMPANY" "$PROJECT" <<'PY'
import json
import sys
from pathlib import Path

workspace = Path(sys.argv[1]).expanduser().resolve()
company = sys.argv[2]
project = sys.argv[3]
handbook = workspace / company / "polaris-config" / project / "handbook"

if not handbook.is_dir():
    print("[]")
    sys.exit(0)

paths = sorted(str(path.resolve()) for path in handbook.rglob("*.md") if path.is_file())
print(json.dumps(paths, ensure_ascii=False))
PY
