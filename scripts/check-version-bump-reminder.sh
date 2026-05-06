#!/usr/bin/env bash
# scripts/check-version-bump-reminder.sh
#
# Purpose: Detect framework distribution/tooling changes that landed without a
#          VERSION bump. Post-commit / post-PR modes emit an advisory reminder;
#          release-preflight mode hard-blocks framework release lanes.
#          Rule source: rules/framework-iteration.md § Version Bump Reminder.
#
# Canary: version-bump-reminder (DP-030 Phase 2C graduation to deterministic)
#
# Modes:
#   --mode post-commit   Inspect HEAD (the just-created commit) via
#                        `git log -1 --name-only HEAD`. Used by the PostToolUse
#                        hook on `git commit`.
#   --mode post-pr       Inspect `${base}..HEAD` when a base is provided. Used
#                        by L2 embeds in engineering after PR
#                        creation. Fallback to HEAD if --base is omitted.
#   --mode release-preflight
#                        Inspect `${base}..${head_ref}` and fail-stop when
#                        framework distribution/tooling files changed without a
#                        VERSION bump. Used by framework release preflight.
#
# Exit codes:
#   0 — pass/skip/advisory
#   2 — release-preflight blocked due to missing VERSION bump
#
# Usage:
#   check-version-bump-reminder.sh --mode post-commit [--repo /path/to/repo]
#   check-version-bump-reminder.sh --mode post-pr --base develop [--repo PATH]
#   check-version-bump-reminder.sh --mode release-preflight --base origin/main \
#       --head-ref task/DP-123-T1-example [--repo PATH]
#   check-version-bump-reminder.sh --self-test
#
# Invoked by:
#   - .claude/hooks/version-bump-reminder.sh (PostToolUse Bash on git commit)
#   - .claude/skills/engineering/SKILL.md (L2 post-PR tail)
#
# Framework-repo detection: only fires when both `VERSION` and `CHANGELOG.md`
# exist at repo root (aligns with .claude/hooks/version-docs-lint-gate.sh).

set -u

MODE=""
BASE=""
HEAD_REF="HEAD"
REPO=""
SELF_TEST=0
ALLOW_MISSING_VERSION_BUMP="${POLARIS_ALLOW_MISSING_VERSION_BUMP:-0}"

FRAMEWORK_FILE_REGEX='^(\.claude/rules/[^/]+\.md|rules/[^/]+\.md|\.claude/skills/.*|skills/.*|\.claude/hooks/[^/]+\.sh|\.claude/settings\.json|\.claude/settings\.local\.json\.example|\.claude/settings\.local\.json\.sub-repo-example|\.github/copilot-instructions\.md|\.github/\.generated/.*|\.codex/AGENTS\.md|\.codex/\.generated/.*|scripts/.*\.sh|_template/.*|docs/[^/]+\.md|docs-manager/.*|README\.md|README\.zh-TW\.md|CLAUDE\.md|CHANGELOG\.md|VERSION)$'

select_framework_files() {
  grep -E "$FRAMEWORK_FILE_REGEX" || true
}

run_self_test() {
  local fixture actual expected tmpdir repo rc output override_output

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

  tmpdir="$(mktemp -d -t version-bump-reminder.XXXXXX)"
  repo="${tmpdir}/repo"
  git init -q -b main "$repo"
  (
    cd "$repo"
    git config user.name "Polaris Selftest"
    git config user.email "polaris-selftest@example.com"
    printf '3.75.8\n' > VERSION
    printf '# Changelog\n' > CHANGELOG.md
    mkdir -p .claude/skills
    printf 'base\n' > .claude/skills/example.md
    git add VERSION CHANGELOG.md .claude/skills/example.md
    git commit -q -m "base"
    git checkout -q -b task/no-bump
    printf 'changed\n' > .claude/skills/example.md
    git add .claude/skills/example.md
    git commit -q -m "framework change without bump"
    git checkout -q main
    git checkout -q -b task/with-bump
    printf 'changed\n' > .claude/skills/example.md
    printf '3.75.9\n' > VERSION
    git add .claude/skills/example.md VERSION
    git commit -q -m "framework change with bump"
  )

  rc=0
  output="$(bash "$0" --mode release-preflight --base main --head-ref task/no-bump --repo "$repo" 2>&1)" || rc=$?
  if [[ "$rc" -ne 2 ]] || ! grep -q "BLOCKED: release-preflight" <<<"$output"; then
    echo "[version-bump-reminder] self-test failed: release-preflight should block missing bump" >&2
    printf '%s\n' "$output" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  if ! bash "$0" --mode release-preflight --base main --head-ref task/with-bump --repo "$repo" >/dev/null 2>&1; then
    echo "[version-bump-reminder] self-test failed: release-preflight should pass when VERSION bumped" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  if ! override_output="$(POLARIS_ALLOW_MISSING_VERSION_BUMP=1 bash "$0" --mode release-preflight --base main --head-ref task/no-bump --repo "$repo" 2>&1)"; then
    echo "[version-bump-reminder] self-test failed: explicit override should bypass block" >&2
    printf '%s\n' "$override_output" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  if ! grep -q "override accepted" <<<"$override_output"; then
    echo "[version-bump-reminder] self-test failed: override message missing" >&2
    printf '%s\n' "$override_output" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
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
    --head-ref)
      HEAD_REF="${2:-}"
      shift 2
      ;;
    --head-ref=*)
      HEAD_REF="${1#--head-ref=}"
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
    --allow-missing-version-bump)
      ALLOW_MISSING_VERSION_BUMP=1
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
      # Diff the requested ref against the provided base.
      changed_files=$(git -C "$REPO" diff --name-only "${BASE}"..."${HEAD_REF}" 2>/dev/null || true)
    else
      # Fallback: use HEAD (same as post-commit).
      changed_files=$(git -C "$REPO" log -1 --name-only --pretty=format: HEAD 2>/dev/null | sed '/^$/d' || true)
    fi
    ;;
  release-preflight)
    [[ -n "$BASE" ]] || {
      echo "[version-bump-reminder] ERROR: release-preflight requires --base" >&2
      exit 2
    }
    changed_files=$(git -C "$REPO" diff --name-only "${BASE}"..."${HEAD_REF}" 2>/dev/null || true)
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

if [[ "$MODE" == "release-preflight" ]]; then
  if [[ "$ALLOW_MISSING_VERSION_BUMP" == "1" ]]; then
    cat <<EOF

[version-bump-reminder] release-preflight override accepted: ${file_count} framework distribution/tooling file(s) changed without a VERSION bump:
$(printf '%s\n' "$framework_files" | head -5 | sed 's/^/  - /')
$([ "$file_count" -gt 5 ] && echo "  ... and $((file_count - 5)) more")

Current version: ${current_version:-<unknown>}

Local override is active via POLARIS_ALLOW_MISSING_VERSION_BUMP=1 or --allow-missing-version-bump.
EOF
    exit 0
  fi

  cat <<EOF

[version-bump-reminder] BLOCKED: release-preflight found ${file_count} framework distribution/tooling file(s) without a VERSION bump:
$(printf '%s\n' "$framework_files" | head -5 | sed 's/^/  - /')
$([ "$file_count" -gt 5 ] && echo "  ... and $((file_count - 5)) more")

Current version: ${current_version:-<unknown>}

Framework release 不能忽略這個 signal。
Remediation:
  - 補 \`VERSION\` + \`CHANGELOG.md\` 到 release PR，然後重新跑 preflight
  - 只有在明確接受 local override 時，才使用 \`POLARIS_ALLOW_MISSING_VERSION_BUMP=1\`
EOF
  exit 2
fi

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
