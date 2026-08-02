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
#   0  Process launched (and ready_signal observed if declared), or completed
#      immediately with exit 0 (for one-shot start commands such as docker up -d)
#   1  Config field missing (fail-loud) / launch failed / ready_signal timeout
#   2  Usage error
#
# Stdout: single-line JSON for orchestrators to parse:
#   {"primitive":"start-command","project":"...","pid":1234,"log":"/tmp/...","status":"ready|launched-no-signal|completed"}
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

start_command_extract_loopback_port() {
  local url="$1"
  python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse

raw = sys.argv[1].strip()
if not raw:
    sys.exit(0)
parsed = urlparse(raw)
host = (parsed.hostname or "").lower()
if host not in {"localhost", "127.0.0.1", "0.0.0.0", "::1"}:
    sys.exit(0)
if parsed.port:
    print(parsed.port)
elif parsed.scheme == "http":
    print(80)
elif parsed.scheme == "https":
    print(443)
PY
}

start_command_pid_cwd() {
  local pid="$1"
  lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | awk '/^n/ { sub(/^n/, ""); print; exit }'
}

start_command_path_within() {
  local child="$1"
  local parent="$2"
  python3 - "$child" "$parent" <<'PY'
import os
import sys

child = os.path.realpath(sys.argv[1])
parent = os.path.realpath(sys.argv[2])
try:
    common = os.path.commonpath([child, parent])
except ValueError:
    sys.exit(1)
sys.exit(0 if common == parent else 1)
PY
}

start_command_pid_tracked_by_other_project() {
  local pid="$1"
  local pid_file=""
  local tracked_pid=""

  for pid_file in "$STATE_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    [[ "$pid_file" == "$PID_FILE" ]] && continue
    tracked_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ "$tracked_pid" == "$pid" ]]; then
      return 0
    fi
  done
  return 1
}

start_command_kill_pid_or_group() {
  local pid="$1"
  local reason="$2"
  local pgid=""
  local self_pgid=""

  pgid="$(ps -p "$pid" -o pgid= 2>/dev/null | tr -d '[:space:]' || true)"
  self_pgid="$(ps -p "$$" -o pgid= 2>/dev/null | tr -d '[:space:]' || true)"
  env_lib_log_warn "killing $reason pid $pid for $PROJECT"
  if [[ -n "$pgid" && "$pgid" != "$self_pgid" ]]; then
    kill "-$pgid" 2>/dev/null || true
  else
    kill "$pid" 2>/dev/null || true
  fi
  sleep 1
  if [[ -n "$pgid" && "$pgid" != "$self_pgid" ]]; then
    kill -0 "$pid" 2>/dev/null && kill -9 "-$pgid" 2>/dev/null || true
  else
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
}

start_command_cleanup_tracked_pid() {
  [[ -f "$PID_FILE" ]] || return 0

  local old_pid=""
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    start_command_kill_pid_or_group "$old_pid" "previous start-command"
  fi
}

start_command_cleanup_untracked_listener() {
  local cleanup_url=""
  local cleanup_port=""
  local listener_pid=""
  local listener_cwd=""

  cleanup_url="$(printf '%s' "$env_json" | env_lib_get_field 'health_check' 2>/dev/null || true)"
  if [[ -z "$cleanup_url" ]]; then
    cleanup_url="$(printf '%s' "$env_json" | env_lib_get_field 'base_url' 2>/dev/null || true)"
  fi
  cleanup_port="$(start_command_extract_loopback_port "$cleanup_url" 2>/dev/null || true)"
  [[ -n "$cleanup_port" ]] || return 0

  if ! command -v lsof >/dev/null 2>&1; then
    env_lib_log_warn "lsof not found; skipping untracked listener cleanup for $PROJECT port $cleanup_port"
    return 0
  fi

  while IFS= read -r listener_pid; do
    [[ -n "$listener_pid" ]] || continue
    [[ "$listener_pid" == "$$" ]] && continue

    listener_cwd="$(start_command_pid_cwd "$listener_pid" || true)"
    if [[ -z "$listener_cwd" ]]; then
      env_lib_log_warn "skipping listener pid $listener_pid for $PROJECT port $cleanup_port; cwd unavailable"
      continue
    fi
    if start_command_pid_tracked_by_other_project "$listener_pid"; then
      env_lib_log_warn "skipping listener pid $listener_pid for $PROJECT port $cleanup_port; owned by another start-command pid file"
      continue
    fi
    if ! start_command_path_within "$listener_cwd" "$launch_cwd"; then
      env_lib_log_warn "skipping listener pid $listener_pid for $PROJECT port $cleanup_port; cwd outside launch cwd"
      continue
    fi

    start_command_kill_pid_or_group "$listener_pid" "untracked start-command listener on port $cleanup_port"
  done < <(lsof -nP -iTCP:"$cleanup_port" -sTCP:LISTEN -t 2>/dev/null | sort -u || true)
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
  hint="$(env_lib_workspace_config_resolution_hint "${start_dir:-$PWD}" 2>/dev/null || true)"
  [[ -n "$hint" ]] && echo "$hint" >&2
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
launch_cwd="${CWD:-$PWD}"
launch_cwd="$(env_lib_expand_path "$launch_cwd")"
if [[ ! -d "$launch_cwd" ]]; then
  env_lib_log_fail "--cwd path does not exist: $launch_cwd"; exit 1
fi

# Stop a previous run for the same project if its PID is still alive — keeps
# repeated invocations idempotent (matches polaris-env.sh's kill-stale pattern
# but only for this project's tracked PID).
start_command_cleanup_tracked_pid
start_command_cleanup_untracked_listener

: > "$LOG_FILE"
env_lib_log_info "launching '$start_command' for $PROJECT in $launch_cwd (log: $LOG_FILE)"
# Launch in a new session so long-running dev servers do not depend on the
# caller shell or command-substitution process group. Python stdlib gives us a
# portable start_new_session primitive where macOS may not provide `setsid`.
launch_result="$(python3 - "$launch_cwd" "$LOG_FILE" "$start_command" <<'PY'
import subprocess
import sys
import time

cwd, log_file, command = sys.argv[1:4]
with open(log_file, "ab", buffering=0) as log:
    process = subprocess.Popen(
        ["bash", "-lc", f"cd {cwd!r} && exec {command}"],
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
    )
    time.sleep(1)
    rc = process.poll()
    if rc is None:
        print(f"{process.pid}\trunning\t")
    else:
        print(f"{process.pid}\texited\t{rc}")
PY
)"
PID="${launch_result%%$'\t'*}"
launch_rest="${launch_result#*$'\t'}"
launch_state="${launch_rest%%$'\t'*}"
launch_rc="${launch_rest#*$'\t'}"
echo "$PID" > "$PID_FILE"

# Quick sanity: does the process die immediately?
if [[ "$launch_state" == "exited" ]]; then
  if [[ "${launch_rc:-1}" -eq 0 ]]; then
    status="completed"
    env_lib_log_pass "$PROJECT start_command completed (pid=$PID, status=$status)"
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
    exit 0
  fi
  env_lib_log_fail "start_command died immediately for $PROJECT (log tail below)"
  tail -20 "$LOG_FILE" >&2 || true
  rm -f "$PID_FILE"
  exit 1
fi
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
