#!/usr/bin/env bash
# mockoon-runner.sh — Start/stop Mockoon CLI instances from environment files
#
# Usage:
#   scripts/mockoon/mockoon-runner.sh start <environments_dir> [--epic <name>] [--proxy]
#   scripts/mockoon/mockoon-runner.sh stop
#   scripts/mockoon/mockoon-runner.sh status
#
# Options:
#   --epic <name>  Load fixtures from <environments_dir>/<name>/ subdirectory (per-epic isolation)
#   --proxy        Start in proxy mode (passthrough to real backends)
#   (no flag)      Start in mock mode (canned responses only, for E2E)
#
# Environments dir:
#   Directory containing Mockoon environment JSON files.
#   With --epic: loads from <environments_dir>/<epic>/*.json
#   Without --epic: loads from <environments_dir>/*.json (legacy, deprecated)
#
# Exit codes:
#   0 = success
#   1 = error
#   2 = environments directory not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_DIR="/tmp/polaris-mockoon"

# --- Ensure Mockoon CLI is installed ---
ensure_cli() {
  if [[ ! -d "$SCRIPT_DIR/node_modules" ]]; then
    echo "Installing Mockoon CLI..."
    npm install --prefix "$SCRIPT_DIR" --silent 2>&1
  fi
}

# --- Start all environments ---
cmd_start() {
  local env_dir="${1:-}"
  shift || true

  # Parse optional flags: --epic <name>, --proxy
  local epic_name=""
  local proxy_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --epic)
        epic_name="${2:-}"
        shift 2 || { echo "ERROR: --epic requires a value" >&2; exit 1; }
        ;;
      --proxy)
        proxy_flag="--proxy"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Resolve epic subdirectory
  if [[ -n "$epic_name" ]]; then
    env_dir="$env_dir/$epic_name"
  fi

  if [[ -z "$env_dir" || ! -d "$env_dir" ]]; then
    echo "ERROR: Environments directory not found: ${env_dir:-<not specified>}" >&2
    echo "Usage: $0 start <environments_dir> [--epic <name>] [--proxy]" >&2
    exit 2
  fi

  ensure_cli

  mkdir -p "$PID_DIR"

  local count=0
  for env_file in "$env_dir"/*.json; do
    [[ -f "$env_file" ]] || continue

    local name
    name=$(basename "$env_file" .json)

    # Skip demo/template files
    [[ "$name" == "demo" || "$name" == "settings" ]] && continue

    # Extract port from environment file
    local port
    port=$(python3 -c "
import json, sys
with open('$env_file') as f:
    d = json.load(f)
print(d.get('port', 0))
" 2>/dev/null || echo "0")

    if [[ "$port" == "0" ]]; then
      echo "  SKIP $name (no port defined)"
      continue
    fi

    # Check if port is already in use
    if lsof -i :"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "  SKIP $name (port $port already in use)"
      continue
    fi

    echo "  Starting $name on port $port..."

    local cli_args=("--data" "$env_file" "--port" "$port")

    # Proxy mode: --proxy enabled (passthrough), Mock mode: --proxy disabled
    # Note: --log-transaction omitted — triggers DecompressBody which crashes on gzip responses from nginx
    if [[ "$proxy_flag" == "--proxy" ]]; then
      cli_args+=("--proxy" "enabled")
    else
      cli_args+=("--proxy" "disabled")
    fi

    "$SCRIPT_DIR/node_modules/.bin/mockoon-cli" start "${cli_args[@]}" \
      > "$PID_DIR/$name.log" 2>&1 &

    echo $! > "$PID_DIR/$name.pid"
    count=$((count + 1))
  done

  echo ""
  echo "Started $count Mockoon instances."
  echo "PID files: $PID_DIR/"
}

# --- Stop all instances ---
cmd_stop() {
  if [[ ! -d "$PID_DIR" ]]; then
    echo "No Mockoon instances running."
    return 0
  fi

  local count=0
  for pid_file in "$PID_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue

    local name
    name=$(basename "$pid_file" .pid)
    local pid
    pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "  Stopped $name (PID $pid)"
      count=$((count + 1))
    fi

    rm -f "$pid_file" "$PID_DIR/$name.log"
  done

  # Also try mockoon-cli stop for any managed instances
  if [[ -d "$SCRIPT_DIR/node_modules" ]]; then
    npx --prefix "$SCRIPT_DIR" mockoon-cli stop all 2>/dev/null || true
  fi

  echo "Stopped $count instance(s)."
}

# --- Status ---
cmd_status() {
  if [[ ! -d "$PID_DIR" ]]; then
    echo "No Mockoon instances tracked."
    return 0
  fi

  echo "Mockoon instances:"
  local running=0
  for pid_file in "$PID_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue

    local name
    name=$(basename "$pid_file" .pid)
    local pid
    pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
      echo "  ✅ $name (PID $pid)"
      running=$((running + 1))
    else
      echo "  ❌ $name (PID $pid — not running)"
    fi
  done

  echo ""
  echo "$running instance(s) running."
}

# --- Main ---
case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 {start|stop|status}" >&2
    echo "  start <environments_dir> [--epic <name>] [--proxy]" >&2
    echo "  stop" >&2
    echo "  status" >&2
    exit 1
    ;;
esac
