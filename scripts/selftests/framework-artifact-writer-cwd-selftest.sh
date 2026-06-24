#!/usr/bin/env bash
# framework-artifact-writer-cwd-selftest.sh — DP-230 T5 / D18 / AC14
# (DP-360 T7 re-pointed: original exemplar write-completion-gate-marker.sh was
# retired; the main-checkout-anchoring contract it demonstrated now lives in the
# shared helper scripts/lib/main-checkout.sh and its surviving consumers).
#
# Verifies that the main-checkout-anchoring contract still holds: framework
# artifact writers that default their evidence-marker OUT path must anchor at
# the MAIN checkout, not a caller worktree's .polaris/evidence/ tree. The contract
# primitive is scripts/lib/main-checkout.sh::resolve_main_checkout(); the surviving
# exemplar consumer is scripts/run-verify-command.sh.
#
# Cases:
#   case 1: resolve_main_checkout() invoked from inside a worktree resolves to the
#           MAIN checkout, not the worktree path (the leak-prevention primitive
#           that the retired completion-gate writer relied on).
#   case 2: resolve_main_checkout() invoked from the main checkout resolves to the
#           main checkout (baseline; no regression for non-worktree runs).
#   case 3: a surviving framework artifact writer (run-verify-command.sh) sources
#           lib/main-checkout.sh and references resolve_main_checkout (source
#           enforcement, not just behavioral).
#   case 4: convention reference exists and lists >= 3 writer callsites
#           (AC14 enforcement; framework-artifact-writer-convention.md).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT_DIR/scripts/lib/main-checkout.sh"
# DP-360 T7: surviving exemplar consumer of the main-checkout-anchoring contract.
ANCHORING_WRITER="$ROOT_DIR/scripts/run-verify-command.sh"
REFERENCE="$ROOT_DIR/.claude/skills/references/framework-artifact-writer-convention.md"

WORKDIR="$(mktemp -d -t dp230-fw-artifact-writer.XXXXXX)"
# macOS /tmp is a symlink to /private/tmp; realpath so paths compare cleanly.
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: scripts/lib/main-checkout.sh missing: $LIB" >&2
  exit 1
fi
if [[ ! -f "$ANCHORING_WRITER" ]]; then
  echo "FAIL: surviving anchoring writer missing: $ANCHORING_WRITER" >&2
  exit 1
fi

# ---- Build a self-contained main+worktree fixture --------------------------
MAIN="$WORKDIR/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email selftest@example.com
git -C "$MAIN" config user.name "DP-230 T5 selftest"
echo "init" >"$MAIN/README.md"
git -C "$MAIN" add -A
git -C "$MAIN" -c commit.gpgsign=false commit -q -m "init"

# Mirror the contract helper into the fixture so the selftest exercises THIS
# helper without relying on the live workspace path layout.
mkdir -p "$MAIN/scripts/lib"
cp "$LIB" "$MAIN/scripts/lib/main-checkout.sh"
git -C "$MAIN" add -A
git -C "$MAIN" -c commit.gpgsign=false commit -q -m "stage main-checkout helper"

# Add a worktree off of main.
WT="$WORKDIR/worktree"
git -C "$MAIN" worktree add -q -b dp230-t5-fixture "$WT"

MAIN_REAL="$(cd "$MAIN" && pwd -P)"
WT_REAL="$(cd "$WT" && pwd -P)"

# ---- Case 1: resolve_main_checkout() from a worktree -> MAIN, not worktree
case1_resolved="$(
  cd "$WT_REAL"
  . "$MAIN_REAL/scripts/lib/main-checkout.sh"
  resolve_main_checkout "$WT_REAL" 2>/dev/null || true
)"
if [[ -z "$case1_resolved" ]]; then
  echo "FAIL (case1): resolve_main_checkout returned empty from a worktree" >&2
  exit 1
fi
case1_real="$(cd "$case1_resolved" && pwd -P)"
if [[ "$case1_real" != "$MAIN_REAL" ]]; then
  echo "FAIL (case1): resolve_main_checkout did not resolve to the main checkout" >&2
  echo "  expected: $MAIN_REAL" >&2
  echo "  got     : $case1_real" >&2
  exit 1
fi
if [[ "$case1_real" == "$WT_REAL" ]]; then
  echo "FAIL (case1): resolve_main_checkout leaked the worktree path (regression of DP-226 P5)" >&2
  exit 1
fi

# ---- Case 2: resolve_main_checkout() from the main checkout -> main (baseline)
case2_resolved="$(
  cd "$MAIN_REAL"
  . "$MAIN_REAL/scripts/lib/main-checkout.sh"
  resolve_main_checkout "$MAIN_REAL" 2>/dev/null || true
)"
if [[ -z "$case2_resolved" ]]; then
  echo "FAIL (case2): resolve_main_checkout returned empty from the main checkout" >&2
  exit 1
fi
case2_real="$(cd "$case2_resolved" && pwd -P)"
if [[ "$case2_real" != "$MAIN_REAL" ]]; then
  echo "FAIL (case2): resolve_main_checkout did not resolve main checkout to itself" >&2
  echo "  expected: $MAIN_REAL" >&2
  echo "  got     : $case2_real" >&2
  exit 1
fi

# ---- Case 3 (AC14 source enforcement): surviving writer sources the helper
if ! grep -q "lib/main-checkout.sh" "$ANCHORING_WRITER"; then
  echo "FAIL (case3): run-verify-command.sh does not source lib/main-checkout.sh" >&2
  exit 1
fi
if ! grep -q "resolve_main_checkout" "$ANCHORING_WRITER"; then
  echo "FAIL (case3): run-verify-command.sh does not call resolve_main_checkout" >&2
  exit 1
fi

# ---- Case 4 (AC14): convention reference exists and lists >= 3 callsites
if [[ ! -f "$REFERENCE" ]]; then
  echo "FAIL (case4): convention reference missing: $REFERENCE" >&2
  exit 1
fi
callsite_count="$(grep -Eoc '`scripts/[A-Za-z0-9_./-]+\.sh`' "$REFERENCE" || true)"
if [[ -z "$callsite_count" ]] || [[ "$callsite_count" -lt 3 ]]; then
  echo "FAIL (case4): convention reference must list >= 3 writer callsites (found ${callsite_count:-0})" >&2
  exit 1
fi

echo "PASS: framework-artifact-writer-cwd-selftest (4/4 cases)"
