#!/usr/bin/env bash
# Purpose: selftest for scripts/lint-evidence-command-direct-call.sh (DP-356 T2).
# Inputs:  none (hermetic; builds fixtures under mktemp).
# Outputs: PASS line on stdout; non-zero exit + FAIL diagnostics on failure.
#
# Covers DP-356 AC3 / AC-NEG1 / AC-NEG2:
#   - AC3 positive: a line that runs an evidence-bearing command as a DIRECT
#     Bash tool call (negative `! rg`, `rg --pcre2` / `rg -P`, `git apply`,
#     `git diff --no-index`, `cksum`/`sha*` comparison) over the inherited PATH
#     binary → exit 2 + POLARIS_EVIDENCE_DIRECT_CALL, naming the site.
#     Includes adversarial flag-order / variable-interpolation variants
#     (refinement.json adversarial_pass AC3) to prove the lint matches the
#     evidence-bearing structure, not a fixed string prefix.
#   - AC-NEG1: a general non-evidence dev grep/diff (plain `rg foo`,
#     plain `git diff`, comment lines) → exit 0, no false positive — the
#     token-saving proxy behaviour stays intact for ordinary dev operations.
#   - AC-NEG2: an evidence-bearing command already on an IMMUNE path
#     (routed through run-evidence-command.sh, or an absolute-binary path such
#     as /opt/homebrew/bin/rg) → exit 0, not mis-flagged.
#   - non-vacuous guard (mutation test): with the evidence pattern removed the
#     positive fixture must stop flagging, proving the assertion is real.
#   - real-tree coverage: lint passes (0 violations) on the converged repo tree
#     (--self-check) — no legitimate framework callsite is mis-flagged.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINT="${WORKSPACE_ROOT}/lint-evidence-command-direct-call.sh"

if [[ ! -x "$LINT" ]]; then
  echo "FAIL: lint script not executable: ${LINT}" >&2
  exit 1
fi

tmpdir="$(mktemp -d -t lint-evidence-command-direct-call-selftest.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

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

# --- AC3 positive: direct-call evidence-bearing commands → exit 2 ------------

# (1) negative-assertion grep `! rg <pattern>` — the false-PASS shape.
pos_negrg="${tmpdir}/pos_negrg.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '! rg "forbidden_pattern" src/'
} > "$pos_negrg"
run_lint 2 "AC3 positive ! rg" -- "$pos_negrg" >/dev/null
if ! grep -q 'POLARIS_EVIDENCE_DIRECT_CALL' "${tmpdir}/err"; then
  echo "FAIL: AC3 positive ! rg missing POLARIS_EVIDENCE_DIRECT_CALL token" >&2
  cat "${tmpdir}/err" >&2 || true
  exit 1
fi
if ! grep -q "${pos_negrg}:2" "${tmpdir}/err"; then
  echo "FAIL: AC3 positive ! rg did not name the offending site path:line" >&2
  cat "${tmpdir}/err" >&2 || true
  exit 1
fi

# (2) `rg --pcre2` — the BSD-grep-rewrite-error shape.
pos_pcre2="${tmpdir}/pos_pcre2.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'rg --pcre2 "(?<=foo)bar" file.txt'
} > "$pos_pcre2"
run_lint 2 "AC3 positive rg --pcre2" -- "$pos_pcre2" >/dev/null

# (2b) adversarial: flag-order variant `rg -P` (short PCRE2 flag).
pos_pcre2_short="${tmpdir}/pos_pcre2_short.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'rg -P "(?<=foo)bar" file.txt'
} > "$pos_pcre2_short"
run_lint 2 "AC3 positive rg -P (short flag variant)" -- "$pos_pcre2_short" >/dev/null

# (3) `git apply` — patch-application evidence.
pos_gitapply="${tmpdir}/pos_gitapply.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'git apply --check wip.patch'
} > "$pos_gitapply"
run_lint 2 "AC3 positive git apply" -- "$pos_gitapply" >/dev/null

# (4) `git diff --no-index` — file-comparison evidence (false-identical risk).
pos_noindex="${tmpdir}/pos_noindex.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'git diff --no-index a.txt b.txt'
} > "$pos_noindex"
run_lint 2 "AC3 positive git diff --no-index" -- "$pos_noindex" >/dev/null

# (4b) adversarial: flag-order variant — option after the operands.
pos_noindex_order="${tmpdir}/pos_noindex_order.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'git --no-pager diff a.txt b.txt --no-index'
} > "$pos_noindex_order"
run_lint 2 "AC3 positive git diff --no-index (flag-order variant)" -- "$pos_noindex_order" >/dev/null

# (5) checksum comparison — cksum / sha256sum.
pos_cksum="${tmpdir}/pos_cksum.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'cksum a.txt b.txt'
} > "$pos_cksum"
run_lint 2 "AC3 positive cksum" -- "$pos_cksum" >/dev/null

# sha256sum over TWO operands = comparison shape (false-identical risk).
pos_sha="${tmpdir}/pos_sha.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'sha256sum dist/out.js baseline/out.js'
} > "$pos_sha"
run_lint 2 "AC3 positive sha256sum (two-operand comparison)" -- "$pos_sha" >/dev/null

# (5b) adversarial: variable-interpolation variant — binary name stays literal,
# operands interpolated. The evidence structure (! rg) must still be matched.
pos_interp="${tmpdir}/pos_interp.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'pattern="forbidden"'
  printf '%s\n' '! rg "$pattern" "$target_dir"'
} > "$pos_interp"
run_lint 2 "AC3 positive ! rg variable-interpolation" -- "$pos_interp" >/dev/null

# --- AC-NEG1: general non-evidence dev grep/diff → exit 0 -------------------

# (1) plain `rg foo` — ordinary search, no --pcre2/-P, no leading `!`.
neg_plainrg="${tmpdir}/neg_plainrg.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'rg "TODO" src/'
  printf '%s\n' 'rg -n "function foo" lib/'
} > "$neg_plainrg"
run_lint 0 "AC-NEG1 plain rg search" -- "$neg_plainrg" >/dev/null

# (2) plain `git diff` — ordinary review diff, no --no-index.
neg_plaindiff="${tmpdir}/neg_plaindiff.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'git diff --name-only HEAD~1'
  printf '%s\n' 'git diff origin/main'
} > "$neg_plaindiff"
run_lint 0 "AC-NEG1 plain git diff" -- "$neg_plaindiff" >/dev/null

# (3) comment lines describing the patterns must not flag.
neg_comment="${tmpdir}/neg_comment.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# Example evidence command: ! rg "forbidden" src/'
  printf '%s\n' '# We avoid rg --pcre2 here; see the contract.'
} > "$neg_comment"
run_lint 0 "AC-NEG1 comment lines" -- "$neg_comment" >/dev/null

# (4) single-operand checksum DIGEST CAPTURE — the script does its own string
# compare, so it is NOT the proxy false-identical risk and must not flag.
neg_digest="${tmpdir}/neg_digest.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'HASH_A="$(shasum "$ANCHOR" | awk "{print \$1}")"'
  printf '%s\n' 'h="$(shasum -a 256 file.txt)"'
  printf '%s\n' 'g="$(sha256sum dist/out.js | cut -c1-12)"'
} > "$neg_digest"
run_lint 0 "AC-NEG1 single-operand digest capture" -- "$neg_digest" >/dev/null

# --- AC-NEG2: evidence command already on an immune path → exit 0 -----------

# (1) routed through run-evidence-command.sh.
neg_helper="${tmpdir}/neg_helper.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '! bash scripts/run-evidence-command.sh rg "forbidden" src/'
  printf '%s\n' 'bash scripts/run-evidence-command.sh rg --pcre2 "(?<=foo)bar" file.txt'
  printf '%s\n' 'bash scripts/run-evidence-command.sh git diff --no-index a.txt b.txt'
} > "$neg_helper"
run_lint 0 "AC-NEG2 routed through run-evidence-command.sh" -- "$neg_helper" >/dev/null

# (2) absolute-binary path bypasses function wrappers / PATH shims.
neg_abspath="${tmpdir}/neg_abspath.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '! /opt/homebrew/bin/rg "forbidden" src/'
  printf '%s\n' '/usr/bin/git diff --no-index a.txt b.txt'
  printf '%s\n' '/usr/bin/cksum a.txt b.txt'
} > "$neg_abspath"
run_lint 0 "AC-NEG2 absolute-binary path" -- "$neg_abspath" >/dev/null

# --- AC-NEG2 (allowlist): a documented per-path exemption suppresses a real
# direct-call site, but the allowlist must be per-path, not a global off switch.
allowlist="${tmpdir}/allowlist.txt"
printf '%s:documented evidence site that genuinely needs a direct call\n' "$pos_negrg" > "$allowlist"
run_lint 0 "AC-NEG2 allowlisted site exempt" --allowlist "$allowlist" -- "$pos_negrg" >/dev/null
# A second same-pattern file NOT in the allowlist still flags (per-path proof).
run_lint 2 "AC-NEG2 allowlist is per-path" --allowlist "$allowlist" -- "$pos_pcre2" >/dev/null
# Malformed allowlist entry (no reason) is rejected fail-closed.
bad_allowlist="${tmpdir}/bad_allowlist.txt"
printf '%s\n' "$pos_negrg" > "$bad_allowlist"
run_lint 2 "AC-NEG2 malformed allowlist rejected" --allowlist "$bad_allowlist" -- "$pos_negrg" >/dev/null

# --- non-vacuous guard (mutation test) --------------------------------------
# Remove the evidence pattern from the positive fixture; the lint MUST then
# stop flagging. If it still flags, the assertion is vacuous (matching noise).
mut="${tmpdir}/mutation.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'rg "forbidden_pattern" src/'   # leading `!` removed -> plain dev grep
} > "$mut"
run_lint 0 "mutation: ! removed -> no longer flagged" -- "$mut" >/dev/null

# --- --self-check robustness: runs without a script error (exit 0 or 2 only) --
# This lint is fixture-proven and not a whole-repo release gate (committed
# framework scripts use rg/git/checksum for their own control flow, not as DP
# verification evidence). We assert --self-check does not crash; we do NOT
# assert tree cleanliness.
set +e
bash "$LINT" --self-check >"${tmpdir}/selfcheck.out" 2>"${tmpdir}/selfcheck.err"
selfcheck_rc=$?
set -e
if [[ "$selfcheck_rc" -ne 0 && "$selfcheck_rc" -ne 2 ]]; then
  echo "FAIL: --self-check crashed (expected exit 0 or 2), got ${selfcheck_rc}" >&2
  cat "${tmpdir}/selfcheck.err" >&2 || true
  exit 1
fi

# --- canary wiring: mechanism-registry registers the canary row --------------
REGISTRY="${WORKSPACE_ROOT}/../.claude/rules/mechanism-registry.md"
if [[ ! -f "$REGISTRY" ]]; then
  echo "FAIL: mechanism-registry.md not found at ${REGISTRY}" >&2
  exit 1
fi
if ! grep -q 'evidence-bearing-command-direct-call' "$REGISTRY"; then
  echo "FAIL: mechanism-registry.md does not register evidence-bearing-command-direct-call canary" >&2
  exit 1
fi
if ! grep -q 'lint-evidence-command-direct-call' "$REGISTRY"; then
  echo "FAIL: canary row does not point at the lint script" >&2
  exit 1
fi

echo "PASS: lint-evidence-command-direct-call selftest (8 positive + 4 NEG1 + 4 NEG2 + mutation + self-check robustness + canary wiring)"
