#!/usr/bin/env bash
# Launch Polaris Specs Viewer in browser
# Usage: polaris-viewer.sh [--port 8080] [--no-open]
#
# Syncs viewer navigation, starts Starlight dev server, opens browser.
# Ctrl+C to stop.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8080
OPEN_BROWSER=true
HOST=127.0.0.1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --no-open) OPEN_BROWSER=false; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

ORIGIN="http://$HOST:$PORT"
VIEWER_URL="$ORIGIN/docs-viewer/"
export POLARIS_DOCS_VIEWER_SITE="$ORIGIN"

viewer_available() {
  local url="$1"
  local body
  body="$(curl -fsS --max-time 5 "$url" 2>/dev/null || true)"
  [[ "$body" == *"Polaris Specs"* && "$body" == *"starlight"* ]]
}

ensure_specs_source() {
  if [[ -d "$WORKSPACE_ROOT/specs" ]]; then
    return 0
  fi

  # Gitignored specs live only in the main checkout. Linked worktrees need a
  # local pointer so the existing sync script can populate this viewer copy.
  local main_checkout
  # shellcheck source=scripts/lib/main-checkout.sh
  source "$WORKSPACE_ROOT/scripts/lib/main-checkout.sh"
  main_checkout="$(resolve_main_checkout "$WORKSPACE_ROOT" || true)"
  if [[ -n "$main_checkout" && -d "$main_checkout/specs" ]]; then
    mkdir -p "$WORKSPACE_ROOT/specs"
    rsync -a --delete \
      --exclude '.git' \
      --exclude '.worktrees' \
      --exclude 'node_modules' \
      "$main_checkout/specs/" "$WORKSPACE_ROOT/specs/"
  fi
}

# 1. Sync viewer navigation/content
echo "Syncing viewer navigation..."
ensure_specs_source
"$WORKSPACE_ROOT/scripts/generate-specs-sidebar.sh" "$WORKSPACE_ROOT"

# 2. Check if port is already in use
if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null; then
  if ! viewer_available "$VIEWER_URL"; then
    echo "Port $PORT is already in use, but $VIEWER_URL is not a Polaris Specs viewer." >&2
    echo "Choose another port with --port <port> or stop the existing service." >&2
    exit 1
  fi
  echo "Port $PORT already has a Polaris Specs viewer. Opening existing server."
  [ "$OPEN_BROWSER" = true ] && open "$VIEWER_URL"
  exit 0
fi

# 3. Start server
echo "Starting server on $VIEWER_URL"
if [ "$OPEN_BROWSER" = true ]; then
  # Small delay to let server start before opening browser
  (sleep 1 && open "$VIEWER_URL") &
fi

cd "$WORKSPACE_ROOT/docs-viewer"
if [ ! -d node_modules ]; then
  echo "Installing docs-viewer dependencies..."
  npm install
fi

npm run dev -- --host "$HOST" --port "$PORT" --strictPort
