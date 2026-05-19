#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="${ROOT_DIR}/scripts/validate-polaris-command-catalog.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

write_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts"
  cp "$ROOT_DIR/scripts/command-catalog.json" "$repo/scripts/command-catalog.json"
  cp "$ROOT_DIR/package.json" "$repo/package.json"
  cp "$ROOT_DIR/mise.toml" "$repo/mise.toml"
  mkdir -p "$repo/scripts"
  touch "$repo/scripts/polaris-viewer.sh" "$repo/scripts/polaris-toolchain.sh" \
    "$repo/scripts/check-script-manifest.sh" "$repo/scripts/validate-polaris-command-catalog.sh" \
    "$repo/scripts/polaris-bootstrap.sh" "$repo/scripts/polaris-doctor.sh" \
    "$repo/scripts/doctor-mise-check.sh" "$repo/scripts/onboard-doctor.sh" \
    "$repo/scripts/framework-release-pr-lane.sh" "$repo/scripts/polaris-pr-create.sh" \
    "$repo/scripts/close-parent-spec-if-complete.sh" "$repo/scripts/refinement-handoff-gate.sh" \
    "$repo/scripts/run-verify-command.sh" "$repo/scripts/sync-skills-cross-runtime.sh"
}

positive="$TMP_DIR/positive"
write_repo "$positive"
bash "$VALIDATOR" --root "$positive" >/dev/null

missing_script="$TMP_DIR/missing-script"
write_repo "$missing_script"
python3 - "$missing_script/package.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["scripts"].pop("viewer:status")
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
if bash "$VALIDATOR" --root "$missing_script" >/tmp/polaris-command-catalog-selftest.out 2>&1; then
  echo "FAIL: expected missing package script fixture to fail" >&2
  exit 1
fi

maintainer_leak="$TMP_DIR/maintainer-leak"
write_repo "$maintainer_leak"
python3 - "$maintainer_leak/scripts/command-catalog.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
for row in d["commands"]:
    if row["id"] == "maintainer.framework-release":
        row["canonical"] = "pnpm framework-release"
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
if bash "$VALIDATOR" --root "$maintainer_leak" >/tmp/polaris-command-catalog-selftest.out 2>&1; then
  echo "FAIL: expected maintainer leak fixture to fail" >&2
  exit 1
fi

legacy_direct="$TMP_DIR/legacy-direct"
write_repo "$legacy_direct"
python3 - "$legacy_direct/scripts/command-catalog.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
for row in d["commands"]:
    if row["id"] == "runtime.bootstrap":
        row["canonical"] = "bash scripts/polaris-bootstrap.sh"
p.write_text(json.dumps(d, indent=2), encoding="utf-8")
PY
if bash "$VALIDATOR" --root "$legacy_direct" >/tmp/polaris-command-catalog-selftest.out 2>&1; then
  echo "FAIL: expected legacy direct public task canonical fixture to fail" >&2
  exit 1
fi

echo "PASS: Polaris command catalog selftest"
