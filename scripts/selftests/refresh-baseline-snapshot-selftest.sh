#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFRESH="$ROOT/scripts/refresh-baseline-snapshot.sh"
INTAKE="$ROOT/scripts/validate-breakdown-escalation-intake.sh"
TMP="$(mktemp -d -t dp207-refresh-baseline.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name "Baseline Refresh Test"
mkdir -p "$repo/tasks/T10" "$repo/.polaris/evidence/baseline-snapshot"
cat >"$repo/tasks/T10/index.md" <<'MD'
---
title: "DP-207 T10: baseline snapshot refresh (3 pt)"
depends_on: [T9]
---

# T10: baseline snapshot refresh (3 pt)

> Source: DP-207 | Task: DP-207-T10 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Base branch | task/DP-207-T9-auto-pass-closeout-chain |
| Task branch | task/DP-207-T10-baseline-snapshot-refresh |

## Allowed Files

- `scripts/refresh-baseline-snapshot.sh`

## Verify Command

```bash
echo "PASS: DP-207-T10 baseline snapshot refresh"
```
MD
git -C "$repo" add tasks/T10/index.md
git -C "$repo" commit -q -m base
old_head="$(git -C "$repo" rev-parse --short=12 HEAD)"

bash "$REFRESH" --repo "$repo" --task-md "$repo/tasks/T10/index.md" --head-sha "$old_head" >/tmp/dp207-refresh-old.out
old_snapshot="$(cat /tmp/dp207-refresh-old.out)"
[[ -f "$old_snapshot" ]] || { echo "FAIL: old snapshot missing" >&2; exit 1; }

python3 - "$repo/tasks/T10/index.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("echo \"PASS: DP-207-T10 baseline snapshot refresh\"", "echo \"PASS: DP-207-T10 baseline snapshot refresh updated\"")
path.write_text(text, encoding="utf-8")
PY
git -C "$repo" add tasks/T10/index.md
git -C "$repo" commit -q -m update
new_head="$(git -C "$repo" rev-parse --short=12 HEAD)"

sidecar="$TMP/T10-1.md"
cat >"$sidecar" <<'MD'
---
skill: engineering
ticket: DP-207-T10
epic: DP-207
flavor: plan-defect
escalation_count: 1
timestamp: 2026-05-20T10:00:00Z
truncated: false
scrubbed: true
---

## Summary

Planner-owned verify command needs task_update.

## Closure Forecast

Yes - task_update closes the gate.

## Required Planner Decisions

1. Fold verify command update into the current task and refresh baseline snapshot.
MD

bash "$INTAKE" \
  --sidecar "$sidecar" \
  --route task_update \
  --closes-gate true \
  --flavor plan-defect \
  --disposition "accepted flavor: plan-defect" \
  --decision "baseline task_update accepted and baseline snapshot refreshed" \
  --repo "$repo" \
  --task-md "$repo/tasks/T10/index.md" \
  --head-sha "$new_head" >/tmp/dp207-intake-refresh.out

new_snapshot="$repo/.polaris/evidence/baseline-snapshot/DP-207-T10-${new_head}.json"
[[ -f "$new_snapshot" ]] || { echo "FAIL: new snapshot missing" >&2; exit 1; }
[[ -f "${old_snapshot}.superseded" ]] || { echo "FAIL: old snapshot was not superseded" >&2; exit 1; }
bash "$ROOT/scripts/validate-task-md.sh" --snapshot "$new_snapshot" "$repo/tasks/T10/index.md" >/tmp/dp207-refresh-snapshot-validate.out

echo "PASS: refresh baseline snapshot selftest"
