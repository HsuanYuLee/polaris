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

info() {
  printf 'INFO: %s\n' "$1"
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

check_skill_tree() {
  local label="$1"
  local path="$2"
  if [[ -d "$path" ]]; then
    local skill_count
    skill_count="$(find "$path" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    pass "$label exists"
    pass "detected ${skill_count} top-level skills under $path"
  else
    warn "$label missing"
  fi
}

validate_skill_frontmatter() {
  local path="$1"
  [[ -d "$path" ]] || return 0

  local invalid
  invalid="$(python3 - "$path" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("SKIP: PyYAML not installed (pip3 install pyyaml)")
    sys.exit(0)
from pathlib import Path

root = Path(sys.argv[1])
errors = []

for skill_file in sorted(root.rglob("SKILL.md")):
    text = skill_file.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        errors.append(f"{skill_file}: missing opening frontmatter delimiter")
        continue

    try:
        _, rest = text.split("---\n", 1)
        frontmatter, _ = rest.split("\n---\n", 1)
    except ValueError:
        errors.append(f"{skill_file}: missing closing frontmatter delimiter")
        continue

    try:
        data = yaml.safe_load(frontmatter) or {}
    except Exception as exc:
        errors.append(f"{skill_file}: invalid YAML ({exc})")
        continue

    if not isinstance(data, dict):
        errors.append(f"{skill_file}: frontmatter must parse to a mapping")

if errors:
    print("\n".join(errors))
PY
)"

  if [[ -n "$invalid" ]]; then
    warn "invalid SKILL.md frontmatter detected under $path"
    printf '%s\n' "$invalid"
  else
    pass "all SKILL.md frontmatter under $path parsed successfully"
  fi
}

echo "Polaris Codex Doctor"
echo "workspace: $ROOT"
echo

echo "[1/5] required commands"
check_cmd git
check_cmd gh
check_cmd rg
echo

echo "[2/5] core Polaris assets"
check_path CLAUDE.md
check_path .claude/rules
check_path .claude/skills
check_path .agents/skills
echo

echo "[3/5] workspace routing config"
if [[ -f workspace-config.yaml ]]; then
  pass "workspace-config.yaml exists"
else
  warn "workspace-config.yaml not found (copy from workspace-config.yaml.example)"
fi
echo

echo "[4/5] skill mirror + frontmatter"
check_skill_tree ".claude/skills" ".claude/skills"
check_skill_tree ".agents/skills" ".agents/skills"
validate_skill_frontmatter ".claude/skills"
validate_skill_frontmatter ".agents/skills"
echo

echo "[5/5] Codex MCP hints"
if [[ -f "$HOME/.codex/config.toml" ]]; then
  pass "~/.codex/config.toml exists"
  if rg -q '^\[mcp_servers\.claude_ai_Slack\]' "$HOME/.codex/config.toml"; then
    info "claude_ai_Slack is configured globally; if Codex says 'not logged in', run 'codex mcp login claude_ai_Slack'"
  fi
  if rg -q '^\[mcp_servers\.figma\]' "$HOME/.codex/config.toml"; then
    info "figma is optional; if you do not use it, run 'codex mcp remove figma' to stop startup warnings"
  fi
else
  warn "~/.codex/config.toml not found"
fi

if [[ "$warn_count" -eq 0 ]]; then
  echo
  echo "Result: READY for Codex compatibility mode."
else
  echo
  echo "Result: NOT READY (${warn_count} warning(s))."
  echo "Fix warnings, then run: bash scripts/polaris-codex-doctor.sh"
fi
