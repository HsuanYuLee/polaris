#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-refinement-artifact-parity.sh"
TMP="$(mktemp -d -t dp207-refinement-parity.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

make_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/refinement.json" <<'JSON'
{"modules":[{"path":"scripts/a.sh","action":"create"},{"path":"scripts/b.sh","action":"modify"}],"changed_files":["scripts/a.sh","scripts/b.sh"],"acceptance_criteria":[{"id":"AC1"},{"id":"AC2"}],"downstream":{"suggested_subtask_count":2,"estimated_total_points":"5 (T1 2 + T2 3)"}}
JSON
  cat >"$dir/refinement.md" <<'MD'
## Modules

| Path | Action | Reason |
|------|--------|--------|
| `scripts/a.sh` | create | fixture |
| `scripts/b.sh` | modify | fixture |

## Acceptance Criteria

- **AC1**: one
- **AC2**: two
MD
  cat >"$dir/index.md" <<'MD'
# DP-999

## Acceptance Criteria

- **AC1**: one
- **AC2**: two

## Downstream Breakdown Hints

2 work items, 5pt.
MD
}

valid="$TMP/valid"
make_fixture "$valid"
bash "$VALIDATOR" "$valid" >/tmp/dp207-parity-valid.out

modules_drift="$TMP/modules-drift"
make_fixture "$modules_drift"
perl -0pi -e 's/scripts\/b\.sh` \\| modify/scripts\/c.sh` | modify/' "$modules_drift/refinement.md"
if bash "$VALIDATOR" "$modules_drift" >/tmp/dp207-parity-modules.out 2>&1; then
  echo "FAIL: modules drift should fail" >&2
  exit 1
fi
rg -n 'modules path/action drift' /tmp/dp207-parity-modules.out >/dev/null

ac_drift="$TMP/ac-drift"
make_fixture "$ac_drift"
perl -0pi -e 's/AC2/AC9/g' "$ac_drift/index.md"
if bash "$VALIDATOR" "$ac_drift" >/tmp/dp207-parity-ac.out 2>&1; then
  echo "FAIL: AC drift should fail" >&2
  exit 1
fi
rg -n 'AC ids missing from index.md' /tmp/dp207-parity-ac.out >/dev/null

changed_drift="$TMP/changed-drift"
make_fixture "$changed_drift"
python3 - "$changed_drift/refinement.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["changed_files"] = ["scripts/a.sh"]
p.write_text(json.dumps(d) + "\n")
PY
if bash "$VALIDATOR" "$changed_drift" >/tmp/dp207-parity-changed.out 2>&1; then
  echo "FAIL: changed_files drift should fail" >&2
  exit 1
fi
rg -n 'changed_files drift' /tmp/dp207-parity-changed.out >/dev/null

points_drift="$TMP/points-drift"
make_fixture "$points_drift"
perl -0pi -e 's/5pt/8pt/' "$points_drift/index.md"
if bash "$VALIDATOR" "$points_drift" >/tmp/dp207-parity-points.out 2>&1; then
  echo "FAIL: points drift should fail" >&2
  exit 1
fi
rg -n 'estimated_total_points' /tmp/dp207-parity-points.out >/dev/null

echo "PASS: validate refinement artifact parity selftest"
