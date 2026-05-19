#!/usr/bin/env bash
# post-memory-index-regenerate.sh — PostToolUse hook for Write / Edit / MultiEdit.
#
# After a legitimate memory file write (a *.md under the memory dir, excluding
# MEMORY.md itself), invoke `memory-hygiene-tiering.py --emit-index` so the
# generated MEMORY.md stays in sync with live frontmatter.
#
# Producer environment: this hook is the canonical daily writer path for
# MEMORY.md. It sets POLARIS_MEMORY_HYGIENE_APPLY=1 when invoking the producer
# so the PreToolUse gate does not block the regenerate step.
#
# Failure handling: exit 1 (surface, do not block subsequent steps). The user
# sees a structured message telling them how to recover.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TIERING_SCRIPT="${POLARIS_MEMORY_TIERING_SCRIPT:-${PROJECT_DIR}/scripts/memory-hygiene-tiering.py}"

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

file_path=$(printf '%s' "$input" | python3 -c "import sys,json
try:
  d=json.load(sys.stdin)
except Exception:
  print('')
  sys.exit(0)
print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

if [[ -z "$file_path" ]]; then
  exit 0
fi

# --- Memory path detection (mirrors pre-memory-write.sh) --------------------
detect_memory_dir() {
  local p="$1"
  if [[ -n "${POLARIS_MEMORY_DIR:-}" ]]; then
    case "$p" in
      "$POLARIS_MEMORY_DIR"/*) echo "$POLARIS_MEMORY_DIR"; return 0;;
    esac
  fi
  case "$p" in
    "$HOME"/.claude/projects/*/memory/*)
      # Extract up to ".../memory"
      python3 -c "
import os, sys
p = sys.argv[1]
home = os.path.expanduser('~')
prefix = os.path.join(home, '.claude', 'projects')
rel = os.path.relpath(p, prefix)
parts = rel.split(os.sep)
if len(parts) >= 2 and parts[1] == 'memory':
  print(os.path.join(prefix, parts[0], 'memory'))
" "$p"
      return 0
      ;;
  esac
  return 1
}

MEMORY_DIR=$(detect_memory_dir "$file_path") || exit 0
if [[ -z "$MEMORY_DIR" || ! -d "$MEMORY_DIR" ]]; then
  exit 0
fi

# --- Skip when not a memory *.md file (e.g., index.md sub-folder, fixtures) -
case "$file_path" in
  *.md) ;;
  *) exit 0;;
esac

# Skip MEMORY.md itself — the apply chain writes it through its own producer
# env, and direct writes are blocked by the PreToolUse hook anyway.
base=$(basename "$file_path")
if [[ "$base" == "MEMORY.md" ]]; then
  exit 0
fi

# Skip if validator producer is missing.
if [[ ! -f "$TIERING_SCRIPT" ]]; then
  exit 0
fi

# --- Regenerate MEMORY.md ---------------------------------------------------
set +e
out=$(POLARIS_MEMORY_HYGIENE_APPLY=1 python3 "$TIERING_SCRIPT" --emit-index --memory-dir "$MEMORY_DIR" 2>&1)
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  cat >&2 <<EOF
POLARIS_MEMORY_INDEX_REGENERATE_FAILED rc=$rc memory_dir=$MEMORY_DIR
$out
Recover with:
  POLARIS_MEMORY_HYGIENE_APPLY=1 python3 $TIERING_SCRIPT --emit-index --memory-dir $MEMORY_DIR
EOF
  exit 1
fi

exit 0
