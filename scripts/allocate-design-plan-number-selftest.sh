#!/usr/bin/env bash
# Selftest for DP number allocation and uniqueness validation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ALLOC="$ROOT_DIR/scripts/allocate-design-plan-number.sh"
UNIQUE="$ROOT_DIR/scripts/validate-dp-number-uniqueness.sh"
tmpdir="$(mktemp -d -t dp-number.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

specs="$tmpdir/specs"
mkdir -p "$specs/design-plans/DP-010-active" "$specs/design-plans/archive/DP-099-archived"
touch "$specs/design-plans/DP-010-active/plan.md" "$specs/design-plans/archive/DP-099-archived/plan.md"

next="$("$ALLOC" --specs-root "$specs")"
if [[ "$next" != "DP-100" ]]; then
  echo "not ok expected DP-100, got $next" >&2
  exit 1
fi

mkdir -p "$specs/design-plans/DP-050-a" "$specs/design-plans/DP-050-b"
touch "$specs/design-plans/DP-050-a/plan.md" "$specs/design-plans/DP-050-b/plan.md"
if "$UNIQUE" --specs-root "$specs" >/tmp/dp-unique-active.out 2>&1; then
  echo "not ok active duplicate should fail" >&2
  exit 1
fi
grep -q 'DP-050' /tmp/dp-unique-active.out

rm -rf "$specs/design-plans/DP-050-a" "$specs/design-plans/DP-050-b"
mkdir -p "$specs/design-plans/DP-060-active" "$specs/design-plans/archive/DP-060-archived"
touch "$specs/design-plans/DP-060-active/plan.md" "$specs/design-plans/archive/DP-060-archived/plan.md"
if "$UNIQUE" --specs-root "$specs" >/tmp/dp-unique-active-archive.out 2>&1; then
  echo "not ok active+archive duplicate should fail" >&2
  exit 1
fi
grep -q 'active + archive' /tmp/dp-unique-active-archive.out

rm -rf "$specs/design-plans/DP-060-active" "$specs/design-plans/archive/DP-060-archived"
mkdir -p "$specs/design-plans/archive/DP-070-a" "$specs/design-plans/archive/DP-070-b"
touch "$specs/design-plans/archive/DP-070-a/plan.md" "$specs/design-plans/archive/DP-070-b/plan.md"
"$UNIQUE" --specs-root "$specs" --report >/tmp/dp-unique-report.out
grep -q 'archive + archive' /tmp/dp-unique-report.out

echo "PASS: DP number allocator selftest"
