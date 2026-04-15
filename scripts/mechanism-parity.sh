#!/usr/bin/env bash
# mechanism-parity.sh — Inventory framework mechanisms and verify Claude/Codex parity
#
# Goal: maintain one source of truth (Claude layout) and keep Codex layout in sync.
#
# Usage:
#   ./scripts/mechanism-parity.sh
#   ./scripts/mechanism-parity.sh --sync
#   ./scripts/mechanism-parity.sh --strict
#
# Options:
#   --sync    run skills sync first (.claude/skills -> .agents/skills)
#   --strict  exit 1 when drift is detected (missing/extra/changed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_DIR="$ROOT_DIR/.claude"
CLAUDE_SKILLS="$CLAUDE_DIR/skills"
AGENTS_SKILLS="$ROOT_DIR/.agents/skills"

DO_SYNC=false
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync) DO_SYNC=true; shift ;;
    --strict) STRICT=true; shift ;;
    -h|--help)
      sed -n '1,24p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$DO_SYNC" == true ]]; then
  "$SCRIPT_DIR/sync-skills-cross-runtime.sh" --to-agents
fi

[[ -d "$CLAUDE_SKILLS" ]] || { echo "Missing $CLAUDE_SKILLS" >&2; exit 1; }
[[ -d "$AGENTS_SKILLS" ]] || { echo "Missing $AGENTS_SKILLS" >&2; exit 1; }

COMPANY_DIRS=()
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
  local skill="$1"
  local skill_file="$CLAUDE_SKILLS/$skill/SKILL.md"
  [[ -f "$skill_file" ]] || return 1
  grep -q 'scope:.*maintainer-only' "$skill_file" 2>/dev/null
}

CLAUDE_ALL=()
while IFS= read -r line; do
  [[ -n "$line" ]] && CLAUDE_ALL+=("$line")
done < <(find "$CLAUDE_SKILLS" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

AGENTS_ALL=()
while IFS= read -r line; do
  [[ -n "$line" ]] && AGENTS_ALL+=("$line")
done < <(find "$AGENTS_SKILLS" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)

PUBLIC_CLAUDE=()
MAINTAINER_ONLY=()
COMPANY_SKILLS=()

for skill in "${CLAUDE_ALL[@]}"; do
  [[ "$skill" == "references" ]] && continue
  if is_company_skill "$skill"; then
    COMPANY_SKILLS+=("$skill")
    continue
  fi
  if is_maintainer_only "$skill"; then
    MAINTAINER_ONLY+=("$skill")
    continue
  fi
  PUBLIC_CLAUDE+=("$skill")
done

MISSING_IN_AGENTS=()
for skill in "${PUBLIC_CLAUDE[@]}"; do
  [[ -d "$AGENTS_SKILLS/$skill" ]] || MISSING_IN_AGENTS+=("$skill")
done

EXTRA_IN_AGENTS=()
for skill in "${AGENTS_ALL[@]}"; do
  [[ "$skill" == "references" ]] && continue
  found=false
  for c in "${PUBLIC_CLAUDE[@]}"; do
    [[ "$skill" == "$c" ]] && found=true && break
  done
  [[ "$found" == true ]] || EXTRA_IN_AGENTS+=("$skill")
done

CHANGED_SKILLS=()
for skill in "${PUBLIC_CLAUDE[@]}"; do
  [[ -d "$AGENTS_SKILLS/$skill" ]] || continue
  if ! diff -qr "$CLAUDE_SKILLS/$skill" "$AGENTS_SKILLS/$skill" >/dev/null 2>&1; then
    CHANGED_SKILLS+=("$skill")
  fi
done

REFERENCES_IN_SYNC=true
if ! diff -qr \
  -x 'learning-queue.md' \
  -x 'learning-archive.md' \
  "$CLAUDE_SKILLS/references" "$AGENTS_SKILLS/references" >/dev/null 2>&1; then
  REFERENCES_IN_SYNC=false
fi

ROOT_RULES_COUNT=$(find "$CLAUDE_DIR/rules" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
L2_RULES_COUNT=$(find "$CLAUDE_DIR/rules" -mindepth 2 -maxdepth 2 -type f -name '*.md' | wc -l | tr -d ' ')
HOOKS_COUNT=$(find "$CLAUDE_DIR/hooks" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
SCRIPTS_COUNT=$(find "$ROOT_DIR/scripts" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')

echo "=== Polaris Mechanism Inventory ==="
echo "Root rules (L1):         $ROOT_RULES_COUNT"
echo "Company rules (L2):      $L2_RULES_COUNT"
echo "Claude hooks:            $HOOKS_COUNT"
echo "Repo scripts:            $SCRIPTS_COUNT"
echo "Claude skills (all):     $((${#CLAUDE_ALL[@]} - 1))"
echo "Public shared skills:    ${#PUBLIC_CLAUDE[@]}"
echo "Maintainer-only skills:  ${#MAINTAINER_ONLY[@]}"
echo "Company-specific skills: ${#COMPANY_SKILLS[@]}"
echo "Codex skills (.agents):  $((${#AGENTS_ALL[@]} - 1))"
echo

if [[ ${#MAINTAINER_ONLY[@]} -gt 0 ]]; then
  echo "Maintainer-only:"
  printf '  - %s\n' "${MAINTAINER_ONLY[@]}"
fi

echo
echo "=== Claude/Codex Parity Check ==="
[[ "$REFERENCES_IN_SYNC" == true ]] && echo "references/: OK" || echo "references/: DRIFT"

if [[ ${#MISSING_IN_AGENTS[@]} -eq 0 ]]; then
  echo "missing in .agents: none"
else
  echo "missing in .agents:"
  printf '  - %s\n' "${MISSING_IN_AGENTS[@]}"
fi

if [[ ${#EXTRA_IN_AGENTS[@]} -eq 0 ]]; then
  echo "extra in .agents: none"
else
  echo "extra in .agents:"
  printf '  - %s\n' "${EXTRA_IN_AGENTS[@]}"
fi

if [[ ${#CHANGED_SKILLS[@]} -eq 0 ]]; then
  echo "changed skill dirs: none"
else
  echo "changed skill dirs:"
  printf '  - %s\n' "${CHANGED_SKILLS[@]}"
fi

DRIFT=false
[[ "$REFERENCES_IN_SYNC" == false ]] && DRIFT=true
[[ ${#MISSING_IN_AGENTS[@]} -gt 0 ]] && DRIFT=true
[[ ${#EXTRA_IN_AGENTS[@]} -gt 0 ]] && DRIFT=true
[[ ${#CHANGED_SKILLS[@]} -gt 0 ]] && DRIFT=true

echo
if [[ "$DRIFT" == true ]]; then
  echo "Result: DRIFT DETECTED"
  echo "Fix: ./scripts/sync-skills-cross-runtime.sh --to-agents"
  [[ "$STRICT" == true ]] && exit 1
else
  echo "Result: IN SYNC"
fi
