#!/usr/bin/env bash
# sync-from-upstream.sh — Sync generic skills/rules/references from a working instance to Polaris
#
# This script copies files from your working workspace (e.g. ~/work),
# strips company-specific references, and prepares them for commit to Polaris.
#
# Usage:
#   ./scripts/sync-from-upstream.sh --source ~/work [--dry-run]
#
# What it syncs:
#   - .claude/skills/ (excluding company-specific skills)
#   - .claude/skills/references/
#   - .claude/rules/bash-command-splitting.md (L1)
#   - .claude/rules/kkday/ → .claude/rules/company/ (L2)
#   - .claude/hooks/
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - _template/workspace-config.yaml
#   - workspace-config.yaml (root config)
#   - CLAUDE.md (NOT synced — Polaris has its own version)
#
# After sync, review the diff and commit manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLARIS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR=""
DRY_RUN=false

# Company-specific skills to exclude (not copied to Polaris)
EXCLUDE_SKILLS="kibana-logs sasd-review docs-sync"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "❌ Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  echo "❌ --source is required (e.g. --source ~/work)" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [[ ! -d "$SOURCE_DIR/.claude/skills" ]]; then
  echo "❌ Source doesn't look like a workspace: $SOURCE_DIR/.claude/skills not found" >&2
  exit 1
fi

echo "📦 Syncing from: $SOURCE_DIR"
echo "📦 Syncing to:   $POLARIS_DIR"
[[ "$DRY_RUN" == true ]] && echo "🔍 DRY RUN — no files will be modified"
echo ""

# ── Step 1: Sync skills ──────────────────────────────────────────────

echo "🔄 Syncing skills..."
for skill_dir in "$SOURCE_DIR"/.claude/skills/*/; do
  skill_name=$(basename "$skill_dir")

  # Skip excluded skills
  skip=false
  for excluded in $EXCLUDE_SKILLS; do
    if [[ "$skill_name" == "$excluded" ]]; then
      skip=true
      break
    fi
  done

  if [[ "$skip" == true ]]; then
    echo "  ⏭️  $skill_name (company-specific, skipped)"
    continue
  fi

  echo "  ✓ $skill_name"
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$POLARIS_DIR/.claude/skills/$skill_name"
    cp -r "$skill_dir" "$POLARIS_DIR/.claude/skills/$skill_name"
  fi
done

# ── Step 2: Sync references ──────────────────────────────────────────

echo "🔄 Syncing references..."
if [[ "$DRY_RUN" == false ]]; then
  # Sync all except company-specific ones
  for ref_file in "$SOURCE_DIR"/.claude/skills/references/*.md; do
    ref_name=$(basename "$ref_file")
    case "$ref_name" in
      sasd-confluence.md) echo "  ⏭️  $ref_name (company-specific, skipped)" ;;
      *) echo "  ✓ $ref_name"; cp "$ref_file" "$POLARIS_DIR/.claude/skills/references/$ref_name" ;;
    esac
  done
fi

# ── Step 3: Sync L1 rules ────────────────────────────────────────────

echo "🔄 Syncing L1 rules..."
if [[ "$DRY_RUN" == false ]]; then
  cp "$SOURCE_DIR/.claude/rules/bash-command-splitting.md" "$POLARIS_DIR/.claude/rules/bash-command-splitting.md"
  echo "  ✓ bash-command-splitting.md"
fi

# ── Step 4: Sync L2 rules (kkday/ → company/) ────────────────────────

echo "🔄 Syncing L2 rules (kkday/ → company/)..."
# Detect source L2 directory (could be kkday/, company/, or other)
L2_SOURCE=""
for candidate in "$SOURCE_DIR"/.claude/rules/*/; do
  dir_name=$(basename "$candidate")
  if [[ "$dir_name" != "." ]]; then
    L2_SOURCE="$candidate"
    echo "  Found L2 source: $dir_name/"
    break
  fi
done

if [[ -n "$L2_SOURCE" ]] && [[ "$DRY_RUN" == false ]]; then
  for rule_file in "$L2_SOURCE"*.md; do
    rule_name=$(basename "$rule_file")
    echo "  ✓ $rule_name"
    cp "$rule_file" "$POLARIS_DIR/.claude/rules/company/$rule_name"
  done
fi

# ── Step 5: Sync hooks & settings ────────────────────────────────────

echo "🔄 Syncing hooks & settings..."
if [[ "$DRY_RUN" == false ]]; then
  cp "$SOURCE_DIR/.claude/hooks/pre-push-quality-gate.sh" "$POLARIS_DIR/.claude/hooks/pre-push-quality-gate.sh" 2>/dev/null && echo "  ✓ pre-push-quality-gate.sh" || true
  cp "$SOURCE_DIR/.claude/settings.json" "$POLARIS_DIR/.claude/settings.json" 2>/dev/null && echo "  ✓ settings.json" || true
  cp "$SOURCE_DIR/.claude/settings.local.json.example" "$POLARIS_DIR/.claude/settings.local.json.example" 2>/dev/null && echo "  ✓ settings.local.json.example" || true
  cp "$SOURCE_DIR/.claude/settings.local.json.sub-repo-example" "$POLARIS_DIR/.claude/settings.local.json.sub-repo-example" 2>/dev/null && echo "  ✓ settings.local.json.sub-repo-example" || true
fi

# ── Step 6: Sync _template/ and root workspace-config.yaml ───────────

echo "🔄 Syncing _template/ and workspace-config.yaml..."
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$POLARIS_DIR/_template"
  cp "$SOURCE_DIR/_template/workspace-config.yaml" "$POLARIS_DIR/_template/workspace-config.yaml"
  echo "  ✓ _template/workspace-config.yaml"
  cp "$SOURCE_DIR/workspace-config.yaml" "$POLARIS_DIR/workspace-config.yaml"
  echo "  ✓ workspace-config.yaml (root)"
  # Remove old example file if exists
  rm -f "$POLARIS_DIR/workspace-config.example.yaml"
fi

# ── Step 7: Genericize ───────────────────────────────────────────────

echo ""
echo "🧹 Genericizing company-specific references..."

if [[ "$DRY_RUN" == false ]]; then
  # Find all text files to process
  find "$POLARIS_DIR/.claude" "$POLARIS_DIR/_template" "$POLARIS_DIR/workspace-config.yaml" \
    -type f \( -name "*.md" -o -name "*.json" -o -name "*.example" -o -name "*.sh" -o -name "*.yaml" \) \
    | xargs sed -i '' \
    -e 's/kkday\.atlassian\.net/your-domain.atlassian.net/g' \
    -e 's/kkday-it/your-org/g' \
    -e 's/kkday-travel/your-org/g' \
    -e 's/kkday-b2c-web/your-app/g' \
    -e 's/kkday-member-ci/your-backend/g' \
    -e 's/kkday-mobile-member-ci/your-mobile/g' \
    -e 's/kkday-email-mjml/your-email-templates/g' \
    -e 's/kkday-appdownload-static/your-static-site/g' \
    -e 's/kkday-web-docker/your-dev-proxy/g' \
    -e 's/web-design-system/your-design-system/g' \
    -e 's/daniel-lee-kk/your-username/g' \
    -e 's/danielfang1977/your-bot-account/g' \
    -e 's/Tim-KKday/teammate-name/g' \
    -e 's/dev\.kkday\.com/dev.yourapp.com/g' \
    -e 's/woodpecker\.sit\.kkday\.com/your-internal-tool.example.com/g' \
    -e 's/@kkday\/b2c-web-main/@your-org\/your-app-main/g' \
    -e 's/b2c-web/your-app/g' \
    -e 's/member-ci/your-backend/g' \
    -e 's/kkday-dev-quality-check/dev-quality-check/g' \
    -e 's/kkday-epic-breakdown/epic-breakdown/g' \
    -e 's/kkday-fix-pr-review/fix-pr-review/g' \
    -e 's/kkday-fix-bug/fix-bug/g' \
    -e 's/kkday-review-pr/review-pr/g' \
    -e 's/kkday-sasd-review/sasd-review/g' \
    -e 's/kkday-systematic-debugging/systematic-debugging/g' \
    -e 's/kkday-jira-estimation/jira-estimation/g' \
    -e 's/kkday-jira-branch-checkout/jira-branch-checkout/g' \
    -e 's/kkday-work-on/work-on/g' \
    -e 's/kkday-web-skills/web-skills/g' \
    -e 's/kkday-ansible-sit/your-ansible-sit/g' \
    -e 's/kkday-ansible/your-ansible/g' \
    -e 's|~/work/kkday|~/work/company|g' \
    -e 's|api-lang\.sit\.kkday\.com|api-lang.sit.example.com|g' \
    -e 's/CUSTOM_VARS\.KKDAY\./CUSTOM_VARS.YOUR_ORG./g' \
    -e 's/KKday Web team/your team/g' \
    -e 's/KKday IT/""/g' \
    -e 's/KKday/YourOrg/g' \
    -e 's/kkday/your-company/g' \
    2>/dev/null

  # Replace JIRA ticket keys
  find "$POLARIS_DIR/.claude" -type f \( -name "*.md" -o -name "*.json" \) \
    | xargs sed -i '' \
    -e 's/GT-[0-9]\{1,\}/PROJ-123/g' \
    -e 's/KB2CW-[0-9]\{1,\}/TASK-123/g' \
    -e 's/project = KB2CW/project = PROJ/g' \
    -e 's/project in (PROJ, KB2CW)/project in (PROJ, TASK)/g' \
    -e 's/KB2CW/TASK/g' \
    2>/dev/null

  # Replace Confluence/Slack/field IDs
  find "$POLARIS_DIR/.claude" -type f \( -name "*.md" -o -name "*.json" \) \
    | xargs sed -i '' \
    -e 's/space = "KW"/space = "YOUR_SPACE"/g' \
    -e 's/C08NJ2GL204/YOUR_CHANNEL_ID/g' \
    -e 's/C0AH75ZE40N/YOUR_CHANNEL_ID/g' \
    -e 's/C0ANMA6VAEA/YOUR_CHANNEL_ID/g' \
    -e 's/1628799074/YOUR_PAGE_ID/g' \
    -e 's/Growth team/Team A/g' \
    -e 's/Web Service team/Team B/g' \
    2>/dev/null

  echo "  ✅ Genericization complete"
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo "✅ Sync complete!"
echo ""
echo "Next steps:"
echo "  1. cd $POLARIS_DIR"
echo "  2. git diff            — review changes"
echo "  3. git add -A && git commit -m 'sync: update from upstream'"
echo "  4. gh auth switch --user HsuanYuLee"
echo "  5. git push"
echo "  6. gh auth switch --user daniel-lee-kk"
echo "════════════════════════════════════════════"
