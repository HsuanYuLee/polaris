#!/usr/bin/env bash
# verify-http.sh — Deterministic HTTP verification
# Asserts HTTP 200 for given URLs. Non-200 = exit 1 = verification failed.
#
# Usage:
#   verify-http.sh <url> [<url2> ...]
#   verify-http.sh --file <url-list-file>
#
# Options:
#   --timeout <seconds>   Request timeout (default: 10)
#   --file <path>         Read URLs from file (one per line)
#   --header <header>     Add custom header (repeatable)
#   --allow <code>        Also accept this status code (repeatable, e.g., --allow 301)
#
# Output: TAB-separated lines: STATUS\tURL\tRESULT
# Exit: 0 if all URLs return 200 (or allowed codes), 1 if any fail

set -euo pipefail

timeout=10
urls=()
headers=()
allowed_codes=(200)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) timeout="$2"; shift 2 ;;
    --file)
      while IFS= read -r line; do
        [[ -n "$line" && ! "$line" =~ ^# ]] && urls+=("$line")
      done < "$2"
      shift 2
      ;;
    --header) headers+=(-H "$2"); shift 2 ;;
    --allow) allowed_codes+=("$2"); shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) urls+=("$1"); shift ;;
  esac
done

if [[ ${#urls[@]} -eq 0 ]]; then
  echo "Usage: verify-http.sh <url> [<url2> ...]" >&2
  exit 1
fi

failed=0
total=${#urls[@]}
passed=0

for url in "${urls[@]}"; do
  status=$(curl -s -o /dev/null -w '%{http_code}' \
    --max-time "$timeout" \
    --location \
    "${headers[@]+"${headers[@]}"}" \
    "$url" 2>/dev/null || echo "000")

  is_allowed=false
  for code in "${allowed_codes[@]}"; do
    if [[ "$status" == "$code" ]]; then
      is_allowed=true
      break
    fi
  done

  if [[ "$is_allowed" == "true" ]]; then
    result="PASS"
    ((passed++))
  else
    result="FAIL"
    ((failed++))
  fi

  printf '%s\t%s\t%s\n' "$status" "$url" "$result"
done

echo ""
echo "Results: ${passed}/${total} passed, ${failed}/${total} failed"

if [[ $failed -gt 0 ]]; then
  echo "VERIFICATION FAILED — ${failed} URL(s) did not return HTTP 200" >&2
  exit 1
fi

exit 0
