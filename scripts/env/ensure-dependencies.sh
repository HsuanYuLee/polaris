#!/usr/bin/env bash
# scripts/env/ensure-dependencies.sh — D11 L2 primitive.
#
# Walks `dev_environment.requires[]` for the given project; for each dependency
# already healthy (its health_check URL returns 2xx), records PASS and moves
# on. For deps that are not healthy, dispatches start-command.sh +
# health-check.sh on each one and reports per-dep status.
#
# Usage:
#   ensure-dependencies.sh --project NAME [--workspace-config PATH] [--cwd-base DIR] [--ready-timeout SECONDS]
#   ensure-dependencies.sh --task-md PATH  [--workspace-config PATH] [--cwd-base DIR] [--ready-timeout SECONDS]
#
# --cwd-base lets the orchestrator point at a directory under which each
# dependency project lives (typical: the company base_dir; each project's
# launch cwd is inferred as "{cwd-base}/{project-name}"). Optional; if absent,
# dependencies launch in $PWD.
#
# Exit codes:
#   0  Every dep is healthy (started or already up)
#   1  Config missing required `requires` field, or one or more deps failed
#   2  Usage error
#
# Stdout: one JSON object per line, plus a final summary line:
#   {"primitive":"ensure-dependencies","dep":"...","action":"already-healthy|started","health":"PASS"}
#   {"primitive":"ensure-dependencies","summary":true,"project":"...","total":N,"ok":N,"failed":0}
# Stderr: human-readable progress.
#
# Fail-loud per D11: missing `requires` key in dev_environment is an
# actionable failure, not a silent default-to-empty.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

START_CMD="$SCRIPT_DIR/start-command.sh"
HEALTH_CHECK="$SCRIPT_DIR/health-check.sh"

dep_has_docker_tag() {
  local dep="$1" config="$2"
  python3 - "$config" "$dep" <<'PY'
import sys, yaml
config, dep = sys.argv[1], sys.argv[2]
with open(config) as f:
    data = yaml.safe_load(f) or {}
for p in data.get("projects", []) or []:
    if p.get("name") == dep:
        print("yes" if "docker" in (p.get("tags") or []) else "no")
        raise SystemExit(0)
print("no")
PY
}

health_url_port() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if u.port:
    print(u.port)
elif u.scheme == "https":
    print(443)
elif u.scheme == "http":
    print(80)
PY
}

port_listening() {
  local port="$1"
  [[ -n "$port" ]] || return 1
  lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1
}

dep_health_passes() {
  local dep="$1" url="$2" timeout="${3:-4}" interval="${4:-2}"
  if [[ "$(dep_has_docker_tag "$dep" "$WORKSPACE_CONFIG")" == "yes" ]]; then
    port_listening "$(health_url_port "$url")"
  else
    "$HEALTH_CHECK" "$url" --timeout "$timeout" --interval "$interval" > /dev/null 2>&1
  fi
}

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") --project NAME [--workspace-config PATH] [--cwd-base DIR] [--ready-timeout SECONDS]
       $(basename "$0") --task-md PATH  [--workspace-config PATH] [--cwd-base DIR] [--ready-timeout SECONDS]

Walks projects[NAME].dev_environment.requires[]; ensures each dep is healthy
by skipping if up, or invoking start-command.sh + health-check.sh otherwise.

Exit:  0 = all deps healthy, 1 = config missing or any dep failed, 2 = usage.
EOF
}

# ── Args ────────────────────────────────────────────────────────────────────
PROJECT=""
TASK_MD=""
WORKSPACE_CONFIG=""
CWD_BASE=""
READY_TIMEOUT=120

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --workspace-config) WORKSPACE_CONFIG="${2:-}"; shift 2 ;;
    --cwd-base) CWD_BASE="${2:-}"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *) env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" && -z "$TASK_MD" ]]; then
  env_lib_log_fail "one of --project or --task-md is required"; usage; exit 2
fi

# ── Resolve PROJECT from --task-md ──────────────────────────────────────────
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

# ── Resolve workspace-config ────────────────────────────────────────────────
if [[ -z "$WORKSPACE_CONFIG" ]]; then
  WORKSPACE_CONFIG="$(env_lib_find_workspace_config "$PWD" 2>/dev/null || true)"
fi
if [[ -z "$WORKSPACE_CONFIG" || ! -f "$WORKSPACE_CONFIG" ]]; then
  env_lib_log_fail "workspace-config.yaml not found (use --workspace-config)"; exit 1
fi

# ── Read project env block + requires[] ─────────────────────────────────────
env_json="$(env_lib_get_project_env "$WORKSPACE_CONFIG" "$PROJECT" 2>/dev/null || true)"
if [[ -z "$env_json" ]]; then
  env_lib_log_fail "project '$PROJECT' has no dev_environment in $WORKSPACE_CONFIG"
  exit 1
fi

requires_json="$(printf '%s' "$env_json" | env_lib_get_field 'requires' 2>/dev/null || true)"
if [[ -z "$requires_json" ]]; then
  env_lib_fail_loud_missing_field "$PROJECT" "requires" "$WORKSPACE_CONFIG" '[]   # empty list when there are no dependencies'
  exit 1
fi

# Empty requires list is a valid "no deps" declaration → nothing to do.
deps=()
while IFS= read -r d; do
  [[ -n "$d" ]] && deps+=("$d")
done < <(printf '%s' "$requires_json" | python3 -c '
import json, sys
data = json.loads(sys.stdin.read() or "[]")
if isinstance(data, list):
    for d in data:
        print(d)
')

if [[ ${#deps[@]} -eq 0 ]]; then
  env_lib_log_pass "$PROJECT has no dependencies (requires=[])"
  python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","summary":True,"project":sys.argv[1],"total":0,"ok":0,"failed":0}))
' "$PROJECT"
  exit 0
fi

# ── Process each dep ────────────────────────────────────────────────────────
total="${#deps[@]}"
ok=0
failed=0
env_lib_log_info "ensuring ${total} dep(s) for $PROJECT: ${deps[*]}"

for dep in "${deps[@]}"; do
  dep_env="$(env_lib_get_project_env "$WORKSPACE_CONFIG" "$dep" 2>/dev/null || true)"
  if [[ -z "$dep_env" ]]; then
    env_lib_log_fail "dep '$dep' has no dev_environment in $WORKSPACE_CONFIG (declared as requires of $PROJECT)"
    failed=$((failed + 1))
    python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"missing-config","health":"FAIL"}))
' "$dep"
    continue
  fi

  dep_health_url="$(printf '%s' "$dep_env" | env_lib_get_field 'health_check' 2>/dev/null || true)"
  if [[ -z "$dep_health_url" ]]; then
    env_lib_fail_loud_missing_field "$dep" "health_check" "$WORKSPACE_CONFIG" '"http://localhost:..."  # declared so ensure-dependencies can verify'
    failed=$((failed + 1))
    python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"missing-config","health":"FAIL"}))
' "$dep"
    continue
  fi

  # Step A: probe health (fast — 4s window for "is it already up?")
  if dep_health_passes "$dep" "$dep_health_url" 4 2; then
    env_lib_log_pass "dep '$dep' already healthy"
    ok=$((ok + 1))
    python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"already-healthy","health":"PASS"}))
' "$dep"
    continue
  fi

  # Step B: start it. If a --cwd-base was given, infer the dep's launch dir;
  # otherwise let start-command run in $PWD (the caller's responsibility).
  start_args=("--project" "$dep" "--workspace-config" "$WORKSPACE_CONFIG" "--ready-timeout" "$READY_TIMEOUT")
  if [[ -n "$CWD_BASE" ]]; then
    inferred_cwd="$(env_lib_expand_path "$CWD_BASE")/$dep"
    if [[ -d "$inferred_cwd" ]]; then
      start_args+=("--cwd" "$inferred_cwd")
    else
      env_lib_log_warn "inferred dep cwd does not exist, falling back to PWD: $inferred_cwd"
    fi
  fi

  env_lib_log_info "starting dep '$dep'"
  if "$START_CMD" "${start_args[@]}" > /dev/null; then
    if dep_health_passes "$dep" "$dep_health_url" "$READY_TIMEOUT" 2; then
      env_lib_log_pass "dep '$dep' started and healthy"
      ok=$((ok + 1))
      python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"started","health":"PASS"}))
' "$dep"
    else
      env_lib_log_fail "dep '$dep' started but health-check failed"
      failed=$((failed + 1))
      python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"started","health":"FAIL"}))
' "$dep"
    fi
  else
    env_lib_log_fail "dep '$dep' start-command failed"
    failed=$((failed + 1))
    python3 -c '
import json, sys
print(json.dumps({"primitive":"ensure-dependencies","dep":sys.argv[1],"action":"start-fail","health":"FAIL"}))
' "$dep"
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────
python3 -c '
import json, sys
print(json.dumps({
  "primitive": "ensure-dependencies",
  "summary": True,
  "project": sys.argv[1],
  "total": int(sys.argv[2]),
  "ok": int(sys.argv[3]),
  "failed": int(sys.argv[4]),
}))
' "$PROJECT" "$total" "$ok" "$failed"

if [[ $failed -gt 0 ]]; then
  env_lib_log_fail "$failed of $total dep(s) failed for $PROJECT"
  exit 1
fi
env_lib_log_pass "$ok/$total dep(s) healthy for $PROJECT"
exit 0
