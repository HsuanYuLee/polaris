#!/usr/bin/env bash
# Selftest for scripts/sync-dp-sidebar-metadata.sh and validate-dp-metadata.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC="$SCRIPT_DIR/sync-dp-sidebar-metadata.sh"
VALIDATE="$SCRIPT_DIR/validate-dp-metadata.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t dp-sidebar-metadata.XXXXXX)"
trap 'rm -rf "$tmpdir" /tmp/dp-sidebar-metadata.out /tmp/dp-sidebar-metadata.err' EXIT

mkdir -p "$tmpdir/design-plans/DP-070-sidebar-metadata"

cat >"$tmpdir/design-plans/DP-070-sidebar-metadata/plan.md" <<'MD'
---
title: "DP sidebar metadata"
description: "Test Design Plan metadata sync."
topic: sidebar metadata
created: 2026-05-02
status: SEED
---

## Goal

Test.
MD

if bash "$SYNC" --check "$tmpdir/design-plans" >/tmp/dp-sidebar-metadata.out 2>/tmp/dp-sidebar-metadata.err; then
  fail "check unexpectedly passed before metadata sync"
fi

bash "$SYNC" --apply "$tmpdir/design-plans" >/tmp/dp-sidebar-metadata.out
grep -q "updated:" /tmp/dp-sidebar-metadata.out || fail "apply did not report update"
grep -q "status: SEEDED" "$tmpdir/design-plans/DP-070-sidebar-metadata/plan.md" || fail "status was not normalized"
grep -q "priority: P3" "$tmpdir/design-plans/DP-070-sidebar-metadata/plan.md" || fail "priority was not inferred"
grep -q 'text: "SEEDED / P3"' "$tmpdir/design-plans/DP-070-sidebar-metadata/plan.md" || fail "badge text missing"

bash "$SYNC" --check "$tmpdir/design-plans" >/tmp/dp-sidebar-metadata.out
grep -q "PASS: spec sidebar metadata check" /tmp/dp-sidebar-metadata.out || fail "check did not pass after sync"

bash "$VALIDATE" "$tmpdir/design-plans" >/tmp/dp-sidebar-metadata.out
grep -q "PASS: DP metadata validation" /tmp/dp-sidebar-metadata.out || fail "validator did not pass"

echo "[selftest] PASS"
