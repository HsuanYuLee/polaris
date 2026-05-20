#!/usr/bin/env bash
# Selftest for scripts/audit-dogfood-evidence.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/audit-dogfood-evidence.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

write_entry() {
  local path="$1"
  local category="$2"
  local consumed_block="${3:-}"
  local proposed_fix="${4:-Add a deterministic gate.}"

  cat >"$path" <<EOF
---
title: "DP-207 dogfood: fixture"
description: "Fixture entry."
draft: true
sidebar:
  hidden: true
$consumed_block
---

## Observed

Observed signal.

## Judgment

Judgment signal.

## Category

$category

## Proposed Fix

$proposed_fix
EOF
}

valid="$tmpdir/valid"
mkdir "$valid"
write_entry "$valid/2026-05-20-valid-gap.md" "deterministic-gap" $'consumed: true\nconsumed_by:\n  - DP-207-T14\n'
write_entry "$valid/2026-05-20-valid-nondeterministic.md" "dp-207-spec-bug" ""
bash "$SCRIPT" "$valid"
bash "$SCRIPT" --require-consumed "$valid"

unconsumed="$tmpdir/unconsumed"
mkdir "$unconsumed"
write_entry "$unconsumed/2026-05-20-unconsumed-gap.md" "deterministic-gap" ""
bash "$SCRIPT" "$unconsumed"
if bash "$SCRIPT" --require-consumed "$unconsumed" >/tmp/audit-dogfood-unconsumed.out 2>/tmp/audit-dogfood-unconsumed.err; then
  echo "FAIL: --require-consumed accepted an unconsumed deterministic-gap entry" >&2
  exit 1
fi
grep -q "requires consumed: true" /tmp/audit-dogfood-unconsumed.err

bad_category="$tmpdir/bad-category"
mkdir "$bad_category"
write_entry "$bad_category/2026-05-20-bad-category.md" "unsure" ""
if bash "$SCRIPT" "$bad_category" >/tmp/audit-dogfood-category.out 2>/tmp/audit-dogfood-category.err; then
  echo "FAIL: invalid category was accepted" >&2
  exit 1
fi
grep -q "category must be one of" /tmp/audit-dogfood-category.err

missing_section="$tmpdir/missing-section"
mkdir "$missing_section"
write_entry "$missing_section/2026-05-20-missing-section.md" "non-dp-207" ""
perl -0pi -e 's/\n## Judgment\n\nJudgment signal\.\n//' "$missing_section/2026-05-20-missing-section.md"
if bash "$SCRIPT" "$missing_section" >/tmp/audit-dogfood-section.out 2>/tmp/audit-dogfood-section.err; then
  echo "FAIL: missing required section was accepted" >&2
  exit 1
fi
grep -q "missing required section ## Judgment" /tmp/audit-dogfood-section.err

echo "PASS: audit dogfood evidence selftest"
