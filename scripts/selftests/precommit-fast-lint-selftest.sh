#!/usr/bin/env bash
# Purpose: DP-360 T2 selftest for scripts/install-precommit-fast-lint.sh (AC1
#          pre-commit segment). Proves the injected fast-lint slot is fail-closed
#          and idempotent WITHOUT ever touching the live .git/hooks/pre-commit:
#          every case runs in an isolated mktemp git repo with a fixture hook,
#          fixture tier-manifest cache, and fixture fast-lint selftests.
# Inputs:  none.
# Outputs: per-case PASS/FAIL lines; exit 0 if all pass, exit 1 on any failure.
#
# Cases:
#   1. install injects the slot; re-install is idempotent (exactly one slot).
#   2. clean staged file + all-green fast-lint subset -> commit succeeds.
#   3. staged file that trips a subset selftest -> commit blocked (exit != 0).
#   4. missing manifest cache -> commit blocked (fail-closed, not skipped).
#   5. nothing staged -> commit succeeds (clean pass; no false block).
#   6. --remove strips the slot; --status reports present/absent.
#
# Hard safety: the installer is only ever pointed at "$repo/.git/hooks/pre-commit"
# inside a throwaway mktemp git repo. The live workspace .git/hooks/pre-commit is
# never read or written by this selftest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$ROOT/scripts/install-precommit-fast-lint.sh"

fail=0
pass() { printf 'PASS: %s\n' "$1"; }
note_fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fail=1
}

# Non-vacuous guard: the installer must exist and carry its slot markers.
if [[ ! -f "$INSTALLER" ]]; then
  echo "FAIL: installer not found at $INSTALLER" >&2
  exit 1
fi
if ! grep -qF "polaris-fast-lint-slot (DP-360)" "$INSTALLER"; then
  note_fail "installer is missing the fast-lint slot marker"
fi
# Guard: the slot must be fail-closed on a missing manifest cache (no silent
# skip). Assert the installer emits the contract markers rather than skipping.
if ! grep -qF "POLARIS_FAST_LINT_SUBSET_UNAVAILABLE" "$INSTALLER"; then
  note_fail "installer slot does not fail-closed on unavailable subset"
fi

# build_fixture_repo — create an isolated git repo whose scripts/ mirrors the
# tier-manifest emit contract via a stub, plus fixture fast-lint selftests.
# Args: $1 = repo dir. Side effects: writes files, git init/commit in $1.
# The stub manifest reads a fixture JSON cache and prints its fast-lint list,
# fail-closed when the cache is absent — same external contract the live
# selftest-tier-manifest.sh exposes via --emit fast-lint.
build_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts/selftests"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@polaris.local
  git -C "$repo" config user.name "Polaris Selftest"

  # Stub tier-manifest: --emit fast-lint -> print cache lines or fail-closed.
  cat >"$repo/scripts/selftest-tier-manifest.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="$SCRIPT_DIR/selftest-tier-manifest.json"
if [[ "${1:-}" == "--emit" && "${2:-}" == "fast-lint" ]]; then
  [[ -f "$cache" ]] || { echo "POLARIS_SELFTEST_TIER_MANIFEST_MISSING: $cache" >&2; exit 2; }
  cat "$cache"
  exit 0
fi
echo "POLARIS_SELFTEST_TIER_ARG: stub only supports --emit fast-lint" >&2
exit 2
STUB
  chmod +x "$repo/scripts/selftest-tier-manifest.sh"

  # Fixture fast-lint selftest: green unless a staged file named TRIGGER exists.
  cat >"$repo/scripts/selftests/fixture-fast-selftest.sh" <<'FIX'
#!/usr/bin/env bash
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
if git -C "$REPO" diff --cached --name-only | grep -q 'TRIGGER'; then
  echo "fixture violation: staged TRIGGER file" >&2
  exit 1
fi
exit 0
FIX
  chmod +x "$repo/scripts/selftests/fixture-fast-selftest.sh"

  # Manifest cache lists the fixture selftest as the fast-lint subset.
  printf 'scripts/selftests/fixture-fast-selftest.sh\n' \
    >"$repo/scripts/selftest-tier-manifest.json"

  git -C "$repo" add -A
  git -C "$repo" commit -qm "fixture base"
}

hook_path() { printf '%s/.git/hooks/pre-commit' "$1"; }

# ---------------------------------------------------------------------------
# Case 1: install + idempotency
# ---------------------------------------------------------------------------
repo1="$(mktemp -d)"
trap 'rm -rf "$repo1"' EXIT
build_fixture_repo "$repo1"
hook1="$(hook_path "$repo1")"

bash "$INSTALLER" "$hook1" >/dev/null
if [[ ! -f "$hook1" ]] || ! grep -qF "polaris-fast-lint-slot (DP-360)" "$hook1"; then
  note_fail "case1: slot not injected into fixture hook"
fi
bash "$INSTALLER" "$hook1" >/dev/null
slot_count="$(grep -cF ">>> polaris-fast-lint-slot (DP-360) >>>" "$hook1" || true)"
if [[ "$slot_count" -eq 1 ]]; then
  pass "case1: install is idempotent (exactly one slot after re-run)"
else
  note_fail "case1: expected 1 slot after re-install, got $slot_count"
fi

# ---------------------------------------------------------------------------
# Case 2: clean staged file + green subset -> commit passes
# ---------------------------------------------------------------------------
repo2="$(mktemp -d)"
trap 'rm -rf "$repo1" "$repo2"' EXIT
build_fixture_repo "$repo2"
bash "$INSTALLER" "$(hook_path "$repo2")" >/dev/null
printf 'clean content\n' >"$repo2/clean.txt"
git -C "$repo2" add clean.txt
if git -C "$repo2" commit -qm "clean commit" >/dev/null 2>&1; then
  pass "case2: clean staged file passes the fast-lint slot"
else
  note_fail "case2: clean staged file was wrongly blocked"
fi

# ---------------------------------------------------------------------------
# Case 3: staged violation -> commit blocked
# ---------------------------------------------------------------------------
repo3="$(mktemp -d)"
trap 'rm -rf "$repo1" "$repo2" "$repo3"' EXIT
build_fixture_repo "$repo3"
bash "$INSTALLER" "$(hook_path "$repo3")" >/dev/null
printf 'bad\n' >"$repo3/TRIGGER.txt"
git -C "$repo3" add TRIGGER.txt
if git -C "$repo3" commit -qm "violating commit" >/dev/null 2>&1; then
  note_fail "case3: violating staged file was NOT blocked (fail-open)"
else
  pass "case3: violating staged file blocks the commit (fail-closed)"
fi

# ---------------------------------------------------------------------------
# Case 4: missing manifest cache -> fail-closed (commit blocked)
# ---------------------------------------------------------------------------
repo4="$(mktemp -d)"
trap 'rm -rf "$repo1" "$repo2" "$repo3" "$repo4"' EXIT
build_fixture_repo "$repo4"
bash "$INSTALLER" "$(hook_path "$repo4")" >/dev/null
rm -f "$repo4/scripts/selftest-tier-manifest.json"
git -C "$repo4" add -A
printf 'content\n' >"$repo4/file.txt"
git -C "$repo4" add file.txt
if git -C "$repo4" commit -qm "no manifest" >/dev/null 2>&1; then
  note_fail "case4: missing manifest cache did NOT block commit (fail-open skip)"
else
  pass "case4: missing manifest cache blocks the commit (fail-closed, no skip)"
fi

# ---------------------------------------------------------------------------
# Case 5: nothing staged -> clean pass (no false block)
# ---------------------------------------------------------------------------
repo5="$(mktemp -d)"
trap 'rm -rf "$repo1" "$repo2" "$repo3" "$repo4" "$repo5"' EXIT
build_fixture_repo "$repo5"
bash "$INSTALLER" "$(hook_path "$repo5")" >/dev/null
# Empty commit: nothing staged -> slot must not block.
if git -C "$repo5" commit -q --allow-empty -m "empty" >/dev/null 2>&1; then
  pass "case5: no staged files -> slot does not block"
else
  note_fail "case5: empty/no-stage commit was wrongly blocked"
fi

# ---------------------------------------------------------------------------
# Case 6: --remove strips slot, --status reports state
# ---------------------------------------------------------------------------
repo6="$(mktemp -d)"
trap 'rm -rf "$repo1" "$repo2" "$repo3" "$repo4" "$repo5" "$repo6"' EXIT
build_fixture_repo "$repo6"
hook6="$(hook_path "$repo6")"
bash "$INSTALLER" "$hook6" >/dev/null
status_present="$(bash "$INSTALLER" "$hook6" --status)"
bash "$INSTALLER" "$hook6" --remove >/dev/null
status_absent="$(bash "$INSTALLER" "$hook6" --status)"
if grep -qF "polaris-fast-lint-slot (DP-360)" "$hook6"; then
  note_fail "case6: --remove did not strip the slot"
elif [[ "$status_present" == POLARIS_FAST_LINT_SLOT_PRESENT:* && "$status_absent" == POLARIS_FAST_LINT_SLOT_ABSENT:* ]]; then
  pass "case6: --remove strips slot; --status reports present/absent"
else
  note_fail "case6: --status output unexpected (present='$status_present' absent='$status_absent')"
fi

# ---------------------------------------------------------------------------
# Safety assertion: the live workspace pre-commit hook was never the target.
# (Defensive: the live hook still carries its own marker, unrelated to ours.)
# ---------------------------------------------------------------------------
live_hook="$ROOT/.git/hooks/pre-commit"
if [[ -f "$live_hook" ]] && grep -qF "polaris-fast-lint-slot (DP-360)" "$live_hook"; then
  note_fail "SAFETY: live .git/hooks/pre-commit was mutated by the selftest"
else
  pass "safety: live .git/hooks/pre-commit untouched by selftest"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "precommit-fast-lint-selftest: FAIL" >&2
  exit 1
fi
echo "precommit-fast-lint-selftest: PASS"
exit 0
