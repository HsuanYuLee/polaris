#!/usr/bin/env bash
# Purpose: D43 constitutional Claude/Codex dual-platform mechanism parity gate.
#          Parses the effective Claude project hook sources (.claude/settings.json
#          + .claude/settings.local.json when present) across all active hook event
#          families, cross-checks the Cross-LLM Hook Parity Registry in
#          mechanism-registry.md, and asserts every active hook has a deterministic,
#          runtime-neutral Codex-equivalent enforcement path (fallback callsite,
#          Codex adapter target / active registration / callsite, adapter selftest,
#          payload-contract golden digest parity) or a recorded parity_exception.
# Inputs:  --repo DIR (default: git toplevel / cwd). Reads settings + registry +
#          generated runtime targets. No BYPASS env is consulted by design.
# Outputs: stdout "PASS: cross-LLM mechanism parity OK"; on any violation exits 2
#          and prints "POLARIS_CROSS_LLM_PARITY_BLOCKED:{hook}" to stderr.
# Exit:    0 = parity OK, 2 = parity violation / missing input.
set -euo pipefail

REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0" >&2
      exit 0
      ;;
    *) echo "POLARIS_CROSS_LLM_PARITY_BLOCKED:usage unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
REPO="$(cd "$REPO" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 2
fi

COMPILE_BIN="${POLARIS_COMPILE_RUNTIME_INSTRUCTIONS_BIN:-$REPO/scripts/compile-runtime-instructions.sh}"

# DP plans (consumed only for parity_exception reason lookup) are workspace-owned
# framework artifacts that live in the main checkout and are shared across worktrees
# (docs-manager specs are local planning artifacts, not tracked in the task branch).
# Resolve them from POLARIS_SPECS_ROOT / POLARIS_WORKSPACE_ROOT, falling back to --repo.
SPECS_ROOT="${POLARIS_SPECS_ROOT:-${POLARIS_WORKSPACE_ROOT:-$REPO}}"
if [[ -z "${POLARIS_SPECS_ROOT:-}" && -z "${POLARIS_WORKSPACE_ROOT:-}" && "$REPO" == *"/.worktrees/"* ]]; then
  MAIN_WORKSPACE="${REPO%%/.worktrees/*}"
  if [[ -d "$MAIN_WORKSPACE/docs-manager/src/content/docs/specs/design-plans" ]]; then
    SPECS_ROOT="$MAIN_WORKSPACE"
  fi
fi

# Phase 1: registry + settings + adapter + golden-digest parity (python).
python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_cross_llm_mechanism_parity_1.py" "$REPO" "$SPECS_ROOT"

# Phase 2: generated runtime target drift (Codex invocation guidance is
# compiler-emitted from mechanism-registry; a stale target is a parity violation).
if [[ -x "$COMPILE_BIN" || -f "$COMPILE_BIN" ]]; then
  if ! bash "$COMPILE_BIN" --target agents --check >/dev/null 2>&1; then
    echo "POLARIS_CROSS_LLM_PARITY_BLOCKED:AGENTS.md generated target drift (compile --target agents --check failed)" >&2
    exit 2
  fi
  if ! bash "$COMPILE_BIN" --target codex --check >/dev/null 2>&1; then
    echo "POLARIS_CROSS_LLM_PARITY_BLOCKED:.codex/AGENTS.md generated target drift (compile --target codex --check failed)" >&2
    exit 2
  fi
else
  echo "POLARIS_CROSS_LLM_PARITY_BLOCKED:compiler compile-runtime-instructions.sh missing" >&2
  exit 2
fi

echo "PASS: cross-LLM mechanism parity OK"
