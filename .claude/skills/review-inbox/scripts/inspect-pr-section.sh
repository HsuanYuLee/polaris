#!/usr/bin/env bash
# inspect-pr-section.sh — bounded inspection of review-inbox diff artifacts.

set -euo pipefail

RUNS_DIR="/tmp/review-inbox-runs"
RUN_ID=""
PR_NUMBER=""
START_LINE=""
END_LINE=""
MAX_LINES=100
HUNKS_ONLY=false

usage() {
  cat >&2 <<'EOF'
Usage:
  inspect-pr-section.sh --run-id ID --pr NUMBER [--start N --end N] [--max-lines N]
  inspect-pr-section.sh --run-id ID --pr NUMBER --hunks [--max-lines N]
  inspect-pr-section.sh --runs-dir PATH --run-id ID --pr NUMBER ...
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs-dir) RUNS_DIR="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --start) START_LINE="$2"; shift 2 ;;
    --end) END_LINE="$2"; shift 2 ;;
    --max-lines) MAX_LINES="$2"; shift 2 ;;
    --hunks) HUNKS_ONLY=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$RUN_ID" || -z "$PR_NUMBER" ]] && usage
if ! [[ "$MAX_LINES" =~ ^[0-9]+$ ]] || (( MAX_LINES < 1 || MAX_LINES > 100 )); then
  echo "inspect-pr-section: --max-lines must be 1..100" >&2
  exit 2
fi

diff_file="$RUNS_DIR/$RUN_ID/pr-$PR_NUMBER.diff"
if [[ ! -f "$diff_file" ]]; then
  echo "inspect-pr-section: diff artifact not found: $diff_file" >&2
  exit 1
fi

if [[ "$HUNKS_ONLY" == "true" ]]; then
  awk '/^(diff --git|@@ )/ { print }' "$diff_file" | head -n "$MAX_LINES"
  exit 0
fi

[[ -z "$START_LINE" || -z "$END_LINE" ]] && usage
if ! [[ "$START_LINE" =~ ^[0-9]+$ && "$END_LINE" =~ ^[0-9]+$ ]]; then
  echo "inspect-pr-section: --start and --end must be numeric" >&2
  exit 2
fi
if (( END_LINE < START_LINE )); then
  echo "inspect-pr-section: --end must be >= --start" >&2
  exit 2
fi
line_count=$(( END_LINE - START_LINE + 1 ))
if (( line_count > MAX_LINES )); then
  END_LINE=$(( START_LINE + MAX_LINES - 1 ))
fi

sed -n "${START_LINE},${END_LINE}p" "$diff_file"
