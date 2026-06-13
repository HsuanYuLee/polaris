#!/usr/bin/env bash
# Purpose: selftest for scripts/lint-bash-variable-utf8-boundary.sh.
# Inputs:  none (hermetic; builds fixtures under mktemp).
# Outputs: PASS line on stdout; non-zero exit + FAIL diagnostics on failure.
#
# Covers DP-255 AC4 / AC-NEG1 / AC-NEG2:
#   - positive fixture (unbraced $VAR followed by CJK fullwidth byte) → exit 2
#   - negative fixture (braced ${VAR} followed by CJK fullwidth byte) → exit 0
#   - negative fixture (unbraced $VAR followed by ASCII punctuation) → exit 0
#   - negative fixture (unbraced $VAR followed by ASCII space + non-ASCII text) → exit 0
#
# Covers DP-307 AC7 (push refspec construction):
#   - positive fixture (git push with task-title-derived var in refspec) → exit 2
#     + POLARIS_REFSPEC_VAR_INTERPOLATION
#   - negative fixture (git push origin HEAD:"$(git symbolic-ref --short HEAD)") → exit 0
#   - real engineering-branch-setup.sh / polaris-pr-create.sh pass the lint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINT="${WORKSPACE_ROOT}/lint-bash-variable-utf8-boundary.sh"

if [[ ! -x "$LINT" ]]; then
  echo "FAIL: lint script not executable: ${LINT}" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t lint-utf8-boundary-selftest.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

# Positive fixture — fullwidth right paren glued to $foo.
positive="${tmpdir}/positive.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'foo=ok'
  # Use printf with \xEF\xBC\x89 (U+FF09 fullwidth right paren) to keep the
  # fixture source ASCII; lint sees the raw bytes after expansion.
  printf 'echo "$foo'
  printf '\xef\xbc\x89'
  printf '"\n'
} > "$positive"

set +e
bash "$LINT" "$positive" >/dev/null 2>"${tmpdir}/positive.err"
positive_rc=$?
set -e
if [[ $positive_rc -ne 2 ]]; then
  echo "FAIL: positive fixture expected exit 2, got ${positive_rc}" >&2
  cat "${tmpdir}/positive.err" >&2 || true
  exit 1
fi
if ! grep -q 'POLARIS_BASH_VAR_UTF8_BOUNDARY' "${tmpdir}/positive.err"; then
  echo "FAIL: positive fixture missing POLARIS_BASH_VAR_UTF8_BOUNDARY token" >&2
  cat "${tmpdir}/positive.err" >&2 || true
  exit 1
fi

# Negative fixture 1 — braced form is safe.
neg_brace="${tmpdir}/neg_brace.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'foo=ok'
  printf 'echo "${foo}'
  printf '\xef\xbc\x89'
  printf '"\n'
} > "$neg_brace"

set +e
bash "$LINT" "$neg_brace" >/dev/null 2>"${tmpdir}/neg_brace.err"
neg_brace_rc=$?
set -e
if [[ $neg_brace_rc -ne 0 ]]; then
  echo "FAIL: negative (braced) fixture expected exit 0, got ${neg_brace_rc}" >&2
  cat "${tmpdir}/neg_brace.err" >&2 || true
  exit 1
fi

# Negative fixture 2 — ASCII punctuation is safe.
neg_ascii="${tmpdir}/neg_ascii.sh"
cat > "$neg_ascii" <<'EOS'
#!/usr/bin/env bash
foo=ok
echo "$foo);"
EOS

set +e
bash "$LINT" "$neg_ascii" >/dev/null 2>"${tmpdir}/neg_ascii.err"
neg_ascii_rc=$?
set -e
if [[ $neg_ascii_rc -ne 0 ]]; then
  echo "FAIL: negative (ASCII punctuation) fixture expected exit 0, got ${neg_ascii_rc}" >&2
  cat "${tmpdir}/neg_ascii.err" >&2 || true
  exit 1
fi

# Negative fixture 3 — ASCII space between $VAR and non-ASCII text is safe.
neg_space="${tmpdir}/neg_space.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'foo=ok'
  printf 'echo "$foo bar '
  printf '\xef\xbc\x89'
  printf '"\n'
} > "$neg_space"

set +e
bash "$LINT" "$neg_space" >/dev/null 2>"${tmpdir}/neg_space.err"
neg_space_rc=$?
set -e
if [[ $neg_space_rc -ne 0 ]]; then
  echo "FAIL: negative (ASCII space) fixture expected exit 0, got ${neg_space_rc}" >&2
  cat "${tmpdir}/neg_space.err" >&2 || true
  exit 1
fi

# --- DP-307 AC7: push refspec construction ---------------------------------
# Fixtures assemble the trigger bytes at runtime via printf so this selftest's
# own source lines never literally contain a `git push <refspec-var>` sequence
# (otherwise the default-scan Verify gate would flag this file). DOLLAR holds a
# literal `$` so `${DOLLAR}TITLE` renders as `$TITLE` in the fixture, not here.
DOLLAR='$'

# Positive fixture — git push with a task-title-derived var in the refspec.
refspec_bad="${tmpdir}/refspec_bad.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'TITLE=$(make_slug)'
  printf 'git push origin refs/heads/%sTITLE:refs/heads/%sTITLE\n' "$DOLLAR" "$DOLLAR"
} > "$refspec_bad"

set +e
bash "$LINT" "$refspec_bad" >/dev/null 2>"${tmpdir}/refspec_bad.err"
refspec_bad_rc=$?
set -e
if [[ $refspec_bad_rc -ne 2 ]]; then
  echo "FAIL: refspec interpolation fixture expected exit 2, got ${refspec_bad_rc}" >&2
  cat "${tmpdir}/refspec_bad.err" >&2 || true
  exit 1
fi
if ! grep -q 'POLARIS_REFSPEC_VAR_INTERPOLATION' "${tmpdir}/refspec_bad.err"; then
  echo "FAIL: refspec interpolation fixture missing POLARIS_REFSPEC_VAR_INTERPOLATION token" >&2
  cat "${tmpdir}/refspec_bad.err" >&2 || true
  exit 1
fi

# Negative fixture — safe construction reads the ref from git via $(...).
refspec_safe="${tmpdir}/refspec_safe.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'git push origin HEAD:"%s(git symbolic-ref --short HEAD)"\n' "$DOLLAR"
} > "$refspec_safe"

set +e
bash "$LINT" "$refspec_safe" >/dev/null 2>"${tmpdir}/refspec_safe.err"
refspec_safe_rc=$?
set -e
if [[ $refspec_safe_rc -ne 0 ]]; then
  echo "FAIL: safe symbolic-ref refspec fixture expected exit 0, got ${refspec_safe_rc}" >&2
  cat "${tmpdir}/refspec_safe.err" >&2 || true
  exit 1
fi

# Real-script coverage — engineering-branch-setup.sh and polaris-pr-create.sh
# must pass the lint (they construct branch/head refs from git, not from
# task-title-derived vars).
for real in engineering-branch-setup.sh polaris-pr-create.sh; do
  real_path="${WORKSPACE_ROOT}/${real}"
  if [[ ! -f "$real_path" ]]; then
    echo "FAIL: expected real script not found: ${real_path}" >&2
    exit 1
  fi
  set +e
  bash "$LINT" "$real_path" >/dev/null 2>"${tmpdir}/${real}.err"
  real_rc=$?
  set -e
  if [[ $real_rc -ne 0 ]]; then
    echo "FAIL: real script ${real} expected to pass lint, got exit ${real_rc}" >&2
    cat "${tmpdir}/${real}.err" >&2 || true
    exit 1
  fi
done

echo "PASS: lint-bash-variable-utf8-boundary selftest (4 boundary + 2 refspec + 2 real-script)"
