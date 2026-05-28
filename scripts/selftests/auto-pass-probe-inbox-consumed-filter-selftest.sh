#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SRC="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-959-fixture"
mkdir -p "$SRC/refinement-inbox" "$TMP/.polaris/evidence/task-snapshot"

cat >"$SRC/index.md" <<'MD'
---
title: "DP-959 fixture"
description: "auto-pass probe consumed inbox fixture"
status: LOCKED
---

## Fixture
MD

cat >"$SRC/refinement.md" <<'MD'
---
title: "DP-959 refinement"
description: "auto-pass probe consumed inbox fixture"
---

## Scope

fixture
MD

cat >"$SRC/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-959"},
  "modules": [],
  "acceptance_criteria": []
}
JSON

cat >"$SRC/refinement-inbox/consumed.md" <<'MD'
---
title: "Consumed"
description: "Already consumed"
consumed: true
---

Consumed.
MD

cat >"$TMP/.polaris/evidence/task-snapshot/DP-959-T1.json" <<'JSON'
{
  "schema_version": 1,
  "marker_kind": "task_snapshot",
  "writer": "selftest",
  "owning_skill": "selftest",
  "source_id": "DP-959",
  "work_item_id": "DP-959-T1",
  "status": "PASS"
}
JSON

probe_next() {
  "$PROBE" --repo "$TMP" --stage breakdown --source-id DP-959 --work-item-id DP-959-T1 \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("next_action"))'
}

if [[ "$(probe_next)" != "engineering" ]]; then
  echo "FAIL: consumed inbox file should not route back to refinement" >&2
  exit 1
fi

cat >"$SRC/refinement-inbox/unconsumed.md" <<'MD'
---
title: "Unconsumed"
description: "Needs amendment"
---

Needs amendment.
MD

if [[ "$(probe_next)" != "refinement_amendment" ]]; then
  echo "FAIL: unconsumed inbox file should route back to refinement" >&2
  exit 1
fi

echo "PASS: auto-pass probe consumed inbox filter"
