#!/usr/bin/env bash
# Purpose: Hermetic selftest for the closeout-driven active-thread recycle injected
#          into scripts/archive-spec.sh (DP-353 T1). Asserts AC1-7: archiving a
#          parent container (single-arg DP / single-arg JIRA-Epic / --sweep --apply)
#          recycles the matching `<!-- thread:<key> -->` section via the canonical
#          writer scripts/update-active-thread.sh --key <key> --done, exact-key only,
#          best-effort (never affects archive exit code), --dry-run never recycles,
#          and a no-match anchor stays byte-identical.
# Inputs:  None (builds its own tmp fixture git repo + fixture anchor; never touches
#          the live workspace / live .claude/active-thread.md).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARCHIVE="$ROOT/scripts/archive-spec.sh"
TMP="$(mktemp -d -t dp353-archive-thread-recycle.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Pin the writer stamp so anchor renders are deterministic across writes.
export POLARIS_ACTIVE_THREAD_STAMP="2026-06-25T00:00:00Z"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

SPECS_REL="docs-manager/src/content/docs/specs"

# Build a fresh hermetic fixture workspace with a single spec container.
#   $1 = workspace root
#   $2 = container relative path under specs (e.g. design-plans/DP-350-foo)
#   $3 = parent anchor basename (index.md)
#   $4 = frontmatter status (IMPLEMENTED etc.)
make_workspace() {
  local ws="$1" container_rel="$2" anchor_name="$3" status="$4"
  local specs="$ws/$SPECS_REL"
  local container="$specs/$container_rel"
  mkdir -p "$container"
  cat >"$container/$anchor_name" <<EOF
---
title: "fixture spec"
description: "hermetic fixture spec container for archive-spec thread-recycle selftest"
status: $status
---

# fixture
EOF
  mkdir -p "$ws/.claude"
}

# Write a keyed anchor with the given thread keys (one section each) via the
# canonical writer, so the fixture anchor matches the real serialization format.
#   $1 = workspace root
#   $2..N = thread keys to seed
seed_anchor() {
  local ws="$1"; shift
  local key
  for key in "$@"; do
    CLAUDE_PROJECT_DIR="$ws" bash "$ROOT/scripts/update-active-thread.sh" \
      --key "$key" --content "$key parked thread body" >/dev/null
  done
}

anchor_path() { printf '%s/.claude/active-thread.md\n' "$1"; }

# ============================================================================
# AC1 — DP container archive recycles matching thread:DP-NNN
# ============================================================================
WS1="$TMP/ac1"
make_workspace "$WS1" "design-plans/DP-350-fixture-dp" "index.md" "IMPLEMENTED"
seed_anchor "$WS1" "DP-350" "review-inbox"
A1="$(anchor_path "$WS1")"
grep -q '<!-- thread:DP-350 -->' "$A1" || fail "AC1 setup: seeded DP-350 thread missing"

bash "$ARCHIVE" --workspace "$WS1" DP-350 >/dev/null || fail "AC1: archive exited non-zero"
[[ -d "$WS1/$SPECS_REL/design-plans/archive/DP-350-fixture-dp" ]] || fail "AC1: container not archived"
if grep -q '<!-- thread:DP-350 -->' "$A1"; then
  fail "AC1: thread:DP-350 was NOT recycled after archiving DP-350 container"
fi
grep -q '<!-- thread:review-inbox -->' "$A1" || fail "AC1: unrelated thread:review-inbox was dropped"

# ============================================================================
# AC2 — JIRA-Epic container archive recycles matching thread:<ticket> (parity)
# ============================================================================
WS2="$TMP/ac2"
make_workspace "$WS2" "companies/exampleco/DEMO-900" "index.md" "IMPLEMENTED"
seed_anchor "$WS2" "DEMO-900" "DP-350"
A2="$(anchor_path "$WS2")"
grep -q '<!-- thread:DEMO-900 -->' "$A2" || fail "AC2 setup: seeded DEMO-900 thread missing"

bash "$ARCHIVE" --workspace "$WS2" DEMO-900 >/dev/null || fail "AC2: archive exited non-zero"
[[ -d "$WS2/$SPECS_REL/companies/exampleco/archive/DEMO-900" ]] || fail "AC2: container not archived"
if grep -q '<!-- thread:DEMO-900 -->' "$A2"; then
  fail "AC2: thread:DEMO-900 was NOT recycled after archiving JIRA-Epic container"
fi
grep -q '<!-- thread:DP-350 -->' "$A2" || fail "AC2: unrelated thread:DP-350 was dropped"

# ============================================================================
# AC3 — --sweep --apply recycles each archived source's key
# ============================================================================
WS3="$TMP/ac3"
make_workspace "$WS3" "design-plans/DP-351-sweep-a" "index.md" "IMPLEMENTED"
make_workspace "$WS3" "companies/exampleco/KB-700" "index.md" "SUPERSEDED"
seed_anchor "$WS3" "DP-351" "KB-700" "keep-me"
A3="$(anchor_path "$WS3")"
grep -q '<!-- thread:DP-351 -->' "$A3" || fail "AC3 setup: seeded DP-351 missing"
grep -q '<!-- thread:KB-700 -->' "$A3" || fail "AC3 setup: seeded KB-700 missing"

bash "$ARCHIVE" --workspace "$WS3" --sweep --apply >/dev/null || fail "AC3: sweep apply exited non-zero"
[[ -d "$WS3/$SPECS_REL/design-plans/archive/DP-351-sweep-a" ]] || fail "AC3: DP-351 not archived"
[[ -d "$WS3/$SPECS_REL/companies/exampleco/archive/KB-700" ]] || fail "AC3: KB-700 not archived"
if grep -q '<!-- thread:DP-351 -->' "$A3"; then
  fail "AC3: thread:DP-351 was NOT recycled after sweep archive"
fi
if grep -q '<!-- thread:KB-700 -->' "$A3"; then
  fail "AC3: thread:KB-700 was NOT recycled after sweep archive"
fi
grep -q '<!-- thread:keep-me -->' "$A3" || fail "AC3: unrelated thread:keep-me was dropped"

# ============================================================================
# AC4 — best-effort: missing anchor / writer failure / unresolvable root must
#       NOT change archive's exit code (warn + continue)
# ============================================================================
# AC4a: anchor file absent entirely -> archive still succeeds.
WS4="$TMP/ac4a"
make_workspace "$WS4" "design-plans/DP-352-noanchor" "index.md" "IMPLEMENTED"
A4="$(anchor_path "$WS4")"
[[ ! -f "$A4" ]] || fail "AC4a setup: anchor should be absent"
bash "$ARCHIVE" --workspace "$WS4" DP-352 >/dev/null \
  || fail "AC4a: archive failed when anchor was missing (best-effort violated)"
[[ -d "$WS4/$SPECS_REL/design-plans/archive/DP-352-noanchor" ]] || fail "AC4a: container not archived"

# AC4b: writer fails non-zero -> archive still succeeds (failure swallowed). The
# matching key IS present (so the writer is genuinely invoked, not a no-op skip);
# a read-only (0444) anchor file makes the writer's overwrite fail with exit 1.
# After archive the key must REMAIN (proves the writer ran + failed + was swallowed,
# rather than silently never being called).
WS4B="$TMP/ac4b"
make_workspace "$WS4B" "design-plans/DP-353-writerfail" "index.md" "IMPLEMENTED"
seed_anchor "$WS4B" "DP-353"
A4B="$(anchor_path "$WS4B")"
grep -qF '<!-- thread:DP-353 -->' "$A4B" || fail "AC4b setup: seeded DP-353 thread missing"
chmod 0444 "$A4B"   # read-only anchor file -> writer overwrite fails deterministically
set +e
bash "$ARCHIVE" --workspace "$WS4B" DP-353 >/dev/null 2>&1
AC4B_RC=$?
set -e
chmod 0644 "$A4B"
[[ "$AC4B_RC" -eq 0 ]] \
  || fail "AC4b: archive exit code changed ($AC4B_RC) when writer failed (best-effort violated)"
[[ -d "$WS4B/$SPECS_REL/design-plans/archive/DP-353-writerfail" ]] || fail "AC4b: container not archived"
grep -qF '<!-- thread:DP-353 -->' "$A4B" \
  || fail "AC4b: anchor was mutated despite writer failure (failure should be swallowed, key kept)"

# ============================================================================
# AC5 — no matching thread => anchor byte-identical (no re-serialize / no bump)
# ============================================================================
WS5="$TMP/ac5"
make_workspace "$WS5" "design-plans/DP-360-nomatch" "index.md" "IMPLEMENTED"
seed_anchor "$WS5" "DP-999" "other-thread"
A5="$(anchor_path "$WS5")"
HASH_BEFORE="$(shasum "$A5" | awk '{print $1}')"
bash "$ARCHIVE" --workspace "$WS5" DP-360 >/dev/null || fail "AC5: archive exited non-zero"
[[ -d "$WS5/$SPECS_REL/design-plans/archive/DP-360-nomatch" ]] || fail "AC5: container not archived"
HASH_AFTER="$(shasum "$A5" | awk '{print $1}')"
[[ "$HASH_BEFORE" == "$HASH_AFTER" ]] \
  || fail "AC5: anchor changed bytes when no matching thread key existed (DP-360 not in anchor)"

# ============================================================================
# AC6 — --dry-run never recycles + never mutates anchor
# ============================================================================
WS6="$TMP/ac6"
make_workspace "$WS6" "design-plans/DP-361-dryrun" "index.md" "IMPLEMENTED"
seed_anchor "$WS6" "DP-361"
A6="$(anchor_path "$WS6")"
HASH6_BEFORE="$(shasum "$A6" | awk '{print $1}')"
bash "$ARCHIVE" --workspace "$WS6" --dry-run DP-361 >/dev/null || fail "AC6: dry-run exited non-zero"
[[ -d "$WS6/$SPECS_REL/design-plans/DP-361-dryrun" ]] || fail "AC6: dry-run unexpectedly moved container"
HASH6_AFTER="$(shasum "$A6" | awk '{print $1}')"
[[ "$HASH6_BEFORE" == "$HASH6_AFTER" ]] \
  || fail "AC6: --dry-run mutated the anchor (recycle must not fire on dry-run)"
grep -q '<!-- thread:DP-361 -->' "$A6" || fail "AC6: dry-run dropped the thread (must keep on dry-run)"

# ============================================================================
# AC7 — exact-key only: archiving DP-30 must NOT recycle thread:DP-303
# ============================================================================
WS7="$TMP/ac7"
make_workspace "$WS7" "design-plans/DP-303-precise" "index.md" "IMPLEMENTED"
seed_anchor "$WS7" "DP-30" "DP-303"
A7="$(anchor_path "$WS7")"
# Archive the DP-303 container; only thread:DP-303 should be recycled, never DP-30.
bash "$ARCHIVE" --workspace "$WS7" DP-303 >/dev/null || fail "AC7: archive exited non-zero"
[[ -d "$WS7/$SPECS_REL/design-plans/archive/DP-303-precise" ]] || fail "AC7: container not archived"
if grep -q '<!-- thread:DP-303 -->' "$A7"; then
  fail "AC7: thread:DP-303 should have been recycled"
fi
grep -q '<!-- thread:DP-30 -->' "$A7" \
  || fail "AC7: prefix-similar thread:DP-30 was wrongly recycled (exact-key match violated)"

echo "PASS: archive-spec thread-recycle selftest (AC1 DP / AC2 JIRA-Epic / AC3 sweep / AC4 best-effort / AC5 byte-identical / AC6 dry-run / AC7 exact-key)"
