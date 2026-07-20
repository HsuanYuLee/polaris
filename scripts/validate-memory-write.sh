#!/usr/bin/env bash
# validate-memory-write.sh — memory write-time contract validator (DP-191 round 3).
#
# Modes:
#   --candidate-path <path>           Path being written.
#   --candidate-content <-|file>      Reconstructed candidate content. `-` reads stdin.
#                                     Omit for direct-on-disk validation of <path>.
#   --memory-dir <dir>                Override memory directory (else derived from
#                                     candidate-path's nearest `memory/` ancestor,
#                                     falling back to POLARIS_MEMORY_DIR).
#   --today YYYY-MM-DD                Test override for "today".
#   --hot-soft-limit N                Test override (default 15).
#
# Checks (only when candidate-path is under a memory dir):
#   - Direct write to MEMORY.md → fail-stop (exit 2), unless
#     POLARIS_MEMORY_HYGIENE_APPLY=1 (apply / regenerate path).
#   - Frontmatter required fields: name, description, type, created.
#   - pinned: true → pinned_reason: required non-empty.
#   - topic: <slug> → either folder memory_dir/<slug>/ exists, OR the file is
#     already inside memory_dir/<slug>/.
#   - Adding/updating candidate would push Hot count > soft limit.
#     Files (and the candidate itself) carrying `hot_overflow_demoted: true`
#     are treated as NOT Hot and excluded from the 15-cap (DP-282). The signal
#     is written by `memory-hygiene-tiering.py apply` on flat-root files demoted
#     out of Hot; Hot membership stays a cheap flat-frontmatter-only model with
#     no MEMORY.md index parse.
#
# Exit codes:
#   0  PASS
#   2  Contract violation (structured stderr; see lines starting with POLARIS_*).
#   3  Usage error.
#
# Bypass:
#   POLARIS_MEMORY_HYGIENE_APPLY=1   Skip all checks (canonical hygiene / regenerate path).

set -euo pipefail

usage() {
  sed -n '2,32p' "${BASH_SOURCE[0]}"
}

CANDIDATE_PATH=""
CANDIDATE_CONTENT_SRC=""
MEMORY_DIR_OVERRIDE=""
TODAY_OVERRIDE=""
HOT_SOFT_LIMIT="${POLARIS_MEMORY_HOT_SOFT_LIMIT:-15}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate-path) CANDIDATE_PATH="$2"; shift 2;;
    --candidate-content) CANDIDATE_CONTENT_SRC="$2"; shift 2;;
    --memory-dir) MEMORY_DIR_OVERRIDE="$2"; shift 2;;
    --today) TODAY_OVERRIDE="$2"; shift 2;;
    --hot-soft-limit) HOT_SOFT_LIMIT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "validate-memory-write: unknown arg: $1" >&2; usage >&2; exit 3;;
  esac
done

if [[ -z "$CANDIDATE_PATH" ]]; then
  echo "validate-memory-write: --candidate-path is required" >&2
  exit 3
fi

if [[ "${POLARIS_MEMORY_HYGIENE_APPLY:-}" == "1" ]]; then
  exit 0
fi

CANDIDATE_CONTENT=""
if [[ -n "$CANDIDATE_CONTENT_SRC" ]]; then
  if [[ "$CANDIDATE_CONTENT_SRC" == "-" ]]; then
    CANDIDATE_CONTENT="$(cat)"
  else
    if [[ ! -f "$CANDIDATE_CONTENT_SRC" ]]; then
      echo "validate-memory-write: candidate-content file not found: $CANDIDATE_CONTENT_SRC" >&2
      exit 3
    fi
    CANDIDATE_CONTENT="$(cat "$CANDIDATE_CONTENT_SRC")"
  fi
else
  # Default: read from disk (post-write inspection mode).
  if [[ -f "$CANDIDATE_PATH" ]]; then
    CANDIDATE_CONTENT="$(cat "$CANDIDATE_PATH")"
  fi
fi

export POLARIS_VALIDATE_MEMORY_WRITE__CANDIDATE_PATH="$CANDIDATE_PATH"
export POLARIS_VALIDATE_MEMORY_WRITE__MEMORY_DIR_OVERRIDE="$MEMORY_DIR_OVERRIDE"
export POLARIS_VALIDATE_MEMORY_WRITE__TODAY_OVERRIDE="$TODAY_OVERRIDE"
export POLARIS_VALIDATE_MEMORY_WRITE__HOT_SOFT_LIMIT="$HOT_SOFT_LIMIT"
# Pass content via env to avoid shell-escaping multi-line YAML.
export POLARIS_VALIDATE_MEMORY_WRITE__CONTENT="$CANDIDATE_CONTENT"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/validate_memory_write_1.py"
