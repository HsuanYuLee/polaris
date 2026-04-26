#!/usr/bin/env bash
# pipeline-artifact-gate.sh — runtime-agnostic PreToolUse dispatcher for pipeline artifacts.
#
# Reads tool input (Edit/Write), extracts file path, and routes to the matching validator:
#   - `*/specs/*/refinement.json`            → validate-refinement-json.sh
#   - `*/specs/*/tasks/complete/*.md`         → skip (D6: completed tasks leave validator scope)
#   - `*/specs/*/tasks/T*.md`                → validate-task-md.sh (T mode) + validate-task-md-deps.sh
#   - `*/specs/*/tasks/V*.md`                → validate-task-md.sh (V mode) + validate-task-md-deps.sh
#                                              (DP-033 Phase B：V mode dispatch by filename，cross-file
#                                              validator 同支共用 — 自動掃 T+V 並檢 V→T pass / T→V fail)
#
# Write-on-new-file handling: when PreToolUse fires for a Write whose target
# does not exist yet, the validator can't read the file. We stage the
# proposed content (from tool_input.content) into a tmp probe whose
# basename mirrors the target so filename-keyed dispatch still routes
# correctly, then run the validator against the probe. Edit on a missing
# target is a no-op (Edit's diff is partial, can't reconstruct full content).
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

# --- Extract candidate paths + per-Write content ---
# Two parallel arrays. CANDIDATE_CONTENTS[i] is base64-encoded Write content
# for entry i, or empty string for Edit / fallback walk.
declare -a CANDIDATE_PATHS=()
declare -a CANDIDATE_CONTENTS=()

if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    CANDIDATE_PATHS+=("$arg")
    CANDIDATE_CONTENTS+=("")
  done
else
  TOOL_INPUT="${CLAUDE_TOOL_INPUT:-${CODEX_TOOL_INPUT:-${TOOL_INPUT:-}}}"
  if [[ -z "$TOOL_INPUT" ]] && [[ ! -t 0 ]]; then
    TOOL_INPUT=$(cat)
  fi

  if [[ -n "$TOOL_INPUT" ]]; then
    while IFS=$'\t' read -r p c; do
      [[ -z "$p" ]] && continue
      CANDIDATE_PATHS+=("$p")
      CANDIDATE_CONTENTS+=("${c:-}")
    done < <(printf '%s' "$TOOL_INPUT" | python3 -c '
import json, sys, base64

def emit(path, content_b64=""):
    print(f"{path}\t{content_b64}")

try:
    raw = sys.stdin.read().strip()
    if not raw:
        sys.exit(0)
    obj = json.loads(raw)
except Exception:
    sys.exit(0)

tool = obj.get("tool_name", "") if isinstance(obj, dict) else ""
ti = obj.get("tool_input", {}) if isinstance(obj, dict) else {}

if tool == "Write" and isinstance(ti, dict):
    fp = ti.get("file_path", "") or ti.get("path", "")
    content = ti.get("content", "") or ""
    if fp:
        b64 = base64.b64encode(content.encode("utf-8")).decode("ascii") if content else ""
        emit(fp, b64)
elif tool == "Edit" and isinstance(ti, dict):
    fp = ti.get("file_path", "") or ti.get("path", "")
    if fp:
        emit(fp, "")
else:
    KEYS = {"file_path", "path", "target", "filename"}
    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in KEYS and isinstance(v, str) and v:
                    emit(v)
                walk(v)
        elif isinstance(node, list):
            for item in node:
                walk(item)
    walk(obj)
' 2>/dev/null || true)
  fi
fi

# Nothing to check — allow.
if [[ ${#CANDIDATE_PATHS[@]} -eq 0 ]]; then
  exit 0
fi

# --- Tmp probe staging for Write on new files ---
declare -a CLEANUP_FILES=()
cleanup_probes() {
  # `set -u` makes ${arr[@]} on an empty array a fatal expansion; guard with
  # the `+` parameter expansion idiom that yields nothing when unset/empty.
  for f in "${CLEANUP_FILES[@]+"${CLEANUP_FILES[@]}"}"; do
    [[ -n "$f" && -f "$f" ]] && rm -f "$f"
  done
}
trap cleanup_probes EXIT

# Returns the path the validator should read.
#   - Existing file → real path
#   - Missing file with Write content → staged tmp probe (basename mirrors target)
#   - Missing file without content (Edit / no content) → real path (validator
#     will fail naturally; nothing we can stage)
resolve_probe_path() {
  local target="$1"
  local content_b64="$2"
  if [[ -f "$target" ]]; then
    printf '%s' "$target"
    return 0
  fi
  if [[ -z "$content_b64" ]]; then
    printf '%s' "$target"
    return 0
  fi
  local base
  base=$(basename -- "$target")
  local tmp
  tmp=$(mktemp -t "polaris-artifact-probe.XXXXXX") || {
    printf '%s' "$target"
    return 0
  }
  local probe="${tmp}__${base}"
  if ! mv "$tmp" "$probe" 2>/dev/null; then
    rm -f "$tmp"
    printf '%s' "$target"
    return 0
  fi
  if ! printf '%s' "$content_b64" | base64 --decode > "$probe" 2>/dev/null; then
    rm -f "$probe"
    printf '%s' "$target"
    return 0
  fi
  CLEANUP_FILES+=("$probe")
  printf '%s' "$probe"
}

# --- Dispatch per file type ---
block=0

for i in "${!CANDIDATE_PATHS[@]}"; do
  path="${CANDIDATE_PATHS[$i]}"
  content_b64="${CANDIDATE_CONTENTS[$i]:-}"

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

  # --- complete/ skip (D6: completed tasks move out of validator scope) ---
  # Must precede T*.md / V*.md so complete/T1.md is never re-validated.
  case "$path" in
    */specs/*/tasks/complete/*.md)
      continue
      ;;
  esac

  probe=$(resolve_probe_path "$path" "$content_b64")

  # --- refinement.json ---
  case "$path" in
    */specs/*/refinement.json)
      if [[ -x "$VALIDATE_REFINEMENT" ]] && [[ -f "$probe" ]]; then
        if ! "$VALIDATE_REFINEMENT" "$probe" >&2; then
          block=1
        fi
      fi
      continue
      ;;
  esac

  # --- implementation task.md (specs/*/tasks/T*.md) ---
  case "$path" in
    */specs/*/tasks/T*.md)
      if [[ -x "$VALIDATE_TASK_MD" ]] && [[ -f "$probe" ]]; then
        if ! "$VALIDATE_TASK_MD" "$probe" >&2; then
          block=1
        fi
      fi
      # Cross-file topology validation runs against the real tasks/ dir.
      # For a Write of a new file the new entry isn't on disk yet, so deps
      # validation only sees siblings — that's fine; the new file's deps
      # are validated by the per-file run above.
      tasks_dir=$(dirname "$path")
      if [[ -x "$VALIDATE_TASK_MD_DEPS" ]] && [[ -d "$tasks_dir" ]]; then
        if ! "$VALIDATE_TASK_MD_DEPS" "$tasks_dir" >&2; then
          block=1
        fi
      fi
      continue
      ;;
  esac

  # --- verification task.md (specs/*/tasks/V*.md, DP-033 Phase B) ---
  case "$path" in
    */specs/*/tasks/V*.md)
      if [[ -x "$VALIDATE_TASK_MD" ]] && [[ -f "$probe" ]]; then
        if ! "$VALIDATE_TASK_MD" "$probe" >&2; then
          block=1
        fi
      fi
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
