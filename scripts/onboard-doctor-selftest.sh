#!/usr/bin/env bash
# Selftest for scripts/onboard-doctor.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$ROOT_DIR/scripts/onboard-doctor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

assert_status() {
  local expected="$1"
  local workspace="$2"
  local output
  output="$(bash "$DOCTOR" --workspace "$workspace" --json 2>/dev/null || true)"
  local actual
  actual="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$output")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected status=$expected got=$actual" >&2
    echo "$output" >&2
    exit 1
  fi
}

make_base() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/.agents" "$dir/.claude/skills" "$dir/.codex/.generated"
  ln -s ../.claude/skills "$dir/.agents/skills"
  touch "$dir/.codex/AGENTS.md" "$dir/polaris-toolchain.yaml" "$dir/scripts/polaris-toolchain.sh"
}

ready="$TMPDIR/ready"
make_base "$ready"
mkdir -p "$ready/acme"
cat > "$ready/workspace-config.yaml" <<'YAML'
language: zh-TW
companies:
  - name: acme
    base_dir: ./acme
YAML
python3 - "$ready/workspace-config.yaml" "$ready" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
root = Path(sys.argv[2])
text = path.read_text()
text = text.replace("./acme", str(root / "acme"))
path.write_text(text)
PY
cat > "$ready/acme/workspace-config.yaml" <<'YAML'
github:
  org: acme
projects:
  - name: app
    repo: acme/app
    dev_environment:
      install_command: pnpm install
      start_command: pnpm dev
      ready_signal: "ready"
      base_url: http://127.0.0.1:3000
      health_check: http://127.0.0.1:3000/health
      requires: []
      env: {}
visual_regression:
  domains:
    - name: example.com
daily_learning_scan:
  enabled: false
YAML
assert_status ready "$ready"

partial="$TMPDIR/partial"
make_base "$partial"
mkdir -p "$partial/acme"
cat > "$partial/workspace-config.yaml" <<'YAML'
language: zh-TW
companies:
  - name: acme
    base_dir: ./acme
YAML
python3 - "$partial/workspace-config.yaml" "$partial" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
root = Path(sys.argv[2])
path.write_text(path.read_text().replace("./acme", str(root / "acme")))
PY
cat > "$partial/acme/workspace-config.yaml" <<'YAML'
projects:
  - name: app
YAML
assert_status partial "$partial"

blocked="$TMPDIR/blocked"
mkdir -p "$blocked/scripts"
assert_status blocked "$blocked"

echo "PASS: onboard-doctor-selftest ready partial blocked"
