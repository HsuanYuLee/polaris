#!/usr/bin/env bash
# Purpose: Canonical writer for the cross-session active-thread anchor file
#          (.claude/active-thread.md). DP-300 T3 upgrades the single-body
#          overwrite into a per-thread-key upsert: each parked thread is stored
#          under an explicit key, so writing a second thread does NOT clobber the
#          first. Re-writing the same key with identical content is byte-idempotent.
#          --done / --remove drops a key's section. The legacy keyless path
#          (single implicit "default" thread) renders byte-exactly as the
#          pre-DP-300 flat anchor so existing single-thread flows regress green.
#          Stamps a last-updated ISO8601 line. Enforces the 10,000-char
#          SessionStart payload guard (DP-290 D5) by truncating the TAIL while
#          preserving the HEAD (the「下一步」/next-step leading section).
# Inputs:  --key <KEY>            Thread key to upsert / remove (default: "default").
#          --content <text>       New thread body (or stdin / first positional arg).
#          --done | --remove      Drop the named key's section instead of upserting.
#          Anchor path resolves via ${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}.
# Outputs: Writes .claude/active-thread.md; prints the resolved anchor path to stdout.
#          Exit 0 on success, exit 2 on contract violation (no input / no project dir).

set -euo pipefail

MAX_CHARS=10000
TRUNCATION_NOTICE='> [truncated by update-active-thread.sh: tail removed, head「下一步」preserved; full detail kept in session memory]'
DEFAULT_KEY='default'

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/update-active-thread.sh --content "<body>"
  bash scripts/update-active-thread.sh --key DP-298 --content "<body>"
  printf '%s' "<body>" | bash scripts/update-active-thread.sh --key DP-298
  bash scripts/update-active-thread.sh --key DP-298 --done      # remove a key
  bash scripts/update-active-thread.sh --key DP-298 --remove    # alias of --done

Maintains the canonical .claude/active-thread.md anchor as a per-thread-key
upsert (multi-thread, idempotent, 10k guard). The keyless path is the legacy
single-thread overwrite and renders flat (no delimiters).
USAGE
}

CONTENT=""
HAVE_CONTENT=0
KEY=""
HAVE_KEY=0
REMOVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --content)
      [[ $# -ge 2 ]] || { echo "[update-active-thread] --content requires a value" >&2; exit 2; }
      CONTENT="$2"
      HAVE_CONTENT=1
      shift 2
      ;;
    --key)
      [[ $# -ge 2 ]] || { echo "[update-active-thread] --key requires a value" >&2; exit 2; }
      KEY="$2"
      HAVE_KEY=1
      shift 2
      ;;
    --done|--remove)
      REMOVE=1
      shift
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

# A key must contain no whitespace and no delimiter-breaking characters so the
# section markers stay grep/awk-safe.
if [[ "$HAVE_KEY" -eq 1 ]]; then
  if [[ -z "$KEY" ]] || [[ "$KEY" =~ [[:space:]] ]]; then
    echo "[update-active-thread] --key must be a non-empty token without whitespace" >&2
    exit 2
  fi
fi
EFFECTIVE_KEY="${KEY:-$DEFAULT_KEY}"

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

# Section delimiters for keyed threads. Kept on their own lines so a flat awk
# state machine can split / re-assemble sections without a real parser.
open_marker() { printf '<!-- thread:%s -->' "$1"; }
close_marker() { printf '<!-- /thread:%s -->' "$1"; }

# --- Read existing keyed sections from the current anchor (if any) ---
# Populates parallel arrays: EXIST_KEYS[] (ordered) and EXIST_BODIES[] (body
# text, no trailing newline). The legacy flat anchor (no delimiters) is read as
# a single DEFAULT_KEY section so a keyless rewrite stays in flat form.
EXIST_KEYS=()
EXIST_BODIES=()

read_existing() {
  [[ -f "$ANCHOR_FILE" ]] || return 0
  # Strip the leading "last-updated:" stamp line + the single blank line that
  # follows it, leaving the section payload.
  local payload
  payload="$(tail -n +2 "$ANCHOR_FILE")"
  # Drop exactly one leading blank line (the stamp separator).
  if [[ "${payload:0:1}" == $'\n' ]]; then
    payload="${payload:1}"
  fi

  if ! grep -q '^<!-- thread:' "$ANCHOR_FILE"; then
    # Legacy flat anchor: whole payload is the default thread body.
    EXIST_KEYS+=("$DEFAULT_KEY")
    EXIST_BODIES+=("$payload")
    return 0
  fi

  # Keyed anchor: re-emit the file as a stream of single-char-tagged lines so a
  # bash loop can reconstruct each section without a NUL-free run-on problem.
  # Tag K<key>  : opens a section with the given key.
  # Tag B<line> : one body line (blank lines included, preserved verbatim).
  # Tag E       : closes the current section.
  # Body lines are emitted line-by-line (one awk record each), so the run-on
  # bug from concatenating body + sentinel on the same record cannot occur.
  local tagged
  tagged="$(awk '
    /^<!-- thread:.* -->$/ {
      key=$0; sub(/^<!-- thread:/, "", key); sub(/ -->$/, "", key)
      print "K" key
      inbody=1; next
    }
    /^<!-- \/thread:.* -->$/ { if (inbody==1) print "E"; inbody=0; next }
    inbody==1 { print "B" $0 }
  ' "$ANCHOR_FILE")"

  local cur_key="" cur_body="" in_body=0 have_body=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "${line:0:1}" in
      K)
        cur_key="${line:1}"
        cur_body=""
        in_body=1
        have_body=0
        ;;
      E)
        if [[ "$in_body" -eq 1 ]]; then
          EXIST_KEYS+=("$cur_key")
          EXIST_BODIES+=("$cur_body")
        fi
        in_body=0
        ;;
      B)
        if [[ "$in_body" -eq 1 ]]; then
          if [[ "$have_body" -eq 0 ]]; then
            cur_body="${line:1}"
            have_body=1
          else
            cur_body="$cur_body"$'\n'"${line:1}"
          fi
        fi
        ;;
    esac
  done <<<"$tagged"
}

read_existing

# --- Resolve content for upsert mode ---
if [[ "$REMOVE" -eq 0 ]]; then
  if [[ "$HAVE_CONTENT" -eq 0 ]]; then
    if [[ -t 0 ]]; then
      echo "[update-active-thread] no content provided (stdin/--content/arg empty)" >&2
      exit 2
    fi
    CONTENT="$(cat)"
  fi
fi

# --- Apply the upsert / remove against the existing key set ---
NEW_KEYS=()
NEW_BODIES=()
FOUND=0
for i in "${!EXIST_KEYS[@]}"; do
  if [[ "${EXIST_KEYS[$i]}" == "$EFFECTIVE_KEY" ]]; then
    FOUND=1
    if [[ "$REMOVE" -eq 1 ]]; then
      continue   # drop this section
    fi
    NEW_KEYS+=("$EFFECTIVE_KEY")
    NEW_BODIES+=("$CONTENT")
  else
    NEW_KEYS+=("${EXIST_KEYS[$i]}")
    NEW_BODIES+=("${EXIST_BODIES[$i]}")
  fi
done

if [[ "$REMOVE" -eq 1 ]]; then
  if [[ "$FOUND" -eq 0 ]]; then
    echo "[update-active-thread] key '$EFFECTIVE_KEY' not present; nothing to remove" >&2
  fi
else
  if [[ "$FOUND" -eq 0 ]]; then
    NEW_KEYS+=("$EFFECTIVE_KEY")
    NEW_BODIES+=("$CONTENT")
  fi
fi

# --- Render the new anchor body ---
# Legacy flat form is preserved byte-exactly when the only remaining thread is
# the implicit default key AND the caller did not opt into explicit keying. This
# keeps single-thread flows (and the DP-290 selftest) byte-identical.
render_flat() {
  printf '%s\n\n%s\n' "$STAMP_LINE" "$1"
}

render_keyed() {
  local out="$STAMP_LINE"$'\n'
  local i
  for i in "${!NEW_KEYS[@]}"; do
    out+=$'\n'"$(open_marker "${NEW_KEYS[$i]}")"$'\n'
    out+="${NEW_BODIES[$i]}"$'\n'
    out+="$(close_marker "${NEW_KEYS[$i]}")"$'\n'
  done
  printf '%s' "$out"
}

if [[ "${#NEW_KEYS[@]}" -eq 0 ]]; then
  # All threads removed: write a stamp-only anchor (no body).
  FILE_CONTENT="$(printf '%s\n' "$STAMP_LINE")"
elif [[ "${#NEW_KEYS[@]}" -eq 1 && "${NEW_KEYS[0]}" == "$DEFAULT_KEY" && "$HAVE_KEY" -eq 0 ]]; then
  # Legacy single-thread flat form.
  FILE_CONTENT="$(render_flat "${NEW_BODIES[0]}")"
else
  FILE_CONTENT="$(render_keyed)"
fi

# The trailing newline is appended at write time via printf '%s\n'; the rendered
# FILE_CONTENT above already ends without it. 10k guard counts that final \n.
BODY_BLOCK="$FILE_CONTENT"

# 10,000-char guard (AC3): truncate TAIL, preserve HEAD + truncation notice.
if [[ $(( ${#BODY_BLOCK} + 1 )) -gt "$MAX_CHARS" ]]; then
  NOTICE_BLOCK="$(printf '\n%s' "$TRUNCATION_NOTICE")"
  budget=$(( MAX_CHARS - ${#NOTICE_BLOCK} - 1 ))
  if [[ "$budget" -lt 0 ]]; then
    budget=0
  fi
  HEAD_KEEP="${BODY_BLOCK:0:budget}"
  BODY_BLOCK="${HEAD_KEEP}${NOTICE_BLOCK}"
  echo "[update-active-thread] anchor input exceeded ${MAX_CHARS} chars; tail truncated, head preserved" >&2
fi

# Overwrite (never append) — idempotent for identical key set modulo timestamp.
printf '%s\n' "$BODY_BLOCK" >"$ANCHOR_FILE"

printf '%s\n' "$ANCHOR_FILE"
