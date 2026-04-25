#!/usr/bin/env bash
# scripts/env/_lib.sh — Shared helpers for D11 L2 env primitives.
#
# Sourced (not executed) by ensure-dependencies.sh / start-command.sh /
# health-check.sh / fixtures-start.sh. Keeps the primitives self-contained
# while avoiding ~5-line python3 yaml block duplication × 4.
#
# Public functions:
#   env_lib_find_workspace_config [START_DIR]
#   env_lib_parse_yaml YAML_PATH
#   env_lib_get_project_env CONFIG_JSON PROJECT_NAME
#   env_lib_get_field JSON DOTTED_PATH
#   env_lib_expand_path PATH
#   env_lib_fail_loud_missing_field PROJECT FIELD CONFIG_PATH [SCHEMA_HINT]
#   env_lib_log_pass MSG
#   env_lib_log_fail MSG
#   env_lib_log_warn MSG

set -u

# ── Logging ─────────────────────────────────────────────────────────────────
if [[ -t 2 ]]; then
  _ENV_LIB_GREEN="\033[0;32m"
  _ENV_LIB_RED="\033[0;31m"
  _ENV_LIB_YELLOW="\033[0;33m"
  _ENV_LIB_RESET="\033[0m"
else
  _ENV_LIB_GREEN=""; _ENV_LIB_RED=""; _ENV_LIB_YELLOW=""; _ENV_LIB_RESET=""
fi

env_lib_log_pass() { printf "${_ENV_LIB_GREEN}[PASS]${_ENV_LIB_RESET} %s\n" "$*" >&2; }
env_lib_log_fail() { printf "${_ENV_LIB_RED}[FAIL]${_ENV_LIB_RESET} %s\n" "$*" >&2; }
env_lib_log_warn() { printf "${_ENV_LIB_YELLOW}[WARN]${_ENV_LIB_RESET} %s\n" "$*" >&2; }
env_lib_log_info() { printf "[INFO] %s\n" "$*" >&2; }

# ── Path expansion (handles leading ~) ──────────────────────────────────────
env_lib_expand_path() {
  local p="${1:-}"
  [[ -z "$p" ]] && { echo ""; return 0; }
  if [[ "$p" == "~"* ]]; then
    p="${HOME}${p:1}"
  fi
  echo "$p"
}

# ── workspace-config.yaml discovery (walk up from START_DIR) ─────────────────
# The Polaris workspace has two config layers:
#   1. ROOT router (e.g. /Users/x/work/workspace-config.yaml) — has `companies[]`
#   2. COMPANY config (e.g. /Users/x/work/kkday/workspace-config.yaml) — has
#      `projects[]` with `dev_environment` (the data L2 primitives need).
#
# This function returns the COMPANY config absolute path. Walks up from
# START_DIR; if it finds a router first, follows `default_company` (or first
# `companies[].base_dir`) to resolve the company config.
#
# Honors POLARIS_WORKSPACE_CONFIG env var as override (must point to a
# company-level config, not the router).
env_lib_find_workspace_config() {
  if [[ -n "${POLARIS_WORKSPACE_CONFIG:-}" ]]; then
    [[ -f "$POLARIS_WORKSPACE_CONFIG" ]] && { echo "$POLARIS_WORKSPACE_CONFIG"; return 0; }
    return 1
  fi
  local start="${1:-$PWD}"
  start="$(cd "$start" 2>/dev/null && pwd)" || return 1
  local cur="$start"
  while [[ "$cur" != "/" && -n "$cur" ]]; do
    if [[ -f "$cur/workspace-config.yaml" ]]; then
      _env_lib_resolve_company_config "$cur/workspace-config.yaml" && return 0
    fi
    # Check direct child (typical: /Users/x/work/kkday/workspace-config.yaml).
    # Skip _template/ — it's a scaffolding stub, not a real config.
    for child in "$cur"/*/workspace-config.yaml; do
      [[ -f "$child" ]] || continue
      [[ "$child" == */_template/* ]] && continue
      _env_lib_resolve_company_config "$child" && return 0
    done
    cur="$(dirname "$cur")"
  done
  return 1
}

# Internal: given a workspace-config.yaml path, return it if it's a company
# config (has `projects[]`), or resolve to the company config via the router's
# `default_company` / first `companies[].base_dir` field.
_env_lib_resolve_company_config() {
  local path="$1"
  local kind
  kind=$(python3 - "$path" <<'PY'
import yaml, sys, os
p = sys.argv[1]
with open(p) as f:
    data = yaml.safe_load(f) or {}
if data.get('projects'):
    print('company')
elif data.get('companies'):
    target = data.get('default_company') or ''
    base_dir = ''
    for c in data['companies']:
        if target and c.get('name') == target:
            base_dir = c.get('base_dir', ''); break
    if not base_dir and data['companies']:
        base_dir = data['companies'][0].get('base_dir', '')
    if base_dir.startswith('~'):
        base_dir = os.path.expanduser(base_dir)
    print(f"router:{base_dir}")
else:
    print('unknown')
PY
)
  case "$kind" in
    company) echo "$path"; return 0 ;;
    router:*)
      local base="${kind#router:}"
      if [[ -n "$base" && -f "$base/workspace-config.yaml" ]]; then
        echo "$base/workspace-config.yaml"
        return 0
      fi
      return 1 ;;
    *) return 1 ;;
  esac
}

# ── YAML parsing (yaml → json via python3) ──────────────────────────────────
env_lib_parse_yaml() {
  local yaml_path="$1"
  python3 -c "
import yaml, json, sys
with open('$yaml_path') as f: print(json.dumps(yaml.safe_load(f) or {}))
"
}

# ── JSON field extraction (dotted path; supports list[index]) ───────────────
# JSON is read from stdin; PATH is the only positional arg.
# Returns the field value as JSON-encoded scalar / object / list on stdout.
# Exit 1 with empty stdout if the path is missing or the value is null.
#
# Note: heredocs would shadow the piped stdin (parse-task-md.sh selftest
# memory), so this uses `python3 -c '...'`.
env_lib_get_field() {
  local path="$1"
  PYPATH="$path" python3 -c '
import json, os, sys
path = os.environ["PYPATH"]
data = json.loads(sys.stdin.read() or "{}")
cur = data
for part in path.split("."):
    if part == "":
        continue
    if "[" in part:
        key, idx = part.rstrip("]").split("[")
        if key:
            if not isinstance(cur, dict) or key not in cur:
                sys.exit(1)
            cur = cur[key]
        if not isinstance(cur, list) or int(idx) >= len(cur):
            sys.exit(1)
        cur = cur[int(idx)]
    else:
        if not isinstance(cur, dict) or part not in cur:
            sys.exit(1)
        cur = cur[part]
if cur is None:
    sys.exit(1)
if isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
'
}

# ── Project env extraction (returns dev_environment JSON for a project) ─────
# Stdout: dev_environment JSON object (or empty + exit 1 if project not found
# or has no dev_environment). Exits 1 only on lookup failure; the *missing
# field* fail-loud is up to each primitive (depending on which sub-field it
# requires).
env_lib_get_project_env() {
  local config_path="$1" project="$2"
  python3 - "$config_path" "$project" <<'PY'
import yaml, json, sys
config_path, project = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    data = yaml.safe_load(f) or {}
for p in (data.get('projects') or []):
    if p.get('name') == project:
        env = p.get('dev_environment')
        if env is None:
            sys.exit(1)
        print(json.dumps(env))
        sys.exit(0)
sys.exit(1)
PY
}

# ── Fail-loud helper ────────────────────────────────────────────────────────
# Prints an actionable error message and returns 1. Caller decides exit.
env_lib_fail_loud_missing_field() {
  local project="$1" field="$2" config_path="$3" schema_hint="${4:-}"
  env_lib_log_fail "project '$project' missing required field 'dev_environment.$field' in workspace-config.yaml"
  echo "" >&2
  echo "Config file: $config_path" >&2
  echo "" >&2
  echo "請在該檔的 projects[] 區塊宣告 '$field' 欄位。例如：" >&2
  echo "" >&2
  echo "  projects:" >&2
  echo "    - name: $project" >&2
  echo "      dev_environment:" >&2
  if [[ -n "$schema_hint" ]]; then
    echo "        $field: $schema_hint" >&2
  else
    echo "        $field: <value>" >&2
  fi
  echo "" >&2
  echo "（DP-035 上線後 handbook/config.yaml 為主要來源；目前過渡期讀 workspace-config.yaml）" >&2
  return 1
}

# Mark lib as loaded (sentinel for callers that source it conditionally)
ENV_LIB_LOADED=1
