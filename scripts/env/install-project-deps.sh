#!/usr/bin/env bash
# scripts/env/install-project-deps.sh — Install project dependencies for a
# fresh checkout / worktree before tests or dev-server launch.
#
# Resolution order:
#   1. workspace-config.yaml → projects[].dev_environment.install_command
#   2. deterministic detector from manifest / lockfile in --cwd
#
# Usage:
#   install-project-deps.sh --project NAME [--workspace-config PATH] [--cwd DIR]
#   install-project-deps.sh --task-md PATH  [--workspace-config PATH] [--cwd DIR]
#
# Exit codes:
#   0  PASS (install succeeded or no known package manager / noop)
#   1  Config missing / install failed
#   2  Usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") --project NAME [--workspace-config PATH] [--cwd DIR]
       $(basename "$0") --task-md PATH  [--workspace-config PATH] [--cwd DIR]

Installs project dependencies before tests / local runtime start.
Uses dev_environment.install_command when declared; otherwise falls back to a
deterministic manifest detector in the target cwd.
EOF
}

PROJECT=""
TASK_MD=""
WORKSPACE_CONFIG=""
CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --workspace-config) WORKSPACE_CONFIG="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *) env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" && -z "$TASK_MD" ]]; then
  env_lib_log_fail "one of --project or --task-md is required"
  usage
  exit 2
fi

if [[ -z "$PROJECT" ]]; then
  if [[ ! -f "$TASK_MD" ]]; then
    env_lib_log_fail "--task-md path not found: $TASK_MD"; exit 2
  fi
  parser="$(cd "$SCRIPT_DIR/.." && pwd)/parse-task-md.sh"
  if [[ ! -x "$parser" ]]; then
    env_lib_log_fail "parse-task-md.sh not executable at $parser"; exit 1
  fi
  PROJECT=$("$parser" "$TASK_MD" 2>/dev/null | python3 -c '
import json, re, sys
data = json.loads(sys.stdin.read() or "{}")
te = data.get("test_environment") or {}
cfg = te.get("dev_env_config") or ""
m = re.search(r"projects\[([^\]]+)\]\.dev_environment", cfg)
if m: print(m.group(1))
')
  if [[ -z "$PROJECT" ]]; then
    env_lib_log_fail "could not extract project name from $TASK_MD test_environment.dev_env_config"
    exit 1
  fi
fi

if [[ -z "$WORKSPACE_CONFIG" ]]; then
  start_dir="${CWD:-$PWD}"
  [[ -n "$TASK_MD" ]] && start_dir="$(dirname "$TASK_MD")"
  WORKSPACE_CONFIG="$(env_lib_find_workspace_config "$start_dir" 2>/dev/null || true)"
fi
if [[ -z "$WORKSPACE_CONFIG" || ! -f "$WORKSPACE_CONFIG" ]]; then
  env_lib_log_fail "workspace-config.yaml not found (use --workspace-config to specify)"
  exit 1
fi

env_json="$(env_lib_get_project_env "$WORKSPACE_CONFIG" "$PROJECT" 2>/dev/null || true)"
if [[ -z "$env_json" ]]; then
  env_lib_log_fail "project '$PROJECT' has no dev_environment in $WORKSPACE_CONFIG"
  exit 1
fi

install_command="$(printf '%s' "$env_json" | env_lib_get_field 'install_command' 2>/dev/null || true)"
mode="configured"
target_cwd="${CWD:-$PWD}"
target_cwd="$(env_lib_expand_path "$target_cwd")"
if [[ ! -d "$target_cwd" ]]; then
  env_lib_log_fail "--cwd path does not exist: $target_cwd"
  exit 1
fi

detect_install_command() {
  local cwd="$1"
  if [[ -f "$cwd/pnpm-lock.yaml" || -f "$cwd/pnpm-workspace.yaml" ]]; then
    printf '%s\n' "pnpm install --frozen-lockfile"
    return 0
  fi
  if [[ -f "$cwd/package-lock.json" ]]; then
    printf '%s\n' "npm ci"
    return 0
  fi
  if [[ -f "$cwd/yarn.lock" ]]; then
    printf '%s\n' "yarn install --frozen-lockfile"
    return 0
  fi
  if [[ -f "$cwd/bun.lockb" || -f "$cwd/bun.lock" ]]; then
    printf '%s\n' "bun install --frozen-lockfile"
    return 0
  fi
  if [[ -f "$cwd/Gemfile.lock" || -f "$cwd/Gemfile" ]]; then
    printf '%s\n' "bundle install"
    return 0
  fi
  if [[ -f "$cwd/poetry.lock" ]]; then
    printf '%s\n' "poetry install --sync"
    return 0
  fi
  if [[ -f "$cwd/requirements.txt" ]]; then
    printf '%s\n' "python3 -m pip install -r requirements.txt"
    return 0
  fi
  if [[ -f "$cwd/composer.lock" || -f "$cwd/composer.json" ]]; then
    printf '%s\n' "composer install"
    return 0
  fi
  if [[ -f "$cwd/go.mod" ]]; then
    printf '%s\n' "go mod download"
    return 0
  fi
  if [[ -f "$cwd/Cargo.lock" || -f "$cwd/Cargo.toml" ]]; then
    printf '%s\n' "cargo fetch"
    return 0
  fi
  return 1
}

if [[ -z "$install_command" ]]; then
  mode="detected"
  install_command="$(detect_install_command "$target_cwd" || true)"
fi

if [[ -z "$install_command" ]]; then
  env_lib_log_warn "no install_command configured and no known dependency manifest found in $target_cwd — treating as noop"
  python3 -c '
import json, sys
print(json.dumps({
  "primitive": "install-project-deps",
  "project": sys.argv[1],
  "status": "PASS",
  "mode": "noop",
  "cwd": sys.argv[2],
}))
' "$PROJECT" "$target_cwd"
  exit 0
fi

env_lib_log_info "installing deps for $PROJECT in $target_cwd via [$mode] '$install_command'"
if ! bash -c "cd '$target_cwd' && $install_command"; then
  env_lib_log_fail "dependency install failed for $PROJECT"
  exit 1
fi

env_lib_log_pass "dependencies ready for $PROJECT"
python3 -c '
import json, sys
print(json.dumps({
  "primitive": "install-project-deps",
  "project": sys.argv[1],
  "status": "PASS",
  "mode": sys.argv[2],
  "command": sys.argv[3],
  "cwd": sys.argv[4],
}))
' "$PROJECT" "$mode" "$install_command" "$target_cwd"
