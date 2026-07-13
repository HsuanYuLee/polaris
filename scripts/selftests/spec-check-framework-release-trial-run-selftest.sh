#!/usr/bin/env bash
# Purpose: DP-417 T14 selftest — proves the framework-release tail trial-run harness
#          (scripts/spec-check-framework-release-trial-run.sh) enforces its exit-code
#          contract and its side-effect isolation:
#            AC22          : a framework DP specimen driven through the release-tail
#                            dry-run + spec<->check parity => 0 bounces => exit 0,
#                            and the framework-release-specific code path is exercised.
#            AC-NEG12 (drift)   : an un-reconciled spec<->check drift (stale parity
#                                 anchors) makes the contract stage bounce => exit 2
#                                 (warning-only never passes).
#            AC-NEG12 (no-substitute + isolation): the harness exercises the
#                                 framework-release-execute code path a product epic
#                                 cannot reach, and creates NO real release
#                                 side-effect (no git tag, no push, no sync) — only
#                                 --enumerate is ever invoked.
#            fail-closed   : unknown argument => exit 2.
# Inputs:  none (uses the real repo + tmpdir fixtures)
# Outputs: stdout PASS line; exit 0 PASS, exit 1 FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS="$REPO_ROOT/scripts/spec-check-framework-release-trial-run.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

run_harness() {
  # run_harness <label> <expected_exit> [cwd] -- <args...>
  local label="$1" expect="$2" cwd="$3"; shift 3
  [[ "$1" == "--" ]] && shift
  local rc=0
  ( cd "$cwd" && bash "$HARNESS" "$@" ) >"$tmpdir/$label.out" 2>"$tmpdir/$label.err" || rc=$?
  if [[ "$rc" -ne "$expect" ]]; then
    echo "--- $label stdout ---"; cat "$tmpdir/$label.out"
    echo "--- $label stderr ---"; cat "$tmpdir/$label.err"
    fail "$label: expected exit $expect, got $rc"
  fi
}

# Case 1 (AC22): framework specimen + real (green) repo => 0 bounces, exit 0, and the
# framework-release code path is exercised.
run_harness "clean" 0 "$REPO_ROOT" -- --source-id DP-417 --repo-root "$REPO_ROOT"
grep -q 'TRIAL RUN CLEAN' "$tmpdir/clean.out" \
  || fail "clean: expected 'TRIAL RUN CLEAN' banner"
grep -q 'release-tail(framework-release-execute' "$tmpdir/clean.out" \
  || fail "clean: expected the framework-release-execute code path to be exercised (AC-NEG12 non-substitute)"

# Case 2 (AC-NEG12 drift): stale parity anchors (empty repo-root) => contract bounce, exit 2.
empty_repo="$tmpdir/empty-repo"
mkdir -p "$empty_repo"
run_harness "parity-drift" 2 "$REPO_ROOT" -- --repo-root "$empty_repo"
grep -q 'contract(' "$tmpdir/parity-drift.out" \
  || fail "parity-drift: expected the contract stage to be reported as bounced"
grep -q 'POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE' "$tmpdir/parity-drift.err" \
  || fail "parity-drift: expected POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE"

# Case 3 (AC-NEG12 isolation): run from a throwaway git repo; assert NO real release
# side-effect (no tag created there), and the framework-release stage was exercised.
throwaway="$tmpdir/throwaway-repo"
mkdir -p "$throwaway"
git -C "$throwaway" init -q
git -C "$throwaway" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
run_harness "isolation" 0 "$throwaway" -- --repo-root "$REPO_ROOT"
tags="$(git -C "$throwaway" tag -l | tr -d '[:space:]')"
[[ -z "$tags" ]] || fail "isolation: harness created a real tag ($tags) — release side-effect leaked"
grep -q 'isolation: release tail runs --enumerate only' "$tmpdir/isolation.out" \
  || fail "isolation: harness must declare --enumerate-only isolation"

# Static isolation guarantee: the harness CODE (comments stripped — the header
# documents the isolation by naming what it never does) must never invoke a real
# release execution flag or side-effect command; only --enumerate is allowed.
harness_code="$(grep -v '^[[:space:]]*#' "$HARNESS")"
for forbidden in '--full-tail' '--land-tasks-to-feat' 'sync-to-polaris' 'git tag' 'git push'; do
  if printf '%s\n' "$harness_code" | grep -qF -- "$forbidden"; then
    fail "isolation(static): harness code must not invoke real side-effect '$forbidden'"
  fi
done

# Case 4 (fail-closed): unknown argument => exit 2.
run_harness "bad-arg" 2 "$REPO_ROOT" -- --nope
grep -q 'POLARIS_SPEC_CHECK_TRIAL_RUN_BOUNCE' "$tmpdir/bad-arg.err" \
  || fail "bad-arg: expected fail-closed marker"

echo "spec-check-framework-release-trial-run selftest: 4 pass, 0 fail"
