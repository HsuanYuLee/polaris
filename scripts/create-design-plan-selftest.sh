#!/usr/bin/env bash
# Selftest for create-design-plan.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CREATE="$ROOT_DIR/scripts/create-design-plan.sh"
tmpdir="$(mktemp -d -t create-dp.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"
specs="$tmpdir/specs"
mkdir -p "$specs/design-plans/archive/DP-099-archived"
cat >"$specs/design-plans/archive/DP-099-archived/plan.md" <<'MD'
---
title: "DP-099: 已封存"
description: "封存 DP fixture。"
status: IMPLEMENTED
priority: P4
sidebar:
  label: "DP-099: 已封存"
  order: 99
  badge:
    text: "IMPLEMENTED / P4"
    variant: "success"
---

## Context

Fixture.
MD

plan="$("$CREATE" --specs-root "$specs" "測試 create command")"
[[ "$plan" == *"DP-100-"*"plan.md" ]]
grep -q '^priority: P2$' "$plan"
grep -q '^sidebar:' "$plan"

plan_p1="$("$CREATE" --specs-root "$specs" --priority P1 "測試 priority")"
grep -q '^priority: P1$' "$plan_p1"

if "$CREATE" --specs-root "$specs" --number DP-100 "撞號測試" >/tmp/create-dp-collision.out 2>&1; then
  echo "not ok collision should fail" >&2
  exit 1
fi
grep -q 'already exists' /tmp/create-dp-collision.out

echo "PASS: create design plan selftest"
