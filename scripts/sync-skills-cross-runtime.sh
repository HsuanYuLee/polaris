#!/usr/bin/env bash
# sync-skills-cross-runtime.sh — sync skills between Claude and Codex layouts
#
# Usage:
#   ./scripts/sync-skills-cross-runtime.sh --to-agents [--dry-run]
#   ./scripts/sync-skills-cross-runtime.sh --to-claude [--dry-run]
#   ./scripts/sync-skills-cross-runtime.sh --both [--dry-run]
#   ./scripts/sync-skills-cross-runtime.sh --to-agents --link
#
# Notes:
# - --to-agents: .claude/skills  -> .agents/skills (public shared skills only)
# - --to-claude: .agents/skills  -> .claude/skills
# - --both:      run --to-agents first, then --to-claude
# - --link:      only valid with --to-agents, create symlink .agents/skills -> ../.claude/skills

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_SKILLS="$ROOT_DIR/.claude/skills"
AGENTS_DIR="$ROOT_DIR/.agents"
AGENTS_SKILLS="$AGENTS_DIR/skills"
COMPANY_DIRS=()

MODE=""
DRY_RUN=false
LINK_MODE=false

usage() {
  cat <<EOF
Usage:
  $0 --to-agents [--dry-run] [--link]
  $0 --to-claude [--dry-run]
  $0 --both [--dry-run]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to-agents) MODE="to-agents"; shift ;;
    --to-claude) MODE="to-claude"; shift ;;
    --both) MODE="both"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --link) LINK_MODE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Missing mode. Use one of: --to-agents, --to-claude, --both" >&2
  usage
  exit 1
fi

if [[ ! -d "$CLAUDE_SKILLS" ]]; then
  echo "Source not found: $CLAUDE_SKILLS" >&2
  exit 1
fi

if [[ "$LINK_MODE" == true && "$MODE" != "to-agents" ]]; then
  echo "--link only supports --to-agents" >&2
  exit 1
fi

while IFS= read -r line; do
  [[ -n "$line" ]] && COMPANY_DIRS+=("$line")
done < <(
  find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name ".git" ! -name ".claude" ! -name ".agents" ! -name "docs" ! -name "scripts" ! -name "_template" \
    -exec test -f "{}/workspace-config.yaml" ';' -print | xargs -n1 basename 2>/dev/null || true
)

is_company_skill() {
  local skill="$1"
  for c in "${COMPANY_DIRS[@]:-}"; do
    [[ "$skill" == "$c" ]] && return 0
  done
  return 1
}

is_maintainer_only() {
  local skill_file="$1/SKILL.md"
  [[ -f "$skill_file" ]] || return 1
  grep -q 'scope:.*maintainer-only' "$skill_file" 2>/dev/null
}

rsync_dir() {
  local src="$1"
  local dst="$2"
  local delete_flag="${3:-false}"

  [[ -d "$src" ]] || {
    echo "Source not found: $src" >&2
    return 1
  }

  if [[ "$DRY_RUN" == true ]]; then
    echo "DRY RUN: would sync $src -> $dst"
    if [[ "$delete_flag" == "true" ]]; then
      echo "DRY RUN: would replace existing contents under $dst"
    fi
    return 0
  fi

  if [[ "$delete_flag" == "true" ]]; then
    rm -rf "$dst"
    mkdir -p "$dst"
  else
    mkdir -p "$dst"
  fi
  local cp_args=(-R)
  [[ "$(uname)" == "Darwin" ]] && cp_args+=(-X)
  cp "${cp_args[@]}" "$src/." "$dst/"
}

to_agents() {
  echo "Sync: .claude/skills -> .agents/skills"
  if [[ "$LINK_MODE" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "DRY RUN: would create symlink $AGENTS_SKILLS -> ../.claude/skills"
      return 0
    fi
    mkdir -p "$AGENTS_DIR"
    rm -rf "$AGENTS_SKILLS"
    ln -s ../.claude/skills "$AGENTS_SKILLS"
    echo "Linked: $AGENTS_SKILLS -> ../.claude/skills"
    return 0
  fi

  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$AGENTS_SKILLS"
  else
    echo "DRY RUN: would update existing directories in $AGENTS_SKILLS"
  fi

  # Sync shared references first.
  rsync_dir "$CLAUDE_SKILLS/references" "$AGENTS_SKILLS/references" true
  if [[ "$DRY_RUN" == false ]]; then
    rm -f "$AGENTS_SKILLS/references/learning-queue.md" "$AGENTS_SKILLS/references/learning-archive.md"
  fi

  for skill_dir in "$CLAUDE_SKILLS"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    [[ "$skill_name" == "references" ]] && continue
    if is_company_skill "$skill_name"; then
      echo "Skip: $skill_name (company-specific)"
      continue
    fi
    if is_maintainer_only "$skill_dir"; then
      echo "Skip: $skill_name (maintainer-only)"
      continue
    fi
    rsync_dir "$skill_dir" "$AGENTS_SKILLS/$skill_name" true
  done
}

to_claude() {
  echo "Sync: .agents/skills -> .claude/skills"
  if [[ -L "$AGENTS_SKILLS" ]]; then
    echo "Skip: $AGENTS_SKILLS is a symlink; no reverse sync needed."
    return 0
  fi
  # Reverse sync is intentionally non-destructive: don't delete anything in .claude/skills.
  rsync_dir "$AGENTS_SKILLS" "$CLAUDE_SKILLS" false
  if [[ "$DRY_RUN" == false ]]; then
    rm -f "$CLAUDE_SKILLS/references/learning-queue.md" "$CLAUDE_SKILLS/references/learning-archive.md"
  fi
}

case "$MODE" in
  to-agents) to_agents ;;
  to-claude) to_claude ;;
  both)
    to_agents
    to_claude
    ;;
esac

echo "Done."
