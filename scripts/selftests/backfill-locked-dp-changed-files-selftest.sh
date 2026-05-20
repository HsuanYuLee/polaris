#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKDIR="$(mktemp -d -t dp207-changed-files-backfill.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

make_dp() {
  local id="$1"
  local status="$2"
  local refinement="$3"
  local dir="$WORKDIR/docs-manager/src/content/docs/specs/design-plans/${id}-fixture"
  mkdir -p "$dir"
  cat >"$dir/index.md" <<MD
---
title: "${id} fixture"
description: "fixture"
status: ${status}
---

## Fixture
MD
  printf '%s\n' "$refinement" >"$dir/refinement.json"
}

make_dp "DP-001" "LOCKED" '{
  "source": {"type": "dp", "id": "DP-001"},
  "modules": [
    {"path": "scripts/example-one.sh", "action": "create"},
    {"path": ".claude/skills/example/SKILL.md", "action": "modify"},
    {"path": "scripts/example-one.sh", "action": "create"}
  ]
}'

make_dp "DP-002" "LOCKED" '{
  "source": {"type": "dp", "id": "DP-002"},
  "changed_files": ["scripts/existing.sh"],
  "modules": [
    {"path": "scripts/should-not-overwrite.sh", "action": "modify"}
  ]
}'

make_dp "DP-003" "DISCUSSION" '{
  "source": {"type": "dp", "id": "DP-003"},
  "modules": [
    {"path": "scripts/discussion.sh", "action": "modify"}
  ]
}'

if bash "$ROOT_DIR/scripts/backfill-locked-dp-changed-files.sh" --root "$WORKDIR" --mode check >/tmp/dp207-backfill-check-before.out 2>&1; then
  echo "FAIL: check should fail before apply" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/backfill-locked-dp-changed-files.sh" --root "$WORKDIR" --mode apply --format json >"$WORKDIR/apply.json"

python3 - "$WORKDIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
dp1 = json.loads((root / "docs-manager/src/content/docs/specs/design-plans/DP-001-fixture/refinement.json").read_text())
dp2 = json.loads((root / "docs-manager/src/content/docs/specs/design-plans/DP-002-fixture/refinement.json").read_text())
dp3 = json.loads((root / "docs-manager/src/content/docs/specs/design-plans/DP-003-fixture/refinement.json").read_text())
assert dp1["changed_files"] == ["scripts/example-one.sh", ".claude/skills/example/SKILL.md"], dp1
assert dp2["changed_files"] == ["scripts/existing.sh"], dp2
assert "changed_files" not in dp3, dp3
PY

bash "$ROOT_DIR/scripts/backfill-locked-dp-changed-files.sh" --root "$WORKDIR" --mode check >/tmp/dp207-backfill-check-after.out
bash "$ROOT_DIR/scripts/backfill-locked-dp-changed-files.sh" --root "$WORKDIR" --mode apply --format json >"$WORKDIR/reapply.json"

python3 - "$WORKDIR/reapply.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["summary"]["applied_count"] == 0, payload
assert payload["summary"]["missing_count"] == 0, payload
PY

echo "PASS: backfill locked DP changed_files selftest"
