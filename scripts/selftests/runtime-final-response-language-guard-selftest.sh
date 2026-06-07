#!/usr/bin/env bash
# runtime-final-response-language-guard-selftest.sh
#
# Enforces AC39 from DP-230, corrected for the actual source-of-truth layering
# (DP-294 AC3):
#   - The Final Response Language Guard's SOURCE layer lives in the runtime
#     overlays .claude/instructions/runtime/{claude,codex,copilot}.md. Each must
#     carry the guard: hook/model does NOT intercept the final response, so the
#     agent must self-check workspace-config.yaml language before replying.
#   - The universal "## Final Response Language Guard" core section and the
#     per-runtime "### {Runtime} Runtime Caveat" are EMITTED BY THE COMPILER
#     (scripts/compile-runtime-instructions.sh), not authored in bootstrap.md.
#     They are therefore asserted at the COMPILED layer (the four generated
#     targets), below.
#   - bootstrap.md does NOT author this guard. Asserting it there was a
#     false FAIL — the guard is not part of bootstrap core (DP-294 AC3).
#
# The selftest greps deterministic phrases rather than full-text equality so
# the wording can evolve without breaking the contract.

set -euo pipefail

# DP-293 T1: honor POLARIS_GOVERNED_TEST_ROOT so the release lane can point this
# selftest at a PR-head isolated worktree instead of its own (main) checkout.
if [[ -n "${POLARIS_GOVERNED_TEST_ROOT:-}" ]]; then
  ROOT="$(cd "$POLARIS_GOVERNED_TEST_ROOT" && pwd)"
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- Source layer: runtime overlay SoT ---------------------------------------
#
# The guard's authored source-of-truth is the three runtime overlays. The
# universal core section is compiler-emitted and is verified at the compiled
# layer below — it is intentionally NOT asserted against bootstrap.md (DP-294
# AC3: bootstrap core must not be falsely failed for a guard it does not own).

for adapter in claude codex copilot; do
  src="$ROOT/.claude/instructions/runtime/${adapter}.md"
  [[ -f "$src" ]] || fail "missing runtime adapter source: $src"
  grep -qi "Final Response Language Guard" "$src" \
    || fail "$src missing 'Final Response Language Guard' section"
  grep -qi "self-check" "$src" \
    || fail "$src missing self-check directive"
  grep -q "workspace-config.yaml" "$src" \
    || fail "$src does not reference workspace-config.yaml"
done

# --- Compiled layer ----------------------------------------------------------

# Refresh generated targets so the selftest reflects the current source.
bash "$ROOT/scripts/compile-runtime-instructions.sh" --check \
  >/tmp/dp230-t18-runtime-guard-check.out 2>&1 \
  || fail "compile-runtime-instructions --check reported drift; regenerate before running this selftest"

TARGETS=(
  "CLAUDE.md|Claude Code"
  "AGENTS.md|Codex"
  ".codex/AGENTS.md|Codex"
  ".github/copilot-instructions.md|Copilot"
)

for entry in "${TARGETS[@]}"; do
  target="${entry%%|*}"
  caveat="${entry##*|}"
  path="$ROOT/$target"
  [[ -f "$path" ]] || fail "missing generated target: $target"
  grep -q "## Final Response Language Guard" "$path" \
    || fail "$target missing core 'Final Response Language Guard' section"
  grep -q "$caveat Runtime Caveat" "$path" \
    || fail "$target missing '$caveat Runtime Caveat' subsection"
  grep -q "self-check" "$path" \
    || fail "$target missing self-check directive"
done

echo "PASS: runtime final/chat response language guard selftest"
