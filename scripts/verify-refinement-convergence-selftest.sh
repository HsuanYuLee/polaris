#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
