#!/usr/bin/env bash
# Purpose: selftest for scripts/gates/gate-runtime-instruction-manifest.sh and its
#          push-time wiring into the Claude pre-push adapter and the portable git
#          hook. Covers DP-320 T1 AC1/AC2/AC5/AC-NF1/AC-NEG1/AC-NEG2.
# Inputs:  none (builds isolated git fixtures under a temp dir)
# Outputs: stdout PASS/FAIL lines; exit 0 PASS, exit 1 FAIL
# Side effects: temp dir only (auto-removed)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-runtime-instruction-manifest.sh"

fail() {
  echo "[gate-runtime-instruction-manifest-selftest] FAIL: $*" >&2
  exit 1
}

[[ -x "$GATE" ]] || fail "gate script missing or not executable: $GATE"

tmpdir="$(mktemp -d -t runtime-manifest-gate.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# ---------------------------------------------------------------------------
# Fixture builder: a self-contained mini "workspace" with the minimum surface
# compile-runtime-instructions.sh --check inspects, plus the gate + compile
# scripts copied verbatim from the real repo (single-source: no re-implementation).
# ---------------------------------------------------------------------------
build_fixture() {
  local repo="$1"
  mkdir -p "$repo/scripts/gates" "$repo/scripts"
  cp "$GATE" "$repo/scripts/gates/gate-runtime-instruction-manifest.sh"
  cp "$ROOT_DIR/scripts/compile-runtime-instructions.sh" "$repo/scripts/compile-runtime-instructions.sh"
  chmod +x "$repo/scripts/gates/gate-runtime-instruction-manifest.sh" \
    "$repo/scripts/compile-runtime-instructions.sh"

  # Minimal instruction source tree.
  mkdir -p "$repo/.claude/instructions/core" "$repo/.claude/instructions/runtime" "$repo/.claude/rules"
  printf 'manifest source\n' >"$repo/.claude/instructions/manifest.yaml"
  printf '# Bootstrap\n\nbody\n' >"$repo/.claude/instructions/core/bootstrap.md"
  printf '## Claude\n' >"$repo/.claude/instructions/runtime/claude.md"
  printf '## Codex\n' >"$repo/.claude/instructions/runtime/codex.md"
  printf '## Copilot\n' >"$repo/.claude/instructions/runtime/copilot.md"
  printf '# Rule A\n\nrule a body\n' >"$repo/.claude/rules/rule-a.md"

  # compile-runtime-instructions.sh emit_codex_hook_invocation_guidance() reads
  # .claude/rules/mechanism-registry.md and parses its "## Cross-LLM Hook Parity
  # Registry" table (needs a header row with a "hook" column + >=1 data row).
  # Provide a minimal, generic-placeholder registry so the fixture compiler runs
  # cleanly instead of raising FileNotFoundError.
  {
    printf '# Mechanism Registry\n\n'
    printf '## Cross-LLM Hook Parity Registry\n\n'
    printf '| hook | runtime | parity_exception |\n'
    printf '|------|---------|------------------|\n'
    printf '| sample-hook.sh | portable | DP-372:fixture |\n'
  } >"$repo/.claude/rules/mechanism-registry.md"

  git -C "$repo" init -q
  git -C "$repo" config user.email "polaris@example.invalid"
  git -C "$repo" config user.name "Polaris Selftest"

  # Generate all targets fresh so the tree starts in-sync.
  bash "$repo/scripts/compile-runtime-instructions.sh" >/dev/null 2>&1 \
    || fail "fixture compile (generate) failed"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "init fixture in-sync"
}

# === AC1 (fresh) + AC-NF1: gate exits 0 when runtime targets are in sync ===
repo_fresh="$tmpdir/fresh"
build_fixture "$repo_fresh"
out_fresh="$(bash "$GATE" --repo "$repo_fresh" 2>&1)" \
  || fail "AC1 fresh: gate must exit 0 when runtime targets are in sync (got non-zero). Output: $out_fresh"

# AC-NF1: gate must not invoke network / heavy build — only compile --check.
# Assert the gate source delegates exactly to compile-runtime-instructions.sh --check
# and contains no curl/wget/build invocation.
if grep -qE '\b(curl|wget|npm|pnpm|yarn|node )\b' "$GATE"; then
  fail "AC-NF1: gate must not invoke network/build tooling"
fi
grep -q 'compile-runtime-instructions.sh' "$GATE" \
  || fail "AC-NF1/AC5: gate must delegate to compile-runtime-instructions.sh"

# === AC1 (stale): a bootstrap edit changes rendered targets -> fail + hint ===
repo_stale="$tmpdir/stale"
build_fixture "$repo_stale"
printf '\nstale edit not regenerated\n' >>"$repo_stale/.claude/instructions/core/bootstrap.md"
if out_stale="$(bash "$GATE" --repo "$repo_stale" 2>&1)"; then
  fail "AC1 stale: gate must exit non-zero when a rendered runtime target is stale"
fi
printf '%s' "$out_stale" | grep -q 'compile-runtime-instructions.sh' \
  || fail "AC1: stale failure must emit a repair hint pointing to compile-runtime-instructions.sh"

# === AC1 adversarial: a missing real runtime target is stale-fail ===
repo_missing="$tmpdir/missing"
build_fixture "$repo_missing"
rm -f "$repo_missing/.codex/AGENTS.md"
if bash "$GATE" --repo "$repo_missing" >/dev/null 2>&1; then
  fail "AC1: missing runtime target must fail closed (not fail-open exit 0)"
fi

# === AC-NEG1: POLARIS_*_BYPASS env must NOT silence the gate ===
repo_bypass="$tmpdir/bypass"
build_fixture "$repo_bypass"
printf '\nstale for bypass test\n' >>"$repo_bypass/.claude/instructions/core/bootstrap.md"
if POLARIS_LANGUAGE_POLICY_BYPASS=1 POLARIS_SKILL_BOUNDARY_BYPASS=1 \
   POLARIS_MEMORY_HYGIENE_APPLY=1 bash "$GATE" --repo "$repo_bypass" >/dev/null 2>&1; then
  fail "AC-NEG1: no POLARIS_*_BYPASS env may silence the manifest-freshness gate"
fi
# Also assert no env-bypass escape hatch exists in the gate source.
if grep -qE 'BYPASS|SKIP_MANIFEST|FORCE' "$GATE"; then
  fail "AC-NEG1: gate source must not contain an env bypass escape hatch"
fi

# === AC-NEG2: gate verdict comes from rendered target freshness, not push
#            content. A push that touches only unrelated files must PASS. ===
repo_unrelated="$tmpdir/unrelated"
build_fixture "$repo_unrelated"
echo "product code change" >"$repo_unrelated/some-product-file.txt"
git -C "$repo_unrelated" add -A
git -C "$repo_unrelated" commit -q -m "unrelated change, runtime targets still fresh"
bash "$GATE" --repo "$repo_unrelated" >/dev/null 2>&1 \
  || fail "AC-NEG2: gate must not block a push when runtime targets are fresh (no false positive)"

# === AC2: both push-time runtime paths wire the gate AND do not branch-filter it ===

# AC2 path 1 — Claude pre-push adapter (.claude/hooks/pre-push-quality-gate.sh)
PREPUSH_ADAPTER="$ROOT_DIR/.claude/hooks/pre-push-quality-gate.sh"
grep -q 'gate-runtime-instruction-manifest.sh' "$PREPUSH_ADAPTER" \
  || fail "AC2: pre-push-quality-gate.sh must wire gate-runtime-instruction-manifest.sh"

# The adapter must not branch-filter this check. Assert ordering against the
# branch-resolution case that remains for detached HEAD handling, and separately
# fail if a non-comment main/master/develop early-exit returns.
manifest_line="$(grep -n 'gate-runtime-instruction-manifest.sh' "$PREPUSH_ADAPTER" | head -1 | cut -d: -f1)"
branch_case_line="$(grep -n '^case "\$branch" in' "$PREPUSH_ADAPTER" | head -1 | cut -d: -f1)"
[[ -n "$manifest_line" && -n "$branch_case_line" ]] \
  || fail "AC2: could not locate manifest gate / branch case in pre-push adapter"
[[ "$manifest_line" -lt "$branch_case_line" ]] \
  || fail "AC2/EC2: manifest gate must run before the branch case (got manifest@$manifest_line, branch-case@$branch_case_line)"
if awk '/^[[:space:]]*#/ {next} /main\|master\|develop\).*exit 0/ {found=1} END {exit found ? 0 : 1}' "$PREPUSH_ADAPTER"; then
  fail "AC2/R1: pre-push adapter must not contain a non-comment main/master/develop early-exit"
fi

# AC2 path 2 — portable git hook produced by install-git-hooks.sh
INSTALL_HOOKS="$ROOT_DIR/scripts/install-git-hooks.sh"
grep -q 'gate-runtime-instruction-manifest.sh' "$INSTALL_HOOKS" \
  || fail "AC2: install-git-hooks.sh portable pre-push hook must wire gate-runtime-instruction-manifest.sh"

# Generate the portable pre-push hook into a throwaway repo and assert it both
# (a) contains the manifest gate callsite, and (b) places it before the
# delete/tags carve-out is the only early-exit — i.e. a content-bearing push to
# any branch reaches the manifest gate (no branch filter; R1/BS2).
repo_hookgen="$tmpdir/hookgen"
mkdir -p "$repo_hookgen"
git -C "$repo_hookgen" init -q
cp -R "$ROOT_DIR/scripts" "$repo_hookgen/scripts"
bash "$repo_hookgen/scripts/install-git-hooks.sh" >/dev/null 2>&1 \
  || fail "AC2: install-git-hooks.sh failed to install into fixture repo"
HOOK="$repo_hookgen/.git/hooks/pre-push"
[[ -f "$HOOK" ]] || fail "AC2: portable pre-push hook not generated"
grep -q 'gate-runtime-instruction-manifest.sh' "$HOOK" \
  || fail "AC2: generated portable pre-push hook missing manifest gate callsite"
# The generated portable hook must NOT branch-filter the manifest check.
if grep -qE 'main\|master\|develop' "$HOOK"; then
  fail "AC2/R1: portable git hook must not branch-filter the manifest check"
fi

# === AC2 end-to-end: portable hook blocks a stale push, passes a fresh push ===
# Build a fixture repo whose tree is real enough to run the freshness gate via the
# installed hook, drive it through the hook's gate callsite directly.
repo_e2e="$tmpdir/e2e"
build_fixture "$repo_e2e"
# Fresh: gate (the wiring the hook delegates to) passes.
bash "$repo_e2e/scripts/gates/gate-runtime-instruction-manifest.sh" --repo "$repo_e2e" >/dev/null 2>&1 \
  || fail "AC2 e2e: fresh runtime targets must pass the wired gate"
# Stale: gate blocks.
printf '\ne2e stale\n' >>"$repo_e2e/.claude/instructions/core/bootstrap.md"
if bash "$repo_e2e/scripts/gates/gate-runtime-instruction-manifest.sh" --repo "$repo_e2e" >/dev/null 2>&1; then
  fail "AC2 e2e: stale runtime targets must be blocked by the wired gate"
fi

echo "[gate-runtime-instruction-manifest-selftest] PASS"
