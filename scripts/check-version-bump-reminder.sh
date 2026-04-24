#!/usr/bin/env bash
# scripts/check-version-bump-reminder.sh
#
# Purpose: Detect framework changes (files under rules/ or .claude/skills/)
#          that landed without a VERSION bump, and emit an advisory reminder.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
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

# Select framework files. Accept both `rules/` (tracked at repo root) and
# `.claude/skills/` (inside .claude/). We avoid matching `_template/`,
# `docs/`, `specs/` etc — those are non-framework.
framework_files=$(printf '%s\n' "$changed_files" \
  | grep -E '^(\.claude/rules/|rules/|\.claude/skills/|skills/)' \
  || true)

if [[ -z "$framework_files" ]]; then
  exit 0
fi

file_count=$(printf '%s\n' "$framework_files" | wc -l | tr -d ' ')
current_version=$(cat "$REPO/VERSION" 2>/dev/null | tr -d '[:space:]' || true)

# Advisory output on stdout (PostToolUse hook + L2 embed convention — surfaces
# back to the LLM / user as a reminder).
cat <<EOF

[version-bump-reminder] ${MODE}: ${file_count} framework file(s) changed under rules/ or .claude/skills/ without a VERSION bump:
$(printf '%s\n' "$framework_files" | head -5 | sed 's/^/  - /')
$([ "$file_count" -gt 5 ] && echo "  ... and $((file_count - 5)) more")

Current version: ${current_version:-<unknown>}

這次改動涉及框架規則/技能，要升版嗎？
  - 升版：bump VERSION + 更新 CHANGELOG.md + 執行 Post-Version-Bump Chain（docs-lint → docs-sync → backlog scan → sync-to-polaris）
  - 不升版：在此次 session 或下一次提交前合併到後續變更（批次升版）
  - 已 opt-out：忽略此訊息（advisory only，不擋）
EOF

exit 0
