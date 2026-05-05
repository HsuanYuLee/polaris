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

Creates docs-manager/src/content/docs/specs/design-plans/DP-NNN-slug/plan.md,
where DP-NNN is allocated from active + archive parent plans unless --number is
provided. The generated plan is immediately validated by
validate-dp-plan-authoring.sh.
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
if [[ -z "$number" ]]; then
  number="$(bash scripts/allocate-design-plan-number.sh --specs-root "$specs_root")"
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
if compgen -G "$base/$number-*/plan.md" >/dev/null || compgen -G "$base/archive/$number-*/plan.md" >/dev/null; then
  echo "error: $number already exists in active or archive design-plans" >&2
  exit 1
fi

container="$base/$number-$slug"
plan="$container/plan.md"
mkdir -p "$container"
created="$(date +%F)"

cat >"$plan" <<MD
---
title: "$number: $topic"
description: "$topic 的 Design Plan。"
topic: "$topic"
created: $created
status: $status
priority: $priority
---

## Context

這份 Design Plan 由 \`scripts/create-design-plan.sh\` 建立，後續由 refinement 補齊內容。
MD

bash scripts/validate-dp-plan-authoring.sh "$plan" >/dev/null
printf '%s\n' "$plan"
