#!/usr/bin/env bash
# Purpose: Refuse to remove a knowledge-face file that still holds content
#          available nowhere else.
# Inputs:  --removing <file>, one or more --available <file|dir>.
# Outputs: exit 0 when every line of the removed file is reachable elsewhere;
#          exit 1 listing the orphan lines otherwise.
#
# This exists because the same content living in two places is a duplicate right
# up until one side grows a section the other lacks — at which point deleting
# "the copy" destroys the only copy. Line counts do not reveal that; only the
# difference does.

set -euo pipefail

REMOVING=""
AVAILABLE=()

die() {
  # Description: print a POLARIS marker plus context to stderr and exit 1.
  # Args: $1 = marker, $2.. = message lines
  local marker="$1"
  shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage:
  check-knowledge-face-removal.sh --removing <file> --available <file|dir> [--available ...]

Every non-blank line of the removed file must appear in at least one available
source. Blank lines are ignored; nothing else is.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --removing)  REMOVING="${2:-}"; shift 2 ;;
    --available) AVAILABLE+=("${2:-}"); shift 2 ;;
    -h|--help)   usage ;;
    *)           echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REMOVING" ]] || usage
[[ ${#AVAILABLE[@]} -gt 0 ]] || usage
[[ -f "$REMOVING" ]] || die "POLARIS_KNOWLEDGE_FACE_REMOVING_MISSING" \
  "not a file: $REMOVING"

# A destination that does not exist would silently make every line an orphan,
# which reads as a scary failure caused by a typo. Fail on the typo instead.
for src in "${AVAILABLE[@]}"; do
  [[ -e "$src" ]] || die "POLARIS_KNOWLEDGE_FACE_AVAILABLE_MISSING" \
    "not a file or directory: $src"
done

HAYSTACK="$(mktemp)"
trap 'rm -f "$HAYSTACK"' EXIT
for src in "${AVAILABLE[@]}"; do
  if [[ -d "$src" ]]; then
    find "$src" -type f -print0 | xargs -0 cat >> "$HAYSTACK" 2>/dev/null || true
  else
    cat "$src" >> "$HAYSTACK"
  fi
done

ORPHANS="$(mktemp)"
trap 'rm -f "$HAYSTACK" "$ORPHANS"' EXIT
# Fixed-string, whole-line matching: a knowledge line is "available" only if it
# survives verbatim somewhere, not if it merely resembles something.
grep -vxF '' "$REMOVING" | sort -u | while IFS= read -r line; do
  grep -qxF -- "$line" "$HAYSTACK" || printf '%s\n' "$line"
done > "$ORPHANS"

count="$(wc -l < "$ORPHANS" | tr -d ' ')"
if [[ "$count" -gt 0 ]]; then
  {
    echo "POLARIS_KNOWLEDGE_FACE_ORPHAN_CONTENT"
    echo "$REMOVING holds $count line(s) reachable nowhere else; removing it would"
    echo "destroy the only copy. Move these first, then re-run:"
    echo
    sed 's/^/  /' "$ORPHANS"
  } >&2
  exit 1
fi

echo "PASS: every line of $REMOVING is reachable in the declared sources"
