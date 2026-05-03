#!/usr/bin/env bash
# scripts/start-test-env.sh — D11 L3 orchestrator.
#
# Chains the L2 env primitives in the canonical order required by
# engineering's runtime verification gate:
#
#   ensure-dependencies → install-project-deps → start-command → health-check
#   → [fixtures-start]
#
# Reads workspace-config.yaml + task.md to resolve which project to start,
# where its repo lives (cwd), and whether per-task fixtures need to come up.
# Each step's evidence is emitted as a JSON object on stdout; any failure is
# fatal (exit 1).
#
# Usage:
#   start-test-env.sh --task-md PATH  [--workspace-config PATH] [--repo PATH] [--with-fixtures] [--ready-timeout SECONDS]
#   start-test-env.sh --project NAME [--workspace-config PATH] [--repo PATH] [--with-fixtures] [--fixtures-dir PATH] [--epic NAME] [--ready-timeout SECONDS]
#
# When --task-md is used, the orchestrator extracts:
#   - project name from `test_environment.dev_env_config`
#   - fixtures dir from `test_environment.fixtures` (regex on `specs/.../mockoon/`)
# Falls back to --fixtures-dir if extraction fails AND --with-fixtures is on.
#
# Exit codes:
#   0  Every step PASS
#   1  Any step FAIL (fail-stop; downstream steps are skipped)
#   2  Usage error
#
# Stop semantics: this orchestrator only starts. Use mockoon-runner.sh stop +
# kill PIDs in /tmp/polaris-env-d11/ to tear down (a future stop-test-env.sh
# orchestrator may consolidate this).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/env"
# shellcheck source=env/_lib.sh
source "$ENV_DIR/_lib.sh"

ENSURE_DEPS="$ENV_DIR/ensure-dependencies.sh"
INSTALL_DEPS="$ENV_DIR/install-project-deps.sh"
START_CMD="$ENV_DIR/start-command.sh"
HEALTH_CHECK="$ENV_DIR/health-check.sh"
FIXTURES_START="$ENV_DIR/fixtures-start.sh"
HANDBOOK_READER="$SCRIPT_DIR/handbook-config-reader.sh"
HANDBOOK_VALIDATOR="$SCRIPT_DIR/handbook-config-validator.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") --task-md PATH  [--workspace-config PATH] [--repo PATH] [--with-fixtures] [--ready-timeout SECONDS]
  $(basename "$0") --project NAME [--workspace-config PATH] [--repo PATH] [--with-fixtures] [--fixtures-dir PATH] [--epic NAME] [--ready-timeout SECONDS]
  $(basename "$0") --project NAME --workspace-config PATH --resolve-config-only

Chains L2 primitives: ensure-dependencies → install-project-deps → start-command
→ health-check → [fixtures-start].

Exit:  0 = all PASS, 1 = first FAIL halts chain, 2 = usage error.
EOF
}

# ── Args ────────────────────────────────────────────────────────────────────
PROJECT=""
TASK_MD=""
WORKSPACE_CONFIG=""
REPO_OVERRIDE=""
WITH_FIXTURES=false
FIXTURES_DIR=""
EPIC=""
READY_TIMEOUT=120
RESOLVE_CONFIG_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --workspace-config) WORKSPACE_CONFIG="${2:-}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --with-fixtures) WITH_FIXTURES=true; shift ;;
    --fixtures-dir) FIXTURES_DIR="${2:-}"; shift 2 ;;
    --epic) EPIC="${2:-}"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="${2:-}"; shift 2 ;;
    --resolve-config-only) RESOLVE_CONFIG_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *) env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" && -z "$TASK_MD" ]]; then
  env_lib_log_fail "one of --project or --task-md is required"; usage; exit 2
fi

# ── Resolve workspace-config + project + cwd_base from task.md (if given) ───
if [[ -z "$WORKSPACE_CONFIG" ]]; then
  WORKSPACE_CONFIG="$(env_lib_find_workspace_config "$PWD" 2>/dev/null || true)"
fi

PROJECT_CWD=""
COMPANY_BASE_DIR=""

if [[ -n "$TASK_MD" ]]; then
  if [[ ! -f "$TASK_MD" ]]; then
    env_lib_log_fail "--task-md path not found: $TASK_MD"; exit 2
  fi
  parser="$SCRIPT_DIR/parse-task-md.sh"
  if [[ ! -x "$parser" ]]; then
    env_lib_log_fail "parse-task-md.sh not executable at $parser"; exit 1
  fi
  parsed_json="$("$parser" "$TASK_MD" 2>/dev/null || true)"
  if [[ -z "$parsed_json" ]]; then
    env_lib_log_fail "parse-task-md.sh produced no output for $TASK_MD"; exit 1
  fi

  if [[ -z "$PROJECT" ]]; then
    PROJECT=$(printf '%s' "$parsed_json" | python3 -c '
import json, re, sys
data = json.loads(sys.stdin.read() or "{}")
te = data.get("test_environment") or {}
cfg = te.get("dev_env_config") or ""
m = re.search(r"projects\[([^\]]+)\]\.dev_environment", cfg)
if m: print(m.group(1))
')
    if [[ -z "$PROJECT" ]]; then
      env_lib_log_fail "could not extract project name from $TASK_MD"; exit 1
    fi
  fi

  # Fixtures dir: try task.md `test_environment.fixtures` if --with-fixtures
  # was requested but no explicit --fixtures-dir was given.
  if $WITH_FIXTURES && [[ -z "$FIXTURES_DIR" ]]; then
    FIXTURES_DIR=$(printf '%s' "$parsed_json" | python3 -c '
import json, re, sys, os
data = json.loads(sys.stdin.read() or "{}")
te = data.get("test_environment") or {}
fx = te.get("fixtures") or ""
m = re.search(r"`?(specs/[^`\s]+/mockoon/?)`?", fx)
if m: print(m.group(1))
')
    if [[ -n "$FIXTURES_DIR" && "$FIXTURES_DIR" != /* ]]; then
      # Resolve relative path relative to the task.md's company dir.
      td="$(cd "$(dirname "$TASK_MD")" && pwd)"
      while [[ "$td" != "/" && ! -d "$td/specs" ]]; do
        td="$(dirname "$td")"
      done
      if [[ "$td" != "/" ]]; then
        FIXTURES_DIR="$td/$FIXTURES_DIR"
      fi
    fi
  fi
fi

if [[ -z "$WORKSPACE_CONFIG" || ! -f "$WORKSPACE_CONFIG" ]]; then
  env_lib_log_fail "workspace-config.yaml not found"; exit 1
fi

EFFECTIVE_WORKSPACE_CONFIG="$WORKSPACE_CONFIG"
RUNTIME_CONFIG_SOURCE="workspace_config"
EFFECTIVE_CONFIG_TMP=""

cleanup_effective_config() {
  if [[ -n "$EFFECTIVE_CONFIG_TMP" && -f "$EFFECTIVE_CONFIG_TMP" ]]; then
    rm -f "$EFFECTIVE_CONFIG_TMP"
  fi
  return 0
}
trap cleanup_effective_config EXIT

resolve_effective_workspace_config() {
  local company_dir project handbook_config validator_out
  company_dir="$(dirname "$WORKSPACE_CONFIG")"
  project="$PROJECT"
  handbook_config="$company_dir/polaris-config/$project/handbook/config.yaml"

  if [[ ! -f "$handbook_config" ]]; then
    env_lib_log_warn "handbook config missing for $project; falling back to workspace-config dev_environment"
    RUNTIME_CONFIG_SOURCE="workspace_config_fallback"
    EFFECTIVE_WORKSPACE_CONFIG="$WORKSPACE_CONFIG"
    return 0
  fi

  if [[ ! -x "$HANDBOOK_READER" || ! -x "$HANDBOOK_VALIDATOR" ]]; then
    env_lib_log_fail "handbook config scripts are not executable"
    exit 1
  fi

  if ! validator_out="$("$HANDBOOK_VALIDATOR" \
      --config "$handbook_config" \
      --project "$project" \
      --workspace-config "$WORKSPACE_CONFIG" \
      --require-section runtime \
      --check-conflicts 2>&1)"; then
    env_lib_log_fail "handbook config validation failed for $project"
    printf '%s\n' "$validator_out" >&2
    exit 1
  fi

  EFFECTIVE_CONFIG_TMP="$(mktemp /tmp/polaris-start-test-env-effective.XXXXXX)"
  python3 - "$WORKSPACE_CONFIG" "$handbook_config" "$project" "$EFFECTIVE_CONFIG_TMP" <<'PY'
import sys

try:
    import yaml
except Exception as exc:
    print(f"PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

workspace_path, handbook_path, project, out_path = sys.argv[1:5]

with open(workspace_path, encoding="utf-8") as handle:
    workspace = yaml.safe_load(handle) or {}
with open(handbook_path, encoding="utf-8") as handle:
    handbook = yaml.safe_load(handle) or {}

runtime = handbook.get("runtime") or {}
test = handbook.get("test") or {}
if not isinstance(runtime, dict):
    print("runtime section must be a mapping", file=sys.stderr)
    sys.exit(1)
if not isinstance(test, dict):
    test = {}

projects = workspace.get("projects") or []
target = None
for item in projects:
    if isinstance(item, dict) and item.get("name") == project:
        target = item
        break
if target is None:
    target = {"name": project}
    projects.append(target)
    workspace["projects"] = projects

env = target.get("dev_environment")
if not isinstance(env, dict):
    env = {}
    target["dev_environment"] = env

mapping = {
    "start_command": runtime.get("start_command"),
    "base_url": runtime.get("base_url"),
    "health_check": runtime.get("health_check"),
    "ready_signal": runtime.get("healthy_signal"),
    "requires": runtime.get("requires"),
    "test_command": test.get("command"),
}
for key, value in mapping.items():
    if value is not None:
        env[key] = value

with open(out_path, "w", encoding="utf-8") as handle:
    yaml.safe_dump(workspace, handle, allow_unicode=True, sort_keys=False)
PY
  RUNTIME_CONFIG_SOURCE="handbook_config"
  EFFECTIVE_WORKSPACE_CONFIG="$EFFECTIVE_CONFIG_TMP"
  env_lib_log_info "using handbook config for $project: $handbook_config"
}

resolve_effective_workspace_config

if $RESOLVE_CONFIG_ONLY; then
  env_json="$(env_lib_get_project_env "$EFFECTIVE_WORKSPACE_CONFIG" "$PROJECT" 2>/dev/null || true)"
  if [[ -z "$env_json" ]]; then
    env_lib_log_fail "project '$PROJECT' has no effective dev_environment"
    exit 1
  fi
  python3 - "$PROJECT" "$RUNTIME_CONFIG_SOURCE" "$EFFECTIVE_WORKSPACE_CONFIG" "$env_json" <<'PY'
import json
import sys
project, source, config_path, env_json = sys.argv[1:5]
print(json.dumps({
    "primitive": "start-test-env",
    "step": "resolve-config",
    "project": project,
    "source": source,
    "workspace_config": config_path,
    "dev_environment": json.loads(env_json),
}, ensure_ascii=False, sort_keys=True))
PY
  exit 0
fi

# ── Infer launch cwd from router's companies[].base_dir + project name ──────
# Best-effort. If the router config can't be located or the path doesn't
# exist, leave PROJECT_CWD empty and let start-command default to $PWD.
router_cfg=""
search="$(dirname "$WORKSPACE_CONFIG")"
search="$(dirname "$search")"
if [[ -f "$search/workspace-config.yaml" ]]; then
  router_cfg="$search/workspace-config.yaml"
fi
if [[ -n "$router_cfg" ]]; then
  base_dir=$(python3 -c '
import yaml, sys, os
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
target = data.get("default_company") or ""
out = ""
for c in data.get("companies", []) or []:
    if not target or c.get("name") == target:
        out = c.get("base_dir", "")
        break
if not out and data.get("companies"):
    out = data["companies"][0].get("base_dir", "")
print(os.path.expanduser(out))
' "$router_cfg")
  COMPANY_BASE_DIR="$base_dir"
  if [[ -n "$base_dir" && -d "$base_dir/$PROJECT" ]]; then
    PROJECT_CWD="$base_dir/$PROJECT"
  fi
fi

if [[ -n "$REPO_OVERRIDE" ]]; then
  PROJECT_CWD="$(cd "$(env_lib_expand_path "$REPO_OVERRIDE")" 2>/dev/null && pwd)" || {
    env_lib_log_fail "--repo path does not exist: $REPO_OVERRIDE"
    exit 2
  }
fi

env_lib_log_info "orchestrator config: project=$PROJECT, cwd=${PROJECT_CWD:-<PWD>}, fixtures=${WITH_FIXTURES} (${FIXTURES_DIR:-N/A})"

# ── Step 1: ensure-dependencies ─────────────────────────────────────────────
env_lib_log_info "Step 1/4: ensure-dependencies"
ed_args=("--project" "$PROJECT" "--workspace-config" "$EFFECTIVE_WORKSPACE_CONFIG" "--ready-timeout" "$READY_TIMEOUT")
if [[ -n "$PROJECT_CWD" ]]; then
  ed_args+=("--cwd-base" "${COMPANY_BASE_DIR:-$(dirname "$PROJECT_CWD")}")
fi
if ! "$ENSURE_DEPS" "${ed_args[@]}"; then
  env_lib_log_fail "Step 1/4 ensure-dependencies FAILED"
  exit 1
fi
echo "{\"primitive\":\"start-test-env\",\"step\":\"ensure-dependencies\",\"status\":\"PASS\"}"

# ── Step 2: install-project-deps (target project) ───────────────────────────
env_lib_log_info "Step 2/5: install-project-deps for $PROJECT"
id_args=("--project" "$PROJECT" "--workspace-config" "$EFFECTIVE_WORKSPACE_CONFIG")
[[ -n "$PROJECT_CWD" ]] && id_args+=("--cwd" "$PROJECT_CWD")
id_out="$("$INSTALL_DEPS" "${id_args[@]}")" || {
  env_lib_log_fail "Step 2/5 install-project-deps FAILED"
  exit 1
}
echo "{\"primitive\":\"start-test-env\",\"step\":\"install-project-deps\",\"status\":\"PASS\",\"detail\":$id_out}"

# ── Step 3: start-command (target project) ──────────────────────────────────
env_lib_log_info "Step 3/5: start-command for $PROJECT"
sc_args=("--project" "$PROJECT" "--workspace-config" "$EFFECTIVE_WORKSPACE_CONFIG" "--ready-timeout" "$READY_TIMEOUT")
[[ -n "$PROJECT_CWD" ]] && sc_args+=("--cwd" "$PROJECT_CWD")
sc_out="$("$START_CMD" "${sc_args[@]}")" || {
  env_lib_log_fail "Step 3/5 start-command FAILED"
  exit 1
}
# Surface the start-command JSON line as our own evidence too.
echo "{\"primitive\":\"start-test-env\",\"step\":\"start-command\",\"status\":\"PASS\",\"detail\":$sc_out}"

# ── Step 4: health-check (target project) ───────────────────────────────────
env_json="$(env_lib_get_project_env "$EFFECTIVE_WORKSPACE_CONFIG" "$PROJECT" 2>/dev/null || true)"
target_url="$(printf '%s' "$env_json" | env_lib_get_field 'health_check' 2>/dev/null || true)"
if [[ -z "$target_url" ]]; then
  env_lib_fail_loud_missing_field "$PROJECT" "health_check" "$EFFECTIVE_WORKSPACE_CONFIG" '"http://localhost:..."  # so the orchestrator can confirm liveness"'
  exit 1
fi
env_lib_log_info "Step 4/5: health-check $target_url"
if ! "$HEALTH_CHECK" "$target_url" --timeout "$READY_TIMEOUT" --interval 2 > /dev/null; then
  env_lib_log_fail "Step 4/5 health-check FAILED for $target_url"
  exit 1
fi
echo "{\"primitive\":\"start-test-env\",\"step\":\"health-check\",\"status\":\"PASS\",\"url\":\"$target_url\"}"

# ── Step 5 (optional): fixtures-start ───────────────────────────────────────
if $WITH_FIXTURES; then
  if [[ -z "$FIXTURES_DIR" ]]; then
    env_lib_log_fail "--with-fixtures requested but FIXTURES_DIR could not be resolved"
    exit 1
  fi
  env_lib_log_info "Step 5/5: fixtures-start $FIXTURES_DIR"
  fx_args=("$FIXTURES_DIR")
  [[ -n "$EPIC" ]] && fx_args+=("--epic" "$EPIC")
  if ! "$FIXTURES_START" "${fx_args[@]}" > /dev/null; then
    env_lib_log_fail "Step 5/5 fixtures-start FAILED"
    exit 1
  fi
  echo "{\"primitive\":\"start-test-env\",\"step\":\"fixtures-start\",\"status\":\"PASS\",\"path\":\"$FIXTURES_DIR\"}"
else
  env_lib_log_info "Step 5/5: fixtures-start SKIPPED (no --with-fixtures)"
  echo "{\"primitive\":\"start-test-env\",\"step\":\"fixtures-start\",\"status\":\"SKIP\"}"
fi

env_lib_log_pass "start-test-env: all steps PASS for $PROJECT"
echo "{\"primitive\":\"start-test-env\",\"summary\":true,\"project\":\"$PROJECT\",\"status\":\"PASS\"}"
