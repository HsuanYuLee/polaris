#!/usr/bin/env bash
# Validate Polaris project handbook config fixtures and migration conflicts.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  handbook-config-validator.sh --config PATH [--project NAME] [--require-section NAME ...]
  handbook-config-validator.sh --company-dir DIR --project NAME [--require-section NAME ...]

Options:
  --config PATH             Direct path to handbook config.yaml.
  --company-dir DIR         Company directory containing polaris-config/ and optional workspace-config.yaml.
  --project NAME            Project name. Required for --company-dir and conflict checks.
  --workspace-config PATH   Optional workspace-config.yaml for conflict checks.
  --require-section NAME    Require a top-level capability section. Repeatable.
  --check-conflicts         Compare overlapping workspace-config dev_environment fields.
  -h, --help                Show this help.
EOF
}

CONFIG_PATH=""
COMPANY_DIR=""
PROJECT=""
WORKSPACE_CONFIG=""
CHECK_CONFLICTS=0
REQUIRE_SECTIONS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_PATH="${2:-}"; shift 2 ;;
    --company-dir) COMPANY_DIR="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --workspace-config) WORKSPACE_CONFIG="${2:-}"; shift 2 ;;
    --require-section) REQUIRE_SECTIONS+=("${2:-}"); shift 2 ;;
    --check-conflicts) CHECK_CONFLICTS=1; shift ;;
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

if [[ -z "$WORKSPACE_CONFIG" && -n "$COMPANY_DIR" && -f "$COMPANY_DIR/workspace-config.yaml" ]]; then
  WORKSPACE_CONFIG="$COMPANY_DIR/workspace-config.yaml"
fi

python_args=("$CONFIG_PATH" "$PROJECT" "$WORKSPACE_CONFIG" "$CHECK_CONFLICTS")
if [[ ${#REQUIRE_SECTIONS[@]} -gt 0 ]]; then
  python_args+=("${REQUIRE_SECTIONS[@]}")
fi

python3 - "${python_args[@]}" <<'PY'
import json
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

config_path = Path(sys.argv[1])
project = sys.argv[2]
workspace_config = Path(sys.argv[3]) if sys.argv[3] else None
check_conflicts = sys.argv[4] == "1"
required_sections = [s for s in sys.argv[5:] if s]
errors = []

def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return yaml.safe_load(handle) or {}
    except Exception as exc:
        errors.append(f"failed to parse YAML: {path}: {exc}")
        return None

if not config_path.is_file():
    errors.append(f"handbook config not found: {config_path}")
    data = None
else:
    data = load_yaml(config_path)

if data is not None:
    if not isinstance(data, dict):
        errors.append("handbook config root must be a mapping")
    else:
        schema_version = data.get("schema_version")
        if schema_version != 1:
            errors.append(f"unsupported schema_version: {schema_version!r}; expected 1")

        declared_project = data.get("project")
        if project and declared_project and declared_project != project:
            errors.append(f"project mismatch: config has {declared_project!r}, expected {project!r}")

        for section in required_sections:
            value = data.get(section)
            if value is None:
                errors.append(f"missing required section: {section}")
            elif not isinstance(value, (dict, list)):
                errors.append(f"required section must be mapping or list: {section}")

        runtime = data.get("runtime")
        if runtime is not None:
            if not isinstance(runtime, dict):
                errors.append("runtime section must be a mapping")
            else:
                for key in ("start_command", "health_check"):
                    if key in runtime and not isinstance(runtime[key], str):
                        errors.append(f"runtime.{key} must be a string")
                if "requires" in runtime and not isinstance(runtime["requires"], list):
                    errors.append("runtime.requires must be a list")

        test = data.get("test")
        if test is not None:
            if not isinstance(test, dict):
                errors.append("test section must be a mapping")
            elif "command" in test and not isinstance(test["command"], str):
                errors.append("test.command must be a string")

        mappings = data.get("file_url_mapping")
        if mappings is not None:
            if not isinstance(mappings, list):
                errors.append("file_url_mapping must be a list")
            else:
                for idx, item in enumerate(mappings):
                    if not isinstance(item, dict):
                        errors.append(f"file_url_mapping[{idx}] must be a mapping")
                    elif not item.get("pattern") or not item.get("url_template"):
                        errors.append(f"file_url_mapping[{idx}] requires pattern and url_template")

        libraries = data.get("key_libraries")
        if libraries is not None:
            if not isinstance(libraries, list):
                errors.append("key_libraries must be a list")
            else:
                for idx, item in enumerate(libraries):
                    if not isinstance(item, dict):
                        errors.append(f"key_libraries[{idx}] must be a mapping")
                    elif not item.get("name") or not item.get("concern"):
                        errors.append(f"key_libraries[{idx}] requires name and concern")

def project_env(workspace, project_name):
    if not workspace or not workspace.is_file() or not project_name:
        return None
    payload = load_yaml(workspace)
    if not isinstance(payload, dict):
        return None
    for item in payload.get("projects") or []:
        if isinstance(item, dict) and item.get("name") == project_name:
            env = item.get("dev_environment")
            return env if isinstance(env, dict) else None
    return None

def normalize(value):
    if isinstance(value, list):
        return [normalize(v) for v in value]
    if isinstance(value, dict):
        return {k: normalize(v) for k, v in sorted(value.items())}
    return value

if check_conflicts and data is not None and isinstance(data, dict):
    env = project_env(workspace_config, project)
    runtime = data.get("runtime") if isinstance(data.get("runtime"), dict) else {}
    test = data.get("test") if isinstance(data.get("test"), dict) else {}
    if env is not None:
        comparisons = [
            ("runtime.start_command", runtime.get("start_command"), "dev_environment.start_command", env.get("start_command")),
            ("runtime.health_check", runtime.get("health_check"), "dev_environment.health_check", env.get("health_check")),
            ("runtime.base_url", runtime.get("base_url"), "dev_environment.base_url", env.get("base_url")),
            ("runtime.healthy_signal", runtime.get("healthy_signal"), "dev_environment.ready_signal", env.get("ready_signal")),
            ("runtime.requires", runtime.get("requires"), "dev_environment.requires", env.get("requires")),
            ("test.command", test.get("command"), "dev_environment.test_command", env.get("test_command")),
        ]
        for left_name, left, right_name, right in comparisons:
            if left is None or right is None:
                continue
            if normalize(left) != normalize(right):
                errors.append(
                    "workspace-config conflict: "
                    f"{left_name}={json.dumps(left, ensure_ascii=False)} != "
                    f"{right_name}={json.dumps(right, ensure_ascii=False)}"
                )

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: handbook config valid: {config_path}")
PY
