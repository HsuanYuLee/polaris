#!/usr/bin/env bash
# docs-viewer-sync-hook.sh
# Runtime-agnostic sidebar sync hook entrypoint for docs-viewer.
#
# Supports:
# - Claude hook env (`CLAUDE_TOOL_INPUT`, `CLAUDE_PROJECT_DIR`)
# - Generic/Codex-style invocation with file paths as arguments
# - Fallback scan from git diff for specs/ changes

set -euo pipefail

detect_workspace_root() {
  if [[ $# -gt 0 && -d "$1" ]]; then
    printf '%s\n' "$1"
    return
  fi

  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  if [[ -n "${CODEX_PROJECT_DIR:-}" ]]; then
    printf '%s\n' "$CODEX_PROJECT_DIR"
    return
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$git_root"
    return
  fi

  pwd
}

is_specs_target() {
  local path="$1"
  case "$path" in
    */specs/design-plans/*|specs/design-plans/*)
      return 0
      ;;
    */specs/*/tasks/*|specs/*/tasks/*)
      return 0
      ;;
    */specs/*/*.md|specs/*/*.md)
      return 0
      ;;
    */specs/*.md|specs/*.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

extract_paths_from_tool_input() {
  local tool_input="$1"
  [[ -n "$tool_input" ]] || return 0

  printf '%s' "$tool_input" | python3 -c '
import json
import sys

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

raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)

try:
    obj = json.loads(raw)
except Exception:
    raise SystemExit(0)

walk(obj)
' 2>/dev/null || true
}

WORKSPACE_ROOT="$(detect_workspace_root "${1:-}")"

declare -a CANDIDATE_PATHS=()

if [[ $# -gt 0 && -d "$1" ]]; then
  shift
fi

if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    CANDIDATE_PATHS+=("$arg")
  done
fi

if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
  TOOL_INPUT="${CLAUDE_TOOL_INPUT:-${CODEX_TOOL_INPUT:-${TOOL_INPUT:-}}}"

  # For Bash tool calls: detect git operations that bring in new files (merge, rebase, checkout)
  if is_git_tree_change="$(printf '%s' "$TOOL_INPUT" | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw: sys.exit(1)
try:
    obj = json.loads(raw)
except Exception:
    sys.exit(1)
cmd = obj.get("command", "")
if re.search(r"\bgit\b.*\b(merge|rebase|cherry-pick|checkout|switch|pull)\b", cmd):
    print("yes")
else:
    sys.exit(1)
' 2>/dev/null)"; then
    # Git tree-change operation detected — check if specs files were affected
    while IFS= read -r p; do
      [[ -n "$p" ]] && CANDIDATE_PATHS+=("$p")
    done < <(git -C "$WORKSPACE_ROOT" diff --name-only HEAD@{1} HEAD -- '*/specs/' 'specs/' 2>/dev/null || true)
  fi

  # Standard path extraction from tool input (Edit/Write)
  if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && CANDIDATE_PATHS+=("$p")
    done < <(extract_paths_from_tool_input "$TOOL_INPUT")
  fi
fi

if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
  # Fallback: scan for recently modified specs files (covers gitignored specs/)
  # Use 10-second window to catch edits that just happened
  cutoff="$(date -v-10S '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -d '10 seconds ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '')"
  if [[ -n "$cutoff" && -d "$WORKSPACE_ROOT/specs" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && CANDIDATE_PATHS+=("$p")
    done < <(find "$WORKSPACE_ROOT/specs" -name '*.md' -newermt "$cutoff" -type f 2>/dev/null || true)
  fi
fi

# Secondary fallback: git diff for tracked specs (rare case)
if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
  while IFS= read -r p; do
    [[ -n "$p" ]] && CANDIDATE_PATHS+=("$p")
  done < <(git -C "$WORKSPACE_ROOT" diff --name-only -- specs 2>/dev/null || true)
fi

needs_sync=false
for path in "${CANDIDATE_PATHS[@]}"; do
  if is_specs_target "$path"; then
    needs_sync=true
    break
  fi
done

if [[ "$needs_sync" != true ]]; then
  exit 0
fi

bash "$WORKSPACE_ROOT/scripts/generate-specs-sidebar.sh" "$WORKSPACE_ROOT" >/dev/null 2>&1
echo "Specs sidebar auto-updated."
