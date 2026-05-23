#!/usr/bin/env bash
# Selftest for validate-spec-primary-doc-authoring.sh — source-agnostic primary
# doc authoring wrapper. Covers DP index.md, DP legacy plan.md, Epic index.md,
# Epic refinement.md PASS paths plus metadata fail-loud cases.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/validate-spec-primary-doc-authoring.sh"
ROUTE_SAFE="$ROOT_DIR/scripts/validate-route-safe-spec-paths.sh"
tmpdir="$(mktemp -d -t spec-primary-doc-authoring.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

cd "$ROOT_DIR"

if [[ ! -x "$WRAPPER" ]]; then
  echo "not ok wrapper missing or not executable: $WRAPPER" >&2
  exit 1
fi

# --- Case 1: DP index.md PASS (source-agnostic primary doc) ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-501-valid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-501-valid/index.md" <<'MD'
---
title: "DP-501: Source-agnostic primary doc fixture"
description: "Validate source-agnostic primary doc authoring wrapper accepts DP index.md."
topic: "Source-agnostic primary doc"
created: 2026-05-22
status: DISCUSSION
priority: P2
---

## Context

DP index.md fixture for the source-agnostic primary doc authoring wrapper.
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-501-valid/index.md" >/tmp/spec-authoring-dp.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-501-valid/index.md"

# --- Case 2: DP legacy plan.md PASS ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-502-legacy"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-502-legacy/plan.md" <<'MD'
---
title: "DP-502: Legacy plan.md fallback fixture"
description: "Legacy DP plan.md container should still pass the source-agnostic wrapper."
topic: "Legacy plan fallback"
created: 2026-05-22
status: DISCUSSION
priority: P2
---

## Context

Legacy DP plan.md fixture for the source-agnostic primary doc authoring wrapper.
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-502-legacy/plan.md" >/tmp/spec-authoring-legacy.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-502-legacy/plan.md"

# --- Case 3: Epic index.md PASS (under epics/ container) ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-1-fixture"
cat >"$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-1-fixture/index.md" <<'MD'
---
title: "EXAMPLE-1: Epic index fixture"
description: "Validate the source-agnostic primary doc authoring wrapper accepts Epic index.md."
topic: "Epic index fixture"
created: 2026-05-22
status: DISCUSSION
priority: P2
---

## Context

Epic index.md fixture for the source-agnostic primary doc authoring wrapper.
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-1-fixture/index.md" >/tmp/spec-authoring-epic.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-1-fixture/index.md"

# --- Case 4: Epic refinement.md PASS ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-2-refinement"
cat >"$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-2-refinement/refinement.md" <<'MD'
---
title: "EXAMPLE-2: Epic refinement fixture"
description: "Validate the source-agnostic primary doc authoring wrapper accepts Epic refinement.md."
topic: "Epic refinement fixture"
created: 2026-05-22
status: DISCUSSION
priority: P2
---

## Context

Epic refinement.md fixture for the source-agnostic primary doc authoring wrapper.
MD

bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-2-refinement/refinement.md" >/tmp/spec-authoring-epic-refinement.out
grep -q 'sidebar:' "$tmpdir/docs-manager/src/content/docs/specs/epics/EXAMPLE-2-refinement/refinement.md"

# --- Case 5: missing description fail-loud (Starlight authoring gate) ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-503-invalid"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-503-invalid/index.md" <<'MD'
---
title: "DP-503: Missing description"
status: DISCUSSION
priority: P2
---

## Context

Should be blocked by the Starlight authoring gate.
MD

if bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-503-invalid/index.md" >/tmp/spec-authoring-invalid.out 2>&1; then
  echo "not ok missing description should fail" >&2
  exit 1
fi

# --- Case 6: route-safe path failure surface ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-504-route"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-504-route/release-v3.74.34.md" <<'MD'
---
title: "Route unsafe"
description: "Route unsafe markdown path fixture."
---

## Route

Fixture.
MD

if bash "$ROUTE_SAFE" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-504-route" >/tmp/spec-route.out 2>&1; then
  echo "not ok route-unsafe filename should fail" >&2
  exit 1
fi
grep -q 'release-v3.74.34.md' /tmp/spec-route.out

# --- Case 7: invalid basename should be rejected ---
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-505-badname"
cat >"$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-505-badname/notes.md" <<'MD'
---
title: "Bad basename"
description: "Should be rejected by the wrapper."
---
MD

if bash "$WRAPPER" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-505-badname/notes.md" >/tmp/spec-authoring-badname.out 2>&1; then
  echo "not ok bad basename should fail" >&2
  exit 1
fi

# --- Case 8: path outside specs/ tree should be rejected ---
mkdir -p "$tmpdir/random/path"
cat >"$tmpdir/random/path/index.md" <<'MD'
---
title: "Outside specs tree"
description: "Should be rejected."
---
MD

if bash "$WRAPPER" "$tmpdir/random/path/index.md" >/tmp/spec-authoring-outside.out 2>&1; then
  echo "not ok path outside specs tree should fail" >&2
  exit 1
fi

echo "PASS: spec primary doc authoring wrapper selftest"
