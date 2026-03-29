#!/usr/bin/env bash
# sync-from-polaris.sh — Pull framework updates from Polaris into a working instance
#
# This script copies generic framework files from Polaris (upstream template)
# into your working workspace, preserving company-specific files and config.
#
# Usage:
#   ./scripts/sync-from-polaris.sh --polaris ~/polaris [--dry-run]
#
# What it syncs (overwrites instance files):
#   - .claude/skills/ (only skills that exist in Polaris; company-specific skills untouched)
#   - .claude/skills/references/ (except company-specific ones)
#   - .claude/rules/*.md (L1 rules — framework-level)
#   - .claude/hooks/
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - scripts/sync-from-upstream.sh, scripts/sync-from-polaris.sh
#   - _template/ (updated templates)
#
# What it does NOT touch:
#   - CLAUDE.md (instance has its own version)
#   - {company}/ directory (config, mapping files, CLAUDE.md, docs)
#   - .claude/rules/{company}/ (L2 rules — may have local edits)
#   - .claude/skills/{company-specific-skills}/ (not in Polaris)
#   - .claude/settings.local.json (personal settings)
#   - workspace-config.yaml (root config — has instance's company list)
#
# L2 rules strategy:
#   New rules from Polaris (company/) are added to {company}/ with a notice.
#   Existing rules are NOT overwritten — instance may have local customizations.
#   Use --force-rules to overwrite existing L2 rules.
#
# After sync, review the diff and commit manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POLARIS_DIR=""
DRY_RUN=false
FORCE_RULES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --polaris) POLARIS_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force-rules) FORCE_RULES=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$POLARIS_DIR" ]]; then
  echo "--polaris is required (e.g. --polaris ~/polaris)" >&2
  exit 1
fi

POLARIS_DIR="$(cd "$POLARIS_DIR" && pwd)"

if [[ ! -d "$POLARIS_DIR/.claude/skills" ]]; then
  echo "Polaris doesn't look right: $POLARIS_DIR/.claude/skills not found" >&2
  exit 1
fi

# Detect company directory in instance (first subdir with workspace-config.yaml)
COMPANY_DIR=""
COMPANY_NAME=""
for candidate in "$INSTANCE_DIR"/*/; do
  dir_name=$(basename "$candidate")
  [[ "$dir_name" == "_template" ]] && continue
  [[ "$dir_name" == "scripts" ]] && continue
  [[ "$dir_name" == "node_modules" ]] && continue
  if [[ -f "$candidate/workspace-config.yaml" ]]; then
    COMPANY_DIR="$candidate"
    COMPANY_NAME="$dir_name"
    break
  fi
done

echo "Syncing from Polaris: $POLARIS_DIR"
echo "Syncing to instance:  $INSTANCE_DIR"
[[ -n "$COMPANY_NAME" ]] && echo "Company detected:     $COMPANY_NAME"
[[ "$DRY_RUN" == true ]] && echo "DRY RUN — no files will be modified"
echo ""

# Helper: copy file with dry-run support
copy_file() {
  local src="$1" dst="$2" label="$3"
  if [[ "$DRY_RUN" == false ]]; then
    cp "$src" "$dst"
  fi
  echo "  + $label"
}

copy_dir() {
  local src="$1" dst="$2" label="$3"
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
  fi
  echo "  + $label"
}

# ── Step 1: Sync skills ──────────────────────────────────────────────

echo "Syncing skills..."
for skill_dir in "$POLARIS_DIR"/.claude/skills/*/; do
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == "references" ]] && continue

  copy_dir "$skill_dir" "$INSTANCE_DIR/.claude/skills/$skill_name" "$skill_name"
done

# ── Step 2: Sync references ──────────────────────────────────────────

echo "Syncing references..."
for ref_file in "$POLARIS_DIR"/.claude/skills/references/*.md; do
  ref_name=$(basename "$ref_file")
  copy_file "$ref_file" "$INSTANCE_DIR/.claude/skills/references/$ref_name" "$ref_name"
done

# ── Step 3: Sync L1 rules ────────────────────────────────────────────

echo "Syncing L1 rules..."
for rule_file in "$POLARIS_DIR"/.claude/rules/*.md; do
  rule_name=$(basename "$rule_file")
  copy_file "$rule_file" "$INSTANCE_DIR/.claude/rules/$rule_name" "$rule_name"
done

# ── Step 4: Sync L2 rules (company/ → {company}/) ───────────────────

echo "Syncing L2 rules..."
POLARIS_L2="$POLARIS_DIR/.claude/rules/company"

if [[ -d "$POLARIS_L2" ]] && [[ -n "$COMPANY_NAME" ]]; then
  INSTANCE_L2="$INSTANCE_DIR/.claude/rules/$COMPANY_NAME"
  mkdir -p "$INSTANCE_L2" 2>/dev/null || true

  for rule_file in "$POLARIS_L2"/*.md; do
    rule_name=$(basename "$rule_file")

    if [[ -f "$INSTANCE_L2/$rule_name" ]]; then
      if [[ "$FORCE_RULES" == true ]]; then
        copy_file "$rule_file" "$INSTANCE_L2/$rule_name" "$rule_name (overwritten)"
      else
        echo "  skip $rule_name (exists, use --force-rules to overwrite)"
      fi
    else
      copy_file "$rule_file" "$INSTANCE_L2/$rule_name" "$rule_name (new)"
    fi
  done
elif [[ ! -d "$POLARIS_L2" ]]; then
  echo "  skip (no company/ rules in Polaris)"
else
  echo "  skip (no company detected in instance)"
fi

# ── Step 5: Sync hooks & settings ────────────────────────────────────

echo "Syncing hooks & settings..."
if [[ "$DRY_RUN" == false ]]; then
  cp "$POLARIS_DIR/.claude/hooks/pre-push-quality-gate.sh" "$INSTANCE_DIR/.claude/hooks/pre-push-quality-gate.sh" 2>/dev/null && echo "  + pre-push-quality-gate.sh" || true
  cp "$POLARIS_DIR/.claude/settings.json" "$INSTANCE_DIR/.claude/settings.json" 2>/dev/null && echo "  + settings.json" || true
  cp "$POLARIS_DIR/.claude/settings.local.json.example" "$INSTANCE_DIR/.claude/settings.local.json.example" 2>/dev/null && echo "  + settings.local.json.example" || true
  cp "$POLARIS_DIR/.claude/settings.local.json.sub-repo-example" "$INSTANCE_DIR/.claude/settings.local.json.sub-repo-example" 2>/dev/null && echo "  + settings.local.json.sub-repo-example" || true
else
  echo "  + pre-push-quality-gate.sh"
  echo "  + settings.json"
  echo "  + settings.local.json.example"
  echo "  + settings.local.json.sub-repo-example"
fi

# ── Step 6: Sync scripts ─────────────────────────────────────────────

echo "Syncing scripts/..."
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$INSTANCE_DIR/scripts"
fi
for script_file in "$POLARIS_DIR"/scripts/*.sh; do
  script_name=$(basename "$script_file")
  copy_file "$script_file" "$INSTANCE_DIR/scripts/$script_name" "$script_name"
done

# ── Step 7: Sync _template/ ──────────────────────────────────────────

echo "Syncing _template/..."
if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$INSTANCE_DIR/_template"
fi
for tmpl_file in "$POLARIS_DIR"/_template/*; do
  tmpl_name=$(basename "$tmpl_file")
  copy_file "$tmpl_file" "$INSTANCE_DIR/_template/$tmpl_name" "$tmpl_name"
done

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo "Sync complete!"
echo ""
echo "NOT synced (instance-specific):"
echo "  - CLAUDE.md"
echo "  - workspace-config.yaml"
[[ -n "$COMPANY_NAME" ]] && echo "  - $COMPANY_NAME/ (config, mapping, docs)"
echo "  - .claude/settings.local.json"
echo ""
echo "Next steps:"
echo "  1. git diff            — review changes"
echo "  2. git add -A && git commit -m 'sync: pull framework updates from Polaris'"
echo "════════════════════════════════════════════"
