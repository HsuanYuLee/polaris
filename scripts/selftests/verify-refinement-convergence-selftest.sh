#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORKDIR="$(mktemp -d -t refinement-convergence-selftest.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

SPECS_ROOT="$WORKDIR/docs-manager/src/content/docs/specs"
SAMPLE_TASK="$SPECS_ROOT/companies/exampleco/EX-001/tasks/T1/index.md"

mkdir -p "$(dirname "$SAMPLE_TASK")" "$SPECS_ROOT/companies/exampleco/EX-001" "$SPECS_ROOT/design-plans/DP-001-safe"

cat >"$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" <<'EOF'
{
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
}
EOF

cat >"$SPECS_ROOT/design-plans/DP-001-safe/refinement.json" <<'EOF'
{
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
}
EOF

# 補齊 current strong-bound schema，讓 backlog 狀態只由 predecessor_audit 決定。
python3 - \
  "$SPECS_ROOT/companies/exampleco/EX-001/refinement.json" \
  "$SPECS_ROOT/design-plans/DP-001-safe/refinement.json" <<'PY'
import json
import sys
from pathlib import Path

for raw in sys.argv[1:]:
    path = Path(raw)
    data = json.loads(path.read_text(encoding="utf-8"))
    source_id = ((data.get("source") or {}).get("id") or data.get("epic") or "DP-999")
    if isinstance(data.get("source"), dict):
        index = path.parent / "index.md"
        index.write_text("---\ntitle: Fixture\ndescription: Fixture\nstatus: LOCKED\n---\n", encoding="utf-8")
        data["source"]["container"] = str(path.parent.resolve())
        data["source"]["plan_path"] = str(index.resolve())
    data["schema_version"] = 1
    data["tasks"] = [{
        "id": f"{source_id}-T1", "kind": "implementation", "title": "fixture",
        "scope": "fixture", "modules": [data["modules"][0]["path"]],
        "ac_ids": ["AC1"], "dependencies": [],
        "verification": {"method": "unit_test", "detail": "fixture"},
    }]
    data["adversarial_pass"] = [{
        "ac_id": "AC1", "attack": "missing predecessor audit", "enforce": "selftest"
    }]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

cat >"$SAMPLE_TASK" <<'EOF'
---
title: "Sample task"
status: IN_PROGRESS
---

# Sample task
EOF

bash "$ROOT_DIR/scripts/verify-refinement-convergence.sh" --root "$WORKDIR" --sample-task "$SAMPLE_TASK" --skip-direct-source --allow-scan-failures >"$WORKDIR/allow.txt"
grep -q '^safe_empty=1$' "$WORKDIR/allow.txt"
grep -q '^scan_consistent=true$' "$WORKDIR/allow.txt"
grep -q '^sample_status_frontmatter=true$' "$WORKDIR/allow.txt"
grep -q '^direct_source=SKIP$' "$WORKDIR/allow.txt"

bash "$ROOT_DIR/scripts/verify-refinement-convergence.sh" --root "$WORKDIR" --skip-direct-source --allow-scan-failures >"$WORKDIR/discovered.txt"
grep -q '^sample_status_frontmatter=true$' "$WORKDIR/discovered.txt"

if bash "$ROOT_DIR/scripts/verify-refinement-convergence.sh" --root "$WORKDIR" --sample-task "$SAMPLE_TASK" --skip-direct-source >/dev/null 2>&1; then
  echo "FAIL: verifier passed before backlog wash" >&2
  exit 1
fi

bash "$ROOT_DIR/scripts/backfill-refinement-predecessor-audit.sh" --root "$WORKDIR" --mode apply --format summary >/dev/null
bash "$ROOT_DIR/scripts/verify-refinement-convergence.sh" --root "$WORKDIR" --sample-task "$SAMPLE_TASK" --skip-direct-source >"$WORKDIR/full.txt"
grep -q '^safe_empty=0$' "$WORKDIR/full.txt"
grep -q '^validator_fail=0$' "$WORKDIR/full.txt"
grep -q 'PASS: refinement convergence verified' "$WORKDIR/full.txt"

echo "PASS: refinement convergence selftest"
