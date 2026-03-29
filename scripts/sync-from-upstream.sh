#!/usr/bin/env bash
# sync-from-upstream.sh — Sync generic skills/rules/references from a working instance to Polaris
#
# This script copies files from your working workspace (e.g. ~/work),
# strips company-specific references, and prepares them for commit to Polaris.
#
# Usage:
#   ./scripts/sync-from-upstream.sh --source ~/work [--company kkday] [--dry-run] [--verify]
#
# What it syncs:
#   - .claude/skills/ (excluding company-specific skills)
#   - .claude/skills/references/
#   - .claude/rules/ (L1 + L2, company/ → company/)
#   - .claude/hooks/
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - scripts/ (sync script + genericize maps)
#   - _template/workspace-config.yaml
#   - workspace-config.yaml (root config)
#   - CLAUDE.md (NOT synced — Polaris has its own version)
#
# Genericization:
#   Sed patterns are maintained in scripts/genericize-map.sed and
#   scripts/genericize-jira.sed for easy editing.
#
# After sync, review the diff and commit manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLARIS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR=""
COMPANY=""
DRY_RUN=false
VERIFY=false

# Company-specific skills directory (matches rules pattern: skills/{company}/)
# The entire company subdirectory is excluded from sync to Polaris.
# Individual skill names no longer need to be listed here.
EXCLUDE_SKILL_DIRS="kkday"

# Company-specific references to exclude
EXCLUDE_REFERENCES="sasd-confluence.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --company) COMPANY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --verify) VERIFY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  echo "--source is required (e.g. --source ~/work)" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [[ ! -d "$SOURCE_DIR/.claude/skills" ]]; then
  echo "Source doesn't look like a workspace: $SOURCE_DIR/.claude/skills not found" >&2
  exit 1
fi

echo "Syncing from: $SOURCE_DIR"
echo "Syncing to:   $POLARIS_DIR"
[[ "$DRY_RUN" == true ]] && echo "DRY RUN — no files will be modified"
echo ""

# ── Step 1: Sync skills ──────────────────────────────────────────────

echo "Syncing skills..."
for skill_dir in "$SOURCE_DIR"/.claude/skills/*/; do
  skill_name=$(basename "$skill_dir")

  # Skip references (synced separately) and company-specific skill directories
  skip=false
  [[ "$skill_name" == "references" ]] && skip=true
  for excluded_dir in $EXCLUDE_SKILL_DIRS; do
    [[ "$skill_name" == "$excluded_dir" ]] && skip=true && break
  done

  if [[ "$skip" == true ]]; then
    echo "  skip $skill_name"
    continue
  fi

  echo "  + $skill_name"
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$POLARIS_DIR/.claude/skills/$skill_name"
    cp -r "$skill_dir" "$POLARIS_DIR/.claude/skills/$skill_name"
  fi
done

# ── Step 2: Sync references ──────────────────────────────────────────

echo "Syncing references..."
if [[ "$DRY_RUN" == false ]]; then
  for ref_file in "$SOURCE_DIR"/.claude/skills/references/*.md; do
    ref_name=$(basename "$ref_file")
    skip=false
    for excluded in $EXCLUDE_REFERENCES; do
      [[ "$ref_name" == "$excluded" ]] && skip=true && break
    done
    if [[ "$skip" == true ]]; then
      echo "  skip $ref_name"
    else
      echo "  + $ref_name"
      cp "$ref_file" "$POLARIS_DIR/.claude/skills/references/$ref_name"
    fi
  done
fi

# ── Step 3: Sync L1 rules ────────────────────────────────────────────

echo "Syncing L1 rules..."
if [[ "$DRY_RUN" == false ]]; then
  for rule_file in "$SOURCE_DIR"/.claude/rules/*.md; do
    rule_name=$(basename "$rule_file")
    echo "  + $rule_name"
    cp "$rule_file" "$POLARIS_DIR/.claude/rules/$rule_name"
  done
fi

# ── Step 4: Sync L2 rules (company dir → company/) ───────────────────

echo "Syncing L2 rules..."
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
  mkdir -p "$POLARIS_DIR/.claude/rules/company"
  for rule_file in "$L2_SOURCE"*.md; do
    rule_name=$(basename "$rule_file")
    echo "  + $rule_name"
    cp "$rule_file" "$POLARIS_DIR/.claude/rules/company/$rule_name"
  done
fi

# ── Step 5: Sync hooks & settings ────────────────────────────────────

echo "Syncing hooks & settings..."
if [[ "$DRY_RUN" == false ]]; then
  cp "$SOURCE_DIR/.claude/hooks/pre-push-quality-gate.sh" "$POLARIS_DIR/.claude/hooks/pre-push-quality-gate.sh" 2>/dev/null && echo "  + pre-push-quality-gate.sh" || true
  cp "$SOURCE_DIR/.claude/settings.json" "$POLARIS_DIR/.claude/settings.json" 2>/dev/null && echo "  + settings.json" || true
  cp "$SOURCE_DIR/.claude/settings.local.json.example" "$POLARIS_DIR/.claude/settings.local.json.example" 2>/dev/null && echo "  + settings.local.json.example" || true
  cp "$SOURCE_DIR/.claude/settings.local.json.sub-repo-example" "$POLARIS_DIR/.claude/settings.local.json.sub-repo-example" 2>/dev/null && echo "  + settings.local.json.sub-repo-example" || true
fi

# ── Step 6: Sync scripts/ ────────────────────────────────────────────

echo "Syncing scripts/..."
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$POLARIS_DIR/scripts"
  # Sync all .sh scripts; genericize-*.sed are instance-specific (generated by /init), skip them
  for script_file in "$SOURCE_DIR"/scripts/*.sh; do
    script_name=$(basename "$script_file")
    echo "  + $script_name"
    cp "$script_file" "$POLARIS_DIR/scripts/$script_name"
  done
fi

# ── Step 7: Sync _template/ and root workspace-config.yaml ───────────

echo "Syncing _template/ and workspace-config.yaml..."
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$POLARIS_DIR/_template"
  cp "$SOURCE_DIR/_template/workspace-config.yaml" "$POLARIS_DIR/_template/workspace-config.yaml"
  echo "  + _template/workspace-config.yaml"
  cp "$SOURCE_DIR/workspace-config.yaml" "$POLARIS_DIR/workspace-config.yaml"
  echo "  + workspace-config.yaml (root)"
  rm -f "$POLARIS_DIR/workspace-config.example.yaml"
fi

# ── Step 8: Genericize ───────────────────────────────────────────────

echo ""
echo "Genericizing company-specific references..."

if [[ "$DRY_RUN" == false ]]; then
  # Collect all text files to process
  TARGETS=$(find "$POLARIS_DIR/.claude" "$POLARIS_DIR/_template" "$POLARIS_DIR/workspace-config.yaml" \
    -type f \( -name "*.md" -o -name "*.json" -o -name "*.example" -o -name "*.sh" -o -name "*.yaml" \) 2>/dev/null)

  # Find mapping files from company directory (generated by /init)
  MAP_DIR=""
  if [[ -n "$COMPANY" ]]; then
    # Explicit --company flag
    if [[ -f "$SOURCE_DIR/$COMPANY/genericize-map.sed" ]]; then
      MAP_DIR="$SOURCE_DIR/$COMPANY/"
    else
      echo "  WARNING: $SOURCE_DIR/$COMPANY/genericize-map.sed not found"
    fi
  else
    # Auto-detect: first non-template dir that has genericize-map.sed
    for company_dir in "$SOURCE_DIR"/*/; do
      dir_name=$(basename "$company_dir")
      [[ "$dir_name" == "_template" || "$dir_name" == "scripts" ]] && continue
      if [[ -f "$company_dir/genericize-map.sed" ]]; then
        MAP_DIR="$company_dir"
        break
      fi
    done
  fi

  if [[ -z "$MAP_DIR" ]]; then
    echo "  WARNING: No genericize-map.sed found in any company directory"
    echo "  Run /init to generate mapping files, or create them manually from _template/"
  else
    echo "  Using mapping from: $(basename "$MAP_DIR")/"
    echo "$TARGETS" | xargs sed -i '' -f "$MAP_DIR/genericize-map.sed" 2>/dev/null
    [[ -f "$MAP_DIR/genericize-jira.sed" ]] && \
      echo "$TARGETS" | xargs sed -i '' -f "$MAP_DIR/genericize-jira.sed" 2>/dev/null
  fi

  echo "  Genericization complete"
fi

# ── Step 9: Verify (optional) ────────────────────────────────────────

if [[ "$VERIFY" == true ]]; then
  echo ""
  echo "Verifying no company-specific references remain..."

  LEAK_PATTERNS="kkday|KKday|kkday-it|kkday-travel|daniel-lee-kk|GT-[0-9]+|KB2CW|kkday\.atlassian"
  LEAKS=$(grep -rn -E "$LEAK_PATTERNS" \
    "$POLARIS_DIR/.claude" "$POLARIS_DIR/_template" "$POLARIS_DIR/workspace-config.yaml" \
    --include="*.md" --include="*.json" --include="*.sh" --include="*.yaml" \
    2>/dev/null || true)

  if [[ -n "$LEAKS" ]]; then
    echo "  WARNING: Company-specific references found after genericize:"
    echo "$LEAKS" | head -20
    LEAK_COUNT=$(echo "$LEAKS" | wc -l | tr -d ' ')
    [[ "$LEAK_COUNT" -gt 20 ]] && echo "  ... and $((LEAK_COUNT - 20)) more"
    echo ""
    echo "  Add missing patterns to scripts/genericize-map.sed or scripts/genericize-jira.sed"
  else
    echo "  All clean — no company-specific references found"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo "Sync complete!"
echo ""
echo "Next steps:"
echo "  1. cd $POLARIS_DIR"
echo "  2. git diff            — review changes"
echo "  3. git add -A && git commit -m 'sync: update from upstream'"
echo "  4. gh auth switch --user HsuanYuLee"
echo "  5. git push"
echo "  6. gh auth switch --user daniel-lee-kk"
echo "════════════════════════════════════════════"
