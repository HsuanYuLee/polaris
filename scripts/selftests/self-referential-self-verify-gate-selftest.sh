#!/usr/bin/env bash
# Purpose: DP-419 T3 hermetic selftest for the D1 self-referential-delivery self-verify
#          wiring in both delivery gates — .claude/hooks/pre-push-quality-gate.sh and
#          scripts/check-framework-pr-gate.sh. Exercises each gate's hidden
#          `--selfref-self-verify` test seam with injected fake classifier / corpus runner
#          (POLARIS_DETECT_SELFREF_BIN / POLARIS_AGGREGATE_SELFTESTS_BIN, *_BIN seams — not
#          *_BYPASS) and asserts the decision contract: self-referential + current corpus
#          green => proceed (0); self-referential + corpus red => fail-closed (AC-NF1 /
#          AC-NEG2); missing input => fail-closed (AC-NF1); classifier undecidable =>
#          fail-closed (AC-NF1); not self-referential => normal path (10, AC-NEG3). Plus a
#          static assertion that neither gate adds a POLARIS_*_BYPASS env and that the
#          pre-existing key gate calls remain (AC-NEG1).
# Inputs:  none (builds fake classifier/corpus scripts under mktemp and drives the two real
#          gate scripts via the --selfref-self-verify subcommand; no git push, no corpus).
# Outputs: stdout PASS/FAIL lines; exit 0 all-pass, exit 1 any failure; exit 2 (missing jq).
# Side effects: tmpdir only (removed on EXIT). No live workspace mutation, no push.
#
# Return-code contract (the ONLY hard-block is a CONFIRMED self-ref change without a green
# corpus; an undeterminable self-ref scope falls through to the normal gate chain rather
# than blocking every push):
#   0  proceed | 1 hard-block (fail-closed) | 10 carve-out N/A -> normal gate chain.
# Coverage map (each asserted against BOTH gates):
#   selfref-green            — self-ref + fake corpus green        => exit 0.
#   selfref-red              — self-ref + fake corpus red          => exit 1 (AC-NF1/NEG2).
#   selfref-corpus-unavail   — self-ref + missing corpus binary    => exit 1 (AC-NF1).
#   missing-input            — no --changed-file                   => exit 10 (fall-through;
#                              non-zero-via-carve-out is NOT how a push proceeds — AC-NF1).
#   classifier-undecid       — fake classifier exit 2              => exit 10 (fall-through).
#   non-selfref              — fake classifier self_ref=false      => exit 10 (AC-NEG3).
#   static-no-bypass         — neither gate declares a POLARIS_*_BYPASS env (AC-NEG1) and
#                              the pre-existing key gate calls are still present.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREPUSH="$ROOT/.claude/hooks/pre-push-quality-gate.sh"
FWGATE="$ROOT/scripts/check-framework-pr-gate.sh"

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:jq (selftest requires jq; run 'mise install')" >&2
  exit 2
fi

for g in "$PREPUSH" "$FWGATE"; do
  [[ -f "$g" ]] || { echo "POLARIS_SELFTEST_MISSING_TARGET:$g" >&2; exit 2; }
done

FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

mkdir -p "$FIXTURE/bin"
ERRF="$FIXTURE/err"

# Fake classifier: self_referential=true. Drains stdin so the producer never hits SIGPIPE.
cat >"$FIXTURE/bin/classifier-true.sh" <<'SH'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '{"self_referential": true, "matched": ["scripts/check-framework-pr-gate.sh"]}\n'
SH
# Fake classifier: self_referential=false (non-delivery-gate change).
cat >"$FIXTURE/bin/classifier-false.sh" <<'SH'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '{"self_referential": false, "matched": []}\n'
SH
# Fake classifier: undecidable (cannot classify) -> exit 2 like the real classifier's
# fail-closed contract.
cat >"$FIXTURE/bin/classifier-undecidable.sh" <<'SH'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
echo "POLARIS_SELF_REFERENTIAL_MANIFEST_MISSING:fixture" >&2
exit 2
SH
# Fake corpus runner: green / red.
cat >"$FIXTURE/bin/corpus-green.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$FIXTURE/bin/corpus-red.sh" <<'SH'
#!/usr/bin/env bash
echo "POLARIS_AGGREGATE_SELFTEST_RED" >&2
exit 1
SH
chmod +x "$FIXTURE"/bin/*.sh

CLS_TRUE="$FIXTURE/bin/classifier-true.sh"
CLS_FALSE="$FIXTURE/bin/classifier-false.sh"
CLS_UNDECID="$FIXTURE/bin/classifier-undecidable.sh"
COR_GREEN="$FIXTURE/bin/corpus-green.sh"
COR_RED="$FIXTURE/bin/corpus-red.sh"
COR_MISSING="$FIXTURE/bin/does-not-exist.sh"  # deliberately never created

# run_case <gate> <classifier_bin> <corpus_bin> [extra args...] ; sets RC/ERR. The
# subcommand's verdict is its exit code (RC); its stdout is irrelevant, so it is dropped.
run_case() {
  local gate="$1" cls="$2" cor="$3"; shift 3
  set +e
  POLARIS_DETECT_SELFREF_BIN="$cls" POLARIS_AGGREGATE_SELFTESTS_BIN="$cor" \
    bash "$gate" --selfref-self-verify --repo-root "$FIXTURE" "$@" >/dev/null 2>"$ERRF"
  RC=$?
  set -e
  ERR="$(cat "$ERRF" 2>/dev/null || true)"
}

gate_label() {
  case "$1" in
    "$PREPUSH") echo "pre-push" ;;
    "$FWGATE")  echo "check-framework" ;;
    *)          echo "$1" ;;
  esac
}

for GATE in "$PREPUSH" "$FWGATE"; do
  LBL="$(gate_label "$GATE")"

  # --- selfref + green corpus => exit 0 ------------------------------------
  run_case "$GATE" "$CLS_TRUE" "$COR_GREEN" --changed-file scripts/check-framework-pr-gate.sh
  if [[ "$RC" -eq 0 ]]; then
    pass "$LBL selfref-green: self-referential + current corpus green => exit 0"
  else
    fail "$LBL selfref-green: expected 0 (rc=$RC err=$ERR)"
  fi

  # --- selfref + red corpus => hard-block (AC-NF1 / AC-NEG2) ---------------
  # The ONLY hard-block is a CONFIRMED self-ref change whose current corpus is not green.
  run_case "$GATE" "$CLS_TRUE" "$COR_RED" --changed-file scripts/check-framework-pr-gate.sh
  if [[ "$RC" -eq 1 ]]; then
    pass "$LBL selfref-red: self-referential + corpus red => hard-block (rc=1)"
  else
    fail "$LBL selfref-red: expected hard-block rc=1, got rc=$RC (err=$ERR)"
  fi

  # --- selfref + corpus binary unavailable => hard-block (AC-NF1) ----------
  # Confirmed self-ref but the corpus green-light cannot be obtained -> fail-closed.
  run_case "$GATE" "$CLS_TRUE" "$COR_MISSING" --changed-file scripts/check-framework-pr-gate.sh
  if [[ "$RC" -eq 1 ]]; then
    pass "$LBL selfref-corpus-unavailable: self-ref + missing corpus binary => hard-block (rc=1)"
  else
    fail "$LBL selfref-corpus-unavailable: expected hard-block rc=1, got rc=$RC (err=$ERR)"
  fi

  # --- missing input => carve-out N/A, fall-through sentinel 10 (AC-NF1) ---
  # Underivable changed set => self-ref scope undeterminable => NOT a hard block; caller
  # falls through to the normal (stricter) gate chain. Non-zero still satisfies AC-NF1
  # ("does not proceed via the carve-out"), but it must be 10, not a hard block.
  run_case "$GATE" "$CLS_TRUE" "$COR_GREEN"
  if [[ "$RC" -eq 10 ]]; then
    pass "$LBL missing-input: no --changed-file => not-applicable sentinel 10 (fall-through)"
  else
    fail "$LBL missing-input: expected 10, got rc=$RC (err=$ERR)"
  fi

  # --- classifier undecidable => carve-out N/A, fall-through 10 (AC-NF1) ---
  # Classifier absent / exit != 0 => self-ref scope undeterminable => fall through, NOT a
  # hard block (a fixture / old tree / non-framework repo without the classifier).
  run_case "$GATE" "$CLS_UNDECID" "$COR_GREEN" --changed-file scripts/check-framework-pr-gate.sh
  if [[ "$RC" -eq 10 ]]; then
    pass "$LBL classifier-undecid: classifier exit 2 => not-applicable sentinel 10 (fall-through)"
  else
    fail "$LBL classifier-undecid: expected 10, got rc=$RC (err=$ERR)"
  fi

  # --- not self-referential => normal path (10) (AC-NEG3) -----------------
  run_case "$GATE" "$CLS_FALSE" "$COR_GREEN" --changed-file .claude/skills/references/foo.md
  if [[ "$RC" -eq 10 ]]; then
    pass "$LBL non-selfref: self_referential=false => normal-path sentinel 10"
  else
    fail "$LBL non-selfref: expected 10, got rc=$RC (err=$ERR)"
  fi
done

# --- static: no new POLARIS_*_BYPASS env; key gate calls intact (AC-NEG1) ---
if grep -Eq 'POLARIS_[A-Z_]*BYPASS' "$PREPUSH" "$FWGATE"; then
  fail "static-no-bypass: a POLARIS_*_BYPASS env token appears in a wired gate (AC-NEG1)"
else
  pass "static-no-bypass: neither gate declares a POLARIS_*_BYPASS env (AC-NEG1)"
fi

if grep -q 'gate-changeset' "$PREPUSH" && grep -q 'selftest-affected-runner' "$PREPUSH"; then
  pass "static-key-calls: pre-push retains gate-changeset + affected-selftest runner"
else
  fail "static-key-calls: pre-push lost a pre-existing key gate call"
fi

if grep -q 'run_gate "W14' "$FWGATE"; then
  pass "static-key-calls: check-framework retains run_gate \"W14\""
else
  fail "static-key-calls: check-framework lost run_gate \"W14\""
fi

# --- static: --list-stages introspection still coexists with the subcommand ----
if bash "$FWGATE" --list-stages | grep -q '^W14 '; then
  pass "list-stages-coexist: --list-stages still emits W14 (subcommand did not break it)"
else
  fail "list-stages-coexist: --list-stages introspection broken"
fi

if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "${FAILS} FAIL(s)"
exit 1
