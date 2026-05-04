#!/usr/bin/env bash
# validate-handbook-path-contract.sh — fail on stale repo-local handbook SoT paths.
#
# Repo handbook source-of-truth is workspace-owned:
#   {company}/polaris-config/{project}/handbook/
# Repo-local .claude/rules/handbook mentions are allowed only when explicitly
# describing legacy/native compatibility overlays.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

targets=(
  "$ROOT_DIR/.claude/instructions"
  "$ROOT_DIR/.claude/rules"
  "$ROOT_DIR/.claude/skills"
  "$ROOT_DIR/docs-manager/src/content/docs/specs"
)

patterns=(
  '\{repo\}/\.claude/rules/handbook'
  '\{project_path\}/\.claude/rules/handbook'
  '\{base_dir\}/<repo>/\.claude/rules/handbook'
  '[[:alnum:]_.-]+/\.claude/rules/handbook/index\.md'
)

hits=""
for pattern in "${patterns[@]}"; do
  pattern_hits="$(rg --no-ignore -n "$pattern" "${targets[@]}" \
    --glob '!**/node_modules/**' \
    --glob '!**/.git/**' \
    --glob '!**/archive/**' \
    --glob '!scripts/validate-handbook-path-contract.sh' 2>/dev/null || true)"

  if [[ -n "$pattern_hits" ]]; then
    filtered="$(printf '%s\n' "$pattern_hits" | grep -Ev 'repo-local|compatibility|legacy|native' || true)"
    if [[ -n "$filtered" ]]; then
      hits+="$filtered"$'\n'
    fi
  fi
done

if [[ -n "$hits" ]]; then
  echo "[handbook-path-contract] FAIL: stale repo-local handbook source paths found." >&2
  echo "Use {company}/polaris-config/{project}/handbook/ as the repo handbook source of truth." >&2
  printf '%s' "$hits" >&2
  exit 1
fi

echo "[handbook-path-contract] PASS"
