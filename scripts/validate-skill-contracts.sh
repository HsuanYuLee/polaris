#!/usr/bin/env bash
# validate-skill-contracts.sh — static linter for Polaris SKILL.md contract drift.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: validate-skill-contracts.sh [--root <skills-dir>] [--strict] [--quiet]

Checks SKILL.md files for common framework contract drift:
  - sub-agent dispatch without Completion Envelope reference
  - likely write skill without Post-Task Reflection
  - external write surface without language gate/helper reference
  - specs markdown producer without Starlight authoring reference
  - legacy specs path patterns
EOF
  exit 2
}

ROOT=".claude/skills"
STRICT=0
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "error: skills root not found: $ROOT" >&2
  exit 2
fi

errors=0
warnings=0

emit() {
  local level="$1"
  local check="$2"
  local file="$3"
  local detail="$4"
  if [[ "$QUIET" -eq 0 ]]; then
    printf '%s\t%s\t%s\t%s\n' "$level" "$check" "$file" "$detail"
  fi
  case "$level" in
    ERROR) errors=$((errors + 1)) ;;
    WARN) warnings=$((warnings + 1)) ;;
  esac
}

while IFS= read -r file; do
  text="$(cat "$file")"

  if grep -Eiq 'sub-?agent|dispatch|平行|委派' "$file" && ! grep -q 'Completion Envelope' "$file"; then
    emit WARN "sub-agent-envelope" "$file" "sub-agent dispatch text exists without Completion Envelope reference"
  fi

  if grep -Eiq '寫入|更新|create|update|JIRA|Slack|Confluence|PR|commit|產出|Write tool|Edit tool' "$file" \
    && ! grep -q 'Post-Task Reflection' "$file"; then
    emit WARN "post-task-reflection" "$file" "likely write skill without Post-Task Reflection section"
  fi

  if grep -Eiq 'JIRA comment|Slack|Confluence|github review|review body|inline comment|slack_send_message|addComment|send_message' "$file" \
    && ! grep -Eq 'validate-language-policy|polaris-external-write-gate|workspace-language-policy' "$file"; then
    emit WARN "external-write-language-gate" "$file" "external write surface without language gate/helper reference"
  fi

  if grep -Eq 'docs-manager/src/content/docs/specs|specs folder|specs/.*\.md|Starlight route' "$file" \
    && ! grep -Eq 'validate-starlight-authoring|starlight-authoring-contract' "$file"; then
    emit WARN "starlight-authoring" "$file" "specs markdown producer without Starlight authoring reference"
  fi

  if grep -Eq '(^|[^A-Za-z0-9_])specs/\{EPIC\}|\{workspace_root\}/specs|~/work/' "$file"; then
    emit WARN "legacy-path-pattern" "$file" "legacy or user-specific path pattern found"
  fi
done < <(find "$ROOT" -type f -name 'SKILL.md' | sort)

if [[ "$QUIET" -eq 0 ]]; then
  printf 'summary\terrors=%d\twarnings=%d\n' "$errors" "$warnings"
fi

if (( errors > 0 || (STRICT == 1 && warnings > 0) )); then
  exit 1
fi
exit 0
