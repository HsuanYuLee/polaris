#!/usr/bin/env bash
# Selftest for migrate-design-plan-number.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATE="$ROOT_DIR/scripts/migrate-design-plan-number.sh"
UNIQUE="$ROOT_DIR/scripts/validate-dp-number-uniqueness.sh"
tmpdir="$(mktemp -d -t migrate-dp.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"
specs="$tmpdir/docs-manager/src/content/docs/specs"
mkdir -p "$specs/design-plans/DP-010-keeper" "$specs/design-plans/archive/DP-010-rename/tasks"
cat >"$specs/design-plans/DP-010-keeper/plan.md" <<'MD'
---
title: "DP-010: Keeper"
description: "Keeper fixture."
status: IMPLEMENTED
priority: P4
sidebar:
  label: "DP-010: Keeper"
  order: 10
  badge:
    text: "IMPLEMENTED / P4"
    variant: "success"
---

## Context

Fixture.
MD
cat >"$specs/design-plans/archive/DP-010-rename/plan.md" <<'MD'
---
title: "DP-010: Rename me"
description: "Rename fixture."
status: IMPLEMENTED
priority: P4
sidebar:
  label: "DP-010: Rename me"
  order: 10
  badge:
    text: "IMPLEMENTED / P4"
    variant: "success"
---

## Link

See DP-010 and DP-010-rename.
MD
cat >"$specs/design-plans/archive/DP-010-rename/tasks/T1.md" <<'MD'
---
title: "DP-010-T1: Rename task"
description: "Task fixture."
status: IMPLEMENTED
---

# T1

Task for DP-010.
MD

"$UNIQUE" --specs-root "$specs" --report >/tmp/migrate-before.out
grep -q 'DP-010' /tmp/migrate-before.out

new_path="$("$MIGRATE" --from "$specs/design-plans/archive/DP-010-rename" --to DP-011)"
[[ -d "$new_path" ]]
grep -q 'DP-011' "$new_path/plan.md"
grep -q 'DP-011-T1' "$new_path/tasks/T1.md"
"$UNIQUE" --specs-root "$specs" >/tmp/migrate-after.out
grep -q 'PASS' /tmp/migrate-after.out

echo "PASS: migrate design plan number selftest"
