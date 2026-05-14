#!/usr/bin/env bash
# scripts/polaris-env-selftest.sh — regression coverage for polaris-env.sh.
#
# Covers DP-165: docker dependency readiness must use dependency-level port
# readiness during Layer 1 / Layer 3 startup, while final verify/status still
# checks route-level HTTP health.
# Covers DP-168: project dir resolution must match exact repo slug, not a
# workspace repo whose remote only contains the product repo name as a prefix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLARIS_ENV="$SCRIPT_DIR/polaris-env.sh"

PORT_DOCKER=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
PORT_APP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
PORT_SHADOW_APP=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
COMPANY=".polaris-env-selftest-$$"
COMPANY_DIR="$WORKSPACE_ROOT/$COMPANY"
MARKER="$COMPANY_DIR/app-ready.marker"
PNPM_CWD_MARKER="$COMPANY_DIR/pnpm-cwd.marker"
SHADOW_MARKER="$COMPANY_DIR/shadow-ready.marker"
SHADOW_PNPM_CWD_MARKER="$COMPANY_DIR/shadow-pnpm-cwd.marker"
PROBE_SCRIPT="$COMPANY_DIR/docker_probe.py"
FAKE_BIN="$COMPANY_DIR/bin"
APP_WORKTREE="$COMPANY_DIR/app-worktree"
WORKSPACE_SHADOW_REPO="$COMPANY_DIR/app-workspace-repo"
OUT_START="$COMPANY_DIR/start.out"
OUT_SHADOW_START="$COMPANY_DIR/shadow-start.out"
OUT_STATUS_BEFORE="$COMPANY_DIR/status-before.out"
OUT_STATUS_AFTER="$COMPANY_DIR/status-after.out"

cleanup() {
  bash "$POLARIS_ENV" stop "$COMPANY" >/dev/null 2>&1 || true
  rm -rf "$COMPANY_DIR"
}
trap cleanup EXIT

mkdir -p "$COMPANY_DIR/app" "$COMPANY_DIR/shadow-app" "$FAKE_BIN" "$APP_WORKTREE" "$WORKSPACE_SHADOW_REPO"

git -C "$APP_WORKTREE" init -q
git -C "$APP_WORKTREE" remote add origin https://github.com/example/app.git
git -C "$WORKSPACE_SHADOW_REPO" init -q
git -C "$WORKSPACE_SHADOW_REPO" remote add origin https://github.com/example/app-workspace.git

cat > "$FAKE_BIN/pnpm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" ]]; then
  cd "$2"
  shift 2
fi
printf '%s\n' "$PWD" > "$PNPM_CWD_MARKER"
python3 -u - <<'PY'
import http.server
import os
import socketserver
from pathlib import Path

Path(os.environ["APP_MARKER"]).write_text("ready")
port = int(os.environ["APP_PORT"])
with socketserver.TCPServer(("127.0.0.1", port), http.server.SimpleHTTPRequestHandler) as httpd:
    httpd.serve_forever()
PY
SH
chmod +x "$FAKE_BIN/pnpm"

cat > "$PROBE_SCRIPT" <<'PY'
import http.server
import socketserver
import sys
from pathlib import Path

port = int(sys.argv[1])
marker = Path(sys.argv[2])

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        if self.path.startswith("/app-route"):
            self.send_response(200 if marker.exists() else 502)
        else:
            self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
    httpd.serve_forever()
PY

cat > "$COMPANY_DIR/workspace-config.yaml" <<EOF
projects:
  - name: docker-proxy
    tags: ["docker"]
    dev_environment:
      start_command: "python3 -u $PROBE_SCRIPT $PORT_DOCKER $MARKER"
      ready_signal: ""
      base_url: "http://127.0.0.1:$PORT_DOCKER"
      health_check: "http://127.0.0.1:$PORT_DOCKER/app-route"
      requires: []
  - name: app
    repo: "example/app"
    tags: ["b2c"]
    dev_environment:
      start_command: "pnpm dev"
      ready_signal: ""
      base_url: "http://127.0.0.1:$PORT_APP"
      health_check: "http://127.0.0.1:$PORT_APP/"
      requires: ["docker-proxy"]
  - name: shadow-app
    repo: "example/app"
    tags: ["b2c"]
    dev_environment:
      start_command: "pnpm dev"
      ready_signal: ""
      base_url: "http://127.0.0.1:$PORT_SHADOW_APP"
      health_check: "http://127.0.0.1:$PORT_SHADOW_APP/"
      requires: []
EOF

if bash "$POLARIS_ENV" status "$COMPANY" > "$OUT_STATUS_BEFORE" 2>&1; then
  :
fi
grep -q "docker-proxy.*HTTP 000" "$OUT_STATUS_BEFORE"

(
  cd "$APP_WORKTREE"
  PATH="$FAKE_BIN:$PATH" \
    APP_MARKER="$MARKER" \
    APP_PORT="$PORT_APP" \
    PNPM_CWD_MARKER="$PNPM_CWD_MARKER" \
    bash "$POLARIS_ENV" start "$COMPANY" --project app > "$OUT_START" 2>&1
)

if grep -q "app skipped" "$OUT_START"; then
  echo "FAIL: app was skipped even though docker dependency port should be enough for startup" >&2
  cat "$OUT_START" >&2
  exit 1
fi

grep -q "docker-proxy (dependency port $PORT_DOCKER)" "$OUT_START"
grep -q "app" "$OUT_START"
grep -q "Done. Logs:" "$OUT_START"
grep -qx "$APP_WORKTREE" "$PNPM_CWD_MARKER"

bash "$POLARIS_ENV" status "$COMPANY" > "$OUT_STATUS_AFTER" 2>&1
grep -q "docker-proxy.*http://127.0.0.1:$PORT_DOCKER/app-route.*Docker" "$OUT_STATUS_AFTER"
grep -q "app.*http://127.0.0.1:$PORT_APP/.*Dev server" "$OUT_STATUS_AFTER"

(
  cd "$WORKSPACE_SHADOW_REPO"
  PATH="$FAKE_BIN:$PATH" \
    APP_MARKER="$SHADOW_MARKER" \
    APP_PORT="$PORT_SHADOW_APP" \
    PNPM_CWD_MARKER="$SHADOW_PNPM_CWD_MARKER" \
    bash "$POLARIS_ENV" start "$COMPANY" --project shadow-app > "$OUT_SHADOW_START" 2>&1
)

if grep -q "Required services failed health check" "$OUT_SHADOW_START"; then
  echo "FAIL: shadow app start failed" >&2
  cat "$OUT_SHADOW_START" >&2
  exit 1
fi
grep -qx "$COMPANY_DIR/shadow-app" "$SHADOW_PNPM_CWD_MARKER"

echo "PASS: polaris-env docker dependency readiness avoids route-health startup deadlock"
