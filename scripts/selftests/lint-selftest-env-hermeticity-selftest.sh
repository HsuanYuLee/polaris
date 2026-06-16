#!/usr/bin/env bash
# Purpose: selftest for scripts/lint-selftest-env-hermeticity.sh.
# Inputs:  none (hermetic; builds fixtures under mktemp).
# Outputs: PASS line on stdout; non-zero exit + FAIL diagnostics on failure.
#
# Covers DP-325 AC4 / AC-NF1 / AC-NEG3:
#   - positive fixture (bash "$0" --scan-root with no env-unset / no --specs-source
#     / no inline POLARIS_WORKSPACE_ROOT export) → exit 2 + POLARIS_SELFTEST_ENV_LEAK
#   - negative fixture (env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT) → exit 0
#   - negative fixture (explicit --specs-source) → exit 0
#   - negative fixture (inline POLARIS_WORKSPACE_ROOT=<fixture> export) → exit 0
#   - negative fixture (the trigger pattern only inside a comment line) → exit 0
#   - negative fixture (--scan-dir, a lint dir arg, not a workspace anchor) → exit 0
#   - allowlist suppression: a leak fixture listed in the override allowlist → exit 0
#   - fail-closed (AC-NF1): empty target set → exit 2 + POLARIS_SELFTEST_ENV_LEAK
#   - fail-closed (AC-NF1): unreadable --allowlist path → exit 2
#   - real tree: the live selftest tree passes the gate (embedded allowlist) → exit 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINT="${WORKSPACE_ROOT}/lint-selftest-env-hermeticity.sh"

if [[ ! -f "$LINT" ]]; then
  echo "FAIL: lint script not found: ${LINT}" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t lint-selftest-env-hermeticity-selftest.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

# Empty override allowlist so embedded entries do not interfere with the synthetic
# fixtures below (the fixtures live under mktemp, not under scripts/selftests).
empty_allowlist="${tmpdir}/empty-allowlist.txt"
: > "$empty_allowlist"

# DOLLAR holds a literal `$` so fixtures render `$0` / `$tmpdir` at runtime without
# this selftest's own source carrying a literal `bash "$0" --scan-root` sequence
# (which the default-scan gate would otherwise pick up from this file).
DOLLAR='$'

run_lint() {
  # Args: $1 = expected exit code; remaining = lint args. Captures stderr.
  local expected="$1"; shift
  local rc=0
  set +e
  bash "$LINT" "$@" >/dev/null 2>"${tmpdir}/lint.err"
  rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "FAIL: expected exit ${expected}, got ${rc} for: $*" >&2
    cat "${tmpdir}/lint.err" >&2 || true
    exit 1
  fi
}

# --- positive: genuine leak ------------------------------------------------
leak="${tmpdir}/leak-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'out="%s(bash "%s0" --scan-root "%stmpdir" DP-047-T1)"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$leak"
run_lint 2 --allowlist "$empty_allowlist" "$leak"
if ! grep -q 'POLARIS_SELFTEST_ENV_LEAK' "${tmpdir}/lint.err"; then
  echo "FAIL: positive fixture missing POLARIS_SELFTEST_ENV_LEAK token" >&2
  cat "${tmpdir}/lint.err" >&2 || true
  exit 1
fi

# --- negative: env -u neutralized ------------------------------------------
safe_unset="${tmpdir}/safe-unset-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'out="%s(env -u RESOLVE -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash "%s0" --scan-root "%stmpdir" DP-047-T1)"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$safe_unset"
run_lint 0 --allowlist "$empty_allowlist" "$safe_unset"

# --- negative: explicit --specs-source -------------------------------------
safe_specs="${tmpdir}/safe-specs-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'out="%s(bash "%s0" --scan-root "%swt" --specs-source "%stmpdir/specs" DP-047-T1)"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$safe_specs"
run_lint 0 --allowlist "$empty_allowlist" "$safe_specs"

# --- negative: inline fixture POLARIS_WORKSPACE_ROOT export -----------------
safe_inline="${tmpdir}/safe-inline-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'out="%s(POLARIS_WORKSPACE_ROOT="%sFIX" bash "%s0" --scan-root "%swt" DP-047-T1)"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$safe_inline"
run_lint 0 --allowlist "$empty_allowlist" "$safe_inline"

# --- negative: trigger pattern only inside a comment ------------------------
safe_comment="${tmpdir}/safe-comment-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '# example: bash "%s0" --scan-root "%stmpdir" DP-047-T1\n' "$DOLLAR" "$DOLLAR"
  printf '%s\n' 'echo ok'
} > "$safe_comment"
run_lint 0 --allowlist "$empty_allowlist" "$safe_comment"

# --- negative: --scan-dir is a lint dir arg, not a workspace anchor ---------
safe_scandir="${tmpdir}/safe-scandir-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'bash "%sLINT" --scan-dir "%sdir" >/dev/null 2>"%serr"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$safe_scandir"
run_lint 0 --allowlist "$empty_allowlist" "$safe_scandir"

# --- allowlist suppression: a leak fixture listed in the allowlist passes ----
# The lint normalizes paths on the `/scripts/` segment; build a fixture under a
# fake scripts/ tree so its normalized key is stable and listable.
mkdir -p "${tmpdir}/scripts/selftests"
allowlisted_leak="${tmpdir}/scripts/selftests/allowlisted-leak-selftest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'out="%s(bash "%s0" --scan-root "%stmpdir" DP-047-T1)"\n' "$DOLLAR" "$DOLLAR" "$DOLLAR"
} > "$allowlisted_leak"
suppress_allowlist="${tmpdir}/suppress-allowlist.txt"
printf '%s\trationale: synthetic allowlist-suppression fixture\n' \
  'scripts/selftests/allowlisted-leak-selftest.sh' > "$suppress_allowlist"
run_lint 0 --allowlist "$suppress_allowlist" "$allowlisted_leak"
# Sanity: the SAME fixture without the allowlist must fail (proves the pass above
# is the allowlist, not a degenerate no-op).
run_lint 2 --allowlist "$empty_allowlist" "$allowlisted_leak"

# --- fail-closed (AC-NF1): empty target set --------------------------------
# An empty TARGETS set (no scan inputs) must fail closed, not silently pass.
# Invoke with an override allowlist that points at a real dir containing zero
# selftests is not directly expressible via the CLI (no targets means default
# discovery); instead assert the default-discovery path returns 0 on the real
# tree and the no-target guard via an empty find root is covered by code review.
# Directly exercise the unreadable-allowlist fail-closed branch:
run_lint 2 --allowlist "${tmpdir}/does-not-exist-allowlist.txt" "$safe_comment"

# --- fail-closed (AC-NF1): empty discovered target set ---------------------
# Drive the no-target branch by pointing the scan at an empty fake workspace.
empty_ws="${tmpdir}/empty-ws"
mkdir -p "${empty_ws}/scripts/selftests"
set +e
( cd "${empty_ws}/scripts" 2>/dev/null
  # Run a copy of the lint anchored in the empty tree so its default discovery
  # resolves zero targets.
  cp "$LINT" "${empty_ws}/scripts/lint-selftest-env-hermeticity.sh"
  bash "${empty_ws}/scripts/lint-selftest-env-hermeticity.sh" >/dev/null 2>"${tmpdir}/empty.err" )
empty_rc=$?
set -e
if [[ $empty_rc -ne 2 ]]; then
  echo "FAIL: empty-target discovery expected fail-closed exit 2, got ${empty_rc}" >&2
  cat "${tmpdir}/empty.err" >&2 || true
  exit 1
fi
if ! grep -q 'POLARIS_SELFTEST_ENV_LEAK' "${tmpdir}/empty.err"; then
  echo "FAIL: empty-target fail-closed missing POLARIS_SELFTEST_ENV_LEAK token" >&2
  cat "${tmpdir}/empty.err" >&2 || true
  exit 1
fi

# --- real tree: live selftest tree passes (embedded allowlist) -------------
run_lint 0

echo "PASS: lint-selftest-env-hermeticity selftest (6 fixture + 2 allowlist + 2 fail-closed + real-tree)"
