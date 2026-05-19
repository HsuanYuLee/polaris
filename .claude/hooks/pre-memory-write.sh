#!/usr/bin/env bash
# pre-memory-write.sh — PreToolUse hook for Write / Edit / MultiEdit.
#
# Reads Claude Code hook JSON from stdin, reconstructs the candidate memory
# file content, and calls scripts/validate-memory-write.sh. fail-stops (exit 2)
# on contract violation. Non-memory paths pass through (exit 0).
#
# Memory path detection (in order):
#   1. POLARIS_MEMORY_DIR (test / production override).
#   2. ~/.claude/projects/*/memory/** glob (production layout).
#   3. POLARIS_MEMORY_INDEX_GRACE_UNTIL=YYYY-MM-DD grace window for MEMORY.md
#      direct writes (one-time hand-maintained → generated transition window).
#
# Bypass: POLARIS_MEMORY_HYGIENE_APPLY=1 (passes through to validator).
#
# Escalation: same file path hitting fail-stop 3 times in the same shell
# session (tracked under /tmp/polaris-pre-memory-write-fails-<USER>/) prints a
# louder escalation banner.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
VALIDATOR="${POLARIS_VALIDATE_MEMORY_WRITE:-${PROJECT_DIR}/scripts/validate-memory-write.sh}"

input=$(cat)

# --- Parse hook JSON --------------------------------------------------------
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

# --- Memory path detection --------------------------------------------------
is_memory_path() {
  local p="$1"
  if [[ -n "${POLARIS_MEMORY_DIR:-}" ]]; then
    case "$p" in
      "$POLARIS_MEMORY_DIR"/*) return 0;;
      "$POLARIS_MEMORY_DIR") return 0;;
    esac
  fi
  case "$p" in
    "$HOME"/.claude/projects/*/memory/*) return 0;;
  esac
  return 1
}

if ! is_memory_path "$file_path"; then
  exit 0
fi

# --- Bypass guard (apply chain) ---------------------------------------------
if [[ "${POLARIS_MEMORY_HYGIENE_APPLY:-}" == "1" ]]; then
  exit 0
fi

# --- Reconstruct candidate content -----------------------------------------
export POLARIS_PRE_MEMORY_WRITE__INPUT="$input"
export POLARIS_PRE_MEMORY_WRITE__TOOL="$tool_name"
export POLARIS_PRE_MEMORY_WRITE__FILE="$file_path"
candidate_content=$(python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

tool_name = os.environ.get("POLARIS_PRE_MEMORY_WRITE__TOOL", "")
file_path = os.environ.get("POLARIS_PRE_MEMORY_WRITE__FILE", "")
raw = os.environ.get("POLARIS_PRE_MEMORY_WRITE__INPUT", "")
try:
    payload = json.loads(raw)
except Exception:
    sys.exit(0)

tool_input = payload.get("tool_input", {}) or {}


def read_existing(path: str) -> str:
    p = Path(path)
    if p.is_file():
        try:
            return p.read_text()
        except OSError:
            return ""
    return ""


def apply_edit(text: str, old: str, new: str, replace_all: bool) -> str:
    if not old:
        # Edit with empty old_string is invalid; pass through unchanged so the
        # validator surfaces the underlying contract issue.
        return text
    if replace_all:
        return text.replace(old, new)
    idx = text.find(old)
    if idx == -1:
        return text
    return text[:idx] + new + text[idx + len(old):]


if tool_name == "Write":
    sys.stdout.write(tool_input.get("content", "") or "")
elif tool_name == "Edit":
    base = read_existing(file_path)
    sys.stdout.write(
        apply_edit(
            base,
            tool_input.get("old_string", "") or "",
            tool_input.get("new_string", "") or "",
            bool(tool_input.get("replace_all", False)),
        )
    )
elif tool_name == "MultiEdit":
    base = read_existing(file_path)
    edits = tool_input.get("edits", []) or []
    out = base
    for edit in edits:
        out = apply_edit(
            out,
            edit.get("old_string", "") or "",
            edit.get("new_string", "") or "",
            bool(edit.get("replace_all", False)),
        )
    sys.stdout.write(out)
else:
    sys.exit(0)
PY
)

# --- Invoke validator -------------------------------------------------------
set +e
printf '%s' "$candidate_content" | "$VALIDATOR" \
  --candidate-path "$file_path" \
  --candidate-content - \
  > >(cat) 2> /tmp/polaris-pre-memory-write-stderr.$$
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  rm -f /tmp/polaris-pre-memory-write-stderr.$$ 2>/dev/null || true
  exit 0
fi

# --- Escalation counter -----------------------------------------------------
state_dir="/tmp/polaris-pre-memory-write-fails-${USER:-anon}"
mkdir -p "$state_dir" 2>/dev/null || true
fail_key=$(printf '%s' "$file_path" | python3 -c "import sys,hashlib; print(hashlib.sha1(sys.stdin.read().encode()).hexdigest())")
fail_stamp="$state_dir/$fail_key"
prev_count=0
if [[ -f "$fail_stamp" ]]; then
  prev_count=$(cat "$fail_stamp" 2>/dev/null || echo 0)
  case "$prev_count" in
    ''|*[!0-9]*) prev_count=0;;
  esac
fi
new_count=$((prev_count + 1))
printf '%s' "$new_count" > "$fail_stamp" 2>/dev/null || true

# Surface validator stderr verbatim.
if [[ -s /tmp/polaris-pre-memory-write-stderr.$$ ]]; then
  cat /tmp/polaris-pre-memory-write-stderr.$$ >&2
  rm -f /tmp/polaris-pre-memory-write-stderr.$$
fi

if [[ "$new_count" -ge 3 ]]; then
  cat >&2 <<EOF

POLARIS_MEMORY_WRITE_ESCALATION path=$file_path attempts=$new_count
This memory write has failed the contract gate $new_count times this session.
Stop retrying with Write/Edit/MultiEdit and switch to /memory-hygiene
(or fix the underlying frontmatter / Hot soft-limit).
EOF
fi

exit "$rc"
