#!/usr/bin/env bash
# pre-write-language-policy.sh — DP-217 writer-side language policy gate.
#
# PreToolUse hook for Write / Edit / MultiEdit. When the target path is under
# `.claude/skills/**`, `.claude/rules/**`, or
# `docs-manager/src/content/docs/specs/**`, the hook invokes
# `scripts/validate-language-policy.sh` against the file contents that are
# about to be written. If the policy validator returns non-zero, the hook
# exits 2 so the write is rejected at PreToolUse time rather than discovered
# downstream by a verify gate.
#
# The hook respects POLARIS_LANGUAGE_POLICY_BYPASS=1 only when a maintainer
# explicitly sets it for a known migration. The bypass is logged to stderr
# so post-task reflection can pick it up; it is not a silent escape.
#
# Exit codes:
#   0  no-op (tool name not Write/Edit/MultiEdit, path outside scope, or PASS)
#   2  language policy violation — write is blocked

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Match scoped writer-side artifact paths.
in_scope=0
case "$file_path" in
  */.claude/skills/*|.claude/skills/*) in_scope=1 ;;
  */.claude/rules/*|.claude/rules/*) in_scope=1 ;;
  */docs-manager/src/content/docs/specs/*|docs-manager/src/content/docs/specs/*) in_scope=1 ;;
esac
if [[ "$in_scope" -ne 1 ]]; then
  exit 0
fi

# DP-217 carve-out: never block Polaris-managed status flips / artifact
# producers that themselves invoke this same path. Producer scripts set
# POLARIS_PRODUCER to declare ownership; hook honors that signal but logs
# it so post-task reflection can audit producer usage.
if [[ -n "${POLARIS_PRODUCER:-}" ]]; then
  echo "[pre-write-language-policy] BYPASS producer=$POLARIS_PRODUCER path=$file_path" >&2
  exit 0
fi

if [[ -n "${POLARIS_LANGUAGE_POLICY_BYPASS:-}" ]]; then
  echo "[pre-write-language-policy] BYPASS explicit POLARIS_LANGUAGE_POLICY_BYPASS=1 path=$file_path" >&2
  # DP-220: deterministic friction trigger — explicit user bypass is a
  # workaround signal. Only fire when AUTO_PASS_LEDGER_PATH is set (i.e.
  # inside an /auto-pass run); the helper is NOOP otherwise.
  # POLARIS_PRODUCER bypass (above) is NOT a friction — it is normal
  # producer attribution and exits earlier without reaching this branch.
  if [[ -n "${AUTO_PASS_LEDGER_PATH:-}" ]]; then
    workspace_root_friction="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    "$workspace_root_friction/scripts/append-auto-pass-friction.sh" \
      "$AUTO_PASS_LEDGER_PATH" \
      --stage engineering \
      --kind env_bypass \
      --summary "POLARIS_LANGUAGE_POLICY_BYPASS=1 explicit bypass for $file_path (auto-trigger from pre-write-language-policy, DP-220)" \
      >/dev/null 2>&1 || true
  fi
  exit 0
fi

# Resolve workspace root + validator path.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="$(cd "$script_dir/../.." && pwd)"
validator="$workspace_root/scripts/validate-language-policy.sh"
if [[ ! -x "$validator" ]]; then
  exit 0
fi

# Resolve the proposed new content. Write tool supplies it directly via
# `content`; Edit/MultiEdit need the file's current state plus the diff,
# which is non-trivial to reconstruct without invoking Claude's own edit
# engine. For Edit/MultiEdit we fall back to inspecting the file AFTER
# Claude commits it would be too late — so we run policy against the
# proposed `new_string` content for Edit, and against the assembled
# pseudo-content for MultiEdit. If parsing fails we fail open (exit 0)
# rather than block legitimate writes.
tmp_payload=""
cleanup_tmp() {
  if [[ -n "$tmp_payload" && -f "$tmp_payload" ]]; then
    rm -f "$tmp_payload"
  fi
}
trap cleanup_tmp EXIT

case "$tool_name" in
  Write)
    content=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('content',''), end='')" 2>/dev/null || true)
    tmp_payload="$(mktemp -t pre-write-lang-XXXX.md)"
    printf '%s' "$content" >"$tmp_payload"
    ;;
  Edit|MultiEdit)
    # For Edit/MultiEdit the file already exists. We assemble a worst-case
    # preview by reading the file and substituting every (old_string, new_string)
    # pair the input provides. If anything looks malformed we exit 0 (fail open).
    preview="$(printf '%s' "$input" | python3 <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input", {}) or {}
    file_path = tool_input.get("file_path", "")
    if not file_path:
        sys.exit(0)
    try:
        with open(file_path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except FileNotFoundError:
        text = ""
    if "edits" in tool_input and isinstance(tool_input["edits"], list):
        edits = tool_input["edits"]
    else:
        edits = [{
            "old_string": tool_input.get("old_string", ""),
            "new_string": tool_input.get("new_string", ""),
            "replace_all": bool(tool_input.get("replace_all", False)),
        }]
    for edit in edits:
        old = edit.get("old_string", "")
        new = edit.get("new_string", "")
        if not old:
            continue
        if edit.get("replace_all"):
            text = text.replace(old, new)
        else:
            text = text.replace(old, new, 1)
    sys.stdout.write(text)
except Exception:
    pass
PY
)"
    tmp_payload="$(mktemp -t pre-write-lang-XXXX.md)"
    printf '%s' "$preview" >"$tmp_payload"
    ;;
esac

if [[ ! -s "$tmp_payload" ]]; then
  # Empty preview — fail open so we don't block legitimate empty-file creates.
  exit 0
fi

# Mirror the user-visible file extension so the validator path heuristics work
# (markdown lookups, YAML detection etc.). Without this all temp files end in
# .md regardless of source and we lose context the validator might use.
case "$file_path" in
  *.md|*.markdown|*.MD)
    if [[ "$tmp_payload" != *.md ]]; then
      renamed="${tmp_payload%.md}.md"
      if [[ "$renamed" != "$tmp_payload" ]]; then
        mv "$tmp_payload" "$renamed"
        tmp_payload="$renamed"
      fi
    fi
    ;;
esac

# Run the canonical validator. Fail-closed when it returns non-zero.
out="$("$validator" --blocking --mode artifact "$tmp_payload" 2>&1 || true)"
status=$?
if printf '%s' "$out" | grep -q '✗ language policy violations'; then
  echo "BLOCKED by pre-write-language-policy: $file_path" >&2
  printf '%s\n' "$out" >&2
  exit 2
fi

exit 0
