#!/usr/bin/env bash
# polaris-write-evidence.sh — Write verification evidence file
# Called by verify-completion skill, fix-bug Step 4.5, or manually after verification.
#
# Usage:
#   polaris-write-evidence.sh --ticket KB2CW-1234 --result "PASS: AC1 breadcrumb position" [--result "PASS: AC2 ..."]
#   polaris-write-evidence.sh --ticket KB2CW-1234 --result "FAIL: AC3 missing entry" --result "PASS: AC1"
#   polaris-write-evidence.sh --ticket KB2CW-1234 --from-file /tmp/verify-results.txt
#   polaris-write-evidence.sh --ticket KB2CW-1234 --task-md specs/companies/kkday/GT-478/tasks/T9.md --result "PASS: runtime verify"
#
# Output: /tmp/polaris-verified-{TICKET}.json
#
# Exit 0 = success, 1 = invalid args

set -euo pipefail

ticket=""
results=()
from_file=""
level=""
runtime_target=""
verify_command=""
task_md=""

extract_markdown_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

extract_first_fenced_code_block() {
  awk '
    /^```/ {
      if (in_block == 0) { in_block=1; next }
      exit
    }
    in_block { print }
  '
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) ticket="$2"; shift 2 ;;
    --result) results+=("$2"); shift 2 ;;
    --from-file) from_file="$2"; shift 2 ;;
    --level) level="$2"; shift 2 ;;
    --runtime-target) runtime_target="$2"; shift 2 ;;
    --verify-command) verify_command="$2"; shift 2 ;;
    --task-md) task_md="$2"; shift 2 ;;
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

if [[ -n "$task_md" ]]; then
  if [[ ! -f "$task_md" ]]; then
    echo "Error: --task-md file not found: $task_md" >&2
    exit 1
  fi
  if [[ -z "$level" ]]; then
    level_line=$(grep -E '^\*\*Level\*\*: |^- \*\*Level\*\*: ' "$task_md" | head -n1 || true)
    level=$(echo "$level_line" | sed -E 's/.*\*\*Level\*\*: *([a-zA-Z]+).*/\1/' | tr '[:upper:]' '[:lower:]')
  fi
  if [[ -z "$runtime_target" ]]; then
    target_line=$(grep -E '^\*\*Runtime verify target\*\*: |^- \*\*Runtime verify target\*\*: ' "$task_md" | head -n1 || true)
    runtime_target=$(echo "$target_line" | sed -E 's/.*\*\*Runtime verify target\*\*: *//' | tr -d '\r' | xargs)
  fi
  if [[ -z "$verify_command" ]]; then
    verify_section=$(extract_markdown_section "$task_md" "## Verify Command")
    verify_command=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block | sed -E 's/[[:space:]]+$//' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs || true)
  fi
fi

output_file="/tmp/polaris-verified-${ticket}.json"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Build JSON
python3 -c "
import json, sys
from urllib.parse import urlparse
import re

ticket = '${ticket}'
timestamp = '${timestamp}'
branch = '${branch}'
level = '${level}'
runtime_target = '${runtime_target}'
verify_command = '${verify_command}'
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

if level or runtime_target or verify_command:
    runtime_target = runtime_target.strip()
    verify_command = verify_command.strip()
    verify_url_match = re.search(r'https?://[^\\s\"\\)\\'\\>]+', verify_command)
    verify_url = verify_url_match.group(0) if verify_url_match else ''
    evidence['runtime_contract'] = {
        'level': level,
        'runtime_verify_target': runtime_target,
        'runtime_verify_target_host': (urlparse(runtime_target).hostname or '').lower() if runtime_target.startswith('http') else '',
        'verify_command': verify_command,
        'verify_command_url': verify_url,
        'verify_command_url_host': (urlparse(verify_url).hostname or '').lower() if verify_url else '',
    }

with open('${output_file}', 'w') as f:
    json.dump(evidence, f, indent=2, ensure_ascii=False)

print(f'Evidence written: ${output_file}')
print(f'  {pass_count} PASS / {fail_count} FAIL / {skip_count} SKIP')
" "${results[@]}"
