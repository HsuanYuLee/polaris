#!/usr/bin/env bash
# scripts/env/start-command.sh — D11 L2 primitive.
#
# Reads `dev_environment.start_command` (and optionally `ready_signal`) for a
# project from workspace-config.yaml, launches the command in the background,
# and (when ready_signal is declared) tails the log until the signal appears.
#
# Usage:
#   start-command.sh --project NAME [--workspace-config PATH] [--cwd DIR] [--ready-timeout SECONDS]
#   start-command.sh --task-md PATH  [--workspace-config PATH] [--cwd DIR] [--ready-timeout SECONDS]
#
# --cwd controls the working directory for the launched start_command. If
# omitted, the script runs in $PWD (matching standard bash semantics). The L3
# orchestrator is responsible for passing the project's repo path; the L2
# primitive intentionally does not infer cwd from the project name.
#
# Exit codes:
#   0  Process launched (and ready_signal observed if declared)
#   1  Config field missing (fail-loud) / launch failed / ready_signal timeout
#   2  Usage error
#
# Stdout: single-line JSON for orchestrators to parse:
#   {"primitive":"start-command","project":"...","pid":1234,"log":"/tmp/...","status":"ready|launched-no-signal"}
# Stderr: human-readable progress.
#
# State files (predictable so orchestrator / stop primitive can find them):
#   /tmp/polaris-env-d11/{project}.pid
#   /tmp/polaris-env-d11/{project}.log
#
# Fail-loud per D11: if start_command is missing from the project's
# dev_environment, exits 1 with an actionable message pointing at
# workspace-config.yaml. NO codebase inference, NO defaults.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

STATE_DIR="/tmp/polaris-env-d11"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") --project NAME [--workspace-config PATH] [--ready-timeout SECONDS]
       $(basename "$0") --task-md PATH  [--workspace-config PATH] [--ready-timeout SECONDS]

Launches dev_environment.start_command for the given project; waits for
ready_signal in the log if declared.

Exit:  0 = launched (and ready), 1 = launch fail / config missing, 2 = usage.
EOF
}

# ── Args ────────────────────────────────────────────────────────────────────
PROJECT=""
TASK_MD=""
WORKSPACE_CONFIG=""
READY_TIMEOUT=120
CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --workspace-config) WORKSPACE_CONFIG="${2:-}"; shift 2 ;;
    --ready-timeout) READY_TIMEOUT="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *) env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" && -z "$TASK_MD" ]]; then
  env_lib_log_fail "one of --project or --task-md is required"
  usage; exit 2
fi
if ! [[ "$READY_TIMEOUT" =~ ^[0-9]+$ ]]; then
  env_lib_log_fail "--ready-timeout must be an integer"; exit 2
fi

# ── Resolve project name from --task-md if needed ───────────────────────────
if [[ -z "$PROJECT" ]]; then
  if [[ ! -f "$TASK_MD" ]]; then
    env_lib_log_fail "--task-md path not found: $TASK_MD"; exit 2
  fi
  # Extract project from test_environment.dev_env_config via the standard
  # `projects[NAME].dev_environment` pattern. parse-task-md.sh is the
  # authoritative parser; we shell out to it for consistency.
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
    echo "Expected pattern: 'workspace-config.yaml → projects[<NAME>].dev_environment'" >&2
    exit 1
  fi
fi

# ── Resolve workspace-config ────────────────────────────────────────────────
if [[ -z "$WORKSPACE_CONFIG" ]]; then
  start_dir="$PWD"
  [[ -n "$TASK_MD" ]] && start_dir="$(dirname "$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")")"
  WORKSPACE_CONFIG="$(env_lib_find_workspace_config "$start_dir" 2>/dev/null || true)"
fi
if [[ -z "$WORKSPACE_CONFIG" || ! -f "$WORKSPACE_CONFIG" ]]; then
  env_lib_log_fail "workspace-config.yaml not found (use --workspace-config to specify)"
  exit 1
fi

# ── Read project env block ──────────────────────────────────────────────────
env_json="$(env_lib_get_project_env "$WORKSPACE_CONFIG" "$PROJECT" 2>/dev/null || true)"
if [[ -z "$env_json" ]]; then
  env_lib_log_fail "project '$PROJECT' has no dev_environment in $WORKSPACE_CONFIG"
  echo "Hint: declare 'dev_environment' under projects[name=$PROJECT] in that file." >&2
  exit 1
fi

start_command="$(printf '%s' "$env_json" | env_lib_get_field 'start_command' 2>/dev/null || true)"
if [[ -z "$start_command" ]]; then
  env_lib_fail_loud_missing_field "$PROJECT" "start_command" "$WORKSPACE_CONFIG" '"<command to launch>"'
  exit 1
fi

ready_signal="$(printf '%s' "$env_json" | env_lib_get_field 'ready_signal' 2>/dev/null || true)"

# ── Launch ──────────────────────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/${PROJECT}.log"
PID_FILE="$STATE_DIR/${PROJECT}.pid"

# Stop a previous run for the same project if its PID is still alive — keeps
# repeated invocations idempotent (matches polaris-env.sh's kill-stale pattern
# but only for this project's tracked PID).
if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    env_lib_log_warn "killing previous start-command pid $old_pid for $PROJECT"
    kill "$old_pid" 2>/dev/null || true
    sleep 1
    kill -0 "$old_pid" 2>/dev/null && kill -9 "$old_pid" 2>/dev/null || true
  fi
fi

: > "$LOG_FILE"
launch_cwd="${CWD:-$PWD}"
launch_cwd="$(env_lib_expand_path "$launch_cwd")"
if [[ ! -d "$launch_cwd" ]]; then
  env_lib_log_fail "--cwd path does not exist: $launch_cwd"; exit 1
fi
env_lib_log_info "launching '$start_command' for $PROJECT in $launch_cwd (log: $LOG_FILE)"
# Use `exec` inside bash -c so PID becomes the actual launched process (not
# an intermediate shell). This makes a subsequent `kill $PID` actually stop
# the worker rather than orphaning a child.
bash -c "cd '$launch_cwd' && exec $start_command" >> "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

# Quick sanity: does the process die immediately?
sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
  env_lib_log_fail "start_command died immediately for $PROJECT (log tail below)"
  tail -20 "$LOG_FILE" >&2 || true
  rm -f "$PID_FILE"
  exit 1
fi

# ── Wait for ready_signal (when declared) ───────────────────────────────────
status="launched-no-signal"
if [[ -n "$ready_signal" ]]; then
  env_lib_log_info "waiting for ready_signal '$ready_signal' (timeout ${READY_TIMEOUT}s)"
  elapsed=0
  while [[ $elapsed -lt $READY_TIMEOUT ]]; do
    if grep -q -F -- "$ready_signal" "$LOG_FILE" 2>/dev/null; then
      status="ready"; break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      env_lib_log_fail "process died before ready_signal observed; log tail below"
      tail -20 "$LOG_FILE" >&2 || true
      rm -f "$PID_FILE"
      exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  if [[ "$status" != "ready" ]]; then
    env_lib_log_fail "ready_signal '$ready_signal' not seen in ${READY_TIMEOUT}s; log tail below"
    tail -20 "$LOG_FILE" >&2 || true
    # Leave process running — orchestrator may still want to inspect it. Caller
    # decides whether to kill via PID file.
    exit 1
  fi
fi

env_lib_log_pass "$PROJECT launched (pid=$PID, status=$status)"
python3 -c '
import json, sys
project, pid, log, status = sys.argv[1:5]
print(json.dumps({
  "primitive": "start-command",
  "project": project,
  "pid": int(pid),
  "log": log,
  "status": status,
}))
' "$PROJECT" "$PID" "$LOG_FILE" "$status"
