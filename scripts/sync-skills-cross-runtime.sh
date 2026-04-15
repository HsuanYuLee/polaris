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
# - --to-agents: .claude/skills  -> .agents/skills
# - --to-claude: .agents/skills  -> .claude/skills
# - --both:      run --to-agents first, then --to-claude
# - --link:      only valid with --to-agents, create symlink .agents/skills -> ../.claude/skills

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_SKILLS="$ROOT_DIR/.claude/skills"
AGENTS_DIR="$ROOT_DIR/.agents"
AGENTS_SKILLS="$AGENTS_DIR/skills"

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

rsync_mirror() {
  local src="$1"
  local dst="$2"

  [[ -d "$src" ]] || {
    echo "Source not found: $src" >&2
    return 1
  }

  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$dst"
  fi

  local args=(
    -a
    --delete
    --exclude 'references/learning-queue.md'
    --exclude 'references/learning-archive.md'
    "$src/"
    "$dst/"
  )
  if [[ "$DRY_RUN" == true ]]; then
    args=(--dry-run "${args[@]}")
  fi

  rsync "${args[@]}"
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
  rsync_mirror "$CLAUDE_SKILLS" "$AGENTS_SKILLS"
}

to_claude() {
  echo "Sync: .agents/skills -> .claude/skills"
  if [[ -L "$AGENTS_SKILLS" ]]; then
    echo "Skip: $AGENTS_SKILLS is a symlink; no reverse sync needed."
    return 0
  fi
  rsync_mirror "$AGENTS_SKILLS" "$CLAUDE_SKILLS"
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
