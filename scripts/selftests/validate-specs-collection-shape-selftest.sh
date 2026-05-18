#!/usr/bin/env bash
# Selftest for validate-specs-collection-shape.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-specs-collection-shape.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/validate-specs-shape.out 2>/tmp/validate-specs-shape.err; then
    cat /tmp/validate-specs-shape.out >&2 || true
    fail "$label unexpectedly passed"
  fi
}

tmpdir="$(mktemp -d -t validate-specs-shape.XXXXXX)"
trap 'rm -rf "$tmpdir" /tmp/validate-specs-shape.out /tmp/validate-specs-shape.err' EXIT

specs="$tmpdir/docs-manager/src/content/docs/specs"
mkdir -p \
  "$specs/design-plans/DP-999-good/artifacts/external-writes" \
  "$specs/design-plans/DP-999-good/artifacts/research" \
  "$specs/design-plans/DP-999-good/jira-comments" \
  "$specs/design-plans/DP-999-good/escalations" \
  "$specs/design-plans/DP-999-good/refinement-inbox" \
  "$specs/companies/exampleco/DEMO-999/artifacts/external-writes"

cat >"$specs/design-plans/DP-999-good/index.md" <<'MD'
---
title: "DP-999"
description: "Valid docs page."
---

## Goal
MD

cat >"$specs/design-plans/DP-999-good/artifacts/external-writes/20260518-body.md" <<'MD'
---
artifact_type: external-write
source: DP-999
created: 2026-05-18
---

## Body
MD

cat >"$specs/design-plans/DP-999-good/artifacts/research/2026-05-18-note.md" <<'MD'
---
artifact_type: research-snapshot
source: DP-999
created: 2026-05-18
---

## Note
MD

cat >"$specs/companies/exampleco/DEMO-999/artifacts/external-writes/20260518-body.md" <<'MD'
---
artifact_type: external-write
source: DEMO-999
created: 2026-05-18
---

## Body
MD

cat >"$specs/design-plans/DP-999-good/jira-comments/20260518-comment.md" <<'MD'
---
title: "JIRA comment"
description: "Existing sidecar schema without D2 artifact_type."
---

## Comment
MD

cat >"$specs/design-plans/DP-999-good/escalations/T1-1.md" <<'MD'
---
skill: engineering
source: escalation
---

## Escalation
MD

cat >"$specs/design-plans/DP-999-good/refinement-inbox/T1-1.md" <<'MD'
---
skill: breakdown
target_skill: refinement
consumed: false
---

## Decision
MD

bash "$VALIDATOR" --workspace "$tmpdir" --all >/dev/null

bad="$tmpdir/bad"
mkdir -p "$bad/docs-manager/src/content/docs/specs/design-plans/DP-998-bad/artifacts/external-writes"
cat >"$bad/docs-manager/src/content/docs/specs/design-plans/DP-998-bad/index.md" <<'MD'
---
description: "Missing title."
---

## Goal
MD
expect_fail "docs page missing title" bash "$VALIDATOR" --workspace "$bad" --all

cat >"$bad/docs-manager/src/content/docs/specs/design-plans/DP-998-bad/index.md" <<'MD'
---
title: "DP-998"
description: "Valid page."
---

## Goal
MD
cat >"$bad/docs-manager/src/content/docs/specs/design-plans/DP-998-bad/artifacts/external-writes/20260518-body.md" <<'MD'
---
artifact_type: external-write
source: DP-998
---

## Body
MD
expect_fail "D2 transport missing created" bash "$VALIDATOR" --workspace "$bad" --all
grep -q 'missing `created`' /tmp/validate-specs-shape.err || fail "missing created error not reported"

echo "[selftest] PASS"
