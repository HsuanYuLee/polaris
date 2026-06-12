#!/usr/bin/env bash
# closeout-chain-archive-selftest.sh
#
# Exercises the closeout chain wiring and the DP-230-T14 tool-call governance
# extensions:
#   - validate-script-dependencies.sh flags direct `rg` calls inside selftests
#     (and migration to `polaris_with_runtime_tools` lets the validator pass).
#   - validate-script-dependencies.sh also flags alias/function wrappers around
#     managed tools (AC34 attack defence).
#   - mark-spec-implemented.sh handles bare DP container keys (AC35) including
#     ABANDONED sibling carve-out (AC-NEG13).
#
# Run:
#   bash scripts/selftests/closeout-chain-archive-selftest.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"

TMPDIR_OUT="$(mktemp -d -t closeout-chain-archive-selftest.XXXXXX)"
trap 'rm -rf "$TMPDIR_OUT"' EXIT

# -----------------------------------------------------------------------------
# Layer 1 — Existing wiring sanity checks (use polaris_with_runtime_tools so the
# rg invocation is routed through mise, not a direct PATH-resolved binary).
# -----------------------------------------------------------------------------
polaris_with_runtime_tools rg -n 'archive-terminal-parent|mark-spec-implemented.sh' \
  "$ROOT/scripts/framework-release-closeout.sh" \
  >"$TMPDIR_OUT/framework-closeout-archive.out"
polaris_with_runtime_tools rg -n 'terminal complete|auto-archive|archive-spec.sh' \
  "$ROOT/.claude/skills/references/auto-pass-execution-flow.md" \
  "$ROOT/.claude/skills/auto-pass/SKILL.md" \
  >"$TMPDIR_OUT/auto-pass-closeout-docs.out"
polaris_with_runtime_tools rg -n 'closeout-chain-archive-not-deterministic|closeout-chain-auto-archive' \
  "$ROOT/.claude/rules/mechanism-registry.md" \
  >"$TMPDIR_OUT/closeout-mechanism.out"
MARK_SPEC_IMPLEMENTED_SELFTEST=1 bash "$ROOT/scripts/mark-spec-implemented.sh" \
  >"$TMPDIR_OUT/dp207-mark-spec-auto-archive.out"

# -----------------------------------------------------------------------------
# Layer 2 — D34 scanner contract: validate-script-dependencies.sh must flag
# direct `rg` calls inside selftest files (broken fixture), and PASS once they
# are migrated to polaris_with_runtime_tools (fixed fixture).
# -----------------------------------------------------------------------------
FIXTURE_DIR="$TMPDIR_OUT/d34-fixture"
mkdir -p "$FIXTURE_DIR/scripts/selftests" \
         "$FIXTURE_DIR/scripts/lib"
# minimal lib copy so validator can resolve dependencies if needed
cp "$ROOT/scripts/validate-script-dependencies.sh" "$FIXTURE_DIR/scripts/validate-script-dependencies.sh"
# Required by validator: inventory + disposition baseline (empty TSV is fine).
printf 'path\tline\ttool\towner\tinstall_authority\truntime_profile\tgoes_to_mise\n' \
  >"$FIXTURE_DIR/scripts/tool-direct-call-inventory.txt"
printf 'path\tline\ttool\tdisposition\towner_decision\tremediation_task\texpiry\tscope\n' \
  >"$FIXTURE_DIR/scripts/tool-direct-call-inventory-disposition.txt"

# Broken fixture: selftest with a bare rg call
cat >"$FIXTURE_DIR/scripts/selftests/broken-direct-rg-selftest.sh" <<'BROKEN'
#!/usr/bin/env bash
set -euo pipefail
rg -n 'pattern' /tmp/file.out
BROKEN

# Fixed fixture: selftest routes rg through polaris_with_runtime_tools
cat >"$FIXTURE_DIR/scripts/selftests/fixed-resolver-selftest.sh" <<'FIXED'
#!/usr/bin/env bash
set -euo pipefail
polaris_with_runtime_tools rg -n 'pattern' /tmp/file.out
FIXED

# Wrapper fixture: function wrapping rg (AC34 attack — should still be flagged)
cat >"$FIXTURE_DIR/scripts/selftests/wrapper-function-rg-selftest.sh" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
ripgrep_wrapper() {
  rg -n "$@"
}
ripgrep_wrapper 'pattern' /tmp/file.out
WRAP

# Run validator in diff mode against the broken fixture: must fail.
broken_rc=0
bash "$FIXTURE_DIR/scripts/validate-script-dependencies.sh" --mode diff \
  --path scripts/selftests/broken-direct-rg-selftest.sh \
  >"$TMPDIR_OUT/d34-broken.out" 2>"$TMPDIR_OUT/d34-broken.err" \
  || broken_rc=$?
if [ "$broken_rc" -eq 0 ]; then
  echo "[selftest] FAIL: D34 broken fixture (direct rg) did not fail-stop" >&2
  exit 1
fi
if ! grep -q 'POLARIS_TOOL_DIRECT_CALL' "$TMPDIR_OUT/d34-broken.err"; then
  echo "[selftest] FAIL: D34 broken fixture did not emit POLARIS_TOOL_DIRECT_CALL" >&2
  cat "$TMPDIR_OUT/d34-broken.err" >&2
  exit 1
fi

# Fixed fixture: must pass.
fixed_rc=0
bash "$FIXTURE_DIR/scripts/validate-script-dependencies.sh" --mode diff \
  --path scripts/selftests/fixed-resolver-selftest.sh \
  >"$TMPDIR_OUT/d34-fixed.out" 2>"$TMPDIR_OUT/d34-fixed.err" \
  || fixed_rc=$?
if [ "$fixed_rc" -ne 0 ]; then
  echo "[selftest] FAIL: D34 fixed fixture (polaris_with_runtime_tools rg) did not pass" >&2
  cat "$TMPDIR_OUT/d34-fixed.err" >&2
  exit 1
fi

# Wrapper fixture: alias/function wrapper around rg must still be flagged.
wrap_rc=0
bash "$FIXTURE_DIR/scripts/validate-script-dependencies.sh" --mode diff \
  --path scripts/selftests/wrapper-function-rg-selftest.sh \
  >"$TMPDIR_OUT/d34-wrap.out" 2>"$TMPDIR_OUT/d34-wrap.err" \
  || wrap_rc=$?
if [ "$wrap_rc" -eq 0 ]; then
  echo "[selftest] FAIL: D34 wrapper fixture did not fail-stop (function wrapping rg should be detected)" >&2
  exit 1
fi
if ! grep -q 'POLARIS_TOOL_DIRECT_CALL.*tool=rg' "$TMPDIR_OUT/d34-wrap.err"; then
  echo "[selftest] FAIL: D34 wrapper fixture did not flag rg inside function body" >&2
  cat "$TMPDIR_OUT/d34-wrap.err" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Layer 3 — D35 bare-DP closeout + AC-NEG13 ABANDONED sibling carve-out
# (delegated to mark-spec-implemented-bare-key-selftest.sh).
# -----------------------------------------------------------------------------
bash "$ROOT/scripts/selftests/mark-spec-implemented-bare-key-selftest.sh"

# -----------------------------------------------------------------------------
# Layer 4 — DP-311 T2 ledger finalize wiring: mark-spec-implemented.sh 的
# parent / bare-DP 分支必須在翻 IMPLEMENTED 之前接上 auto-pass-finalize-ledger.sh，
# 且 execution-flow 文件與 mechanism registry 都登錄此 finalize 步驟。
# (hermetic 行為覆蓋委派給 auto-pass-finalize-ledger-selftest.sh。)
# -----------------------------------------------------------------------------
polaris_with_runtime_tools rg -n 'finalize_auto_pass_ledger_before_flip|auto-pass-finalize-ledger' \
  "$ROOT/scripts/mark-spec-implemented.sh" \
  >"$TMPDIR_OUT/ledger-finalize-callsite.out"
polaris_with_runtime_tools rg -n 'auto-pass-finalize-ledger' \
  "$ROOT/.claude/skills/references/auto-pass-execution-flow.md" \
  "$ROOT/.claude/rules/mechanism-registry.md" \
  >"$TMPDIR_OUT/ledger-finalize-docs.out"

echo "PASS: closeout chain archive selftest"
