#!/usr/bin/env bash
# quality-gate.sh — PreToolUse hook
# Blocks `git commit` unless quality evidence exists for the current branch.
#
# Evidence file: /tmp/polaris-quality-{branch}.json
# Created by pre-commit-quality.sh after lint + typecheck + test pass.
#
# Env:
#   POLARIS_SKIP_QUALITY=1  — bypass (for WIP commits, framework changes)
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Only intercept git commit (not git commit --amend for hooks, etc.)
printf '%s' "$command" | grep -qE '\bgit\b.*\bcommit\b' || exit 0

# Don't intercept git commit --amend (used by hooks and rebases)
# But DO intercept regular commits including amend by the user
# The key gate: any git commit should have quality evidence

# Bypass for WIP commits (commit message starts with "wip:")
if printf '%s' "$command" | grep -qiE -- '-m[[:space:]]+["\x27"]wip:'; then
  exit 0
fi

# Global bypass
if [[ "${POLARIS_SKIP_QUALITY:-}" == "1" ]]; then
  exit 0
fi

# Extract repo path from git -C <path> or use current dir
repo_dir=""
if printf '%s' "$command" | grep -qE 'git[[:space:]]+-C[[:space:]]+'; then
  repo_dir=$(printf '%s' "$command" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^ ]+).*/\1/p')
fi

# Get branch name
if [[ -n "$repo_dir" ]]; then
  branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
else
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

if [[ -z "$branch" ]]; then
  # Can't determine branch — allow (edge case)
  exit 0
fi

# Skip for main/develop (direct commits are rare but shouldn't be gated here)
if [[ "$branch" == "main" || "$branch" == "develop" || "$branch" == "master" ]]; then
  exit 0
fi

# Skip for Polaris framework repo (workspace root)
if [[ -n "$repo_dir" ]]; then
  repo_root=$(cd "$repo_dir" && git rev-parse --show-toplevel 2>/dev/null || true)
else
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi

if [[ "$repo_root" == "$HOME/work" ]]; then
  exit 0
fi

evidence_file="/tmp/polaris-quality-${branch}.json"

if [[ ! -f "$evidence_file" ]]; then
  echo "BLOCKED: No quality evidence for branch '${branch}'" >&2
  echo "" >&2
  echo "Before committing, run the quality check:" >&2
  echo "  scripts/pre-commit-quality.sh --repo ${repo_root:-<repo>}" >&2
  echo "" >&2
  echo "This runs lint + typecheck + test and writes evidence to:" >&2
  echo "  ${evidence_file}" >&2
  echo "" >&2
  echo "To bypass (WIP commit): use 'wip:' prefix in commit message" >&2
  echo "  or set POLARIS_SKIP_QUALITY=1" >&2
  exit 2
fi

# Validate evidence file
valid=$(python3 -c "
import json, sys
try:
    with open('${evidence_file}') as f:
        d = json.load(f)
    assert d.get('branch') == '${branch}', f\"branch mismatch: {d.get('branch')} != ${branch}\"
    assert d.get('timestamp'), 'missing timestamp'
    # Check if quality passed (bypassed counts as passed)
    if d.get('bypassed'):
        print('valid')
    elif d.get('all_passed'):
        print('valid')
    else:
        results = d.get('results', {})
        failures = [k for k, v in results.items() if v == 'FAIL']
        print(f\"failed: {', '.join(failures)}\")
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

if [[ "$valid" == "valid" ]]; then
  exit 0
fi

if [[ "$valid" == failed:* ]]; then
  echo "BLOCKED: Quality checks have failures for branch '${branch}'" >&2
  echo "  ${valid}" >&2
  echo "" >&2
  echo "Fix the failing checks and re-run:" >&2
  echo "  scripts/pre-commit-quality.sh --repo ${repo_root:-<repo>}" >&2
  exit 2
fi

echo "BLOCKED: Quality evidence is malformed for branch '${branch}'" >&2
echo "  ${evidence_file}: ${valid}" >&2
echo "  Re-run: scripts/pre-commit-quality.sh --repo ${repo_root:-<repo>}" >&2
exit 2
