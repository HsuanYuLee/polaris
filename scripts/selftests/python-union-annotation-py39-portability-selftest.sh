#!/usr/bin/env bash
# Purpose: Guard that framework embedded-python heredocs using modern union type
#          annotations (`X | None`, `tuple[...] | None`) stay portable to Python 3.9
#          by carrying `from __future__ import annotations` (PEP 563 lazy annotations).
# Inputs:  none (resolves repo root from this script's location).
# Outputs: stdout PASS/SKIP notes; exit 0 = PASS, 1 = FAIL.
#          Static assertion (future-import present) always runs. Dynamic assertion
#          runs the real validators under a located python<3.10 interpreter and
#          asserts no union TypeError; when no such interpreter exists it
#          skip-with-notes WITHOUT false-passing the dynamic claim (DP-265 AC-NEG1).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Files whose embedded python heredoc carries union annotations (DP-265 scope).
TARGETS=(
  "scripts/validate-script-categorization.sh"
  "scripts/validate-memory-write.sh"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Static assertion (always runs): each target heredoc must declare the future
# import. The grep pattern is single-quoted to avoid command substitution.
# ---------------------------------------------------------------------------
for rel in "${TARGETS[@]}"; do
  path="$REPO_ROOT/$rel"
  [[ -f "$path" ]] || fail "target not found: $rel"
  if ! grep -q 'from __future__ import annotations' "$path"; then
    fail "$rel: missing 'from __future__ import annotations' in embedded python (union annotations would crash on Python 3.9)"
  fi
done
echo "PASS(static): future-import present in ${#TARGETS[@]} target validator(s)"

# ---------------------------------------------------------------------------
# Locate a Python < 3.10 interpreter for the dynamic assertion.
# ---------------------------------------------------------------------------
is_pre310() {
  local interp="$1"
  [[ -x "$interp" ]] || command -v "$interp" >/dev/null 2>&1 || return 1
  "$interp" -c 'import sys; sys.exit(0 if sys.version_info < (3, 10) else 1)' >/dev/null 2>&1
}

PY39=""
for cand in /usr/bin/python3 python3.9 /usr/bin/python3.9 /opt/homebrew/bin/python3.9; do
  if is_pre310 "$cand"; then
    PY39="$cand"
    break
  fi
done

if [[ -z "$PY39" ]]; then
  echo "SKIP(dynamic): no python<3.10 interpreter located; static assertion is authoritative on this host (DP-265 AC-NEG1)"
  echo "PASS: python-union-annotation-py39-portability-selftest"
  exit 0
fi
echo "INFO: dynamic assertion uses $PY39 ($($PY39 -V 2>&1))"

# Build a PATH shim so the validators' `python3 - <<'PY'` resolves to the
# located pre-3.10 interpreter (reproduces the framework-release-pr-lane crash path).
SHIM_DIR="$(mktemp -d)"
trap 'rm -rf "$SHIM_DIR" "$DUMMY_MEMORY_DIR" 2>/dev/null || true' EXIT
ln -s "$(command -v "$PY39" 2>/dev/null || echo "$PY39")" "$SHIM_DIR/python3"

UNION_ERR='unsupported operand type'

run_under_py39() {
  # Runs a validator under the 3.9 shim and fails only on the union TypeError.
  # The validator itself may exit non-zero for unrelated reasons (audit
  # findings, candidate contract violations) — that is fine; we only assert the
  # embedded python no longer crashes evaluating union annotations.
  local label="$1"; shift
  local out
  out="$(PATH="$SHIM_DIR:$PATH" "$@" 2>&1 || true)"
  if grep -qF "$UNION_ERR" <<<"$out"; then
    echo "$out" >&2
    fail "$label: embedded python raised union TypeError under $PY39 (future-import not effective)"
  fi
  echo "PASS(dynamic): $label executed under $PY39 without union TypeError"
}

# validate-script-categorization.sh: audit mode reaches classify_violation()'s
# union-annotated def.
run_under_py39 "validate-script-categorization.sh" \
  bash "$REPO_ROOT/scripts/validate-script-categorization.sh" --mode audit --root "$REPO_ROOT"

# validate-memory-write.sh: provide a candidate path + isolated memory dir so the
# python body proceeds past env reads and evaluates its union-annotated defs.
DUMMY_MEMORY_DIR="$(mktemp -d)"
DUMMY_CANDIDATE="$DUMMY_MEMORY_DIR/probe.md"
printf '%s\n' '---' 'name: probe' 'description: py39 portability probe' '---' 'body' > "$DUMMY_CANDIDATE"
run_under_py39 "validate-memory-write.sh" \
  bash "$REPO_ROOT/scripts/validate-memory-write.sh" --candidate-path "$DUMMY_CANDIDATE" --memory-dir "$DUMMY_MEMORY_DIR"

echo "PASS: python-union-annotation-py39-portability-selftest"
