#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-specs-bound-write-contract.sh"
TMP="$(mktemp -d -t dp207-specs-bound.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name "Specs Bound Test"
mkdir -p "$repo/scripts/lib"
cp "$ROOT/scripts/lib/evidence-producers.json" "$repo/scripts/lib/evidence-producers.json"

valid="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/dogfood-evidence/DP-999/valid.md"
mkdir -p "$(dirname "$valid")"
cat >"$valid" <<'MD'
---
title: "Valid evidence"
description: "Valid fixture."
draft: true
sidebar:
  hidden: true
---

## Observed

valid
MD
bash "$VALIDATOR" --repo "$repo" --files "$valid" >/tmp/dp207-specs-bound-valid.out

invalid="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/dogfood-evidence/DP-999/invalid.md"
cat >"$invalid" <<'MD'
## Observed

missing frontmatter
MD
if bash "$VALIDATOR" --repo "$repo" --files "$invalid" >/tmp/dp207-specs-bound-invalid.out 2>&1; then
  echo "FAIL: invalid frontmatter should fail" >&2
  exit 1
fi
rg -n 'missing required frontmatter' /tmp/dp207-specs-bound-invalid.out >/dev/null

unregistered="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-topic/random.md"
cat >"$unregistered" <<'MD'
---
title: "Random"
description: "Random."
draft: true
sidebar:
  hidden: true
---
MD
if bash "$VALIDATOR" --repo "$repo" --files "$unregistered" >/tmp/dp207-specs-bound-unregistered.out 2>&1; then
  echo "FAIL: unregistered path should fail" >&2
  exit 1
fi
rg -n 'no specs-bound producer registration' /tmp/dp207-specs-bound-unregistered.out >/dev/null

echo "PASS: validate specs-bound write contract selftest"
