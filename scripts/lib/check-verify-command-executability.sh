#!/usr/bin/env bash
# Purpose: DP-311 T6 (AC8 / AC-NEG7) — shared executability check for task.md
#          Verify Command / Test Command text. Single source of judgment for
#          BOTH derive-task-md-from-refinement-json.sh (write-time gate) and
#          validate-breakdown-ready.sh (readiness gate) — D9: derive and
#          readiness must share ONE helper; no second copy of this judgment.
#
#          Two fail-closed checks:
#            1. `bash -n` parse — the command text must be parseable bash.
#               (Catches e.g. the DP-252-T1 prose whose `Don't` apostrophe is an
#               unterminated quote.)
#            2. outside-quote CJK detection — any CJK character (ideographs,
#               CJK punctuation, fullwidth forms) OUTSIDE single/double quotes
#               marks prose masquerading as a command. This is the PRIMARY
#               interceptor: `bash -n` alone accepts a CJK bare word as a
#               command name (DP-252-T1 escalation evidence, EC11). Quoted CJK
#               patterns (e.g. `grep -q '既有未動'`) stay legal (EC10).
#
# Inputs:  command text on stdin (default) or via --file <path>;
#          --label <context> names the violating source in the marker.
# Outputs: exit 0 = executable; exit 2 = violation, stderr carries reasons plus
#          POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE:<label>; exit 1 = usage or
#          missing tool (POLARIS_TOOL_MISSING:<tool>).

set -euo pipefail

LABEL="verify-command"
FILE=""

usage() {
  cat >&2 <<'USAGE'
usage: check-verify-command-executability.sh [--label <context>] [--file <path>]

Reads verify/test command text from stdin (or --file) and fail-closes when the
text is not executable bash: `bash -n` parse failure, or CJK characters outside
single/double quotes (prose masquerading as a command). Quoted CJK patterns are
legal.

exit: 0 = executable, 2 = violation (+ POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE
marker on stderr), 1 = usage / missing tool.
USAGE
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "check-verify-command-executability: unknown argument: $1" >&2; usage ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 1
fi

if [[ -n "$FILE" ]]; then
  if [[ ! -f "$FILE" ]]; then
    echo "check-verify-command-executability: file not found: $FILE" >&2
    exit 1
  fi
  cmd_text="$(cat "$FILE")"
else
  cmd_text="$(cat)"
fi

violations=()

if [[ -z "${cmd_text//[$' \t\n']/}" ]]; then
  # Fail-closed: being asked to certify an empty command is a contract misuse,
  # not a pass. Callers skip absent fences themselves.
  violations+=("command text is empty")
else
  # Check 1: bash parse.
  if ! parse_err="$(printf '%s\n' "$cmd_text" | bash -n 2>&1)"; then
    violations+=("bash -n parse failed: $(printf '%s' "$parse_err" | tr '\n' ' ')")
  fi

  # Check 2: CJK outside quotes. A character-level quote-state machine (single
  # quote / double quote / backslash escape) over the raw text; CJK found while
  # NOT inside a quote is a violation. Comments are NOT exempt — the spec gates
  # on quote position only, and a prose line is prose whether or not it starts
  # with '#'. Ranges: CJK punctuation (U+3000-303F), ideographs (U+3400-4DBF,
  # U+4E00-9FFF, U+F900-FAFF), fullwidth forms (U+FF01-FF5E).
  # The command text travels via env var (NOT a pipe): `python3 -` consumes
  # stdin as the script body, so piping the text would silently feed nothing.
  cjk_hits="$(POLARIS_CHECK_CMD_TEXT="$cmd_text" python3 - <<'PY'
import os
import re

CJK_RE = re.compile(r"[　-〿㐀-䶿一-鿿豈-﫿！-～]")

text = os.environ.get("POLARIS_CHECK_CMD_TEXT", "")
state = None  # None = unquoted | "'" = single-quoted | '"' = double-quoted
lineno = 1
i = 0
hits = []
while i < len(text):
    ch = text[i]
    if ch == "\n":
        lineno += 1
        i += 1
        continue
    if state is None:
        if ch == "\\":
            i += 2
            continue
        if ch == "'":
            state = "'"
        elif ch == '"':
            state = '"'
        elif CJK_RE.match(ch):
            hits.append((lineno, ch))
    elif state == "'":
        if ch == "'":
            state = None
    elif state == '"':
        if ch == "\\":
            i += 2
            continue
        if ch == '"':
            state = None
    i += 1

for lineno, ch in hits:
    print(f"CJK outside quotes at line {lineno}: {ch}")
PY
)"
  if [[ -n "$cjk_hits" ]]; then
    while IFS= read -r hit_line; do
      [[ -n "$hit_line" ]] && violations+=("$hit_line")
    done <<<"$cjk_hits"
  fi
fi

if ((${#violations[@]} > 0)); then
  for v in "${violations[@]}"; do
    echo "check-verify-command-executability: $v" >&2
  done
  echo "POLARIS_VERIFY_COMMAND_NOT_EXECUTABLE:$LABEL" >&2
  exit 2
fi

exit 0
