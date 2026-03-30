#!/usr/bin/env bash
# sync-to-polaris.sh — Push framework changes from working instance to Polaris template
#
# This is the reverse of sync-from-polaris.sh. It copies framework-level files
# from your working instance back to the Polaris template repo.
#
# Usage:
#   ./scripts/sync-to-polaris.sh [--polaris ~/polaris] [--dry-run] [--commit] [--push]
#
# What it syncs:
#   - .claude/skills/ (only generic skills; company-specific excluded)
#   - .claude/skills/references/
#   - .claude/rules/*.md (L1 rules only, not {company}/ subdirs)
#   - .claude/hooks/
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - scripts/*.sh
#   - _template/
#   - CHANGELOG.md, VERSION, README.md, CLAUDE.md
#
# What it does NOT sync:
#   - {company}/ directories (config, mapping, docs, CLAUDE.md)
#   - .claude/rules/{company}/ (L2 rules — instance-specific)
#   - .claude/skills/{company}/ (company-specific skills)
#   - .claude/polaris-backlog.md (instance-specific)
#   - workspace-config.yaml (instance-specific)
#   - .claude/settings.local.json (personal settings)
#
# --commit: auto-commit in template with version from VERSION file
# --push:   auto-push (includes gh auth switch for dual-account setups)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POLARIS_DIR="${HOME}/polaris"
DRY_RUN=false
AUTO_COMMIT=false
AUTO_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --polaris) POLARIS_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --commit) AUTO_COMMIT=true; shift ;;
    --push) AUTO_PUSH=true; AUTO_COMMIT=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

POLARIS_DIR="$(cd "$POLARIS_DIR" && pwd)"

if [[ ! -d "$POLARIS_DIR/.claude/skills" ]]; then
  echo "Polaris not found at $POLARIS_DIR" >&2
  echo "Use --polaris <path> to specify location" >&2
  exit 1
fi

# Read version from instance
VERSION=""
if [[ -f "$INSTANCE_DIR/VERSION" ]]; then
  VERSION=$(cat "$INSTANCE_DIR/VERSION" | tr -d '[:space:]')
fi

# Detect company directories to exclude
COMPANY_DIRS=()
for candidate in "$INSTANCE_DIR"/*/; do
  dir_name=$(basename "$candidate")
  [[ "$dir_name" == "_template" ]] && continue
  [[ "$dir_name" == "scripts" ]] && continue
  [[ "$dir_name" == "node_modules" ]] && continue
  [[ "$dir_name" == "docs" ]] && continue
  if [[ -f "$candidate/workspace-config.yaml" ]]; then
    COMPANY_DIRS+=("$dir_name")
  fi
done

echo "╔══════════════════════════════════════════╗"
echo "║  sync-to-polaris.sh                      ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Instance:  $INSTANCE_DIR"
echo "Polaris:   $POLARIS_DIR"
echo "Version:   ${VERSION:-unknown}"
echo "Companies: ${COMPANY_DIRS[*]:-none} (excluded from sync)"
[[ "$DRY_RUN" == true ]] && echo "Mode:      DRY RUN"
echo ""

copy_file() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$src" ]]; then return; fi
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
  echo "  + $label"
}

copy_dir() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -d "$src" ]]; then return; fi
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
  fi
  echo "  + $label/"
}

# ── Step 1: Sync skills (exclude company-specific) ─────────────────

echo "Skills..."
for skill_dir in "$INSTANCE_DIR"/.claude/skills/*/; do
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == "references" ]] && continue

  # Skip company-specific skill directories
  skip=false
  for company in "${COMPANY_DIRS[@]}"; do
    [[ "$skill_name" == "$company" ]] && skip=true && break
  done
  [[ "$skip" == true ]] && continue

  copy_dir "$skill_dir" "$POLARIS_DIR/.claude/skills/$skill_name" "$skill_name"
done

# ── Step 2: Sync references ────────────────────────────────────────

echo "References..."
mkdir -p "$POLARIS_DIR/.claude/skills/references" 2>/dev/null || true
for ref_file in "$INSTANCE_DIR"/.claude/skills/references/*.md; do
  ref_name=$(basename "$ref_file")
  copy_file "$ref_file" "$POLARIS_DIR/.claude/skills/references/$ref_name" "$ref_name"
done

# ── Step 3: Sync L1 rules (root only, skip company subdirs) ───────

echo "L1 Rules..."
for rule_file in "$INSTANCE_DIR"/.claude/rules/*.md; do
  rule_name=$(basename "$rule_file")
  copy_file "$rule_file" "$POLARIS_DIR/.claude/rules/$rule_name" "$rule_name"
done

# ── Step 4: Sync hooks & settings ──────────────────────────────────

echo "Hooks & settings..."
copy_file "$INSTANCE_DIR/.claude/hooks/pre-push-quality-gate.sh" \
          "$POLARIS_DIR/.claude/hooks/pre-push-quality-gate.sh" "pre-push-quality-gate.sh"
copy_file "$INSTANCE_DIR/.claude/settings.json" \
          "$POLARIS_DIR/.claude/settings.json" "settings.json"
copy_file "$INSTANCE_DIR/.claude/settings.local.json.example" \
          "$POLARIS_DIR/.claude/settings.local.json.example" "settings.local.json.example"
copy_file "$INSTANCE_DIR/.claude/settings.local.json.sub-repo-example" \
          "$POLARIS_DIR/.claude/settings.local.json.sub-repo-example" "settings.local.json.sub-repo-example"

# ── Step 5: Sync scripts ──────────────────────────────────────────

echo "Scripts..."
for script_file in "$INSTANCE_DIR"/scripts/*.sh; do
  script_name=$(basename "$script_file")
  copy_file "$script_file" "$POLARIS_DIR/scripts/$script_name" "$script_name"
done

# ── Step 6: Sync _template/ ───────────────────────────────────────

echo "Templates..."
if [[ -d "$INSTANCE_DIR/_template" ]]; then
  for tmpl in "$INSTANCE_DIR"/_template/*; do
    tmpl_name=$(basename "$tmpl")
    if [[ -d "$tmpl" ]]; then
      copy_dir "$tmpl" "$POLARIS_DIR/_template/$tmpl_name" "$tmpl_name"
    else
      copy_file "$tmpl" "$POLARIS_DIR/_template/$tmpl_name" "$tmpl_name"
    fi
  done
fi

# ── Step 7: Sync top-level files ──────────────────────────────────

echo "Top-level files..."
copy_file "$INSTANCE_DIR/CHANGELOG.md" "$POLARIS_DIR/CHANGELOG.md" "CHANGELOG.md"
copy_file "$INSTANCE_DIR/VERSION"      "$POLARIS_DIR/VERSION"      "VERSION"
copy_file "$INSTANCE_DIR/README.md"    "$POLARIS_DIR/README.md"    "README.md"
copy_file "$INSTANCE_DIR/CLAUDE.md"    "$POLARIS_DIR/CLAUDE.md"    "CLAUDE.md"

# ── Step 8: Auto-commit ──────────────────────────────────────────

echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "DRY RUN complete. No files were modified."
  exit 0
fi

CHANGES=$(git -C "$POLARIS_DIR" status --porcelain | wc -l | tr -d ' ')
if [[ "$CHANGES" == "0" ]]; then
  echo "No changes detected — template is already up to date."
  exit 0
fi

echo "$CHANGES file(s) changed in template."

if [[ "$AUTO_COMMIT" == true ]]; then
  echo ""
  echo "Committing..."
  git -C "$POLARIS_DIR" add -A

  # Use the latest instance commit message as reference
  INSTANCE_MSG=$(git -C "$INSTANCE_DIR" log -1 --format="%s")
  git -C "$POLARIS_DIR" commit -m "$INSTANCE_MSG"

  if [[ -n "$VERSION" ]]; then
    # Tag if not already tagged
    if ! git -C "$POLARIS_DIR" tag -l "v$VERSION" | grep -q "v$VERSION"; then
      git -C "$POLARIS_DIR" tag "v$VERSION"
      echo "Tagged v$VERSION"
    fi
  fi
fi

# ── Step 9: Auto-push (with account switch) ───────────────────────

if [[ "$AUTO_PUSH" == true ]]; then
  echo ""
  echo "Pushing to remote..."

  # Detect if we need to switch GitHub accounts
  REMOTE_URL=$(git -C "$POLARIS_DIR" remote get-url origin 2>/dev/null || true)
  CURRENT_USER=$(gh auth status 2>&1 | grep "Logged in" | head -1 | awk '{print $NF}' || true)
  NEEDS_SWITCH=false
  ORIGINAL_USER="$CURRENT_USER"

  # If remote is HsuanYuLee but current user is not, switch
  if [[ "$REMOTE_URL" == *"HsuanYuLee"* ]] && [[ "$CURRENT_USER" != "HsuanYuLee" ]]; then
    echo "Switching GitHub account: $CURRENT_USER → HsuanYuLee"
    gh auth switch --user HsuanYuLee
    gh auth setup-git
    NEEDS_SWITCH=true
  fi

  git -C "$POLARIS_DIR" push origin main --tags

  # Switch back
  if [[ "$NEEDS_SWITCH" == true ]]; then
    echo "Switching back: HsuanYuLee → $ORIGINAL_USER"
    gh auth switch --user "$ORIGINAL_USER"
    gh auth setup-git
  fi
fi

# ── Summary ───────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo "Sync complete! Template at v${VERSION:-?}"
[[ "$AUTO_COMMIT" == true ]] && echo "✓ Committed"
[[ "$AUTO_PUSH" == true ]] && echo "✓ Pushed + account restored"
if [[ "$AUTO_COMMIT" == false ]]; then
  echo ""
  echo "Next steps:"
  echo "  cd $POLARIS_DIR"
  echo "  git diff            — review changes"
  echo "  git add -A && git commit -m 'feat: Polaris v$VERSION'"
  echo "  git tag v$VERSION"
  echo "  git push origin main --tags"
fi
echo "════════════════════════════════════════════"
