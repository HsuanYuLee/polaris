#!/usr/bin/env bash
# Create a Design Plan container through the deterministic authoring gates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
specs_root="docs-manager/src/content/docs/specs"
specs_root_explicit=0
priority="P2"
status="DISCUSSION"
number=""
topic=""
lock_dir=""

cleanup_lock() {
  if [[ -n "$lock_dir" && -d "$lock_dir" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

acquire_lock() {
  local target="$1"
  local attempt=0
  while ! mkdir "$target" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ "$attempt" -ge 200 ]]; then
      echo "error: timed out waiting for design-plan allocation lock: $target" >&2
      exit 1
    fi
    sleep 0.05
  done
  lock_dir="$target"
  trap cleanup_lock EXIT
}

usage() {
  cat >&2 <<'EOF'
usage: create-design-plan.sh [--specs-root <path>] [--number DP-NNN] [--priority P0..P4] <topic>

Creates docs-manager/src/content/docs/specs/design-plans/DP-NNN-slug/index.md,
where DP-NNN is allocated from active + archive parent plans unless --number is
provided. Legacy readers still support existing plan.md containers, but new
Design Plan containers are folder-native.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --specs-root)
      specs_root="${2:-}"
      specs_root_explicit=1
      shift 2
      ;;
    --number)
      number="${2:-}"
      shift 2
      ;;
    --priority)
      priority="${2:-}"
      shift 2
      ;;
    --status)
      status="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage
      ;;
    *)
      topic="${topic:+$topic }$1"
      shift
      ;;
  esac
done

if [[ -z "$topic" ]]; then
  usage
fi
if [[ ! "$priority" =~ ^P[0-4]$ ]]; then
  echo "error: invalid priority: $priority" >&2
  exit 2
fi
if [[ ! "$status" =~ ^(SEEDED|DISCUSSION|LOCKED|IMPLEMENTING|IMPLEMENTED|ABANDONED)$ ]]; then
  echo "error: invalid status: $status" >&2
  exit 2
fi

# DP-437: local-only specs do not materialize in linked worktrees. In default
# workspace mode, bind allocation and the write target to the canonical main
# checkout before looking at active/archive inventory. An explicit --specs-root
# remains caller-owned so hermetic fixtures keep their isolated semantics.
if [[ "$specs_root_explicit" -eq 0 ]]; then
  # shellcheck source=lib/specs-root.sh
  . "$SCRIPT_DIR/lib/specs-root.sh"
  canonical_workspace_root="$(resolve_specs_workspace_root "$(pwd)" 2>/dev/null || true)"
  if [[ -z "$canonical_workspace_root" ]]; then
    echo "POLARIS_DP_CANONICAL_SPECS_ROOT_UNRESOLVED: cannot resolve canonical workspace from $(pwd)" >&2
    exit 2
  fi
  specs_root="$(resolve_specs_root "$canonical_workspace_root" 2>/dev/null || true)"
  if [[ -z "$specs_root" || ! -d "$specs_root" ]]; then
    echo "POLARIS_DP_CANONICAL_SPECS_ROOT_UNRESOLVED: cannot resolve canonical specs root from $canonical_workspace_root" >&2
    exit 2
  fi
fi

dp_number_exists() {
  local base_dir="$1"
  local candidate="$2"
  compgen -G "$base_dir/$candidate-*/plan.md" >/dev/null \
    || compgen -G "$base_dir/$candidate-*/index.md" >/dev/null \
    || compgen -G "$base_dir/archive/$candidate-*/plan.md" >/dev/null \
    || compgen -G "$base_dir/archive/$candidate-*/index.md" >/dev/null
}

base="$specs_root/design-plans"
mkdir -p "$base"
acquire_lock "$base/.create-design-plan.lock"

if [[ -z "$number" ]]; then
  number="$(bash "$SCRIPT_DIR/allocate-design-plan-number.sh" --specs-root "$specs_root")"
  while dp_number_exists "$base" "$number"; do
    next_number="$((10#${number#DP-} + 1))"
    number="$(printf 'DP-%03d' "$next_number")"
  done
fi
if [[ ! "$number" =~ ^DP-[0-9]{3}$ ]]; then
  echo "error: invalid DP number: $number" >&2
  exit 2
fi

slug="$(python3 - "$topic" <<'PY'
import re
import sys
topic = sys.argv[1].strip().lower()
topic = re.sub(r"[^a-z0-9]+", "-", topic).strip("-")
print(topic or "design-plan")
PY
)"

if dp_number_exists "$base" "$number"; then
  echo "error: $number already exists in active or archive design-plans" >&2
  exit 1
fi

container="$base/$number-$slug"
plan="$container/index.md"
mkdir -p "$container"
cleanup_lock
trap - EXIT
created="$(date +%F)"
order="${number#DP-}"
order="$((10#$order))"
case "$status" in
  IMPLEMENTED) badge_variant="success" ;;
  ABANDONED) badge_variant="danger" ;;
  IMPLEMENTING) badge_variant="caution" ;;
  LOCKED) badge_variant="tip" ;;
  SEEDED|DISCUSSION) badge_variant="note" ;;
esac

cat >"$plan" <<MD
---
title: "$number: $topic"
description: "$topic 的 Design Plan。"
topic: "$topic"
created: $created
status: $status
priority: $priority
sidebar:
  label: "$number: $topic"
  order: $order
  badge:
    text: "$status / $priority"
    variant: "$badge_variant"
---

## Goal

說明這張 DP 要解決的核心問題與預期成果。

## Background

這份 Design Plan 由 \`scripts/create-design-plan.sh\` 建立，後續由 refinement 補齊內容。
Template contract：本文件與 JIRA Epic refinement 共用
\`.claude/skills/references/refinement-source-template.md\` 的 canonical source sections。

## Scope

- 待補。

## Out of Scope

- 待補。

## Target State

描述 migration 完成後的最終 source of truth、runtime ownership 與 steady-state 行為。

## Decision Policy

列出此題選擇 direct migration / phased delivery / compatibility bridge 的決策規則。

## Migration Boundaries

若存在 temporary compatibility、fallback、mirror、dual-write 等機制，需列 owner、移除條件、
驗證方式與 follow-up task；沒有則寫 N/A。

## Decisions

- 待補。

## Blind Spots

- 待補。

## Acceptance Criteria

### 功能 AC

- 待補。

### 非功能 AC

- 若不適用請寫 N/A 並附原因。

### 負面 AC

- 待補。

### 驗證方式

- 每條 AC 對應一種驗證方法：playwright / lighthouse / curl / unit_test / manual。

## Technical Approach

說明預計影響的模組、交付邊界與主要風險。

## Dependencies

- 待補。

## Open Questions

- 待補。

## Downstream Breakdown Hints

- 待補。
MD

bash "$SCRIPT_DIR/validate-starlight-authoring.sh" check "$plan" >/dev/null
bash "$SCRIPT_DIR/validate-language-policy.sh" --blocking --mode artifact "$plan" >/dev/null
bash "$SCRIPT_DIR/validate-handbook-path-contract.sh" >/dev/null
bash "$SCRIPT_DIR/validate-route-safe-spec-paths.sh" "$container" >/dev/null
if [[ -x "$SCRIPT_DIR/validate-dp-number-uniqueness.sh" ]]; then
  bash "$SCRIPT_DIR/validate-dp-number-uniqueness.sh" --plan "$plan" >/dev/null
fi
printf '%s\n' "$plan"
