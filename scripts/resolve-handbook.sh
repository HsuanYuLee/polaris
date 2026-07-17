#!/usr/bin/env bash
# Resolve one repo-scoped Polaris handbook from its project configuration root.
# Inputs: generic scope identity or a direct config path; optional output mode.
# Outputs: deterministic JSON; missing/invalid configured handbooks fail closed.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  resolve-handbook.sh --scope-root DIR --scope-id ID
  resolve-handbook.sh --company-dir DIR --project ID
  resolve-handbook.sh --project ID
  resolve-handbook.sh --config PATH [--field DOTTED_PATH]

The forms are equivalent; without a root, the repository root is used. The resolver reads:
  {scope-root}/polaris-config/{scope-id}/handbook/config.yaml

It emits deterministic JSON containing the config, narrative index, and all
existing handbook Markdown paths. A configured handbook with missing or
invalid required files fails closed.
EOF
}

SCOPE_ROOT=""
SCOPE_ID=""
CONFIG_PATH=""
FIELD=""
PATHS_ONLY="false"
OPTIONAL="false"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope-root|--company-dir)
      SCOPE_ROOT="${2:-}"
      shift 2
      ;;
    --scope-id|--project)
      SCOPE_ID="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --field)
      FIELD="${2:-}"
      shift 2
      ;;
    --paths-only)
      PATHS_ONLY="true"
      shift
      ;;
    --optional)
      OPTIONAL="true"
      shift
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

if [[ -z "$CONFIG_PATH" && -z "$SCOPE_ID" ]]; then
  echo "--scope-id/--project is required" >&2
  usage >&2
  exit 2
fi
if [[ -z "$CONFIG_PATH" && -z "$SCOPE_ROOT" ]]; then
  SCOPE_ROOT="$REPO_ROOT"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$SCOPE_ROOT" "$SCOPE_ID" "$CONFIG_PATH" "$FIELD" "$PATHS_ONLY" "$OPTIONAL" <<'PY'
import json
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

scope_root_arg, scope_id, config_arg, field = sys.argv[1:5]
paths_only = sys.argv[5] == "true"
optional = sys.argv[6] == "true"

if config_arg:
    config_path = Path(config_arg).expanduser().resolve()
    handbook_root = config_path.parent
else:
    scope_root = Path(scope_root_arg).expanduser().resolve()
    handbook_root = scope_root / "polaris-config" / scope_id / "handbook"
    config_path = handbook_root / "config.yaml"
index_path = handbook_root / "index.md"

if optional and paths_only and not config_path.exists():
    legacy_paths = sorted(
        str(path.resolve()) for path in handbook_root.rglob("*.md") if path.is_file()
    ) if handbook_root.is_dir() else []
    print(json.dumps(legacy_paths, ensure_ascii=False))
    sys.exit(0)
if optional and not config_path.exists() and not index_path.exists():
    print(json.dumps({
        "schema_version": 1,
        "status": "not_configured",
        "scope_root": str(scope_root),
        "scope_id": scope_id,
    }, sort_keys=True))
    sys.exit(0)

required_paths = [("config", config_path)]
if not (config_arg and field):
    required_paths.append(("narrative index", index_path))
for label, path in required_paths:
    if not path.is_file():
        print(f"handbook {label} not found: {path}", file=sys.stderr)
        sys.exit(1)

try:
    with config_path.open(encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}
except Exception as exc:
    print(f"failed to parse handbook config: {config_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(config, dict):
    print("handbook config root must be a mapping", file=sys.stderr)
    sys.exit(1)

if config_arg:
    scope_id = config.get("project")
    scope_root = handbook_root.parents[2]
if not isinstance(scope_id, str) or not scope_id:
    print("handbook config project identity is required", file=sys.stderr)
    sys.exit(1)
if config.get("project") != scope_id:
    print(
        f"handbook project identity mismatch: expected {scope_id!r}, "
        f"found {config.get('project')!r}",
        file=sys.stderr,
    )
    sys.exit(1)

markdown_paths = sorted(path.resolve() for path in handbook_root.rglob("*.md") if path.is_file())
narrative_paths = [index_path.resolve(), *(path for path in markdown_paths if path != index_path.resolve())]

if field:
    selected = config
    try:
        for part in field.split("."):
            if not part:
                continue
            if "[" in part:
                key, index = part.rstrip("]").split("[", 1)
                if key:
                    selected = selected[key]
                selected = selected[int(index)]
            else:
                selected = selected[part]
    except (KeyError, IndexError, TypeError, ValueError):
        print(f"missing field: {field}", file=sys.stderr)
        sys.exit(1)
    print(json.dumps(selected, ensure_ascii=False, sort_keys=True))
    sys.exit(0)

if paths_only:
    print(json.dumps([str(path) for path in narrative_paths], ensure_ascii=False))
    sys.exit(0)

payload = {
    "schema_version": 1,
    "scope_root": str(scope_root),
    "scope_id": scope_id,
    "handbook_root": str(handbook_root.resolve()),
    "config_path": str(config_path.resolve()),
    "index_path": str(index_path.resolve()),
    "narrative_paths": [str(path) for path in narrative_paths],
    "config": config,
}
print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
PY
