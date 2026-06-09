#!/usr/bin/env bash
# Purpose: DP-298 T1 selftest for lint-no-business-gate-reads-derived-md.sh.
#   Exercises the derived-md business-read detector against hermetic sandbox
#   fixtures plus the live scripts/ tree:
#     1. business-read fixture (git show + ## Scope heading diff) → exit 2 + marker
#     2. idempotency-read fixture (render-refinement-md.sh --check style) → PASS
#     3. parity-read fixture mirroring validate-refinement-artifact-parity.sh → PASS
#        (AC-NEG3: legitimate parity reader not misclassified)
#     4. existence-only fixture ([[ -f refinement.md ]]) → PASS
#     5. live scripts/ scan PASSes (no false positives on real readers)
# Inputs:  none (builds fixtures in a tmpdir).
# Outputs: PASS/FAIL lines per case; exit 0 if all pass, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$ROOT/scripts/lint-no-business-gate-reads-derived-md.sh"

if [[ ! -f "$LINT" ]]; then
  echo "FAIL: lint missing: $LINT" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "PASS: $label (exit=$actual)"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

assert_stderr_contains() {
  local label="$1" needle="$2" file="$3"
  if grep -Fq "$needle" "$file"; then
    echo "PASS: $label (stderr contains '$needle')"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (stderr missing '$needle')" >&2
    cat "$file" >&2
    fail=$((fail + 1))
  fi
}

run_scan() {
  # run_scan <scan-dir> <stderr-file>; echoes the lint exit code to stdout so the
  # caller can capture it without tripping `set -e` on a non-zero return.
  local dir="$1" errfile="$2" rc=0
  bash "$LINT" --scan-dir "$dir" >/dev/null 2>"$errfile" || rc=$?
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# Case 1 — business-read fixture: a gate that does `git show ...:refinement.md`
# and diffs `## Scope` to drive an exit-2 lifecycle decision. NOT allowlisted.
# ---------------------------------------------------------------------------
biz="$tmpdir/case1"
mkdir -p "$biz"
cat >"$biz/bad-business-gate.sh" <<'FIX'
#!/usr/bin/env bash
# A new lifecycle gate that reads the DERIVED refinement.md body.
set -euo pipefail
container="$1"
rel="$container/refinement.md"
before="$(git show "HEAD~1:$rel")"
after="$(git show "HEAD:$rel")"
if grep -A20 '## Scope' <<<"$before" | diff - <(grep -A20 '## Scope' <<<"$after"); then
  echo "scope changed" >&2
  exit 2
fi
FIX
err1="$tmpdir/err1"
rc1=$(run_scan "$biz" "$err1")
assert_exit "business-read fixture fails" 2 "$rc1"
assert_stderr_contains "business-read marker emitted" "POLARIS_DERIVED_MD_BUSINESS_READ" "$err1"

# ---------------------------------------------------------------------------
# Case 2 — idempotency-read fixture: allowlisted render-refinement-md.sh basename.
# ---------------------------------------------------------------------------
idem="$tmpdir/case2"
mkdir -p "$idem"
cat >"$idem/render-refinement-md.sh" <<'FIX'
#!/usr/bin/env bash
# Renders refinement.json -> refinement.md; --check compares without writing.
set -euo pipefail
out="$(dirname "$1")/refinement.md"
if [[ "${2:-}" == "--check" ]]; then
  diff "$out" /dev/stdin || echo "POLARIS_REFINEMENT_MD_HAND_EDIT_DETECTED" >&2
fi
FIX
err2="$tmpdir/err2"
rc2=$(run_scan "$idem" "$err2")
assert_exit "idempotency-read fixture passes" 0 "$rc2"

# ---------------------------------------------------------------------------
# Case 3 — parity-read fixture: allowlisted validate-refinement-artifact-parity.sh
# basename, reads refinement.md to compare AC ids against json (AC-NEG3).
# ---------------------------------------------------------------------------
par="$tmpdir/case3"
mkdir -p "$par"
cat >"$par/validate-refinement-artifact-parity.sh" <<'FIX'
#!/usr/bin/env bash
set -euo pipefail
ref_md="$1/refinement.md"
cat "$ref_md" | grep -oE 'AC[0-9]+' >/dev/null
echo "AC ids missing from refinement.md: parity check"
FIX
err3="$tmpdir/err3"
rc3=$(run_scan "$par" "$err3")
assert_exit "parity-read fixture passes (AC-NEG3)" 0 "$rc3"

# ---------------------------------------------------------------------------
# Case 4 — existence-only fixture: probes existence, never reads body. PASS even
# though the basename is not allowlisted.
# ---------------------------------------------------------------------------
exi="$tmpdir/case4"
mkdir -p "$exi"
cat >"$exi/some-existence-probe.sh" <<'FIX'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f "$1/refinement.md" ]]; then
  echo "refinement.md present"
fi
FIX
err4="$tmpdir/err4"
rc4=$(run_scan "$exi" "$err4")
assert_exit "existence-only fixture passes" 0 "$rc4"

# ---------------------------------------------------------------------------
# Case 5 — live scripts/ scan must PASS (no false positives on real readers,
# selftests excluded, transitional locked-scope guard allowlisted).
# ---------------------------------------------------------------------------
err5="$tmpdir/err5"
set +e
bash "$LINT" --scan-dir "$ROOT/scripts" >/dev/null 2>"$err5"
rc5=$?
set -e
assert_exit "live scripts/ scan passes" 0 "$rc5"

echo "---"
echo "lint-no-business-gate-reads-derived-md selftest: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
