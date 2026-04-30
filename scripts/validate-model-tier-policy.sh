#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

fail=0

relpath() {
  local path="$1"
  python3 - "$ROOT_DIR" "$path" <<'PY'
import os
import sys

root, path = sys.argv[1:3]
print(os.path.relpath(path, root))
PY
}

is_allowed_raw_model_location() {
  local rel="$1"
  case "$rel" in
    .claude/skills/references/model-tier-policy.md) return 0 ;;
    CHANGELOG.md|*/CHANGELOG.md) return 0 ;;
    *release-notes*.md|*ReleaseNotes*.md|*release-notes*) return 0 ;;
    *runtime*example*.md|*runtime*adapter*.md|*model*adapter*.md) return 0 ;;
    specs/*/artifacts/research-report-*.md|specs/design-plans/*/artifacts/research-report-*.md) return 0 ;;
    *) return 1 ;;
  esac
}

check_mirror_mode() {
  local agents_skills="$ROOT_DIR/.agents/skills"
  local expected_target="../.claude/skills"

  if [[ ! -L "$agents_skills" ]]; then
    echo "FAIL: $agents_skills is not a symlink." >&2
    fail=1
    return
  fi

  local actual_target
  actual_target="$(readlink "$agents_skills")"
  if [[ "$actual_target" != "$expected_target" ]]; then
    echo "FAIL: $agents_skills points to '$actual_target', expected '$expected_target'." >&2
    fail=1
    return
  fi

  echo "OK: .agents/skills -> $expected_target"
}

scan_raw_model_policy() {
  local -a roots=()
  local path rel matches

  [[ -d "$ROOT_DIR/.claude/skills" ]] && roots+=("$ROOT_DIR/.claude/skills")
  [[ -d "$ROOT_DIR/.claude/rules" ]] && roots+=("$ROOT_DIR/.claude/rules")
  [[ -f "$ROOT_DIR/CLAUDE.md" ]] && roots+=("$ROOT_DIR/CLAUDE.md")
  [[ -f "$ROOT_DIR/AGENTS.md" ]] && roots+=("$ROOT_DIR/AGENTS.md")

  [[ "${#roots[@]}" -gt 0 ]] || return 0

  while IFS= read -r -d '' path; do
    rel="$(relpath "$path")"
    if is_allowed_raw_model_location "$rel"; then
      continue
    fi

    matches="$(
      rg -n --no-heading --color never \
        'model:[[:space:]]*"?((haiku)|(sonnet)|(opus)|(claude-[A-Za-z0-9._-]+)|(gpt-[A-Za-z0-9._-]+))"?|claude-sonnet-[A-Za-z0-9._-]+|gpt-[0-9][A-Za-z0-9._-]*|\b(haiku|sonnet|opus)[[:space:]]+(model|sub-agent|subagent)\b|\b(haiku|sonnet|opus)\b[[:space:]]+for[[:space:]].*(batch|jira|explore|execute|review|implementation|coding)' \
        "$path" 2>/dev/null || true
    )"

    if [[ -n "$matches" ]]; then
      echo "FAIL: raw provider model policy outside approved mapping location: $rel" >&2
      echo "$matches" >&2
      fail=1
    fi
  done < <(
    find "${roots[@]}" \
      \( -type d \( -name .git -o -name node_modules \) -prune \) -o \
      \( -type f \( -name '*.md' -o -name 'SKILL.md' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) -print0 \)
  )
}

check_mirror_mode
scan_raw_model_policy

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "PASS: model tier policy drift check passed"
