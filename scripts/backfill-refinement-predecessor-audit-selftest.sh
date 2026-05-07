#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d -t refinement-predecessor-backfill-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

SPECS_ROOT="$WORKDIR/docs-manager/src/content/docs/specs"

write_artifact() {
  local file="$1"
  local body="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$body" >"$file"
}

write_artifact "$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" '{
  "epic": "EX-001",
  "version": "1.0",
  "created_at": "2026-05-07T00:00:00Z",
  "modules": [
    { "path": "src/a.ts", "action": "modify" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "safe empty fixture",
      "verification": { "method": "manual", "detail": "inspect" }
    }
  ]
}'

write_artifact "$SPECS_ROOT/companies/exampleco/EX-002/refinement.json" '{
  "epic": "EX-002",
  "version": "1.0",
  "created_at": "2026-05-07T00:00:00Z",
  "modules": [
    { "path": "src/b.ts", "action": "modify", "reason": "承接 EX-001 predecessor findings" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "needs review fixture",
      "verification": { "method": "manual", "detail": "inspect" }
    }
  ]
}'

write_artifact "$SPECS_ROOT/design-plans/DP-001-safe/refinement.json" '{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-001",
    "container": "/tmp/DP-001-safe",
    "plan_path": "/tmp/DP-001-safe/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "created_at": "2026-05-07T00:00:00Z",
  "modules": [
    { "path": "scripts/a.sh", "action": "modify" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "already ok fixture",
      "verification": { "method": "manual", "detail": "inspect" }
    }
  ],
  "predecessor_audit": []
}'

write_artifact "$SPECS_ROOT/design-plans/archive/DP-999-archived/refinement.json" '{
  "epic": null,
  "source": {
    "type": "dp",
    "id": "DP-999",
    "container": "/tmp/DP-999-archived",
    "plan_path": "/tmp/DP-999-archived/index.md",
    "jira_key": null
  },
  "version": "1.0",
  "created_at": "2026-05-07T00:00:00Z",
  "modules": [
    { "path": "scripts/archive.sh", "action": "modify" }
  ],
  "dependencies": [],
  "edge_cases": [],
  "acceptance_criteria": [
    {
      "id": "AC1",
      "text": "archive fixture",
      "verification": { "method": "manual", "detail": "inspect" }
    }
  ]
}'

REPORT="$WORKDIR/report.txt"
bash "$ROOT_DIR/scripts/backfill-refinement-predecessor-audit.sh" --root "$WORKDIR" --mode report --format summary >"$REPORT"
grep -q '^total=3$' "$REPORT"
grep -q '^already_ok=1$' "$REPORT"
grep -q '^safe_empty=1$' "$REPORT"
grep -q '^needs_review=1$' "$REPORT"
grep -q '^schema_error=0$' "$REPORT"
grep -q 'EX-001 predecessor findings' "$REPORT"

python3 - "$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
assert "predecessor_audit" not in data, "report mode modified safe_empty fixture"
PY

bash "$ROOT_DIR/scripts/backfill-refinement-predecessor-audit.sh" --root "$WORKDIR" --mode apply --format summary >/dev/null
python3 - "$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
assert data["predecessor_audit"] == []
PY

python3 - "$SPECS_ROOT/companies/exampleco/EX-002/refinement.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
assert "predecessor_audit" not in data, "apply mode modified needs_review fixture"
PY

bash "$ROOT_DIR/scripts/validate-refinement-json.sh" "$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" >/dev/null
bash "$ROOT_DIR/scripts/backfill-refinement-predecessor-audit.sh" --root "$WORKDIR" --mode apply --format summary >"$WORKDIR/reapply.txt"
grep -q '^applied=0$' "$WORKDIR/reapply.txt"

if bash "$ROOT_DIR/scripts/backfill-refinement-predecessor-audit.sh" --root "$WORKDIR" --mode check --format summary >/dev/null 2>&1; then
  echo "FAIL: check mode passed with needs_review backlog" >&2
  exit 1
fi

echo "PASS: refinement predecessor audit backfill selftest"
