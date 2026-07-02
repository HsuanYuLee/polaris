#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

company_dir="$(find .claude/skills -maxdepth 2 -type d -name jira-worklog -print -quit | sed 's#^\.claude/skills/##; s#/jira-worklog$##')"
[[ -n "$company_dir" ]] || { echo "company skill dir not found" >&2; exit 1; }
test ! -e ".claude/skills/${company_dir}/bug-rca"
bash scripts/check-skills-mirror-mode.sh >/dev/null

tmp="$(mktemp -t bug-rca-active-hits.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

set +e
rg -n 'bug-rca|/bug-rca|bug RCA|補 RCA' \
  CLAUDE.md .claude scripts \
  -g '!docs-manager/**' \
  -g '!scripts/manifest.json' \
  -g '!scripts/selftests/bug-rca-skill-absence-selftest.sh' \
  >"$tmp"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  cat "$tmp" >&2
  echo "FAIL: active bug-rca routing surface still contains sunset trigger" >&2
  exit 1
fi

echo "PASS: bug-rca skill absence"
