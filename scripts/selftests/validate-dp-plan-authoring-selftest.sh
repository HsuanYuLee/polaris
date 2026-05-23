#!/usr/bin/env bash
# Selftest for validate-dp-plan-authoring.sh — thin alias for
# scripts/validate-spec-primary-doc-authoring.sh. Verifies alias parity for DP
# index.md / legacy plan.md, the missing-description fail-loud case, and the
# route-safe path failure surface.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/validate-dp-plan-authoring.sh"
ROUTE_SAFE="$ROOT_DIR/scripts/validate-route-safe-spec-paths.sh"
tmpdir="$(mktemp -d -t dp-plan-authoring.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"

# Alias guard: invoking with no args should print usage and exit 2.
if bash "$WRAPPER" >/tmp/dp-authoring-noargs.out 2>&1; then
  echo "not ok alias should exit non-zero when called without args" >&2
  exit 1
fi

# Alias parity: DP index.md PASS path delegated to the source-agnostic wrapper.
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/index.md" <<'MD'
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

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/index.md" >/tmp/dp-authoring-valid.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-001-valid/index.md"
grep -q 'PASS: spec primary doc authoring wrapper' /tmp/dp-authoring-valid.out

# Alias parity: legacy plan.md container should still pass.
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-legacy"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-legacy/plan.md" <<'MD'
---
title: "DP-002: Legacy plan fallback"
description: "Legacy plan.md container should remain valid."
topic: "Legacy plan fallback"
created: 2026-05-05
status: DISCUSSION
priority: P2
---

## Context

這份 fixture 用來驗證 legacy plan.md fallback。
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-legacy/plan.md" >/tmp/dp-authoring-legacy.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-002-legacy/plan.md"

# Alias parity: missing description should fail.
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-invalid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-invalid/index.md" <<'MD'
---
title: "DP-003: Missing description"
status: DISCUSSION
priority: P2
---

## Context

這份 fixture 應該被 Starlight authoring gate 擋下。
MD

if bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-003-invalid/index.md" >/tmp/dp-authoring-invalid.out 2>&1; then
  echo "not ok missing description should fail" >&2
  exit 1
fi

# Route-safe path failure surface stays unchanged.
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-004-route"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-004-route/release-v3.74.34.md" <<'MD'
---
title: "Route unsafe"
description: "Route unsafe markdown path fixture."
---

## Route

Fixture.
MD

if bash "$ROUTE_SAFE" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-004-route" >/tmp/dp-route.out 2>&1; then
  echo "not ok route-unsafe filename should fail" >&2
  exit 1
fi
grep -q 'release-v3.74.34.md' /tmp/dp-route.out

echo "PASS: DP plan authoring wrapper selftest"
