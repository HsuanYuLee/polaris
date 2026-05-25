#!/usr/bin/env bash
# framework-artifact-writer-cwd-selftest.sh — DP-230 T5 / D18 / AC14.
#
# Verifies that framework artifact writers anchored at the main checkout do
# NOT leak completion_gate / pr_freshness / blocked_conflict / ci-local /
# unsupported_mutation markers into a caller worktree's
# .polaris/evidence/ tree. The exemplar writer for this contract is
# scripts/write-completion-gate-marker.sh.
#
# Cases:
#   case 1: writer invoked from a worktree -> marker absolute path begins with
#           the MAIN checkout, not the worktree path.
#   case 2: writer invoked from the main checkout -> marker still lands under
#           the main checkout (baseline; no regression for non-worktree runs).
#   case 3: writer sources scripts/lib/main-checkout.sh and references
#           resolve_main_checkout() (source enforcement, not just behavioral).
#   case 4: convention reference exists and lists >= 3 writer callsites
#           (AC14 enforcement; .claude/skills/references/framework-artifact-writer-convention.md).
#   case 5: explicit --out absolute path still honored (writer must not silently
#           remap a caller-provided absolute --out into the main checkout).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/write-completion-gate-marker.sh"
LIB="$ROOT_DIR/scripts/lib/main-checkout.sh"
REFERENCE="$ROOT_DIR/.claude/skills/references/framework-artifact-writer-convention.md"

WORKDIR="$(mktemp -d -t dp230-fw-artifact-writer.XXXXXX)"
# macOS /tmp is a symlink to /private/tmp; realpath so paths compare cleanly.
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: write-completion-gate-marker.sh not executable: $SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$LIB" ]]; then
  echo "FAIL: scripts/lib/main-checkout.sh missing: $LIB" >&2
  exit 1
fi

# ---- Build a self-contained main+worktree fixture --------------------------
MAIN="$WORKDIR/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q
git -C "$MAIN" config user.email selftest@example.com
git -C "$MAIN" config user.name "DP-230 T5 selftest"
# Stage a token file so the worktree can detach a branch from a real commit.
echo "init" >"$MAIN/README.md"
git -C "$MAIN" add -A
git -C "$MAIN" -c commit.gpgsign=false commit -q -m "init"

# Mirror the writer + lib into the fixture so the selftest tests THIS script
# without relying on the live workspace path layout. We copy by file (no
# symlink) so the worktree behavior is identical to how the writer runs in
# real life.
mkdir -p "$MAIN/scripts/lib"
cp "$SCRIPT" "$MAIN/scripts/write-completion-gate-marker.sh"
cp "$LIB" "$MAIN/scripts/lib/main-checkout.sh"
chmod +x "$MAIN/scripts/write-completion-gate-marker.sh"
git -C "$MAIN" add -A
git -C "$MAIN" -c commit.gpgsign=false commit -q -m "stage writer + main-checkout helper"

# Add a worktree off of main.
WT="$WORKDIR/worktree"
git -C "$MAIN" worktree add -q -b dp230-t5-fixture "$WT"

MAIN_REAL="$(cd "$MAIN" && pwd -P)"
WT_REAL="$(cd "$WT" && pwd -P)"

FIXTURE_HEAD="$(git -C "$MAIN" rev-parse HEAD)"

# ---- Case 1 (AC14): writer from worktree -> marker under MAIN, not worktree
(
  cd "$WT_REAL"
  bash "$WT_REAL/scripts/write-completion-gate-marker.sh" \
    --source-id DP-230 \
    --work-item-id DP-230-T5-case1 \
    --head-sha "$FIXTURE_HEAD" \
    --status PASS \
    >"$WORKDIR/case1.out" 2>&1
)

# Resolve actual emitted path from stderr/stdout "WROTE: <path>" line.
case1_path="$(grep -E '^WROTE: ' "$WORKDIR/case1.out" | tail -n1 | sed -E 's/^WROTE: //')"
if [[ -z "$case1_path" ]]; then
  echo "FAIL (case1): writer did not emit 'WROTE: <path>' line" >&2
  cat "$WORKDIR/case1.out" >&2
  exit 1
fi
# Absolutize (writer may emit relative path; if so resolve against main checkout)
if [[ "$case1_path" != /* ]]; then
  case1_path="$MAIN_REAL/$case1_path"
fi
case1_real="$(cd "$(dirname "$case1_path")" && pwd -P)/$(basename "$case1_path")"

if [[ "$case1_real" != "$MAIN_REAL/.polaris/evidence/completion-gate/"* ]]; then
  echo "FAIL (case1): marker did not land under main checkout .polaris/evidence/completion-gate/" >&2
  echo "  expected prefix: $MAIN_REAL/.polaris/evidence/completion-gate/" >&2
  echo "  got            : $case1_real" >&2
  exit 1
fi
if [[ "$case1_real" == "$WT_REAL/.polaris/"* ]]; then
  echo "FAIL (case1): marker leaked into worktree .polaris/ (regression of DP-226 P5)" >&2
  echo "  worktree path: $case1_real" >&2
  exit 1
fi
if [[ ! -f "$case1_real" ]]; then
  echo "FAIL (case1): marker file does not exist on disk: $case1_real" >&2
  exit 1
fi
rm -f "$case1_real"

# ---- Case 2: writer from main checkout -> marker under main (no regression)
(
  cd "$MAIN_REAL"
  bash "$MAIN_REAL/scripts/write-completion-gate-marker.sh" \
    --source-id DP-230 \
    --work-item-id DP-230-T5-case2 \
    --head-sha "$FIXTURE_HEAD" \
    --status PASS \
    >"$WORKDIR/case2.out" 2>&1
)
case2_path="$(grep -E '^WROTE: ' "$WORKDIR/case2.out" | tail -n1 | sed -E 's/^WROTE: //')"
if [[ -z "$case2_path" ]]; then
  echo "FAIL (case2): writer did not emit 'WROTE: <path>' line" >&2
  cat "$WORKDIR/case2.out" >&2
  exit 1
fi
if [[ "$case2_path" != /* ]]; then
  case2_path="$MAIN_REAL/$case2_path"
fi
case2_real="$(cd "$(dirname "$case2_path")" && pwd -P)/$(basename "$case2_path")"
if [[ "$case2_real" != "$MAIN_REAL/.polaris/evidence/completion-gate/"* ]]; then
  echo "FAIL (case2): marker did not land under main checkout .polaris/evidence/completion-gate/" >&2
  echo "  expected prefix: $MAIN_REAL/.polaris/evidence/completion-gate/" >&2
  echo "  got            : $case2_real" >&2
  exit 1
fi
if [[ ! -f "$case2_real" ]]; then
  echo "FAIL (case2): marker file does not exist on disk: $case2_real" >&2
  exit 1
fi
rm -f "$case2_real"

# ---- Case 3 (AC14 source enforcement): writer sources lib/main-checkout.sh
if ! grep -q "lib/main-checkout.sh" "$SCRIPT"; then
  echo "FAIL (case3): write-completion-gate-marker.sh does not source lib/main-checkout.sh" >&2
  exit 1
fi
if ! grep -q "resolve_main_checkout" "$SCRIPT"; then
  echo "FAIL (case3): write-completion-gate-marker.sh does not call resolve_main_checkout" >&2
  exit 1
fi

# ---- Case 4 (AC14): convention reference exists and lists >= 3 callsites
if [[ ! -f "$REFERENCE" ]]; then
  echo "FAIL (case4): convention reference missing: $REFERENCE" >&2
  exit 1
fi
# Callsites are declared as backticked script paths under scripts/ to match
# `scripts/<name>.sh` literals in the reference markdown.
callsite_count="$(grep -Eoc '`scripts/[A-Za-z0-9_./-]+\.sh`' "$REFERENCE" || true)"
if [[ -z "$callsite_count" ]] || [[ "$callsite_count" -lt 3 ]]; then
  echo "FAIL (case4): convention reference must list >= 3 writer callsites (found ${callsite_count:-0})" >&2
  exit 1
fi

# ---- Case 5: explicit absolute --out is honored (no silent rewrite to main)
ABS_OUT="$WORKDIR/explicit-out/case5.json"
mkdir -p "$(dirname "$ABS_OUT")"
(
  cd "$WT_REAL"
  bash "$WT_REAL/scripts/write-completion-gate-marker.sh" \
    --source-id DP-230 \
    --work-item-id DP-230-T5-case5 \
    --head-sha "$FIXTURE_HEAD" \
    --status PASS \
    --out "$ABS_OUT" \
    >"$WORKDIR/case5.out" 2>&1
)
if [[ ! -f "$ABS_OUT" ]]; then
  echo "FAIL (case5): explicit --out absolute path not honored: $ABS_OUT" >&2
  cat "$WORKDIR/case5.out" >&2
  exit 1
fi

echo "PASS: framework-artifact-writer-cwd-selftest (5/5 cases)"
