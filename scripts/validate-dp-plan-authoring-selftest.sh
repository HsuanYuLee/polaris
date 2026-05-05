#!/usr/bin/env bash
# Selftest for validate-dp-plan-authoring.sh and route-safe path validation.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/validate-dp-plan-authoring.sh"
ROUTE_SAFE="$ROOT_DIR/scripts/validate-route-safe-spec-paths.sh"
tmpdir="$(mktemp -d -t dp-plan-authoring.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"

mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/plan.md" <<'MD'
---
title: "DP-001: 測試建單"
description: "驗證 DP plan authoring wrapper 會補齊 sidebar metadata。"
topic: "測試建單"
created: 2026-05-05
status: DISCUSSION
priority: P2
---

## Context

這份 fixture 用來驗證 authoring wrapper。
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/plan.md" >/tmp/dp-authoring-valid.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/plan.md"

mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-invalid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-invalid/plan.md" <<'MD'
---
title: "DP-002: Missing description"
status: DISCUSSION
priority: P2
---

## Context

這份 fixture 應該被 Starlight authoring gate 擋下。
MD

if bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-invalid/plan.md" >/tmp/dp-authoring-invalid.out 2>&1; then
  echo "not ok missing description should fail" >&2
  exit 1
fi

mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-route"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-route/release-v3.74.34.md" <<'MD'
---
title: "Route unsafe"
description: "Route unsafe markdown path fixture."
---

## Route

Fixture.
MD

if bash "$ROUTE_SAFE" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-route" >/tmp/dp-route.out 2>&1; then
  echo "not ok route-unsafe filename should fail" >&2
  exit 1
fi
grep -q 'release-v3.74.34.md' /tmp/dp-route.out

echo "PASS: DP plan authoring wrapper selftest"
