#!/usr/bin/env bash
set -euo pipefail

make_refinement_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/index.md" <<'MD'
---
title: "Fixture"
description: "Fixture"
status: LOCKED
---
MD
  cat >"$dir/refinement.md" <<'MD'
---
title: "Fixture refinement"
description: "Fixture refinement"
---

# Fixture Refinement

## Predecessor Scan
- keyword: refinement gate
- hits: DP-229 fixture

## Decisions
- **D1：driver**。Enforced by: AC1

## Adversarial Pass
- **AC1** attack: missing driver; enforce: selftest

## Edge Cases
- **EC1**: input missing - fail loudly

## Risks
- **R1**: false positive - fixture coverage

## Modules
| Path | Action |
|------|--------|
| `scripts/fixture-driver.sh` | create |
| `scripts/selftests/fixture-driver-selftest.sh` | create |
MD
  cat >"$dir/refinement.json" <<JSON
{
  "schema_version": 1,
  "epic": null,
  "source": {"type": "dp", "id": "DP-999", "container": "$dir", "plan_path": "$dir/index.md", "jira_key": null},
  "version": "1.0",
  "tier": 2,
  "created_at": "2026-05-24T00:00:00Z",
  "modules": [
    {"path": "scripts/fixture-driver.sh", "action": "create", "complexity": "low", "risk": "low", "reason": "fixture"},
    {"path": "scripts/selftests/fixture-driver-selftest.sh", "action": "create", "complexity": "low", "risk": "low", "reason": "fixture"}
  ],
  "dependencies": [],
  "predecessor_audit": [],
  "edge_cases": [{"scenario": "input missing", "handling": "fail loudly", "severity": "low", "source": "ai_suggested"}],
  "acceptance_criteria": [
    {"id": "AC1", "text": "D1 fixture mentions fixture-driver.sh", "category": "functional", "verification": {"method": "unit_test", "detail": "bash scripts/selftests/fixture-driver-selftest.sh"}, "negative": false}
  ],
  "gaps": {"pm_questions": [], "rd_risks": [{"risk": "false positive", "severity": "low", "mitigation": "fixture coverage"}]},
  "tasks": [
    {"id": "DP-999-T1", "kind": "implementation", "title": "fixture", "scope": "fixture", "modules": ["scripts/fixture-driver.sh"], "ac_ids": ["AC1"], "dependencies": [], "verification": {"method": "unit_test", "detail": "fixture"}}
  ],
  "adversarial_pass": [
    {"ac_id": "AC1", "attack": "missing driver", "enforce": "selftest"}
  ]
}
JSON
}
