#!/usr/bin/env bash
# Purpose: DP-338 T2 (D2) — assert the auto-pass marker READER (probe / runner)
#          resolves the .polaris/evidence root SYMMETRICALLY with the marker
#          writer anchor. For a JIRA-Epic-backed source the spec container lives
#          in the Polaris workspace (docs-manager/.../specs/companies/{co}/{EPIC})
#          but the code / PR / breakdown evidence is written into the PRODUCT
#          repo ({workspace}/{Repo header}). The reader must therefore resolve
#          the product repo via the task.md `Repo:` header (the same authority
#          resolve-task-base.sh::derive_repo_path uses) and read evidence there,
#          NOT from the workspace `--repo` root, and NOT by band-aiding the
#          marker into the workspace root.
# Inputs:  none (builds hermetic fixtures under a mktemp dir)
# Outputs: stdout PASS/FAIL lines; exit 0 on PASS, non-zero on failure
#
# AC coverage:
#   AC2     — /auto-pass on a JIRA-Epic source finds the breakdown task-snapshot
#             marker in the product repo .polaris/evidence with no manual re-emit.
#   AC9     — single writer: D2 only changes the reader; the marker stays where
#             the writer put it (product repo). No second writer path is exercised
#             and the workspace root never receives the marker.
#   AC-NEG2 — no workspace-root band-aid: the marker exists ONLY in the product
#             repo; the reader must find it there. A JIRA-Epic source with the
#             marker absent from BOTH roots must fail-loud (blocked), never
#             silently pass by synthesizing a workspace-root fallback.
#   symmetry — DP-backed source evidence still resolves at the workspace `--repo`
#             root (the reader change must not regress the DP path).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SPECS="$TMP/docs-manager/src/content/docs/specs"
JIRA_CONTAINER="$SPECS/companies/exampleco/EXAMPLE-556"
DP_CONTAINER="$SPECS/design-plans/DP-900-fixture"
PRODUCT_REPO="$TMP/exampleco-web"

mkdir -p \
  "$JIRA_CONTAINER/tasks/T1" \
  "$DP_CONTAINER/tasks/T1" \
  "$PRODUCT_REPO/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/task-snapshot"

# ─── JIRA-Epic source fixture (container in workspace specs) ───────────────────
cat >"$JIRA_CONTAINER/index.md" <<'MD'
---
title: "EXAMPLE-556 fixture"
description: "JIRA-Epic source marker-reader fixture"
status: LOCKED
---

## Fixture
MD
cat >"$JIRA_CONTAINER/refinement.md" <<'MD'
---
title: "EXAMPLE-556 refinement"
description: "JIRA-Epic refinement"
---

## Scope
fixture
MD
cat >"$JIRA_CONTAINER/refinement.json" <<'JSON'
{"source": {"type": "jira", "id": "EXAMPLE-556"}, "modules": [], "acceptance_criteria": []}
JSON

# JIRA task.md carries `Repo: exampleco-web` — the writer anchor authority. The
# breakdown evidence for this work item was written into the PRODUCT repo, never
# the workspace root.
cat >"$JIRA_CONTAINER/tasks/T1/index.md" <<'MD'
---
title: "EXAMPLE-556 T1 fixture"
description: "JIRA-Epic task fixture"
status: IN_PROGRESS
task_kind: T
task_shape: implementation
---

# T1 fixture

> Epic: EXAMPLE-556 | JIRA: EXAMPLE-557 | Repo: exampleco-web

## Fixture
MD

# ─── DP-backed source fixture (symmetry guard) ────────────────────────────────
cat >"$DP_CONTAINER/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "DP source marker-reader symmetry fixture"
status: LOCKED
---

## Fixture
MD
cat >"$DP_CONTAINER/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "DP refinement"
---

## Scope
fixture
MD
cat >"$DP_CONTAINER/refinement.json" <<'JSON'
{"source": {"type": "dp", "id": "DP-900"}, "modules": [], "acceptance_criteria": []}
JSON

write_snapshot_marker() {
  local path="$1" source_id="$2" work_item_id="$3"
  python3 - "$path" "$source_id" "$work_item_id" <<'PY'
import json, sys
from pathlib import Path
path, source_id, work_item_id = sys.argv[1:4]
payload = {
    "schema_version": 1,
    "marker_kind": "task_snapshot",
    "writer": "selftest",
    "owning_skill": "selftest",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": "PASS",
    "freshness": {"head_sha": "abc1234"},
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

probe_field() {
  local field="$1"; shift
  "$PROBE" --repo "$TMP" "$@" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field'))"
}

assert_probe_field() {
  local label="$1" expected="$2"; shift 2
  local actual
  actual="$(probe_field "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label expected $expected got $actual" >&2
    exit 1
  fi
  echo "ok: $label -> $actual"
}

# ─── AC2: JIRA-Epic source marker lives in the product repo; reader finds it ───
# Writer anchor: product repo .polaris/evidence (cwd at breakdown emit = product
# repo worktree). The orchestrator invokes the probe with --repo = workspace root.
write_snapshot_marker \
  "$PRODUCT_REPO/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" \
  EXAMPLE-556 EXAMPLE-556-T1
assert_probe_field "jira-marker-in-product-repo-found" "engineering" next_action \
  --stage breakdown --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-T1

# ─── AC-NEG2: the marker is ONLY in the product repo — never the workspace root ─
# Prove there is no band-aid copy at the workspace root.
if [[ -f "$TMP/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" ]]; then
  echo "FAIL: AC-NEG2 marker leaked into workspace root (band-aid)" >&2
  exit 1
fi
echo "ok: AC-NEG2 marker not present at workspace root"

# ─── AC-NEG2: marker absent from BOTH roots → fail-loud (blocked), no fallback ─
rm -f "$PRODUCT_REPO/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json"
assert_probe_field "jira-marker-absent-blocks" "blocked_by_gate_failure" terminal_status \
  --stage breakdown --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-T1
# And it must NOT have synthesized a workspace-root marker to mask the gap.
if [[ -f "$TMP/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" ]]; then
  echo "FAIL: AC-NEG2 reader synthesized a workspace-root marker on miss" >&2
  exit 1
fi
echo "ok: AC-NEG2 no workspace-root synthesis on miss"

# ─── symmetry: DP-backed source marker still resolves at the workspace root ────
write_snapshot_marker \
  "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" \
  DP-900 DP-900-T1
assert_probe_field "dp-marker-at-workspace-root-found" "engineering" next_action \
  --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

# ─── runner parity: runner mirrors the probe decision for the JIRA-Epic case ───
write_snapshot_marker \
  "$PRODUCT_REPO/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" \
  EXAMPLE-556 EXAMPLE-556-T1
runner_field() {
  local field="$1"; shift
  "$RUNNER" --repo "$TMP" "$@" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field'))"
}
runner_next="$(runner_field next_action --stage breakdown --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-T1)"
if [[ "$runner_next" != "dispatch" ]]; then
  echo "FAIL: runner-jira-marker-in-product-repo expected dispatch got $runner_next" >&2
  exit 1
fi
echo "ok: runner-jira-marker-in-product-repo -> dispatch"

echo "PASS: auto-pass marker product-repo reader selftest"
