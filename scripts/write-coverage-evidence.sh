#!/usr/bin/env bash
# write-coverage-evidence.sh — Write coverage evidence file
#
# Called by engineering / engineer-delivery-flow Step 2 after running
# vitest --coverage on changed files. Consumed by .claude/hooks/coverage-gate.sh
# as the gate marker for git push.
#
# Usage:
#   write-coverage-evidence.sh --status PASS [--branch <name>] [--note "..."]
#   write-coverage-evidence.sh --status FAIL --note "uncovered lines: product.ts L120-125"
#
# Output: /tmp/polaris-coverage-{branch-slug}.json
#
# Schema:
#   {
#     "branch": "fix/KB2CW-3847-duplicate-fetch-product",
#     "status": "PASS | FAIL",
#     "timestamp": "2026-04-20T04:30:00Z",
#     "note": "...",
#     "patch_files": ["apps/main/api/product/product.ts", ...]
#   }
#
# Exit 0 = success, 1 = invalid args

set -euo pipefail

status=""
branch=""
note=""
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)  status="$2"; shift 2 ;;
    --branch)  branch="$2"; shift 2 ;;
    --note)    note="$2"; shift 2 ;;
    --file)    files+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$status" ]]; then
  echo "Error: --status is required (PASS|FAIL)" >&2
  exit 1
fi

status_upper=$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')
case "$status_upper" in
  PASS|FAIL) ;;
  *) echo "Error: --status must be PASS or FAIL (got: $status)" >&2; exit 1 ;;
esac

if [[ -z "$branch" ]]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

if [[ -z "$branch" ]]; then
  echo "Error: cannot detect branch — pass --branch <name>" >&2
  exit 1
fi

branch_slug=$(printf '%s' "$branch" | tr '/' '-')
output_file="/tmp/polaris-coverage-${branch_slug}.json"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON (Python for safe escaping)
python3 - "$output_file" "$branch" "$status_upper" "$timestamp" "$note" "${files[@]}" <<'PY'
import json, sys

output_file, branch, status, timestamp, note, *files = sys.argv[1:]

payload = {
    "branch": branch,
    "status": status,
    "timestamp": timestamp,
    "note": note,
    "patch_files": files,
}

with open(output_file, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)

print(f"Coverage evidence written: {output_file}")
print(f"  branch={branch}")
print(f"  status={status}")
if note:
    print(f"  note={note}")
if files:
    print(f"  patch_files={len(files)}")
PY
