#!/bin/bash
set -eo pipefail

# ─── JIRA Attachment Uploader ───
# Uploads file(s) to a JIRA issue and returns attachment metadata (id, filename, url).
# Shared across skills (VR screenshots, test reports, design docs).
#
# Usage:
#   jira-upload-attachment.sh <issue-key> <file> [file2 ...]
#   jira-upload-attachment.sh KB2CW-3653 /tmp/screenshot.png
#   jira-upload-attachment.sh GT-483 ./diff-homepage-desktop.png ./diff-homepage-mobile.png
#
# Output (JSON per file, one per line):
#   {"filename":"screenshot.png","id":"12345","url":"https://kkday.atlassian.net/rest/api/3/attachment/content/12345"}
#
# Env:
#   JIRA_EMAIL      — Atlassian account email (from {company}/.env.secrets)
#   JIRA_API_TOKEN  — Atlassian API token (from {company}/.env.secrets)
#   JIRA_SITE       — Atlassian site URL (default: https://kkday.atlassian.net)
#
# Secrets file auto-detection:
#   Searches for .env.secrets in: $POLARIS_COMPANY_DIR, workspace dirs, ~/work/kkday/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Load credentials ──
load_credentials() {
  # Already set via env
  if [[ -n "$JIRA_EMAIL" && -n "$JIRA_API_TOKEN" ]]; then return 0; fi

  # Search for .env.secrets
  local search_dirs=(
    "${POLARIS_COMPANY_DIR:-}"
    "$SCRIPT_DIR/../kkday"
    "$HOME/work/kkday"
  )

  for dir in "${search_dirs[@]}"; do
    [[ -z "$dir" ]] && continue
    local secrets="$dir/.env.secrets"
    if [[ -f "$secrets" ]]; then
      # shellcheck disable=SC1090
      source "$secrets"
      return 0
    fi
  done

  echo "ERROR: JIRA credentials not found. Set JIRA_EMAIL + JIRA_API_TOKEN or create .env.secrets" >&2
  return 1
}

# ── Upload a single file ──
upload_file() {
  local issue_key="$1" filepath="$2"
  local site="${JIRA_SITE:-https://kkday.atlassian.net}"
  local filename; filename="$(basename "$filepath")"

  if [[ ! -f "$filepath" ]]; then
    echo "ERROR: File not found: $filepath" >&2
    return 1
  fi

  local response
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "X-Atlassian-Token: no-check" \
    -F "file=@$filepath" \
    "$site/rest/api/3/issue/$issue_key/attachments" 2>/dev/null)

  local http_code; http_code=$(echo "$response" | tail -1)
  local body; body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: Upload failed (HTTP $http_code) for $filename: $body" >&2
    return 1
  fi

  # Parse response — JIRA returns array of attachment objects
  echo "$body" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for att in data:
    print(json.dumps({
        'filename': att['filename'],
        'id': att['id'],
        'url': att['content'],
        'thumbnail': att.get('thumbnail', ''),
        'mimeType': att.get('mimeType', ''),
    }))
" 2>/dev/null
}

# ── Main ──
main() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <issue-key> <file> [file2 ...]" >&2
    exit 1
  fi

  local issue_key="$1"; shift

  load_credentials || exit 1

  local success=0 fail=0
  for filepath in "$@"; do
    if upload_file "$issue_key" "$filepath"; then
      success=$((success + 1))
    else
      fail=$((fail + 1))
    fi
  done

  echo "---" >&2
  echo "Uploaded: $success, Failed: $fail" >&2
  [[ $fail -eq 0 ]] || exit 1
}

main "$@"
