#!/usr/bin/env bash
# scripts/check-version-bump-reminder.sh
#
# Purpose: Detect framework distribution/tooling changes that landed without a
#          VERSION bump, and emit an advisory reminder.
#          Rule source: rules/framework-iteration.md § Version Bump Reminder.
#
# Canary: version-bump-reminder (DP-030 Phase 2C graduation to deterministic)
#
# Modes:
#   --mode post-commit   Inspect HEAD (the just-created commit) via
#                        `git log -1 --name-only HEAD`. Used by the PostToolUse
#                        hook on `git commit`.
#   --mode post-pr       Inspect `${base}..HEAD` when a base is provided. Used
#                        by L2 embeds in engineering / git-pr-workflow after PR
#                        creation. Fallback to HEAD if --base is omitted.
#
# Mode: Advisory only. Exit 0 on every path (framework change with no bump
#       still exit 0 — we only surface the reminder on stdout). This matches
#       the "path B" advisory posture documented in DP-030 Phase 2C plan.
#
# Exit codes:
#   0 — always (stdout carries the advisory reminder when applicable)
#
# Usage:
#   check-version-bump-reminder.sh --mode post-commit [--repo /path/to/repo]
#   check-version-bump-reminder.sh --mode post-pr --base develop [--repo PATH]
#   check-version-bump-reminder.sh --self-test
#
# Invoked by:
#   - .claude/hooks/version-bump-reminder.sh (PostToolUse Bash on git commit)
#   - .claude/skills/engineering/SKILL.md (L2 post-PR tail)
#   - .claude/skills/git-pr-workflow/SKILL.md (L2 post-PR tail)
#
# Framework-repo detection: only fires when both `VERSION` and `CHANGELOG.md`
# exist at repo root (aligns with .claude/hooks/version-docs-lint-gate.sh).

set -u

MODE=""
BASE=""
REPO=""
SELF_TEST=0

FRAMEWORK_FILE_REGEX='^(\.claude/rules/[^/]+\.md|rules/[^/]+\.md|\.claude/skills/.*|skills/.*|\.claude/hooks/[^/]+\.sh|\.claude/settings\.json|\.claude/settings\.local\.json\.example|\.claude/settings\.local\.json\.sub-repo-example|\.github/copilot-instructions\.md|\.github/\.generated/.*|\.codex/AGENTS\.md|\.codex/\.generated/.*|scripts/.*\.sh|_template/.*|docs/[^/]+\.md|docs-manager/.*|README\.md|README\.zh-TW\.md|CLAUDE\.md|CHANGELOG\.md|VERSION)$'

select_framework_files() {
  grep -E "$FRAMEWORK_FILE_REGEX" || true
}

run_self_test() {
  local fixture actual expected

  fixture=$(cat <<'EOF'
.claude/rules/framework-iteration.md
.claude/rules/company/private.md
.claude/skills/engineering/SKILL.md
.claude/hooks/version-bump-reminder.sh
.claude/settings.local.json.example
scripts/check-version-bump-reminder.sh
scripts/lib/runtime.sh
docs/release.md
docs/nested/ignored.md
docs-manager/README.md
_template/CLAUDE.md
.github/.generated/copilot-instructions.md
.codex/AGENTS.md
README.zh-TW.md
specs/design-plans/DP-061/plan.md
src/product-code.ts
EOF
)

  expected=$(cat <<'EOF'
.claude/rules/framework-iteration.md
.claude/skills/engineering/SKILL.md
.claude/hooks/version-bump-reminder.sh
.claude/settings.local.json.example
scripts/check-version-bump-reminder.sh
scripts/lib/runtime.sh
docs/release.md
docs-manager/README.md
_template/CLAUDE.md
.github/.generated/copilot-instructions.md
.codex/AGENTS.md
README.zh-TW.md
EOF
)

  actual=$(printf '%s\n' "$fixture" | select_framework_files)

  if [[ "$actual" != "$expected" ]]; then
    echo "[version-bump-reminder] self-test failed" >&2
    echo "--- expected" >&2
    printf '%s\n' "$expected" >&2
    echo "--- actual" >&2
    printf '%s\n' "$actual" >&2
    return 1
  fi

  echo "[version-bump-reminder] self-test passed"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      SELF_TEST=1
      shift
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --mode=*)
      MODE="${1#--mode=}"
      shift
      ;;
    --base)
      BASE="${2:-}"
      shift 2
      ;;
    --base=*)
      BASE="${1#--base=}"
      shift
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --repo=*)
      REPO="${1#--repo=}"
      shift
      ;;
    -h|--help)
      sed -n '2,32p' "$0" >&2
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$SELF_TEST" -eq 1 ]]; then
  run_self_test
  exit $?
fi

if [[ -z "$MODE" ]]; then
  echo "[version-bump-reminder] WARN: --mode not specified — skipping" >&2
  exit 0
fi

# Resolve repo path (fall back to CLAUDE_PROJECT_DIR → cwd).
if [[ -z "$REPO" ]]; then
  REPO="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi

# Framework repo gate: must have VERSION + CHANGELOG.md.
if [[ ! -f "$REPO/VERSION" || ! -f "$REPO/CHANGELOG.md" ]]; then
  exit 0
fi

# --- Collect changed files per mode ---
changed_files=""
case "$MODE" in
  post-commit)
    # Inspect the most recent commit only (matches the behavior of the legacy
    # hook). Use `git log -1 --name-only --pretty=format:` to avoid the
    # leading commit hash.
    changed_files=$(git -C "$REPO" log -1 --name-only --pretty=format: HEAD 2>/dev/null | sed '/^$/d' || true)
    ;;
  post-pr)
    if [[ -n "$BASE" ]]; then
      # Diff the current branch against the provided base.
      changed_files=$(git -C "$REPO" diff --name-only "${BASE}"...HEAD 2>/dev/null || true)
    else
      # Fallback: use HEAD (same as post-commit).
      changed_files=$(git -C "$REPO" log -1 --name-only --pretty=format: HEAD 2>/dev/null | sed '/^$/d' || true)
    fi
    ;;
  *)
    echo "[version-bump-reminder] WARN: unknown mode '$MODE' — skipping" >&2
    exit 0
    ;;
esac

if [[ -z "$changed_files" ]]; then
  exit 0
fi

# Skip if VERSION is in the diff — user already bumped.
if printf '%s\n' "$changed_files" | grep -qE '^VERSION$'; then
  exit 0
fi

# Select framework distribution/tooling files. The allowlist intentionally
# stays generic: local release actions live in local scripts/skills,
# not in this portable advisory.
framework_files=$(printf '%s\n' "$changed_files" | select_framework_files)

if [[ -z "$framework_files" ]]; then
  exit 0
fi

file_count=$(printf '%s\n' "$framework_files" | wc -l | tr -d ' ')
current_version=$(cat "$REPO/VERSION" 2>/dev/null | tr -d '[:space:]' || true)

# Advisory output on stdout (PostToolUse hook + L2 embed convention — surfaces
# back to the LLM / user as a reminder).
cat <<EOF

[version-bump-reminder] ${MODE}: ${file_count} framework distribution/tooling file(s) changed without a VERSION bump:
$(printf '%s\n' "$framework_files" | head -5 | sed 's/^/  - /')
$([ "$file_count" -gt 5 ] && echo "  ... and $((file_count - 5)) more")

Current version: ${current_version:-<unknown>}

這次改動涉及框架發佈檔案或工具，要升版嗎？
  - 升版：bump VERSION + 更新 CHANGELOG.md，並依本 workspace release policy 執行後續 release chain
  - 不升版：在此次 session 或下一次提交前合併到後續變更（批次升版）
  - 已 opt-out：忽略此訊息（advisory only，不擋）
EOF

exit 0
