#!/usr/bin/env bash
# .claude/hooks/checkpoint-carry-forward-fallback.sh
#
# PreToolUse fallback hook for Write / Edit when the target path looks
# like a project checkpoint memory file. Fires when the user (or another
# skill) writes a checkpoint directly without going through the
# `checkpoint` skill's Step 2.5 L2 call.
#
# Behaviour:
#   - Non-memory paths           → exit 0 (allow)
#   - Memory path but not project memory → exit 0 (allow)
#   - Project-memory write       → delegate to scripts/check-carry-forward.sh
#
# The delegated script returns:
#   0 → PASS → we exit 0 (allow Write/Edit)
#   1 → RECOVERABLE_FAIL (usage error) → we fail-open with a stderr warn
#       (do NOT block the user's write on an invocation glitch)
#   2 → HARD_STOP → we exit 2 (block Write/Edit)
#
# Design: specs/design-plans/DP-030-llm-to-script-migration/plan.md
#         § Phase 1 POC #2

set -u

# Read hook input (PreToolUse: JSON on stdin).
input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

# Only care about files under a `memory/` directory with `.md` suffix.
# This catches both `~/.claude/projects/.../memory/*.md` and any other
# polaris memory roots.
if [[ -z "$file_path" ]]; then
  exit 0
fi

case "$file_path" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac

# We only want to validate when a NEW checkpoint-style project memory is
# being written/edited. Inspect the proposed content for `type: project`
# in the frontmatter AND a pending-style heading (下一步 / next / ...).
# If either signal is absent we fail-open silently to avoid false-positive
# blocks on unrelated memory edits (feedback, reference, user memories).

proposed_content=$(printf '%s' "$input" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
ti = d.get("tool_input", {}) or {}
# Write tool: ti["content"]. Edit tool: ti["new_string"] (partial, may
# miss frontmatter — we still union to catch the common cases).
content = ti.get("content") or ti.get("new_string") or ""
sys.stdout.write(content)
')

# Heuristic A — check proposed content first (works for Write, partial
# for Edit). If we see clear project-memory signals, proceed to validate.
has_type_project=false
has_pending_section=false

if printf '%s' "$proposed_content" | grep -qE '^type:[[:space:]]*project[[:space:]]*$'; then
  has_type_project=true
fi
if printf '%s' "$proposed_content" | grep -qiE '(^|\n)#{1,6}[[:space:]]+(下一步|下步|next[[:space:]]*steps?|pending|待實施|still[[:space:]]+pending|未完成|carry[-[:space:]]?forward|接下來|還沒做)'; then
  has_pending_section=true
fi

# Heuristic B — for Edit tool, the diff may not contain the full file.
# Try the on-disk version (the current state of the file) as a secondary
# source — an Edit to a checkpoint means the file already exists.
if [[ "$has_type_project" != "true" || "$has_pending_section" != "true" ]]; then
  if [[ -f "$file_path" ]]; then
    if grep -qE '^type:[[:space:]]*project[[:space:]]*$' "$file_path" 2>/dev/null; then
      has_type_project=true
    fi
    if grep -qiE '^#{1,6}[[:space:]]+(下一步|下步|next[[:space:]]*steps?|pending|待實施|still[[:space:]]+pending|未完成|carry[-[:space:]]?forward|接下來|還沒做)' "$file_path" 2>/dev/null; then
      has_pending_section=true
    fi
  fi
fi

# Either signal missing → this is not the checkpoint pattern we gate.
if [[ "$has_type_project" != "true" || "$has_pending_section" != "true" ]]; then
  exit 0
fi

# --- Locate validator + derive memory_dir ---
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker="${project_dir}/scripts/check-carry-forward.sh"

if [[ ! -f "$checker" ]]; then
  echo "[carry-forward fallback] WARN: validator missing at $checker — allowing (fail-open)" >&2
  exit 0
fi

# Derive memory root: if path looks like `.../memory/**` use everything up
# to and including `memory/` as the root. Handles both flat and topic-
# folder layouts.
memory_dir="${file_path%/memory/*}/memory"
if [[ ! -d "$memory_dir" ]]; then
  echo "[carry-forward fallback] WARN: could not derive memory_dir from $file_path — allowing (fail-open)" >&2
  exit 0
fi

# Stage a probe file the validator can read against the proposed write.
#   - Write tool: the proposed_content IS the full file. Always stage to
#     tmp so the validator sees the new content, regardless of whether
#     the target already exists (overwrite case must not read stale on-
#     disk content — that was the bug).
#   - Edit tool: new_string is a diff fragment, not a full file. Read the
#     on-disk file (validator sees current state). The structural carry-
#     forward check tolerates this because Edit on a checkpoint memory
#     means the prior file content is already on disk.
probe_path="$file_path"
cleanup=""
if [[ "$tool_name" == "Write" && -n "$proposed_content" ]]; then
  tmp_base=$(mktemp "/tmp/carry-forward-probe.XXXXXX")
  tmp_file="${tmp_base}.md"
  mv "$tmp_base" "$tmp_file"
  printf '%s' "$proposed_content" > "$tmp_file"
  probe_path="$tmp_file"
  cleanup="$tmp_file"
fi

bash "$checker" --new-checkpoint "$probe_path" --memory-dir "$memory_dir"
rc=$?

[[ -n "$cleanup" ]] && rm -f "$cleanup"

case "$rc" in
  0) exit 0 ;;
  2) exit 2 ;;
  *)
    echo "[carry-forward fallback] WARN: validator returned rc=$rc — allowing (fail-open)" >&2
    exit 0
    ;;
esac
