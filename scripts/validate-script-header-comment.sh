#!/usr/bin/env bash
# validate-script-header-comment.sh — D26 hot path executable header gate.
#
# Purpose: ensure every Polaris-owned .sh / .py / .mjs / .ts hot path
# executable carries an intent comment (or module docstring for .py) within
# the first 20 lines, so future maintainers can identify ownership and
# purpose without reading the implementation.
#
# Scope (D26 multi-language): .sh, .py, .mjs, .ts hot path executables under
# scripts/, .claude/skills/*/scripts/, and (audit mode) the entire repo with
# generated targets / fixtures excluded.
#
# Modes:
#   --mode diff   (default) Only scan new / modified scripts against --base
#                 ref (default HEAD). Violations emit
#                 POLARIS_SCRIPT_HEADER_MISSING:{path} and exit 2.
#   --mode audit  Scan all in-scope scripts under --root, emit a debt
#                 summary (counts + path list) and exit 0. Useful for
#                 legacy debt enumeration (DP-240-T7).
#
# Exit codes:
#   0 — PASS (diff: no violations; audit: report emitted)
#   2 — diff mode violations OR usage error
#
# Examples:
#   bash scripts/validate-script-header-comment.sh
#   bash scripts/validate-script-header-comment.sh --mode diff --base origin/main
#   bash scripts/validate-script-header-comment.sh --mode audit --root .

set -euo pipefail

MODE="diff"
BASE_REF="HEAD"
ROOT_DIR=""
# Explicit file list overrides diff/audit discovery (used by selftest).
EXPLICIT_FILES=()

usage() {
  cat >&2 <<'EOF'
usage: validate-script-header-comment.sh [--mode diff|audit]
                                         [--base <ref>]
                                         [--root <dir>]
                                         [--file <path>]...

Modes:
  --mode diff       (default) Block new/modified scripts that lack a header
                    comment. Compares against --base ref (default HEAD).
  --mode audit      Walk the repository under --root and emit a debt
                    summary; always exits 0.

Options:
  --base <ref>      Git ref used for diff mode (default: HEAD).
  --root <dir>      Repository root (default: derived from script location).
  --file <path>     Explicit file to check (repeatable). Skips git discovery.
                    Useful for selftests / fixtures.
  -h, --help        Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --base)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --root)
      ROOT_DIR="${2:-}"
      shift 2
      ;;
    --file)
      EXPLICIT_FILES+=("${2:-}")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$MODE" != "diff" && "$MODE" != "audit" ]]; then
  printf 'error: --mode must be diff or audit (got %s)\n' "$MODE" >&2
  exit 2
fi

if [[ -z "$ROOT_DIR" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if [[ ! -d "$ROOT_DIR" ]]; then
  printf 'error: --root not a directory: %s\n' "$ROOT_DIR" >&2
  exit 2
fi

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_script_header_comment_1.py" "$MODE" "$BASE_REF" "$ROOT_DIR" "${EXPLICIT_FILES[@]+"${EXPLICIT_FILES[@]}"}"
