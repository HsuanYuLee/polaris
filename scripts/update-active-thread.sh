#!/usr/bin/env bash
# Purpose: Single canonical writer for the cross-session active-thread anchor file
#          (.claude/active-thread.md). Overwrites (never appends) so repeated calls
#          with identical input are byte-idempotent. Stamps a last-updated ISO8601
#          line. Enforces the 10,000-char SessionStart payload guard (DP-290 D5) by
#          truncating the TAIL while preserving the HEAD (the「下一步」/next-step
#          leading section) and appending a truncation notice.
# Inputs:  New anchor body from stdin, or via --content <text> / first positional arg.
#          Anchor path resolves via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}.
# Outputs: Writes .claude/active-thread.md; prints the resolved anchor path to stdout.
#          Exit 0 on success, exit 2 on contract violation (no input / no project dir).

set -euo pipefail

MAX_CHARS=10000
TRUNCATION_NOTICE='> [truncated by update-active-thread.sh: tail removed, head「下一步」preserved; full detail kept in session memory]'

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/update-active-thread.sh --content "<body>"
  printf '%s' "<body>" | bash scripts/update-active-thread.sh
  bash scripts/update-active-thread.sh "<body>"

Writes the canonical .claude/active-thread.md anchor (overwrite, idempotent, 10k guard).
USAGE
}

CONTENT=""
HAVE_CONTENT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --content)
      [[ $# -ge 2 ]] || { echo "[update-active-thread] --content requires a value" >&2; exit 2; }
      CONTENT="$2"
      HAVE_CONTENT=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      CONTENT="$1"
      HAVE_CONTENT=1
      shift
      ;;
  esac
done

# Fall back to stdin when no --content / positional arg was supplied.
if [[ "$HAVE_CONTENT" -eq 0 ]]; then
  if [[ -t 0 ]]; then
    echo "[update-active-thread] no content provided (stdin/--content/arg empty)" >&2
    exit 2
  fi
  CONTENT="$(cat)"
fi

# Resolve the in-project anchor directory deterministically.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_DIR" ]]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_DIR" ]]; then
  echo "[update-active-thread] cannot resolve project dir (set CLAUDE_PROJECT_DIR or run inside a git repo)" >&2
  exit 2
fi

ANCHOR_DIR="$PROJECT_DIR/.claude"
ANCHOR_FILE="$ANCHOR_DIR/active-thread.md"
mkdir -p "$ANCHOR_DIR"

# Allow the caller (e.g. selftest) to pin the stamp for byte-exact idempotency
# assertions via POLARIS_ACTIVE_THREAD_STAMP; default to current UTC time.
STAMP="${POLARIS_ACTIVE_THREAD_STAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
STAMP_LINE="last-updated: $STAMP"

# Compose the candidate file: stamp line + blank line + body.
BODY_BLOCK="$(printf '%s\n\n%s\n' "$STAMP_LINE" "$CONTENT")"

# 10,000-char guard (AC3): if the composed file exceeds MAX_CHARS, truncate the
# TAIL and preserve the HEAD plus a truncation notice; keep total length <= MAX_CHARS.
# The final write appends one trailing newline (printf '%s\n'); count it against
# the budget so the on-disk file length stays <= MAX_CHARS.
if [[ $(( ${#BODY_BLOCK} + 1 )) -gt "$MAX_CHARS" ]]; then
  # Reserve room for a leading newline + the truncation notice + the final
  # trailing newline added at write time.
  NOTICE_BLOCK="$(printf '\n%s' "$TRUNCATION_NOTICE")"
  budget=$(( MAX_CHARS - ${#NOTICE_BLOCK} - 1 ))
  if [[ "$budget" -lt 0 ]]; then
    budget=0
  fi
  HEAD_KEEP="${BODY_BLOCK:0:budget}"
  BODY_BLOCK="${HEAD_KEEP}${NOTICE_BLOCK}"
  echo "[update-active-thread] anchor input exceeded ${MAX_CHARS} chars; tail truncated, head preserved" >&2
fi

# Overwrite (never append) — idempotent for identical input modulo the timestamp.
printf '%s\n' "$BODY_BLOCK" >"$ANCHOR_FILE"

printf '%s\n' "$ANCHOR_FILE"
