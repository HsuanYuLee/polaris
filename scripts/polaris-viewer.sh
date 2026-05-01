#!/usr/bin/env bash
# Launch Polaris docs-manager in browser.
# Usage: polaris-viewer.sh [--port 8080] [--host 127.0.0.1] [--no-open] [--preview|--mode dev|preview]
#
# Dev mode serves live canonical specs from {workspace_root}/specs.
# Preview mode builds first, then serves static output for production/search checks.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8080
OPEN_BROWSER=true
HOST=127.0.0.1
MODE=dev

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --no-open) OPEN_BROWSER=false; shift ;;
    --preview) MODE=preview; shift ;;
    --mode)
      MODE="${2:-}"
      if [[ "$MODE" != "dev" && "$MODE" != "preview" ]]; then
        echo "Invalid --mode value: $MODE (expected dev or preview)" >&2
        exit 1
      fi
      shift 2
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ORIGIN="http://$HOST:$PORT"
MANAGER_URL="$ORIGIN/docs-manager/"
export POLARIS_DOCS_MANAGER_SITE="$ORIGIN"

docs_manager_available() {
  local url="$1"
  local body
  body="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

if [[ ! -d "$WORKSPACE_ROOT/docs-manager" ]]; then
  echo "docs-manager directory not found under $WORKSPACE_ROOT" >&2
  exit 1
fi

if [[ -d "$WORKSPACE_ROOT/specs" ]]; then
  export POLARIS_WORKSPACE_ROOT="$WORKSPACE_ROOT"
else
  # Gitignored specs live only in the main checkout. T2's direct loader can
  # resolve them from the main checkout when launched from a linked worktree.
  # This warning is informational; no mirror copy is created here.
  echo "WARN: $WORKSPACE_ROOT/specs not found; docs-manager will resolve canonical specs from the main checkout if available." >&2
fi

if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null; then
  if ! docs_manager_available "$MANAGER_URL"; then
    echo "Port $PORT is already in use, but $MANAGER_URL is not Polaris docs-manager." >&2
    echo "Choose another port with --port <port> or stop the existing service." >&2
    exit 1
  fi
  echo "Port $PORT already has Polaris docs-manager. Opening existing server."
  [ "$OPEN_BROWSER" = true ] && open "$MANAGER_URL"
  exit 0
fi

echo "Starting $MODE server on $MANAGER_URL"
if [ "$OPEN_BROWSER" = true ]; then
  (sleep 1 && open "$MANAGER_URL") &
fi

cd "$WORKSPACE_ROOT/docs-manager"
if [ ! -d node_modules ]; then
  echo "Installing docs-manager dependencies..."
  npm install
fi

if [ "$MODE" = "preview" ]; then
  npm run build
  npm run preview -- --host "$HOST" --port "$PORT" --strictPort
else
  npm run dev -- --host "$HOST" --port "$PORT" --strictPort
fi
