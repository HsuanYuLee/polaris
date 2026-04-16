#!/usr/bin/env bash
# Launch Polaris Specs Viewer in browser
# Usage: polaris-viewer.sh [--port 8080] [--no-open]
#
# Generates sidebar, starts HTTP server, opens browser.
# Ctrl+C to stop.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8080
OPEN_BROWSER=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --no-open) OPEN_BROWSER=false; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# 1. Generate sidebar
echo "Generating sidebar..."
"$WORKSPACE_ROOT/scripts/generate-specs-sidebar.sh" "$WORKSPACE_ROOT"

# 2. Check if port is already in use
if lsof -i :"$PORT" -sTCP:LISTEN &>/dev/null; then
  echo "Port $PORT already in use. Opening browser to existing server."
  [ "$OPEN_BROWSER" = true ] && open "http://localhost:$PORT/docs-viewer/"
  exit 0
fi

# 3. Start server
echo "Starting server on http://localhost:$PORT/docs-viewer/"
if [ "$OPEN_BROWSER" = true ]; then
  # Small delay to let server start before opening browser
  (sleep 1 && open "http://localhost:$PORT/docs-viewer/") &
fi

python3 -m http.server "$PORT" --directory "$WORKSPACE_ROOT" --bind 127.0.0.1
