#!/usr/bin/env bash
# Purpose: selftest for scripts/lint-naive-section-parse.sh (DP-345 D4).
# Inputs:  none (hermetic; builds fixtures under mktemp).
# Outputs: PASS line on stdout; non-zero exit + FAIL diagnostics on failure.
#
# Covers DP-345 AC5 / AC-NEG1 / AC-NEG2:
#   - AC5 positive: naive blob-level `text.find("## ...")` / `.index(...)` /
#     `.split("## ...")` over un-frontmatter-stripped markdown → exit 2 +
#     POLARIS_NAIVE_SECTION_PARSE.
#   - AC-NEG1: line-anchored idioms (awk $0==heading / ^## re.M / splitlines +
#     startswith("## ")) and path-string find (find("/apps/") /
#     find("src/content/docs/")) → exit 0, no false positive.
#   - AC-NEG2: <path>:<reason> allowlist exempts a genuinely frontmatter-less
#     file (CHANGELOG-style `## ` version-block find); a same-pattern file NOT in
#     the allowlist still → exit 2.
#   - AC5 wiring: scripts/check-framework-pr-gate.sh aggregate references the lint.
#   - real-tree coverage: lint passes (0 violations) on the converged repo tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINT="${WORKSPACE_ROOT}/lint-naive-section-parse.sh"

if [[ ! -x "$LINT" ]]; then
  echo "FAIL: lint script not executable: ${LINT}" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t lint-naive-section-parse-selftest.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

# DOLLAR keeps fixture `${...}` literals from being expanded by this shell, and
# HASH avoids embedding the literal naive idiom in this selftest's own source
# (otherwise the lint's real-tree scan over scripts/** would flag this file).
HASH='##'

run_lint() {
  # run_lint <expected_rc> <label> [extra lint args...] -- <target ...>
  local expected="$1"; shift
  local label="$1"; shift
  local -a args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do args+=("$1"); shift; done
  shift # drop --
  set +e
  bash "$LINT" ${args[@]+"${args[@]}"} "$@" >"${tmpdir}/out" 2>"${tmpdir}/err"
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected" ]]; then
    echo "FAIL: ${label} expected exit ${expected}, got ${rc}" >&2
    cat "${tmpdir}/err" >&2 || true
    exit 1
  fi
  printf '%s' "$rc"
}

# --- AC5 positive: naive blob find/index/split → exit 2 ---------------------
pos_find="${tmpdir}/pos_find.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def section(text, heading):'
  printf '    marker = "%s " + heading\n' "$HASH"
  printf '    start = text.find(marker)\n'
  printf '    end = text.find("\\n%s ", start + 1)\n' "$HASH"
  printf '    return text[start:end]\n'
} > "$pos_find"
run_lint 2 "AC5 positive find" -- "$pos_find" >/dev/null
if ! grep -q 'POLARIS_NAIVE_SECTION_PARSE' "${tmpdir}/err"; then
  echo "FAIL: AC5 positive find missing POLARIS_NAIVE_SECTION_PARSE token" >&2
  cat "${tmpdir}/err" >&2 || true
  exit 1
fi

pos_index="${tmpdir}/pos_index.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def section(text):'
  printf '    start = text.index("%s Allowed Files")\n' "$HASH"
  printf '    return text[start:]\n'
} > "$pos_index"
run_lint 2 "AC5 positive index" -- "$pos_index" >/dev/null

pos_split="${tmpdir}/pos_split.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def split_sections(text):'
  printf '    return text.split("\\n%s ")\n' "$HASH"
} > "$pos_split"
run_lint 2 "AC5 positive split" -- "$pos_split" >/dev/null

# --- AC-NEG1: line-anchored idioms + path-string find → exit 0 --------------
# (1) awk $0==heading
neg_awk="${tmpdir}/neg_awk.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'awk -v h="%s Allowed Files" '"'"'$0==h {found=1} found {print}'"'"' "$1"\n' "$HASH"
} > "$neg_awk"
run_lint 0 "AC-NEG1 awk line-anchor" -- "$neg_awk" >/dev/null

# (2) re.M ^## anchored regex
neg_re="${tmpdir}/neg_re.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'import re'
  printf '%s\n' 'def section(text, heading):'
  printf '    pat = re.compile(r"^%s " + re.escape(heading) + r"$", re.M)\n' "$HASH"
  printf '    m = pat.search(text)\n'
  printf '    return m.start() if m else -1\n'
} > "$neg_re"
run_lint 0 "AC-NEG1 re.M line-anchor" -- "$neg_re" >/dev/null

# (3) splitlines + startswith("## ")
neg_splitlines="${tmpdir}/neg_splitlines.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def section(text, heading):'
  printf '    marker = "%s " + heading\n' "$HASH"
  printf '    for line in text.splitlines():\n'
  printf '        if line.startswith("%s "):\n' "$HASH"
  printf '            return line\n'
  printf '    return ""\n'
} > "$neg_splitlines"
run_lint 0 "AC-NEG1 splitlines+startswith" -- "$neg_splitlines" >/dev/null

# (4) path-string find — no ## marker, must not flag
neg_pathfind="${tmpdir}/neg_pathfind.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def is_app(path):'
  printf '    return path.find("/apps/") != -1\n'
  printf '%s\n' 'def is_docs(path):'
  printf '    return path.find("src/content/docs/") >= 0\n'
} > "$neg_pathfind"
run_lint 0 "AC-NEG1 path-string find" -- "$neg_pathfind" >/dev/null

# --- AC-NEG2: allowlist exempts genuinely frontmatter-less file --------------
# A CHANGELOG-style file that legitimately blob-finds a `## ` version block —
# CHANGELOG has no frontmatter, so the blob find is safe.
changelog_parser="${tmpdir}/changelog_version_block.py"
{
  printf '%s\n' '#!/usr/bin/env python3'
  printf '%s\n' 'def latest_block(changelog_text, version):'
  printf '    start = changelog_text.find("%s [" + version + "]")\n' "$HASH"
  printf '    end = changelog_text.find("\\n%s [", start + 1)\n' "$HASH"
  printf '    return changelog_text[start:end]\n'
} > "$changelog_parser"

# Without allowlist → flagged (exit 2): proves the pattern IS naive.
run_lint 2 "AC-NEG2 same-pattern not-allowlisted" -- "$changelog_parser" >/dev/null

# With per-path allowlist → exempt (exit 0).
allowlist="${tmpdir}/allowlist.txt"
printf '%s:CHANGELOG version block has no frontmatter; blob find is safe\n' "$changelog_parser" > "$allowlist"
run_lint 0 "AC-NEG2 allowlisted exempt" --allowlist "$allowlist" -- "$changelog_parser" >/dev/null

# AC-NEG2 guard: an allowlist entry must not be an over-broad directory wildcard.
# A second same-pattern file NOT in the allowlist still flags even when the
# allowlist is present (proves allowlist is per-path, not a global off switch).
other_parser="${tmpdir}/other_naive.py"
cp "$changelog_parser" "$other_parser"
run_lint 2 "AC-NEG2 allowlist is per-path" --allowlist "$allowlist" -- "$other_parser" >/dev/null

# --- AC5 wiring: framework PR gate aggregate references the lint -------------
if ! grep -q 'lint-naive-section-parse' "${WORKSPACE_ROOT}/check-framework-pr-gate.sh"; then
  echo "FAIL: check-framework-pr-gate.sh aggregate does not reference lint-naive-section-parse" >&2
  exit 1
fi

# --- real-tree coverage: lint passes on the converged repo (--self-check) ----
set +e
bash "$LINT" --self-check >"${tmpdir}/selfcheck.out" 2>"${tmpdir}/selfcheck.err"
selfcheck_rc=$?
set -e
if [[ "$selfcheck_rc" -ne 0 ]]; then
  echo "FAIL: --self-check on the converged repo tree expected exit 0, got ${selfcheck_rc}" >&2
  echo "(If this flags a legitimate remaining callsite, either it belongs in the" >&2
  echo " allowlist with a reason, or T1 missed a naive parser — report, do not widen.)" >&2
  cat "${tmpdir}/selfcheck.err" >&2 || true
  exit 1
fi

echo "PASS: lint-naive-section-parse selftest (3 positive + 4 NEG1 + 3 NEG2 + wiring + self-check)"
