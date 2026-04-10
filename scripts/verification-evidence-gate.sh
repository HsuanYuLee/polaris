#!/usr/bin/env bash
# verification-evidence-gate.sh — PreToolUse hook
# Blocks `gh pr create` unless verification evidence exists for the ticket.
#
# Evidence file: /tmp/polaris-verified-{TICKET}.json
# Created by verify-completion skill or verify-http.sh wrapper.
# Must contain: { "ticket": "...", "timestamp": "...", "results": [...] }
#
# The file is intentionally in /tmp (ephemeral) — each session must verify fresh.
# POLARIS_PR_WORKFLOW=1 must also be set (checked by pr-create-guard.sh).
#
# Env:
#   POLARIS_SKIP_EVIDENCE=1  — bypass (for non-ticket PRs like framework changes)
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Only intercept gh pr create
printf '%s' "$command" | grep -qiE '^gh\s+pr\s+create\b' || exit 0

# Bypass for non-ticket PRs (framework, docs, etc.)
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  exit 0
fi

# Extract ticket key from current branch name
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
ticket=""

# Match patterns: task/KB2CW-1234-desc, feat/GT-521-desc, fix/KB2CW-1234
# Project keys may contain digits (e.g., KB2CW), so [A-Z][A-Z0-9]+ not [A-Z]+
if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
  ticket="${BASH_REMATCH[1]}"
fi

if [[ -z "$ticket" ]]; then
  # No ticket in branch name — likely a framework/docs PR, allow
  exit 0
fi

evidence_file="/tmp/polaris-verified-${ticket}.json"

if [[ ! -f "$evidence_file" ]]; then
  echo "BLOCKED: No verification evidence for ${ticket}" >&2
  echo "" >&2
  echo "Before creating a PR, run verify-completion to produce evidence:" >&2
  echo "  Evidence file expected at: ${evidence_file}" >&2
  echo "" >&2
  echo "The file must be created by verify-completion or polaris-write-evidence.sh," >&2
  echo "containing ticket, timestamp, and verification results." >&2
  echo "" >&2
  echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
  exit 2
fi

# Validate evidence file is not empty and has required fields
valid=$(python3 -c "
import json, sys
try:
    with open('${evidence_file}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${ticket}', 'ticket mismatch'
    assert d.get('timestamp'), 'missing timestamp'
    assert d.get('results') and len(d['results']) > 0, 'empty results'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

if [[ "$valid" != "valid" ]]; then
  echo "BLOCKED: Verification evidence file is malformed for ${ticket}" >&2
  echo "  ${evidence_file}: ${valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, timestamp, and non-empty results array." >&2
  exit 2
fi

# Check evidence age — must be from this session (< 4 hours old)
age_check=$(python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
with open('${evidence_file}') as f:
    d = json.load(f)
ts = datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00'))
age = datetime.now(timezone.utc) - ts
if age > timedelta(hours=4):
    print(f'stale: {age.total_seconds()/3600:.1f}h old')
else:
    print('fresh')
" 2>/dev/null || echo "fresh")

if [[ "$age_check" != "fresh" ]]; then
  echo "BLOCKED: Verification evidence is stale for ${ticket}" >&2
  echo "  ${evidence_file}: ${age_check}" >&2
  echo "  Re-run verify-completion to produce fresh evidence." >&2
  exit 2
fi

exit 0
