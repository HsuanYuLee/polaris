#!/usr/bin/env bash
# Selftest for scripts/lint-bash-variable-utf8-boundary.sh.
#
# Covers DP-255 AC4 / AC-NEG1 / AC-NEG2:
#   - positive fixture (unbraced $VAR followed by CJK fullwidth byte) → exit 2
#   - negative fixture (braced ${VAR} followed by CJK fullwidth byte) → exit 0
#   - negative fixture (unbraced $VAR followed by ASCII punctuation) → exit 0
#   - negative fixture (unbraced $VAR followed by ASCII space + non-ASCII text) → exit 0

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

echo "PASS: lint-bash-variable-utf8-boundary selftest (positive + 3 negatives)"
