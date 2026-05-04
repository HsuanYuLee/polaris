#!/usr/bin/env bash
# Selftest for the Polaris toolchain runner and manifest parser.

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash "$WORKSPACE_ROOT/scripts/validate-polaris-toolchain-manifest.sh" "$WORKSPACE_ROOT/polaris-toolchain.yaml" >/dev/null
bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" manifest --required --json >/tmp/polaris-toolchain-required.json
python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path("/tmp/polaris-toolchain-required.json").read_text())
caps = data["capabilities"]
assert set(caps) == {"docs.viewer", "fixtures.mockoon", "browser.playwright"}
assert all(caps[key]["required"] is True for key in caps)
PY

(
  cd /tmp
  bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" manifest --json >/dev/null
)

if bash "$WORKSPACE_ROOT/scripts/polaris-toolchain.sh" run unknown.capability >/tmp/polaris-toolchain-unknown.out 2>/tmp/polaris-toolchain-unknown.err; then
  echo "expected unknown capability to fail" >&2
  exit 1
fi

echo "PASS: Polaris toolchain selftest"
