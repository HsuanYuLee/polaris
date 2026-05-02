#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC="$SCRIPT_DIR/sync-spec-sidebar-metadata.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t sync-spec-sidebar.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p \
  "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-065-task-gate-contract-hardening" \
  "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1"

cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-065-task-gate-contract-hardening/plan.md" <<'MD'
---
title: "DP-065：task / gate contract hardening"
status: IMPLEMENTED
priority: P2
sidebar:
  label: "DP-065：task / gate contract hardening"
  order: 65
  badge:
    text: "LOCKED / P2"
    variant: "note"
---

# DP-065
MD

cat >"$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" <<'MD'
---
title: "BUG-1 修正"
status: IMPLEMENTED
sidebar:
  label: "BUG-1 custom"
  order: 7
  badge:
    text: "DISCUSSION"
    variant: "note"
---

# BUG-1
MD

if bash "$SYNC" --check "$tmpdir/docs-manager/src/content/docs/specs" >/tmp/sync-spec.out 2>/tmp/sync-spec.err; then
  cat /tmp/sync-spec.out >&2
  fail "check should detect stale sidebar metadata"
fi

bash "$SYNC" --apply "$tmpdir/docs-manager/src/content/docs/specs" >/tmp/sync-spec.out

grep -q 'text: "IMPLEMENTED / P2"' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-065-task-gate-contract-hardening/plan.md" || fail "DP badge text not refreshed"
grep -q 'variant: "success"' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-065-task-gate-contract-hardening/plan.md" || fail "DP badge variant not refreshed"
grep -q 'label: "BUG-1 custom"' "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" || fail "company label not preserved"
grep -q 'order: 7' "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" || fail "company order not preserved"
grep -q 'text: "IMPLEMENTED"' "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" || fail "company badge text not refreshed"
grep -q 'variant: "success"' "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" || fail "company badge variant not refreshed"

bash "$SYNC" --check "$tmpdir/docs-manager/src/content/docs/specs" >/tmp/sync-spec.out

echo "[selftest] PASS"
