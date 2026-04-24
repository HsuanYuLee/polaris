#!/usr/bin/env bash
# verification-evidence-gate.sh — PreToolUse hook
# Blocks `gh pr create` and `git push` (to task/fix branches on product repos)
# unless verification evidence exists for the ticket.
#
# Intercepts:
#   - `gh pr create` — all cases (original DP-029 behavior)
#   - `git push` — only task/* and fix/* branches on repos with codecov config (DP-031)
#
# Evidence file: /tmp/polaris-verified-{TICKET}.json
# Created by verify-completion skill or verify-http.sh wrapper.
# Must contain: { "ticket": "...", "timestamp": "...", "results": [...], "runtime_contract": {...} }
#
# The file is intentionally in /tmp (ephemeral) — each session must verify fresh.
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

# Determine which command we're intercepting
MODE=""
if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+create\b'; then
  MODE="pr-create"
elif printf '%s' "$command" | grep -qiE '^git[[:space:]]+((-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push|push)\b'; then
  MODE="push"
fi

[[ -n "$MODE" ]] || exit 0

# --- Push-specific filters: only block task/fix branches on product repos ---
if [[ "$MODE" == "push" ]]; then
  # Extract repo path from git -C <path> push, or use current dir
  push_repo=$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //')
  push_repo="${push_repo:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

  # Only intercept task/* and fix/* branches (skip wip/*, feat/*, main, develop)
  push_branch=$(git -C "${push_repo:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$push_branch" in
    task/*|fix/*) ;; # continue checking
    *) exit 0 ;;     # not a delivery branch, allow
  esac

  # Only intercept product repos (those with codecov config)
  has_codecov=false
  for cfg in codecov.yml .codecov.yml; do
    [[ -f "${push_repo:-.}/$cfg" ]] && has_codecov=true && break
  done
  # Also check .woodpecker/codecov.yml
  [[ -f "${push_repo:-.}/.woodpecker/codecov.yml" ]] && has_codecov=true

  if ! $has_codecov; then
    exit 0  # No CI coverage config — not a product repo, allow
  fi

  # Skip destructive/tag pushes
  if printf '%s' "$command" | grep -qE '\-\-delete|\-\-tags'; then
    exit 0
  fi
fi

# Bypass for non-ticket PRs (framework, docs, etc.)
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  exit 0
fi

# Extract ticket key from current branch name
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# For push mode, use the repo we already resolved
if [[ "$MODE" == "push" ]]; then
  branch="$push_branch"
fi
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
  echo "BLOCKED: Verification evidence file is malformed for ${ticket}" >&2
  echo "  ${evidence_file}: ${valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, timestamp, non-empty results, and runtime_contract." >&2
  echo "Use: scripts/polaris-write-evidence.sh --ticket ${ticket} --task-md <path> --result \"PASS: ...\"" >&2
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

# CI contract parity gate: if repo has Codecov patch gate, require fresh PASS coverage evidence.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)

# For push mode, use the repo we already resolved
if [[ "$MODE" == "push" && -n "${push_repo:-}" ]]; then
  repo_root="$push_repo"
fi
has_patch_gate=false
if [[ -n "$repo_root" ]]; then
  for cfg in codecov.yml .codecov.yml; do
    if [[ -f "$repo_root/$cfg" ]] && grep -qE '^[[:space:]]*-?[[:space:]]*type:[[:space:]]*patch' "$repo_root/$cfg"; then
      has_patch_gate=true
      break
    fi
  done
fi

if $has_patch_gate; then
  branch_slug=$(printf '%s' "$branch" | tr '/' '-')
  coverage_file="/tmp/polaris-coverage-${branch_slug}.json"

  if [[ ! -f "$coverage_file" ]]; then
    echo "BLOCKED: Missing CI contract coverage evidence for ${branch}" >&2
    echo "  Expected: ${coverage_file}" >&2
    echo "  Run: scripts/ci-contract-run.sh --repo ${repo_root} --skip-install --write-coverage-evidence" >&2
    exit 2
  fi

  coverage_valid=$(python3 -c "
import json
from datetime import datetime, timezone, timedelta
try:
    with open('${coverage_file}') as f:
        d = json.load(f)
    assert d.get('branch') == '${branch}', 'branch mismatch'
    assert str(d.get('status', '')).upper() == 'PASS', 'status is not PASS'
    ts = datetime.fromisoformat(str(d.get('timestamp', '')).replace('Z', '+00:00'))
    age = datetime.now(timezone.utc) - ts
    assert age <= timedelta(hours=4), f'stale: {age.total_seconds()/3600:.1f}h old'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

  if [[ "$coverage_valid" != "valid" ]]; then
    echo "BLOCKED: Invalid CI contract coverage evidence for ${branch}" >&2
    echo "  ${coverage_file}: ${coverage_valid}" >&2
    echo "  Re-run: scripts/ci-contract-run.sh --repo ${repo_root} --skip-install --write-coverage-evidence" >&2
    exit 2
  fi
fi

exit 0
