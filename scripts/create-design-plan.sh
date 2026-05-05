#!/usr/bin/env bash
# Create a Design Plan container through the deterministic authoring gates.

set -euo pipefail

specs_root="docs-manager/src/content/docs/specs"
priority="P2"
status="DISCUSSION"
number=""
topic=""

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

dp_number_exists() {
  local base_dir="$1"
  local candidate="$2"
  compgen -G "$base_dir/$candidate-*/plan.md" >/dev/null \
    || compgen -G "$base_dir/$candidate-*/index.md" >/dev/null \
    || compgen -G "$base_dir/archive/$candidate-*/plan.md" >/dev/null \
    || compgen -G "$base_dir/archive/$candidate-*/index.md" >/dev/null
}

if [[ -z "$number" ]]; then
  number="$(bash scripts/allocate-design-plan-number.sh --specs-root "$specs_root")"
  base_for_allocation="$specs_root/design-plans"
  while dp_number_exists "$base_for_allocation" "$number"; do
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

base="$specs_root/design-plans"
mkdir -p "$base"
if dp_number_exists "$base" "$number"; then
  echo "error: $number already exists in active or archive design-plans" >&2
  exit 1
fi

container="$base/$number-$slug"
plan="$container/index.md"
mkdir -p "$container"
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

## Context

這份 Design Plan 由 \`scripts/create-design-plan.sh\` 建立，後續由 refinement 補齊內容。
MD

bash scripts/validate-starlight-authoring.sh check "$plan" >/dev/null
bash scripts/validate-language-policy.sh --blocking --mode artifact "$plan" >/dev/null
bash scripts/validate-handbook-path-contract.sh >/dev/null
bash scripts/validate-route-safe-spec-paths.sh "$container" >/dev/null
if [[ -x scripts/validate-dp-number-uniqueness.sh ]]; then
  bash scripts/validate-dp-number-uniqueness.sh --plan "$plan" >/dev/null
fi
printf '%s\n' "$plan"
