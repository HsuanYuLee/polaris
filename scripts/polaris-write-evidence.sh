#!/usr/bin/env bash
# polaris-write-evidence.sh — Write verification evidence file
# Called by verify-completion skill, fix-bug Step 4.5, or manually after verification.
#
# Usage:
#   polaris-write-evidence.sh --ticket KB2CW-1234 --result "PASS: AC1 breadcrumb position" [--result "PASS: AC2 ..."]
#   polaris-write-evidence.sh --ticket KB2CW-1234 --result "FAIL: AC3 missing entry" --result "PASS: AC1"
#   polaris-write-evidence.sh --ticket KB2CW-1234 --from-file /tmp/verify-results.txt
#
# Output: /tmp/polaris-verified-{TICKET}.json
#
# Exit 0 = success, 1 = invalid args

set -euo pipefail

ticket=""
results=()
from_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) ticket="$2"; shift 2 ;;
    --result) results+=("$2"); shift 2 ;;
    --from-file) from_file="$2"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ticket" ]]; then
  echo "Error: --ticket is required" >&2
  exit 1
fi

# Read results from file if specified
if [[ -n "$from_file" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" && ! "$line" =~ ^# ]] && results+=("$line")
  done < "$from_file"
fi

if [[ ${#results[@]} -eq 0 ]]; then
  echo "Error: at least one --result is required" >&2
  exit 1
fi

output_file="/tmp/polaris-verified-${ticket}.json"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Build JSON
python3 -c "
import json, sys

ticket = '${ticket}'
timestamp = '${timestamp}'
branch = '${branch}'
results_raw = sys.argv[1:]

results = []
pass_count = 0
fail_count = 0
skip_count = 0

for r in results_raw:
    if r.upper().startswith('PASS'):
        status = 'PASS'
        pass_count += 1
    elif r.upper().startswith('FAIL'):
        status = 'FAIL'
        fail_count += 1
    elif r.upper().startswith('SKIP'):
        status = 'SKIP'
        skip_count += 1
    else:
        status = 'UNKNOWN'
    results.append({'status': status, 'detail': r})

evidence = {
    'ticket': ticket,
    'timestamp': timestamp,
    'branch': branch,
    'summary': {
        'total': len(results),
        'pass': pass_count,
        'fail': fail_count,
        'skip': skip_count,
    },
    'results': results,
}

with open('${output_file}', 'w') as f:
    json.dump(evidence, f, indent=2, ensure_ascii=False)

print(f'Evidence written: ${output_file}')
print(f'  {pass_count} PASS / {fail_count} FAIL / {skip_count} SKIP')
" "${results[@]}"
