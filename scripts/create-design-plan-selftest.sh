#!/usr/bin/env bash
# Selftest for create-design-plan.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CREATE="$ROOT_DIR/scripts/create-design-plan.sh"
tmpdir_rel="tmp-fixtures/create-dp-selftest-$$"
tmpdir="$ROOT_DIR/$tmpdir_rel"
rm -rf "$tmpdir"
mkdir -p "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"
specs="$tmpdir_rel/specs"
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
[[ "$plan" == *"DP-100-"*"index.md" ]]
grep -q '^priority: P2$' "$plan"
grep -q '^sidebar:' "$plan"
[[ ! -f "$(dirname "$plan")/plan.md" ]]

plan_p1="$("$CREATE" --specs-root "$specs" --priority P1 "測試 priority")"
grep -q '^priority: P1$' "$plan_p1"
[[ "$plan_p1" == *"index.md" ]]

if "$CREATE" --specs-root "$specs" --number DP-100 "撞號測試" >/tmp/create-dp-collision.out 2>&1; then
  echo "not ok collision should fail" >&2
  exit 1
fi
grep -q 'already exists' /tmp/create-dp-collision.out

specs_parallel="$tmpdir_rel/specs-parallel"
mkdir -p "$specs_parallel/design-plans/archive/DP-099-archived"
cp "$specs/design-plans/archive/DP-099-archived/plan.md" "$specs_parallel/design-plans/archive/DP-099-archived/plan.md"
(
  "$CREATE" --specs-root "$specs_parallel" "平行測試 A" >/tmp/create-dp-parallel-a.out 2>/tmp/create-dp-parallel-a.err
) &
pid_a=$!
(
  "$CREATE" --specs-root "$specs_parallel" "平行測試 B" >/tmp/create-dp-parallel-b.out 2>/tmp/create-dp-parallel-b.err
) &
pid_b=$!
if ! wait "$pid_a"; then
  cat /tmp/create-dp-parallel-a.err >&2 || true
  exit 1
fi
if ! wait "$pid_b"; then
  cat /tmp/create-dp-parallel-b.err >&2 || true
  exit 1
fi

plan_a="$(cat /tmp/create-dp-parallel-a.out)"
plan_b="$(cat /tmp/create-dp-parallel-b.out)"
[[ "$plan_a" != "$plan_b" ]]
[[ "$plan_a" == *"DP-100-"*"index.md" || "$plan_b" == *"DP-100-"*"index.md" ]]
[[ "$plan_a" == *"DP-101-"*"index.md" || "$plan_b" == *"DP-101-"*"index.md" ]]

echo "PASS: create design plan selftest"
