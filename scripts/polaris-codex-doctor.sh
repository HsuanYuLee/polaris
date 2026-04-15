#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
cd "$ROOT"

pass_count=0
warn_count=0

pass() {
  printf 'PASS: %s\n' "$1"
  pass_count=$((pass_count + 1))
}

warn() {
  printf 'WARN: %s\n' "$1"
  warn_count=$((warn_count + 1))
}

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "command '$cmd' found"
  else
    warn "command '$cmd' missing"
  fi
}

check_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    pass "path '$p' exists"
  else
    warn "path '$p' missing"
  fi
}

echo "Polaris Codex Doctor"
echo "workspace: $ROOT"
echo

echo "[1/4] required commands"
check_cmd git
check_cmd gh
check_cmd rg
echo

echo "[2/4] core Polaris assets"
check_path CLAUDE.md
check_path .claude/rules
check_path .claude/skills
echo

echo "[3/4] workspace routing config"
if [[ -f workspace-config.yaml ]]; then
  pass "workspace-config.yaml exists"
else
  warn "workspace-config.yaml not found (copy from workspace-config.yaml.example)"
fi
echo

echo "[4/4] quick health hints"
if [[ -d .claude/skills ]]; then
  skill_count="$(find .claude/skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  pass "detected ${skill_count} top-level skills under .claude/skills"
fi

if [[ "$warn_count" -eq 0 ]]; then
  echo
  echo "Result: READY for Codex compatibility mode."
else
  echo
  echo "Result: NOT READY (${warn_count} warning(s))."
  echo "Fix warnings, then run: bash scripts/polaris-codex-doctor.sh"
fi
