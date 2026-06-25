#!/usr/bin/env bash
# Purpose: selftest for DP-356 T1 — scripts/run-evidence-command.sh executes an
#          evidence-bearing command on a proxy-immune path so the verification
#          evidence (stdout + exit code) comes from the REAL binary, not from a
#          command-rewrite proxy's token-optimized summary.
# Inputs:  none (builds synthetic fixtures + fake-proxy shims in a tmpdir).
# Outputs: PASS line on success; non-zero exit + FAIL line on contract regression.
#
# Covers (DP-356):
#   AC1     : evidence-immune path runs `rg --pcre2` / `! rg <pattern>` and gets
#             REAL ripgrep results. For a fixture where a command-rewrite proxy
#             would exit 0 (false PASS), the immune path exits non-zero correctly.
#   AC2     : a patch/diff produced on the immune path is a valid unified diff
#             (`git apply` succeeds); two actually-different files are NOT reported
#             identical.
#   AC-NF1  : proxy-agnostic — core protection (script subprocess + absolute
#             binary / `command` bypassing a function wrapper) is not bound to any
#             specific proxy; the kill-switch env is an extensible allowlist
#             (RTK_DISABLED first). The mechanism stays correct even when the
#             simulated proxy's rewrite rule changes (no hardcoded proxy rule
#             shape).
#   AC-NF1-attack (adversarial pass): a SECOND simulated proxy with a DIFFERENT
#             rewrite rule (e.g. mapping the binary to `false`) is still defeated
#             by the immune path — proving the protection is not tied to one
#             proxy's specific rule string.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/scripts/run-evidence-command.sh"

[[ -f "$HELPER" ]] || { echo "FAIL: missing script: $HELPER" >&2; exit 1; }

TMP="$(mktemp -d -t dp356-evidence-command.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Fixture: a "fake proxy" shim directory placed at the FRONT of PATH and a
# matching shell function wrapper. Both rewrite the evidence binary into a
# token-optimized fake that returns the WRONG answer (false PASS / identical).
# This stands in for rtk's PreToolUse rewrite. The immune helper must run the
# command in a subprocess that resolves the REAL binary by absolute path and
# sets the kill-switch env, so neither the shim nor the function wrapper wins.
# ---------------------------------------------------------------------------

REAL_RG="$(command -v rg || true)"
[[ -n "$REAL_RG" ]] || fail "real ripgrep (rg) not found on PATH — cannot run AC1"

SHIM_DIR="$TMP/fake-proxy-bin"
mkdir -p "$SHIM_DIR"

# Fake `rg`: ALWAYS exits 0 and prints a token-optimized "no matches" summary.
# If a `! rg <forbidden>` Verify Command trusted this, the error-exit would flip
# to exit 0 = false PASS.
cat >"$SHIM_DIR/rg" <<'SHIM'
#!/usr/bin/env bash
# fake proxy rewrite of rg: pretends every search succeeds with no real output
echo "[proxy] rg rewritten: 0 matches (token-optimized)"
exit 0
SHIM
chmod +x "$SHIM_DIR/rg"

# Fake `git`: rewrites `git diff --no-index` into "Files are identical".
cat >"$SHIM_DIR/git" <<'SHIM'
#!/usr/bin/env bash
# fake proxy rewrite of git diff: always claims identical
echo "[proxy] Files are identical (token-optimized)"
exit 0
SHIM
chmod +x "$SHIM_DIR/git"

# ===========================================================================
# AC1 — immune path runs REAL rg; `! rg <forbidden>` does NOT false-PASS.
# ===========================================================================
TARGET="$TMP/ac1-target.txt"
printf 'allowed line\nFORBIDDEN_TOKEN here\nanother line\n' >"$TARGET"

# Sanity: under the fake proxy (shim at front of PATH), a naive `! rg` would
# false-PASS (proxy rg exits 0 → `! 0` = 1... but proxy makes rg exit 0 so the
# forbidden token is "not found"). Demonstrate the breakage the immune path
# must avoid: run rg via the shim and confirm it lies.
shim_rg_out="$(PATH="$SHIM_DIR:$PATH" rg --pcre2 'FORBIDDEN_TOKEN' "$TARGET" || true)"
case "$shim_rg_out" in
  *"[proxy]"*) : ;;  # confirmed the shim is intercepting (fixture works)
  *) fail "AC1 fixture broken: fake proxy rg shim did not intercept" ;;
esac

# Immune path: helper must resolve the REAL rg and actually FIND the forbidden
# token (exit 0 from rg => the forbidden token IS present). We invoke the helper
# with the poisoned PATH/function-wrapper environment; it must still hit real rg.
set +e
PATH="$SHIM_DIR:$PATH" \
  bash "$HELPER" -- rg --pcre2 'FORBIDDEN_TOKEN' "$TARGET" >"$TMP/ac1.out" 2>"$TMP/ac1.err"
ac1_rc=$?
set -e

grep -q 'FORBIDDEN_TOKEN' "$TMP/ac1.out" \
  || fail "AC1: immune path did not return REAL ripgrep match output (got: $(cat "$TMP/ac1.out"))"
[[ "$ac1_rc" -eq 0 ]] \
  || fail "AC1: real rg should exit 0 when match present (got rc=$ac1_rc)"
grep -q '\[proxy\]' "$TMP/ac1.out" \
  && fail "AC1: immune path output came from fake proxy shim, not real rg"

# Negative-assertion shape: `! rg <forbidden>` must FAIL (exit non-zero) because
# the forbidden token IS present. The helper exits with rg's real exit code, so
# `! helper rg ...` is non-zero. Prove the immune path does NOT false-PASS.
set +e
PATH="$SHIM_DIR:$PATH" bash "$HELPER" -- rg --pcre2 'FORBIDDEN_TOKEN' "$TARGET" >/dev/null 2>&1
neg_rc=$?
set -e
[[ "$neg_rc" -eq 0 ]] \
  || fail "AC1: immune rg should exit 0 (match found) so that ! rg correctly fails-closed"

# And the true-clean case: a token genuinely absent → real rg exits 1.
set +e
PATH="$SHIM_DIR:$PATH" bash "$HELPER" -- rg --pcre2 'TOKEN_NOT_PRESENT' "$TARGET" >/dev/null 2>&1
clean_rc=$?
set -e
[[ "$clean_rc" -ne 0 ]] \
  || fail "AC1: real rg must exit non-zero for an absent pattern (got rc=$clean_rc); proxy false-PASS leaked"

# ===========================================================================
# AC2 — immune diff produces a valid unified diff; two different files are not
# reported identical.
# ===========================================================================
FA="$TMP/ac2-a.txt"
FB="$TMP/ac2-b.txt"
printf 'line one\nline two\nline three\n' >"$FA"
printf 'line one\nline TWO changed\nline three\n' >"$FB"

# Immune git diff --no-index: real git reports a diff (exit 1 for differences).
set +e
PATH="$SHIM_DIR:$PATH" \
  bash "$HELPER" -- git diff --no-index "$FA" "$FB" >"$TMP/ac2.diff" 2>"$TMP/ac2.err"
diff_rc=$?
set -e

grep -q '\[proxy\]' "$TMP/ac2.diff" \
  && fail "AC2: diff output came from fake proxy shim, not real git"
grep -q 'identical' "$TMP/ac2.diff" \
  && fail "AC2: two different files were reported identical by the (poisoned) path"
grep -q '^@@' "$TMP/ac2.diff" \
  || fail "AC2: immune git diff did not produce a unified diff hunk header (got: $(cat "$TMP/ac2.diff"))"
[[ "$diff_rc" -ne 0 ]] \
  || fail "AC2: git diff --no-index should exit non-zero when files differ (got rc=$diff_rc)"

# The produced diff must be a VALID unified diff: git apply (check) succeeds
# against a copy of file A, transforming it toward file B.
WORK="$TMP/ac2-apply"
mkdir -p "$WORK"
git -C "$WORK" init -q
# Build a diff between two real tracked states so git apply can target file.txt.
cp "$FA" "$WORK/file.txt"
git -C "$WORK" add file.txt
git -C "$WORK" -c user.email=t@t -c user.name=t commit -qm base
cp "$FB" "$WORK/file.txt"
set +e
PATH="$SHIM_DIR:$PATH" bash "$HELPER" -- git -C "$WORK" diff -- file.txt >"$TMP/ac2-tracked.diff" 2>/dev/null
set -e
grep -q '^@@' "$TMP/ac2-tracked.diff" \
  || fail "AC2: tracked git diff produced no hunk via immune path"
# Reset working tree, then git apply the immune-produced diff must succeed.
# The apply check ALSO runs through the immune helper (under the poisoned PATH),
# so a passing check proves the REAL git applied a REAL unified diff — not the
# fake proxy rubber-stamping "identical".
git -C "$WORK" checkout -q -- file.txt
set +e
PATH="$SHIM_DIR:$PATH" bash "$HELPER" -- \
  git -C "$WORK" apply --check "$TMP/ac2-tracked.diff" >"$TMP/ac2-apply.out" 2>&1
apply_rc=$?
set -e
grep -q '\[proxy\]' "$TMP/ac2-apply.out" \
  && fail "AC2: git apply --check ran the fake proxy shim, not real git"
[[ "$apply_rc" -eq 0 ]] \
  || fail "AC2: immune-produced unified diff failed real git apply --check (rc=$apply_rc, out: $(cat "$TMP/ac2-apply.out"))"

# ===========================================================================
# AC-NF1 — proxy-agnostic: core protection not bound to one proxy. The
# kill-switch env is an extensible allowlist (RTK_DISABLED first). Even a SECOND
# simulated proxy with a DIFFERENT rewrite rule is defeated.
# ===========================================================================

# (a) Core protection survives a function-wrapper proxy (not just PATH shim):
#     define an `rg` shell function in this shell, export it, and confirm the
#     helper still hits the real binary (function wrappers must be bypassed via
#     `command` / absolute path).
ac_nf1_run() {
  # shellcheck disable=SC2317,SC2329
  rg() { echo "[func-proxy] rewritten rg"; exit 0; }
  export -f rg
  set +e
  PATH="$SHIM_DIR:$PATH" bash "$HELPER" -- rg --pcre2 'FORBIDDEN_TOKEN' "$TARGET" >"$TMP/nf1.out" 2>&1
  local rc=$?
  set -e
  echo "$rc"
}
nf1_rc="$(ac_nf1_run)"
grep -q 'FORBIDDEN_TOKEN' "$TMP/nf1.out" \
  || fail "AC-NF1: function-wrapper proxy not bypassed (got: $(cat "$TMP/nf1.out"))"
grep -q 'func-proxy' "$TMP/nf1.out" \
  && fail "AC-NF1: helper executed the function wrapper instead of the real binary"
[[ "$nf1_rc" -eq 0 ]] \
  || fail "AC-NF1: real rg should exit 0 for present token under function-wrapper proxy (rc=$nf1_rc)"

# (b) Extensible kill-switch allowlist: RTK_DISABLED must be the first entry and
#     the helper must export it (proxy-specific, but additive). Assert the helper
#     sets RTK_DISABLED=1 in the subprocess environment.
set +e
bash "$HELPER" -- bash -c 'printf "RTK_DISABLED=%s\n" "${RTK_DISABLED:-UNSET}"' >"$TMP/nf1-env.out" 2>&1
set -e
grep -q 'RTK_DISABLED=1' "$TMP/nf1-env.out" \
  || fail "AC-NF1: helper did not set the RTK_DISABLED=1 kill-switch (got: $(cat "$TMP/nf1-env.out"))"

# (c) Different-rule proxy: a shim that maps the binary to `false` (exit 1
#     always). The immune path must still get the REAL result, proving the
#     mechanism does not depend on one proxy's rewrite-rule shape.
ALT_SHIM="$TMP/alt-proxy-bin"
mkdir -p "$ALT_SHIM"
cat >"$ALT_SHIM/rg" <<'SHIM'
#!/usr/bin/env bash
# alternate proxy rule: always fail
exit 1
SHIM
chmod +x "$ALT_SHIM/rg"
set +e
PATH="$ALT_SHIM:$PATH" bash "$HELPER" -- rg --pcre2 'FORBIDDEN_TOKEN' "$TARGET" >"$TMP/nf1-alt.out" 2>&1
alt_rc=$?
set -e
grep -q 'FORBIDDEN_TOKEN' "$TMP/nf1-alt.out" \
  || fail "AC-NF1: alternate-rule proxy not defeated; helper bound to one proxy's rule (got: $(cat "$TMP/nf1-alt.out"))"
[[ "$alt_rc" -eq 0 ]] \
  || fail "AC-NF1: real rg should exit 0 (match) under alternate-rule proxy (rc=$alt_rc)"

# ===========================================================================
# Usage / contract guards.
# ===========================================================================
set +e
bash "$HELPER" >/dev/null 2>&1
usage_rc=$?
set -e
[[ "$usage_rc" -eq 2 ]] \
  || fail "usage: helper with no command should exit 2 (got rc=$usage_rc)"

echo "PASS: run-evidence-command-selftest (AC1 / AC2 / AC-NF1)"
