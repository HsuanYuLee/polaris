#!/usr/bin/env bash
# verification-evidence-gate.sh — PreToolUse hook (Dimension A only)
# Blocks `gh pr create` and `git push` (to task/fix branches on product repos)
# unless runtime/build verification evidence exists for the ticket.
#
# Intercepts:
#   - `gh pr create` — all cases (original DP-029 behavior)
#   - `git push` — only task/* and fix/* branches on repos with .claude/scripts/ci-local.sh
#     (DP-031 + DP-032 D12-c + DP-043: path relocated from scripts/ to .claude/scripts/)
#
# Evidence file (preferred, DP-032 Wave β D15):
#   /tmp/polaris-verified-{TICKET}-{HEAD_SHA}.json
#     - written by run-verify-command.sh
#     - head_sha-bound (auto-stale on rebase; no 4h age check needed)
#     - schema: { ticket, head_sha, writer, exit_code, at, level, ... }
#
# Evidence file (legacy, pre-D15):
#   /tmp/polaris-verified-{TICKET}.json
#     - written by polaris-write-evidence.sh / verify-completion skill
#     - 4-hour stale check + strict runtime_contract validation
#     - retained for backward compatibility during D15 rollout
#
# Writer whitelist: evidence `writer` field must be in
#   { run-verify-command.sh, polaris-write-evidence.sh }
# Missing `writer` field is treated as polaris-write-evidence.sh (legacy compat).
#
# Dimension B (ci-local mirror evidence) is enforced separately by ci-local-gate.sh
# (DP-032 D12-c). The two hooks both register on `gh pr create` + `git push` and
# share the same task/* + .claude/scripts/ci-local.sh filter for product-repo gating.
#
# Env:
#   POLARIS_SKIP_EVIDENCE=1  — bypass (for non-ticket PRs like framework changes)
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

# Single source of truth for the ci-local.sh repo-relative path (DP-043).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"

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
  push_repo=$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)
  push_repo="${push_repo:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

  # Only intercept task/* and fix/* branches (skip wip/*, feat/*, main, develop)
  push_branch=$(git -C "${push_repo:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$push_branch" in
    task/*|fix/*) ;; # continue checking
    *) exit 0 ;;     # not a delivery branch, allow
  esac

  # Only intercept repos with ci-local.sh (DP-032 D12-c + DP-043)
  if [[ ! -f "$(ci_local_path_for_repo "${push_repo:-.}")" ]]; then
    exit 0  # No ci-local.sh — repo not onboarded to D12 mirror, allow
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

# --- Resolve evidence file: prefer head_sha-bound (D15), fallback to legacy ----
EVIDENCE_FILE=""
EVIDENCE_FORMAT=""   # "new" or "legacy"

# Resolve repo root for head_sha lookup. For push mode, $push_repo is already set;
# otherwise use cwd. Best-effort — failure leaves head_sha empty and we fall back.
HEAD_SHA=""
gate_repo="${push_repo:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [[ -n "$gate_repo" ]] && [[ -d "$gate_repo/.git" || -f "$gate_repo/.git" ]]; then
  HEAD_SHA="$(git -C "$gate_repo" rev-parse HEAD 2>/dev/null || true)"
fi

new_evidence="/tmp/polaris-verified-${ticket}-${HEAD_SHA}.json"
legacy_evidence="/tmp/polaris-verified-${ticket}.json"

if [[ -n "$HEAD_SHA" && -f "$new_evidence" ]]; then
  EVIDENCE_FILE="$new_evidence"
  EVIDENCE_FORMAT="new"
elif [[ -f "$legacy_evidence" ]]; then
  EVIDENCE_FILE="$legacy_evidence"
  EVIDENCE_FORMAT="legacy"
else
  echo "BLOCKED: No verification evidence for ${ticket}" >&2
  echo "" >&2
  echo "Expected one of:" >&2
  echo "  ${new_evidence}      (DP-032 Wave β D15 — head_sha-bound, written by run-verify-command.sh)" >&2
  echo "  ${legacy_evidence}     (legacy — written by polaris-write-evidence.sh / verify-completion)" >&2
  echo "" >&2
  echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${ticket}] to produce evidence." >&2
  echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
  exit 2
fi

# --- Validate evidence per format ------------------------------------------
if [[ "$EVIDENCE_FORMAT" == "new" ]]; then
  # D15 schema (head_sha-bound, looser): ticket, head_sha, writer, exit_code, at
  # writer ∈ { run-verify-command.sh, polaris-write-evidence.sh } (whitelist)
  # No 4h stale check — head_sha self-binds freshness (rebase invalidates filename)
  valid=$(python3 -c "
import json
WHITELIST = {'run-verify-command.sh', 'polaris-write-evidence.sh'}
try:
    with open('${EVIDENCE_FILE}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${ticket}', 'ticket mismatch'
    assert d.get('head_sha') == '${HEAD_SHA}', 'head_sha mismatch'
    writer = d.get('writer', 'polaris-write-evidence.sh')  # default = legacy writer
    assert writer in WHITELIST, f'writer not in whitelist: {writer!r}'
    assert 'exit_code' in d, 'missing exit_code'
    assert isinstance(d['exit_code'], int), 'exit_code must be int'
    assert d.get('at'), 'missing at'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

  if [[ "$valid" != "valid" ]]; then
    echo "BLOCKED: head_sha-bound evidence file is malformed for ${ticket}" >&2
    echo "  ${EVIDENCE_FILE}: ${valid}" >&2
    echo "" >&2
    echo "Evidence must contain: ticket, head_sha, writer (whitelisted), exit_code, at." >&2
    echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${ticket}" >&2
    exit 2
  fi

  # exit_code must be 0 — verify command must have passed
  exit_code_pass=$(python3 -c "
import json
with open('${EVIDENCE_FILE}') as f:
    d = json.load(f)
print('pass' if int(d.get('exit_code', -1)) == 0 else 'fail')
" 2>/dev/null || echo "fail")
  if [[ "$exit_code_pass" != "pass" ]]; then
    echo "BLOCKED: Verification evidence shows verify command FAIL for ${ticket}" >&2
    echo "  ${EVIDENCE_FILE}: exit_code != 0" >&2
    echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
    exit 2
  fi
else
  # Legacy schema (timestamp-based, 4h stale check, strict runtime_contract)
  valid=$(python3 -c "
import json
WHITELIST = {'run-verify-command.sh', 'polaris-write-evidence.sh'}
try:
    with open('${EVIDENCE_FILE}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${ticket}', 'ticket mismatch'
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
    echo "BLOCKED: Legacy verification evidence file is malformed for ${ticket}" >&2
    echo "  ${EVIDENCE_FILE}: ${valid}" >&2
    echo "" >&2
    echo "Evidence must contain: ticket, timestamp, non-empty results, runtime_contract, writer (whitelisted)." >&2
    echo "Use: scripts/polaris-write-evidence.sh --ticket ${ticket} --task-md <path> --result \"PASS: ...\"" >&2
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
    echo "BLOCKED: Legacy verification evidence is stale for ${ticket}" >&2
    echo "  ${EVIDENCE_FILE}: ${age_check}" >&2
    echo "  Re-run verify-completion (or migrate to scripts/run-verify-command.sh)." >&2
    exit 2
  fi
fi

# Dimension B (ci-local mirror evidence) is handled by ci-local-gate.sh — DP-032 D12-c

exit 0
