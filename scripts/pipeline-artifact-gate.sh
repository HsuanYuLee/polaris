#!/usr/bin/env bash
# pipeline-artifact-gate.sh — runtime-agnostic PreToolUse dispatcher for pipeline artifacts.
#
# Reads tool input (Edit/Write), extracts file path, and routes to the matching validator:
#   - `*/specs/*/refinement.json`     → validate-refinement-json.sh
#   - `*/specs/*/tasks/T*.md`         → validate-task-md.sh + validate-task-md-deps.sh
#
# Invoked by:
#   - Claude hook: `.claude/hooks/pipeline-artifact-gate.sh` (wrapper)
#   - Codex / manual: `bash scripts/pipeline-artifact-gate.sh <path>` or stdin JSON
#
# Exit:
#   0 = allow (not a pipeline artifact, or validator passed)
#   2 = block (validator failed; stderr has actionable error)
#
# Bypass:
#   POLARIS_SKIP_ARTIFACT_GATE=1  → skip all validation (emergency escape hatch)

set -euo pipefail

# --- Bypass ---
if [[ "${POLARIS_SKIP_ARTIFACT_GATE:-}" == "1" ]]; then
  exit 0
fi

# --- Detect script locations ---
WORKSPACE_ROOT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-}}"
if [[ -z "$WORKSPACE_ROOT" ]]; then
  WORKSPACE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi

VALIDATE_REFINEMENT="$WORKSPACE_ROOT/scripts/validate-refinement-json.sh"
VALIDATE_TASK_MD="$WORKSPACE_ROOT/scripts/validate-task-md.sh"
VALIDATE_TASK_MD_DEPS="$WORKSPACE_ROOT/scripts/validate-task-md-deps.sh"

# --- Extract candidate file paths ---
declare -a CANDIDATE_PATHS=()

if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    CANDIDATE_PATHS+=("$arg")
  done
else
  TOOL_INPUT="${CLAUDE_TOOL_INPUT:-${CODEX_TOOL_INPUT:-${TOOL_INPUT:-}}}"
  # If no env var set, try to read from stdin (Claude hook protocol).
  if [[ -z "$TOOL_INPUT" ]] && [[ ! -t 0 ]]; then
    TOOL_INPUT=$(cat)
  fi

  if [[ -n "$TOOL_INPUT" ]]; then
    # Extract paths from Edit/Write tool input JSON
    while IFS= read -r p; do
      [[ -n "$p" ]] && CANDIDATE_PATHS+=("$p")
    done < <(printf '%s' "$TOOL_INPUT" | python3 -c '
import json, sys
KEYS = {"file_path", "path", "target", "filename"}
def walk(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k in KEYS and isinstance(v, str) and v:
                print(v)
            walk(v)
    elif isinstance(node, list):
        for item in node:
            walk(item)
try:
    raw = sys.stdin.read().strip()
    if raw:
        obj = json.loads(raw)
        walk(obj)
except Exception:
    pass
' 2>/dev/null || true)
  fi
fi

# Nothing to check — allow.
if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
  exit 0
fi

# --- Dispatch per file type ---
block=0

for path in "${CANDIDATE_PATHS[@]}"; do
  # Normalize: if not absolute, resolve relative to workspace root.
  if [[ ! "$path" = /* ]]; then
    path="$WORKSPACE_ROOT/$path"
  fi

  # Skip worktrees / node_modules / archives
  case "$path" in
    */.worktrees/*|*/node_modules/*|*/archive/*)
      continue
      ;;
  esac

  # --- refinement.json ---
  case "$path" in
    */specs/*/refinement.json)
      if [[ -x "$VALIDATE_REFINEMENT" ]]; then
        if ! "$VALIDATE_REFINEMENT" "$path" >&2; then
          block=1
        fi
      fi
      continue
      ;;
  esac

  # --- task.md (specs/*/tasks/T*.md) ---
  case "$path" in
    */specs/*/tasks/T*.md)
      if [[ -x "$VALIDATE_TASK_MD" ]]; then
        if ! "$VALIDATE_TASK_MD" "$path" >&2; then
          block=1
        fi
      fi
      # Also validate the Epic's cross-file topology
      tasks_dir=$(dirname "$path")
      if [[ -x "$VALIDATE_TASK_MD_DEPS" ]] && [[ -d "$tasks_dir" ]]; then
        if ! "$VALIDATE_TASK_MD_DEPS" "$tasks_dir" >&2; then
          block=1
        fi
      fi
      continue
      ;;
  esac
done

if [[ $block -eq 1 ]]; then
  echo "" >&2
  echo "BLOCKED: pipeline artifact schema violation (DP-025)." >&2
  echo "Fix the errors above, or bypass with POLARIS_SKIP_ARTIFACT_GATE=1 (emergency only)." >&2
  exit 2
fi

exit 0
