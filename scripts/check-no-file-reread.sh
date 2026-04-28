#!/usr/bin/env bash
# scripts/check-no-file-reread.sh
#
# Purpose: Track per-file Read counts per session and warn when the same file
#          is read more than twice (unless modified). Rule
#          (rules/context-monitoring.md § 3 Avoid Re-Reading Files) says note
#          key info from a Read and reference it directly later.
#
# Canary: no-file-reread (legacy Claude Code L1 hook retired; script kept for
#         historical/manual diagnostics)
#
# Mode: Advisory only. Exit 0 always; warning emitted on stdout on the
#       3rd-or-later Read of the same absolute path.
#
# Heuristic for "unless modified":
#   If the file's mtime is newer than the last recorded Read timestamp for
#   that path, we treat the prior Reads as stale and reset the count to 1.
#
# Exit codes:
#   0 — always (stdout carries the advisory when threshold hit)
#
# State:
#   /tmp/polaris-file-reads.txt — one line per Read event:
#     <epoch_seconds>\t<read_count>\t<file_path>
#   Compacted to most-recent entry per path on each run.
#
# Usage:
#   check-no-file-reread.sh --file-path "<absolute_file_path>"

set -u

STATE_FILE="${POLARIS_FILE_READS_STATE:-/tmp/polaris-file-reads.txt}"
THRESHOLD=2  # warn when count STRICTLY exceeds this (i.e. at the 3rd read)

file_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path)
      file_path="${2:-}"
      shift 2
      ;;
    --file-path=*)
      file_path="${1#--file-path=}"
      shift
      ;;
    -h|--help)
      sed -n '2,32p' "$0" >&2
      exit 0
      ;;
    *)
      if [[ -z "$file_path" ]]; then
        file_path="$1"
      fi
      shift
      ;;
  esac
done

# Empty path → nothing to track → PASS silently.
if [[ -z "$file_path" ]]; then
  exit 0
fi

now_epoch=$(date +%s)

# Find prior entry for this path (latest), if any. Use awk directly — grep -F
# with newline-suffixed patterns can misbehave (newline splits alternation).
prior_line=""
if [[ -f "$STATE_FILE" ]]; then
  prior_line=$(awk -v p="$file_path" -F '\t' '$3 == p {last=$0} END{if(length(last)) print last}' "$STATE_FILE" 2>/dev/null || true)
fi

# Determine new count.
new_count=1
if [[ -n "$prior_line" ]]; then
  prior_epoch=$(printf '%s' "$prior_line" | awk -F '\t' '{print $1}')
  prior_count=$(printf '%s' "$prior_line" | awk -F '\t' '{print $2}')
  prior_epoch=${prior_epoch:-0}
  prior_count=${prior_count:-0}

  # Check file mtime vs prior Read timestamp.
  file_mtime=0
  if [[ -f "$file_path" ]]; then
    if stat -f %m "$file_path" >/dev/null 2>&1; then
      file_mtime=$(stat -f %m "$file_path")  # BSD (macOS)
    else
      file_mtime=$(stat -c %Y "$file_path")  # GNU (Linux)
    fi
  fi

  if (( file_mtime > prior_epoch )); then
    # File was modified since last Read — reset to 1.
    new_count=1
  else
    new_count=$((prior_count + 1))
  fi
fi

# Rewrite state file: remove any prior entry for this path, then append fresh.
if [[ -f "$STATE_FILE" ]]; then
  tmp_file=$(mktemp)
  awk -v p="$file_path" -F '\t' '$3 != p' "$STATE_FILE" > "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$STATE_FILE"
fi
printf '%s\t%s\t%s\n' "$now_epoch" "$new_count" "$file_path" >> "$STATE_FILE"

# Warn if threshold exceeded.
if (( new_count > THRESHOLD )); then
  cat <<EOF
📄 [no-file-reread] \`${file_path}\` read ${new_count} times this session (threshold ${THRESHOLD}).

Per rules/context-monitoring.md § 3, note key info from a Read and reference it directly — do not re-read the same unmodified file. If you need the file's structure multiple times, capture the essentials in a milestone summary.

Counter resets automatically when the file's mtime advances (i.e. the file was actually modified).
EOF
fi

exit 0
