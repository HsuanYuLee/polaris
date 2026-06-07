#!/usr/bin/env bash
# runtime-final-response-language-guard-selftest.sh
#
# Enforces AC39 from DP-230:
#   - .claude/instructions/core/bootstrap.md must declare that final/chat
#     response is user-facing prose governed by workspace-config.yaml language.
#   - .claude/instructions/runtime/{claude,codex,copilot}.md must each carry a
#     runtime-specific caveat: hook/model does NOT intercept final response;
#     agent must self-check workspace language before replying.
#   - After compiling, CLAUDE.md, AGENTS.md, .codex/AGENTS.md, and
#     .github/copilot-instructions.md must each contain the corresponding guard.
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

# --- Source layer ------------------------------------------------------------

BOOTSTRAP="$ROOT/.claude/instructions/core/bootstrap.md"
[[ -f "$BOOTSTRAP" ]] || fail "missing bootstrap source: $BOOTSTRAP"

grep -q "Final Response Language Guard" "$BOOTSTRAP" \
  || fail "bootstrap missing 'Final Response Language Guard' section"
grep -q "workspace-config.yaml" "$BOOTSTRAP" \
  || fail "bootstrap final-response guard does not reference workspace-config.yaml"
grep -qE "user-facing prose|user facing prose" "$BOOTSTRAP" \
  || fail "bootstrap final-response guard does not classify final response as user-facing prose"

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
