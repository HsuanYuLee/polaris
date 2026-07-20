#!/usr/bin/env bash
# validate-script-categorization.sh — D26 script categorization gate.
#
# Purpose: detect root scripts/*.sh / .py / .mjs / .ts whose callsites all
# live inside a single .claude/skills/{skill}/ directory. Such scripts
# should be relocated to .claude/skills/{skill}/scripts/ instead of
# polluting the shared root namespace.
#
# Scope (D26 multi-language): scripts/*.sh, scripts/*.py, scripts/*.mjs,
# scripts/*.ts (hot path executables). Generated targets (CLAUDE.md /
# AGENTS.md / .codex/AGENTS.md / .github/copilot-instructions.md) and
# fixtures under scripts/fixtures/** are out of scope (AC-NEG2).
#
# This validator wraps scripts/script-ownership-audit.py and consumes its
# JSON classification/taxonomy. It does NOT duplicate the callsite scan;
# the audit script is the single source of truth for ownership placement.
#
# Modes:
#   --mode diff   (default) Only flag scripts that are newly added or
#                 modified against --base (default HEAD). Violations emit
#                 POLARIS_SCRIPT_MISPLACED:{path} -> {skill}/scripts/ and
#                 exit 2.
#   --mode audit  Scan all root scripts under --root and emit a debt
#                 summary (skill_local candidates). Always exits 0 so
#                 legacy debt does not block PRs (EC5).
#
# Exit codes:
#   0 — PASS (diff: no misplaced new/modified scripts; audit: report)
#   2 — diff mode violation OR usage error
#
# Dynamic-invoke exception (EC3):
#   scripts/lib/script-categorization-exception.txt lists scripts that are
#   invoked dynamically (e.g. via `bash "$resolved_path"`) and therefore
#   produce a misleading single-skill callsite count. Each entry is
#   `path<TAB>owning-skill<TAB>reason`. The owning skill + reason are
#   mandatory (AC4 adversarial pass).
#
# Examples:
#   bash scripts/validate-script-categorization.sh
#   bash scripts/validate-script-categorization.sh --mode diff --base origin/main
#   bash scripts/validate-script-categorization.sh --mode audit --root .

set -euo pipefail

MODE="diff"
BASE_REF="HEAD"
ROOT_DIR=""
EXPLICIT_FILES=()
EXCEPTION_FILE=""

usage() {
  cat >&2 <<'EOF'
usage: validate-script-categorization.sh [--mode diff|audit]
                                         [--base <ref>]
                                         [--root <dir>]
                                         [--file <path>]...
                                         [--exception-file <path>]

Modes:
  --mode diff       (default) Block new/modified root scripts that are
                    classified as skill_local (single-skill misplaced).
                    Compares against --base ref (default HEAD).
  --mode audit      Walk the repository under --root and emit a debt
                    summary; always exits 0 (legacy debt is non-blocking
                    per EC5).

Options:
  --base <ref>            Git ref used for diff mode (default: HEAD).
  --root <dir>            Repository root (default: derived from script).
  --file <path>           Explicit file to mark as in-scope (repeatable).
                          Skips git diff discovery in diff mode. Used by
                          selftest to drive synthetic fixtures.
  --exception-file <path> Override path to the dynamic-invoke exception
                          allowlist (default:
                          scripts/lib/script-categorization-exception.txt).
  -h, --help              Show this message.
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
    --exception-file)
      EXCEPTION_FILE="${2:-}"
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

if [[ -z "$EXCEPTION_FILE" ]]; then
  EXCEPTION_FILE="$ROOT_DIR/scripts/lib/script-categorization-exception.txt"
fi

AUDIT_SCRIPT="$ROOT_DIR/scripts/script-ownership-audit.py"
if [[ ! -f "$AUDIT_SCRIPT" ]]; then
  printf 'error: script-ownership-audit.py not found under --root: %s\n' \
    "$ROOT_DIR" >&2
  exit 2
fi

# Materialise audit JSON via env to avoid heredoc escaping issues. The
# ownership audit is the single source of truth for classification.
POLARIS_SCRIPT_CATEGORIZATION_AUDIT_JSON="$(python3 "$AUDIT_SCRIPT" \
  --root "$ROOT_DIR" --format json)"
export POLARIS_SCRIPT_CATEGORIZATION_AUDIT_JSON

# Build explicit-file string list for python (NUL-separated would be
# nicer, but argv is easier here since the count is small).
EXPLICIT_BLOB=""
if (( ${#EXPLICIT_FILES[@]} > 0 )); then
  EXPLICIT_BLOB="$(printf '%s\n' "${EXPLICIT_FILES[@]}")"
fi
export POLARIS_SCRIPT_CATEGORIZATION_EXPLICIT_FILES="$EXPLICIT_BLOB"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_script_categorization_1.py" "$MODE" "$BASE_REF" "$ROOT_DIR" "$EXCEPTION_FILE"
