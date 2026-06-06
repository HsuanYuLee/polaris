#!/usr/bin/env bash
# Purpose: Hermetic selftest for scripts/update-active-thread.sh (DP-290 T1).
#          Covers AC2 (overwrite, no append residue, byte-idempotent for identical
#          input) and AC3 (>10k input truncates tail, preserves「下一步」head, emits
#          truncation notice, total length <= 10000).
# Inputs:  None (builds its own tmp git repo as CLAUDE_PROJECT_DIR).
# Outputs: Prints PASS on success; exits non-zero with FAIL on any assertion failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$ROOT/scripts/update-active-thread.sh"
TMP="$(mktemp -d -t dp290-update-active-thread.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

PROJECT="$TMP/project"
mkdir -p "$PROJECT"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email test@example.com
git -C "$PROJECT" config user.name "Active Thread Test"

ANCHOR="$PROJECT/.claude/active-thread.md"
export CLAUDE_PROJECT_DIR="$PROJECT"
export POLARIS_ACTIVE_THREAD_STAMP="2026-06-06T00:00:00Z"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---- AC2: overwrite (no append residue) ----
FIRST=$'# 下一步\n\nFIRST RUN content alpha unique-marker-AAA'
SECOND=$'# 下一步\n\nSECOND RUN content beta unique-marker-BBB'

printf '%s' "$FIRST" | bash "$WRITER" >/dev/null
[[ -f "$ANCHOR" ]] || fail "anchor file not created on first run"
grep -q 'unique-marker-AAA' "$ANCHOR" || fail "first-run content missing"

printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
grep -q 'unique-marker-BBB' "$ANCHOR" || fail "second-run content missing"
if grep -q 'unique-marker-AAA' "$ANCHOR"; then
  fail "AC2: append residue detected — first-run content survived overwrite"
fi

# Final file must equal a fresh compose of the SECOND input (byte-exact).
EXPECTED="$TMP/expected.md"
printf '%s\n\n%s\n' "last-updated: $POLARIS_ACTIVE_THREAD_STAMP" "$SECOND" >"$EXPECTED"
if ! diff -q "$EXPECTED" "$ANCHOR" >/dev/null; then
  echo "--- expected ---" >&2; cat "$EXPECTED" >&2
  echo "--- actual ---" >&2; cat "$ANCHOR" >&2
  fail "AC2: final anchor does not byte-match second input compose"
fi

# ---- AC2: idempotency (identical input twice => byte-identical file) ----
printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
HASH_A="$(shasum "$ANCHOR" | awk '{print $1}')"
printf '%s' "$SECOND" | bash "$WRITER" >/dev/null
HASH_B="$(shasum "$ANCHOR" | awk '{print $1}')"
[[ "$HASH_A" == "$HASH_B" ]] || fail "AC2: identical input produced different files (not idempotent)"

# ---- AC3: >10k input truncates tail, preserves head + emits notice ----
HEAD_MARKER='# 下一步: deterministic-handoff-head-MARKER'
# Build a body whose head carries the marker and whose tail is filler exceeding 10k.
BIG_BODY="$TMP/big.txt"
{
  printf '%s\n\n' "$HEAD_MARKER"
  # ~12000 chars of tail filler
  for _ in $(seq 1 240); do
    printf 'TAILFILLER-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-%s\n' "$_"
  done
} >"$BIG_BODY"

[[ "$(wc -c <"$BIG_BODY")" -gt 10000 ]] || fail "AC3 fixture not >10k chars"

bash "$WRITER" --content "$(cat "$BIG_BODY")" >/dev/null

CHARS="$(wc -m <"$ANCHOR" | tr -d ' ')"
[[ "$CHARS" -le 10000 ]] || fail "AC3: truncated anchor exceeds 10000 chars (got $CHARS)"
grep -qF "$HEAD_MARKER" "$ANCHOR" || fail "AC3: head「下一步」marker was truncated away"
grep -q 'truncated by update-active-thread.sh' "$ANCHOR" || fail "AC3: truncation notice line missing"
if grep -q 'TAILFILLER-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-240' "$ANCHOR"; then
  fail "AC3: tail filler末段 should have been truncated"
fi

echo "PASS: update-active-thread selftest (AC2 overwrite/idempotent, AC3 10k truncation)"
