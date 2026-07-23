#!/usr/bin/env bash
# Selftest for create-design-plan.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
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

# DP-437: default-mode creation from a linked worktree with no local-only specs
# overlay must allocate and write against the canonical main checkout specs root.
# Explicit --specs-root fixtures above retain their caller-supplied semantics.
canonical_repo="$tmpdir/canonical-repo"
linked_worktree="$tmpdir/canonical-linked"
mkdir -p "$canonical_repo"
git -C "$canonical_repo" init -q
git -C "$canonical_repo" config user.email selftest@example.test
git -C "$canonical_repo" config user.name "Self Test"
cat >"$canonical_repo/workspace-config.yaml" <<'YAML'
language: zh-TW
YAML
git -C "$canonical_repo" add workspace-config.yaml
git -C "$canonical_repo" commit -qm init

canonical_specs="$canonical_repo/docs-manager/src/content/docs/specs"
mkdir -p "$canonical_specs/design-plans/archive/DP-437-existing"
cat >"$canonical_specs/design-plans/archive/DP-437-existing/index.md" <<'MD'
---
title: "DP-437: 既有 canonical source"
description: "驗證 linked worktree 配號仍讀取 canonical archive。"
status: IMPLEMENTED
priority: P4
sidebar:
  label: "DP-437: 既有 canonical source"
  order: 437
  badge:
    text: "IMPLEMENTED / P4"
    variant: "success"
---

## Goal

Fixture。
MD

git -C "$canonical_repo" worktree add -q -b test-linked "$linked_worktree" HEAD
linked_plan="$(cd "$linked_worktree" && "$CREATE" "隔離 worktree canonical 配號")"
[[ "$linked_plan" == "$canonical_specs/design-plans/DP-438-"*"/index.md" ]] || {
  echo "not ok linked worktree should allocate DP-438 in canonical specs: $linked_plan" >&2
  exit 1
}
[[ -f "$linked_plan" ]]
[[ ! -d "$linked_worktree/docs-manager/src/content/docs/specs/design-plans" ]]

# An explicit workspace authority that points at a linked worktree without the
# local-only specs tree must fail closed instead of manufacturing a partial
# inventory there.
linked_override_out=""
linked_override_rc=0
linked_override_out="$(cd "$linked_worktree" && POLARIS_WORKSPACE_ROOT="$linked_worktree" "$CREATE" "錯誤 workspace override 不得落 local" 2>&1)" || linked_override_rc=$?
[[ "$linked_override_rc" -eq 2 ]] || {
  echo "not ok linked POLARIS_WORKSPACE_ROOT should fail closed, got $linked_override_rc: $linked_override_out" >&2
  exit 1
}
grep -q "POLARIS_DP_CANONICAL_SPECS_ROOT_UNRESOLVED" <<<"$linked_override_out"
[[ ! -d "$linked_worktree/docs-manager/src/content/docs/specs/design-plans" ]]

# POLARIS_SPECS_ROOT remains the existing explicit specs authority. When it
# points at the canonical inventory it may recover the same linked-worktree call.
explicit_specs_plan="$(cd "$linked_worktree" && POLARIS_WORKSPACE_ROOT="$linked_worktree" POLARIS_SPECS_ROOT="$canonical_specs" "$CREATE" "顯式 canonical specs authority")"
[[ "$explicit_specs_plan" == "$canonical_specs/design-plans/DP-439-"*"/index.md" ]] || {
  echo "not ok POLARIS_SPECS_ROOT should allocate DP-439 canonically: $explicit_specs_plan" >&2
  exit 1
}
[[ -f "$explicit_specs_plan" ]]
[[ ! -d "$linked_worktree/docs-manager/src/content/docs/specs/design-plans" ]]

echo "PASS: create design plan selftest"
