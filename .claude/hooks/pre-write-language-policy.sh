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

# DP-217 / DP-226 producer carve-out: never block Polaris-managed status flips /
# artifact producers that invoke this same path. Producer scripts set
# POLARIS_PRODUCER to declare ownership; hook honors that signal but logs
# it so post-task reflection can audit producer usage.
#
# DP-226 tightening: bypass requires BOTH (a) token listed in some producer
# entry's producer_tokens[] AND (b) file_path matching that same entry's
# path_globs[]. Token-first lookup (find the unique entry whose
# producer_tokens[] contains the token, then verify path). When neither
# condition holds, fall through to the language validator instead of granting
# a free-form bypass. Entries without producer_tokens[] do not participate
# in token bypass — those producers continue to operate via their own
# scripted writers (see scripts/lib/evidence-producers.json).
if [[ -n "${POLARIS_PRODUCER:-}" ]]; then
  script_dir_pp="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  workspace_root_pp="$(cd "$script_dir_pp/../.." && pwd)"
  producers_json_pp="$workspace_root_pp/scripts/lib/evidence-producers.json"
  decision_pp="NO_TABLE"
  if [[ -f "$producers_json_pp" ]]; then
    decision_pp=$(POLARIS_PRODUCER_VAL="$POLARIS_PRODUCER" FILE_PATH_VAL="$file_path" \
      PRODUCERS_JSON_VAL="$producers_json_pp" python3 - <<'PY' 2>/dev/null || true
import fnmatch
import json
import os
import sys

token = os.environ.get("POLARIS_PRODUCER_VAL", "")
file_path = os.environ.get("FILE_PATH_VAL", "")
producers_json = os.environ.get("PRODUCERS_JSON_VAL", "")

try:
    with open(producers_json, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    print("NO_TABLE")
    sys.exit(0)

producers = data.get("producers", []) or []

# Token-first lookup: locate the unique entry whose producer_tokens[] contains token.
matching = [p for p in producers if token in (p.get("producer_tokens") or [])]
if len(matching) > 1:
    print("TOKEN_NOT_UNIQUE")
    sys.exit(0)
if len(matching) == 0:
    print("TOKEN_UNKNOWN")
    sys.exit(0)

entry = matching[0]
globs = entry.get("path_globs", []) or []

def match_any(path, globs):
    for g in globs:
        if fnmatch.fnmatch(path, g):
            return True
        parts = path.split("/")
        for i in range(len(parts)):
            tail = "/".join(parts[i:])
            if fnmatch.fnmatch(tail, g):
                return True
        g_alt = g.replace("**/", "*/").replace("/**", "/*")
        if fnmatch.fnmatch(path, g_alt):
            return True
    return False

if match_any(file_path, globs):
    print("BYPASS_TOKEN")
else:
    print("PATH_OUT_OF_GLOBS")
PY
)
  fi
  case "$decision_pp" in
    BYPASS_TOKEN)
      echo "[pre-write-language-policy] BYPASS producer=$POLARIS_PRODUCER path=$file_path (DP-226 token+glob)" >&2
      exit 0
      ;;
    PATH_OUT_OF_GLOBS)
      echo "[pre-write-language-policy] DENIED token+path mismatch producer=$POLARIS_PRODUCER path=$file_path (DP-226 strict)" >&2
      # Fall through to the language validator below.
      ;;
    TOKEN_NOT_UNIQUE)
      echo "[pre-write-language-policy] DENIED token uniqueness violated producer=$POLARIS_PRODUCER (DP-226)" >&2
      # Fall through.
      ;;
    TOKEN_UNKNOWN|NO_TABLE|"")
      echo "[pre-write-language-policy] DENIED token not in producer_tokens[] producer=$POLARIS_PRODUCER path=$file_path (DP-226 strict)" >&2
      # Fall through to the language validator below.
      ;;
  esac
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
