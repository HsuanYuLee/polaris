#!/usr/bin/env bash
set -euo pipefail

# gate-evidence.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from scripts/verification-evidence-gate.sh for cross-LLM portability.
# Can be called from: git pre-commit/pre-push hooks, polaris-pr-create.sh, or directly.
#
# Usage:
#   bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_EVIDENCE=1

PREFIX="[polaris gate-evidence]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
TICKET=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --ticket) TICKET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>]"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>    JIRA ticket key (default: extract from branch name)"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Default repo
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Bypass
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_EVIDENCE=1 — bypassing." >&2
  exit 0
fi

# Extract ticket from branch if not provided
if [[ -z "$TICKET" ]]; then
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
  fi
fi

# No ticket → framework/docs PR, allow
if [[ -z "$TICKET" ]]; then
  exit 0
fi

# Resolve HEAD SHA
HEAD_SHA=""
if [[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]]; then
  HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi

# --- Resolve evidence file: prefer head_sha-bound (D15), fallback to legacy ---
EVIDENCE_FILE=""
EVIDENCE_FORMAT=""

new_evidence="/tmp/polaris-verified-${TICKET}-${HEAD_SHA}.json"
legacy_evidence="/tmp/polaris-verified-${TICKET}.json"

if [[ -n "$HEAD_SHA" && -f "$new_evidence" ]]; then
  EVIDENCE_FILE="$new_evidence"
  EVIDENCE_FORMAT="new"
elif [[ -f "$legacy_evidence" ]]; then
  EVIDENCE_FILE="$legacy_evidence"
  EVIDENCE_FORMAT="legacy"
else
  echo "$PREFIX BLOCKED: No verification evidence for ${TICKET}" >&2
  echo "" >&2
  echo "Expected one of:" >&2
  echo "  ${new_evidence}  (D15 — head_sha-bound, written by run-verify-command.sh)" >&2
  echo "  ${legacy_evidence}  (legacy — written by polaris-write-evidence.sh)" >&2
  echo "" >&2
  echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${TICKET}] to produce evidence." >&2
  echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
  exit 2
fi

# --- Validate evidence per format ---
if [[ "$EVIDENCE_FORMAT" == "new" ]]; then
  # D15 schema: ticket, head_sha, writer (whitelisted), exit_code, at
  valid=$(python3 -c "
import json
WHITELIST = {'run-verify-command.sh', 'polaris-write-evidence.sh'}
try:
    with open('${EVIDENCE_FILE}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${TICKET}', 'ticket mismatch'
    assert d.get('head_sha') == '${HEAD_SHA}', 'head_sha mismatch'
    writer = d.get('writer', 'polaris-write-evidence.sh')
    assert writer in WHITELIST, f'writer not in whitelist: {writer!r}'
    assert 'exit_code' in d, 'missing exit_code'
    assert isinstance(d['exit_code'], int), 'exit_code must be int'
    assert d.get('at'), 'missing at'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

  if [[ "$valid" != "valid" ]]; then
    echo "$PREFIX BLOCKED: head_sha-bound evidence file is malformed for ${TICKET}" >&2
    echo "  ${EVIDENCE_FILE}: ${valid}" >&2
    echo "" >&2
    echo "Evidence must contain: ticket, head_sha, writer (whitelisted), exit_code, at." >&2
    echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${TICKET}" >&2
    exit 2
  fi

  # exit_code must be 0
  exit_code_pass=$(python3 -c "
import json
with open('${EVIDENCE_FILE}') as f:
    d = json.load(f)
print('pass' if int(d.get('exit_code', -1)) == 0 else 'fail')
" 2>/dev/null || echo "fail")

  if [[ "$exit_code_pass" != "pass" ]]; then
    echo "$PREFIX BLOCKED: Verification evidence shows FAIL for ${TICKET}" >&2
    echo "  ${EVIDENCE_FILE}: exit_code != 0" >&2
    echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
    exit 2
  fi

  echo "$PREFIX ✅ D15 evidence valid for ${TICKET} @ ${HEAD_SHA}." >&2
else
  # Legacy schema: ticket, timestamp, results, runtime_contract, writer
  valid=$(python3 -c "
import json
WHITELIST = {'run-verify-command.sh', 'polaris-write-evidence.sh'}
try:
    with open('${EVIDENCE_FILE}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${TICKET}', 'ticket mismatch'
    assert d.get('timestamp'), 'missing timestamp'
    assert d.get('results') and len(d['results']) > 0, 'empty results'
    writer = d.get('writer', 'polaris-write-evidence.sh')
    assert writer in WHITELIST, f'writer not in whitelist: {writer!r}'
    rc = d.get('runtime_contract')
    assert isinstance(rc, dict), 'missing runtime_contract'
    level = str(rc.get('level', '')).lower()
    assert level in ('static', 'build', 'runtime'), 'runtime_contract.level must be static|build|runtime'
    if level == 'runtime':
        target = str(rc.get('runtime_verify_target', '')).strip()
        assert target and target.lower() != 'n/a', 'runtime level requires runtime_verify_target'
        assert target.startswith('http://') or target.startswith('https://'), 'runtime_verify_target must be live URL'
        verify_url = str(rc.get('verify_command_url', '')).strip()
        assert verify_url, 'runtime level requires verify_command_url'
        target_host = str(rc.get('runtime_verify_target_host', '')).strip().lower()
        verify_host = str(rc.get('verify_command_url_host', '')).strip().lower()
        assert target_host and verify_host, 'unable to parse runtime hosts'
        assert target_host == verify_host, f'host mismatch: target={target_host}, verify={verify_host}'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

  if [[ "$valid" != "valid" ]]; then
    echo "$PREFIX BLOCKED: Legacy evidence file is malformed for ${TICKET}" >&2
    echo "  ${EVIDENCE_FILE}: ${valid}" >&2
    echo "" >&2
    echo "Evidence must contain: ticket, timestamp, non-empty results, runtime_contract, writer (whitelisted)." >&2
    echo "Use: scripts/polaris-write-evidence.sh --ticket ${TICKET} --task-md <path> --result \"PASS: ...\"" >&2
    exit 2
  fi

  # Legacy: 4-hour staleness check
  age_check=$(python3 -c "
import json
from datetime import datetime, timezone, timedelta
with open('${EVIDENCE_FILE}') as f:
    d = json.load(f)
ts = datetime.fromisoformat(d['timestamp'].replace('Z', '+00:00'))
age = datetime.now(timezone.utc) - ts
if age > timedelta(hours=4):
    print(f'stale: {age.total_seconds()/3600:.1f}h old')
else:
    print('fresh')
" 2>/dev/null || echo "fresh")

  if [[ "$age_check" != "fresh" ]]; then
    echo "$PREFIX BLOCKED: Legacy evidence is stale for ${TICKET}" >&2
    echo "  ${EVIDENCE_FILE}: ${age_check}" >&2
    echo "  Re-run verify-completion (or migrate to scripts/run-verify-command.sh)." >&2
    exit 2
  fi

  echo "$PREFIX ✅ Legacy evidence valid for ${TICKET}." >&2
fi

exit 0
