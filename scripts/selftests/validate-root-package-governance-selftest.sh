#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="${ROOT_DIR}/scripts/validate-root-package-governance.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

write_repo() {
  local repo="$1"
  mkdir -p "$repo"
  cp "$ROOT_DIR/package.json" "$repo/package.json"
  cp "$ROOT_DIR/pnpm-workspace.yaml" "$repo/pnpm-workspace.yaml"
  cp "$ROOT_DIR/pnpm-lock.yaml" "$repo/pnpm-lock.yaml"
}

positive="$TMP_DIR/positive"
write_repo "$positive"
bash "$VALIDATOR" --root "$positive" >/dev/null

root_dep="$TMP_DIR/root-dep"
write_repo "$root_dep"
python3 - "$root_dep/package.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["dependencies"] = {"left-pad": "1.3.0"}
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
if bash "$VALIDATOR" --root "$root_dep" >/tmp/root-package-governance-selftest.out 2>&1; then
  echo "FAIL: expected root dependency fixture to fail" >&2
  exit 1
fi

inline_orchestration="$TMP_DIR/inline"
write_repo "$inline_orchestration"
python3 - "$inline_orchestration/package.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["scripts"]["scripts:check"] = "bash scripts/check-script-manifest.sh && bash scripts/validate-polaris-command-catalog.sh"
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
if bash "$VALIDATOR" --root "$inline_orchestration" >/tmp/root-package-governance-selftest.out 2>&1; then
  echo "FAIL: expected inline orchestration fixture to fail" >&2
  exit 1
fi

missing_workspace="$TMP_DIR/missing-workspace"
write_repo "$missing_workspace"
cat > "$missing_workspace/pnpm-workspace.yaml" <<'YAML'
packages:
  - docs-manager
YAML
if bash "$VALIDATOR" --root "$missing_workspace" >/tmp/root-package-governance-selftest.out 2>&1; then
  echo "FAIL: expected missing workspace package fixture to fail" >&2
  exit 1
fi

echo "PASS: root package governance selftest"
