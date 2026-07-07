#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
collector="$ROOT/scripts/lib/refinement-handoff-advisory-collector.py"
tmp="$(mktemp -d -t refinement-advisory-collector.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

write_dp_fixture() {
  local dir="$1"
  local modules_json="$2"
  local advisories_json="${3:-null}"
  mkdir -p "$dir"
  cat >"$dir/index.md" <<'MD'
---
title: "Fixture"
description: "Fixture"
status: LOCKED
---
MD
  python3 - "$dir/refinement.json" "$dir" "$modules_json" "$advisories_json" <<'PY'
import json
import sys
from pathlib import Path

target, container, modules_json, advisories_json = sys.argv[1:]
modules = json.loads(modules_json)
advisories = json.loads(advisories_json)
payload = {
    "schema_version": 1,
    "epic": None,
    "source": {
        "type": "dp",
        "id": "DP-999",
        "container": container,
        "plan_path": f"{container}/index.md",
        "jira_key": None,
    },
    "version": "1.0",
    "tier": 2,
    "created_at": "2026-07-07T00:00:00Z",
    "modules": modules,
    "dependencies": [],
    "predecessor_audit": [],
    "edge_cases": [],
    "acceptance_criteria": [
        {
            "id": "AC1",
            "text": "advisory fixture",
            "category": "functional",
            "verification": {"method": "unit_test", "detail": "collector selftest"},
            "negative": False,
        }
    ],
    "tasks": [
        {
            "id": "DP-999-T1",
            "kind": "implementation",
            "title": "fixture",
            "scope": "fixture",
            "modules": [m["path"] for m in modules],
            "ac_ids": ["AC1"],
            "dependencies": [],
            "verification": {"method": "unit_test", "detail": "collector selftest"},
        }
    ],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "missing advisory", "enforce": "collector blocks"}],
}
if advisories is not None:
    payload["handoff_advisories"] = advisories
Path(target).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_dp_fixture "$tmp/legacy" '[{"path":"docs/readme.md","action":"modify"}]'
python3 "$collector" "$tmp/legacy/refinement.json"

write_dp_fixture "$tmp/missing" '[{"path":"scripts/fixture-driver.sh","action":"create"}]'
if python3 "$collector" "$tmp/missing/refinement.json" 2>"$tmp/missing.err"; then
  echo "FAIL: framework-touching fixture without durable advisory passed" >&2
  exit 1
fi
grep -q "POLARIS_REFINEMENT_HANDOFF_ADVISORY_MISSING" "$tmp/missing.err"

write_dp_fixture "$tmp/absorbed" \
  '[{"path":"scripts/fixture-driver.sh","action":"create"}]' \
  '[{"id":"framework-release-surface-missing","producer":"refinement-release-surface-advisory","severity":"actionable","recommended_action":"absorbed","disposition":"absorbed_by_task","task_ids":["DP-999-T1"]}]'
python3 "$collector" "$tmp/absorbed/refinement.json"

write_dp_fixture "$tmp/pending" \
  '[{"path":"scripts/fixture-driver.sh","action":"create"}]' \
  '[{"id":"framework-release-surface-missing","producer":"refinement-release-surface-advisory","severity":"actionable","recommended_action":"pending","disposition":"pending"}]'
if python3 "$collector" "$tmp/pending/refinement.json" 2>"$tmp/pending.err"; then
  echo "FAIL: pending durable advisory passed" >&2
  exit 1
fi
grep -q "POLARIS_REFINEMENT_HANDOFF_ADVISORY_PENDING" "$tmp/pending.err"

echo "PASS: refinement handoff advisory collector"
