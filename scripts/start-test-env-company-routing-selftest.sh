#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/start-test-env.sh"

tmpdir="$(mktemp -d -t start-test-env-routing.XXXXXX)"
cleanup() {
  pid_file="/tmp/polaris-env-d11/app.pid"
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')"

mkdir -p "$tmpdir/rightco/app" "$tmpdir/wrongco/app"

cat >"$tmpdir/workspace-config.yaml" <<EOF
language: zh-TW
default_company: wrongco
companies:
  - name: rightco
    base_dir: "$tmpdir/rightco"
  - name: wrongco
    base_dir: "$tmpdir/wrongco"
EOF

cat >"$tmpdir/rightco/workspace-config.yaml" <<EOF
projects:
  - name: app
    dev_environment:
      install_command: "python3 -c \"from pathlib import Path; Path('.rightco-installed').write_text('ok')\""
      start_command: "python3 -u -m http.server $port --bind 127.0.0.1"
      ready_signal: "Serving HTTP on 127.0.0.1"
      base_url: "http://127.0.0.1:$port"
      health_check: "http://127.0.0.1:$port/"
      requires: []
EOF

cat >"$tmpdir/wrongco/workspace-config.yaml" <<EOF
projects:
  - name: app
    dev_environment:
      install_command: "python3 -c \"from pathlib import Path; Path('.wrongco-installed').write_text('ok')\""
      start_command: "true"
      health_check: "http://127.0.0.1:$port/"
      requires: []
EOF

bash "$SCRIPT" --project app --workspace-config "$tmpdir/rightco/workspace-config.yaml" --ready-timeout 10 >/tmp/start-test-env-routing.out 2>/tmp/start-test-env-routing.err

[[ -f "$tmpdir/rightco/app/.rightco-installed" ]] || {
  echo "FAIL: install_command did not run in rightco/app" >&2
  cat /tmp/start-test-env-routing.err >&2 || true
  exit 1
}

[[ ! -f "$tmpdir/wrongco/app/.rightco-installed" ]] || {
  echo "FAIL: install_command incorrectly ran in wrongco/app" >&2
  exit 1
}

echo "PASS: start-test-env company routing selftest"
