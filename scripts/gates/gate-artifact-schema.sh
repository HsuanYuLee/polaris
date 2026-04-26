#!/usr/bin/env bash
set -euo pipefail

# gate-artifact-schema.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from install-copilot-hooks.sh Gates 2-4 for cross-LLM portability.
# Can be called from: git pre-commit hooks, or directly.
#
# Validates staged pipeline artifacts:
#   - */tasks/T*.md and */tasks/V*.md → validate-task-md.sh
#   - */refinement.json               → validate-refinement-json.sh
#   - specs directories with tasks    → validate-task-md-deps.sh
#
# Usage:
#   bash scripts/gates/gate-artifact-schema.sh [--repo <path>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_ARTIFACT_GATE=1

PREFIX="[polaris gate-artifact-schema]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-artifact-schema.sh [--repo <path>]"
      echo "  --repo <path>   Target repo (default: git rev-parse --show-toplevel)"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Default repo
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Bypass
if [[ "${POLARIS_SKIP_ARTIFACT_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_ARTIFACT_GATE=1 — bypassing." >&2
  exit 0
fi

# Locate validation scripts (check repo first, then workspace)
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
VALIDATE_TASK_MD=""
VALIDATE_REFINEMENT=""
VALIDATE_DEPS=""

for search_dir in "$REPO_ROOT/scripts" "$WORKSPACE_SCRIPTS"; do
  [[ -z "$VALIDATE_TASK_MD" && -f "$search_dir/validate-task-md.sh" ]] && VALIDATE_TASK_MD="$search_dir/validate-task-md.sh"
  [[ -z "$VALIDATE_REFINEMENT" && -f "$search_dir/validate-refinement-json.sh" ]] && VALIDATE_REFINEMENT="$search_dir/validate-refinement-json.sh"
  [[ -z "$VALIDATE_DEPS" && -f "$search_dir/validate-task-md-deps.sh" ]] && VALIDATE_DEPS="$search_dir/validate-task-md-deps.sh"
done

# Get staged files
staged_files=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || true)
if [[ -z "$staged_files" ]]; then
  exit 0
fi

FAILED=0
CHECKED=0

# --- Gate 1: Validate task.md schemas (T*.md and V*.md) ---
if [[ -n "$VALIDATE_TASK_MD" ]]; then
  while IFS= read -r staged_file; do
    [[ -z "$staged_file" ]] && continue
    case "$staged_file" in
      */tasks/T*.md|*/tasks/V*.md)
        full_path="$REPO_ROOT/$staged_file"
        [[ -f "$full_path" ]] || continue
        CHECKED=$((CHECKED + 1))
        echo "$PREFIX Validating task.md: $staged_file ..." >&2
        if ! bash "$VALIDATE_TASK_MD" "$full_path" 2>&1; then
          echo "$PREFIX ❌ task.md schema validation failed: $staged_file" >&2
          FAILED=$((FAILED + 1))
        fi
        ;;
    esac
  done <<< "$staged_files"
fi

# --- Gate 2: Validate refinement.json schemas ---
if [[ -n "$VALIDATE_REFINEMENT" ]]; then
  while IFS= read -r staged_file; do
    [[ -z "$staged_file" ]] && continue
    case "$staged_file" in
      */refinement.json)
        full_path="$REPO_ROOT/$staged_file"
        [[ -f "$full_path" ]] || continue
        CHECKED=$((CHECKED + 1))
        echo "$PREFIX Validating refinement.json: $staged_file ..." >&2
        if ! bash "$VALIDATE_REFINEMENT" "$full_path" 2>&1; then
          echo "$PREFIX ❌ refinement.json schema validation failed: $staged_file" >&2
          FAILED=$((FAILED + 1))
        fi
        ;;
    esac
  done <<< "$staged_files"
fi

# --- Gate 3: Validate task.md dependency DAG ---
if [[ -n "$VALIDATE_DEPS" ]]; then
  declare -a specs_dirs=()
  while IFS= read -r staged_file; do
    [[ -z "$staged_file" ]] && continue
    case "$staged_file" in
      */tasks/T*.md|*/tasks/V*.md)
        # Compute the specs dir: go up from tasks/ to the parent spec folder
        dir="$(dirname "$(dirname "$REPO_ROOT/$staged_file")")"
        # Deduplicate
        already_added=0
        for existing in "${specs_dirs[@]:-}"; do
          if [[ "$existing" == "$dir" ]]; then
            already_added=1
            break
          fi
        done
        if [[ "$already_added" -eq 0 ]]; then
          specs_dirs+=("$dir")
        fi
        ;;
    esac
  done <<< "$staged_files"

  for dir in "${specs_dirs[@]:-}"; do
    [[ -z "$dir" || ! -d "$dir" ]] && continue
    CHECKED=$((CHECKED + 1))
    echo "$PREFIX Validating task.md dependency DAG: $dir ..." >&2
    if ! bash "$VALIDATE_DEPS" "$dir" 2>&1; then
      echo "$PREFIX ❌ task.md dependency DAG invalid: $dir" >&2
      FAILED=$((FAILED + 1))
    fi
  done
fi

# Report
if [[ "$FAILED" -gt 0 ]]; then
  echo "" >&2
  echo "$PREFIX BLOCKED: ${FAILED} artifact validation(s) failed out of ${CHECKED} checked." >&2
  echo "  Fix the issues above and re-stage." >&2
  echo "  Bypass: POLARIS_SKIP_ARTIFACT_GATE=1 (not recommended)" >&2
  exit 2
fi

if [[ "$CHECKED" -gt 0 ]]; then
  echo "$PREFIX ✅ All ${CHECKED} artifact(s) validated." >&2
fi

exit 0
