#!/usr/bin/env bash
# Purpose: PostToolUse hook for Write / Edit / MultiEdit. After a legitimate
#          write to a runtime-instruction manifest source, regenerate the
#          runtime instruction targets + generated rules-manifest snapshots by
#          delegating to the canonical writer compile-runtime-instructions.sh
#          (single writer; this hook carries NO checksum logic of its own).
#          Mirrors post-memory-index-regenerate.sh for the memory index.
# Inputs:  PostToolUse hook JSON on stdin (tool_name, tool_input.file_path).
#          CLAUDE_PROJECT_DIR (project root); POLARIS_COMPILE_RUNTIME_SCRIPT
#          (test override for the producer path).
# Outputs: exit 0 (regenerated or no-op); exit 1 (regenerate failed — surface,
#          do not block subsequent steps) with structured stderr + recover hint.
#
# Manifest source set (must mirror compile-runtime-instructions.sh
# write_manifest_snapshot sources):
#   - .claude/instructions/manifest.yaml
#   - .claude/instructions/core/bootstrap.md
#   - .claude/instructions/runtime/{claude,codex,copilot}.md
#   - .claude/rules/*.md  (maxdepth 1; nested company subfolders are NOT sources)
#
# Non-source writes (incl. nested .claude/rules subfolders and any other path)
# are a no-op exit 0. Coverage: EC3 (MultiEdit edits[] scan) handled by checking
# both tool_input.file_path and any tool_input.edits[].file_path.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
COMPILE_SCRIPT="${POLARIS_COMPILE_RUNTIME_SCRIPT:-${PROJECT_DIR}/scripts/compile-runtime-instructions.sh}"

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit(0)
print(d.get('tool_name',''))" 2>/dev/null || true)

case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0;;
esac

# Collect every candidate file path from this tool call: the top-level
# tool_input.file_path plus any tool_input.edits[].file_path (MultiEdit / EC3).
# NUL-delimited to survive any whitespace; read with a portable loop (bash 3.2).
candidate_paths=()
while IFS= read -r -d '' p; do
  candidate_paths+=("$p")
done < <(printf '%s' "$input" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
except Exception:
  sys.exit(0)
ti = d.get('tool_input', {}) or {}
seen = []
fp = ti.get('file_path')
if fp:
  seen.append(fp)
for edit in (ti.get('edits') or []):
  efp = edit.get('file_path') if isinstance(edit, dict) else None
  if efp:
    seen.append(efp)
for p in seen:
  sys.stdout.write(p + '\0')
" 2>/dev/null || true)

[[ "${#candidate_paths[@]}" -gt 0 ]] || exit 0

# --- Manifest-source detection ---------------------------------------------
# Returns 0 if $1 (absolute or project-relative) is a manifest source file.
is_manifest_source() {
  local p="$1"
  local rel="$p"
  # Normalize to a project-relative path when under PROJECT_DIR.
  case "$p" in
    "$PROJECT_DIR"/*) rel="${p#"$PROJECT_DIR"/}" ;;
  esac

  case "$rel" in
    .claude/instructions/manifest.yaml) return 0 ;;
    .claude/instructions/core/bootstrap.md) return 0 ;;
    .claude/instructions/runtime/claude.md) return 0 ;;
    .claude/instructions/runtime/codex.md) return 0 ;;
    .claude/instructions/runtime/copilot.md) return 0 ;;
    .claude/rules/*.md)
      # maxdepth 1 only: reject nested company subfolders
      # (e.g. .claude/rules/exampleco/foo.md has an extra path segment).
      local tail="${rel#.claude/rules/}"
      case "$tail" in
        */*) return 1 ;;   # nested → not a source
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

hit=0
for p in "${candidate_paths[@]}"; do
  [[ -n "$p" ]] || continue
  if is_manifest_source "$p"; then
    hit=1
    break
  fi
done

[[ "$hit" -eq 1 ]] || exit 0

# Skip if the canonical producer is missing (graceful no-op).
if [[ ! -f "$COMPILE_SCRIPT" ]]; then
  exit 0
fi

# --- Regenerate (delegate to the single canonical writer) -------------------
set +e
out=$(bash "$COMPILE_SCRIPT" 2>&1)
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  cat >&2 <<EOF
POLARIS_RUNTIME_MANIFEST_REGENERATE_FAILED rc=$rc project_dir=$PROJECT_DIR
$out
Recover with:
  bash $COMPILE_SCRIPT
EOF
  exit 1
fi

exit 0
