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
#   - .claude/hooks/*.sh (all hook scripts)
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - .github/copilot-instructions.md + .github/.generated/
#   - scripts/**/*.sh (recursive, includes scripts/env/ subfolder)
#   - _template/
#   - CHANGELOG.md, VERSION, README.md, README.zh-TW.md, CLAUDE.md
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

# ── Leak check: scan synced files for company-specific patterns ──
leak_check() {
  local polaris_dir="$1"
  shift
  local company_dirs=("$@")

  if [[ ${#company_dirs[@]} -eq 0 ]]; then return 0; fi

  # Collect patterns from each company's workspace-config.yaml
  local patterns=()
  for company in "${company_dirs[@]}"; do
    local cfg="$INSTANCE_DIR/$company/workspace-config.yaml"
    [[ -f "$cfg" ]] || continue

    # JIRA project keys as ticket patterns (e.g., GT-\d+, KB2CW-\d+)
    # Use ticket format (KEY-123) to avoid false positives on short keys like "GT"
    while IFS= read -r key; do
      [[ -n "$key" ]] && patterns+=("${key}-[0-9]+")
    done < <(python3 -c "
import yaml, sys
with open('$cfg') as f:
    d = yaml.safe_load(f)
for p in d.get('jira', {}).get('projects', []):
    k = p.get('key', '')
    if k and len(k) >= 2:
        print(k)
" 2>/dev/null || true)

    # Domain names (e.g., kkday.com, sit.kkday.com)
    while IFS= read -r domain; do
      [[ -n "$domain" ]] && patterns+=("$domain")
    done < <(python3 -c "
import yaml, sys
with open('$cfg') as f:
    d = yaml.safe_load(f)
urls = d.get('web_urls', {})
for k, v in urls.items():
    if isinstance(v, str) and '.' in v:
        # Extract domain from URL
        import re
        m = re.search(r'://([^/]+)', v)
        if m:
            print(m.group(1))
ji = d.get('jira', {}).get('instance', '')
if ji:
    print(ji)
" 2>/dev/null || true)

    # Slack channel IDs (e.g., C08NJ2GL204)
    while IFS= read -r ch; do
      [[ -n "$ch" ]] && patterns+=("$ch")
    done < <(python3 -c "
import yaml, sys
with open('$cfg') as f:
    d = yaml.safe_load(f)
channels = d.get('slack', {}).get('channels', {})
for k, v in channels.items():
    if isinstance(v, str) and v.startswith('C'):
        print(v)
" 2>/dev/null || true)

    # GitHub org (e.g., kkday-it)
    while IFS= read -r org; do
      [[ -n "$org" ]] && patterns+=("$org")
    done < <(python3 -c "
import yaml, sys
with open('$cfg') as f:
    d = yaml.safe_load(f)
org = d.get('github', {}).get('org', '')
if org:
    print(org)
" 2>/dev/null || true)
  done

  if [[ ${#patterns[@]} -eq 0 ]]; then return 0; fi

  # Deduplicate patterns
  local unique_patterns
  unique_patterns=$(printf '%s\n' "${patterns[@]}" | sort -u)

  # Build grep pattern (alternation)
  local grep_pattern
  grep_pattern=$(echo "$unique_patterns" | paste -sd '|' -)

  # Scan all .md files in the polaris template
  local hits
  hits=$(grep -rn -E "$grep_pattern" "$polaris_dir/.claude/" "$polaris_dir/docs/" "$polaris_dir/CLAUDE.md" "$polaris_dir/README.md" "$polaris_dir/README.zh-TW.md" 2>/dev/null | grep -v "Binary file" || true)

  if [[ -n "$hits" ]]; then
    echo ""
    echo "⚠  Leak check: company-specific patterns found in template!"
    echo "   Patterns searched: $(echo "$unique_patterns" | tr '\n' ', ' | sed 's/,$//')"
    echo ""
    echo "$hits" | head -20
    local count
    count=$(echo "$hits" | wc -l | tr -d ' ')
    if [[ "$count" -gt 20 ]]; then
      echo "   ... and $((count - 20)) more matches"
    fi
    echo ""
    echo "   These references survived auto-genericize. Update your company's"
    echo "   genericize-map.sed / genericize-jira.sed to cover these patterns."
    echo "   Continuing push (warn only, not blocking)."
    return 0
  fi

  return 0
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

  # Skip maintainer-only skills (scope: maintainer-only in SKILL.md frontmatter)
  if [[ -f "$skill_dir/SKILL.md" ]]; then
    if grep -q 'scope:.*maintainer-only' "$skill_dir/SKILL.md" 2>/dev/null; then
      echo "  ~ $skill_name/ (maintainer-only, skipped)"
      continue
    fi
  fi

  copy_dir "$skill_dir" "$POLARIS_DIR/.claude/skills/$skill_name" "$skill_name"
done

# ── Step 2: Sync references ────────────────────────────────────────

echo "References..."
mkdir -p "$POLARIS_DIR/.claude/skills/references" 2>/dev/null || true
for ref_file in "$INSTANCE_DIR"/.claude/skills/references/*.md; do
  ref_name=$(basename "$ref_file")
  # Skip user-specific learning data
  [[ "$ref_name" == "learning-queue.md" || "$ref_name" == "learning-archive.md" ]] && continue
  copy_file "$ref_file" "$POLARIS_DIR/.claude/skills/references/$ref_name" "$ref_name"
done

# ── Step 3: Sync L1 rules (root only, skip company subdirs) ───────

echo "L1 Rules..."
for rule_file in "$INSTANCE_DIR"/.claude/rules/*.md; do
  rule_name=$(basename "$rule_file")
  copy_file "$rule_file" "$POLARIS_DIR/.claude/rules/$rule_name" "$rule_name"
done

# ── Step 4: Sync hooks & settings ──────────────────────────────────

echo "Hooks..."
mkdir -p "$POLARIS_DIR/.claude/hooks" 2>/dev/null || true
for hook_file in "$INSTANCE_DIR"/.claude/hooks/*.sh; do
  [[ -f "$hook_file" ]] || continue
  hook_name=$(basename "$hook_file")
  copy_file "$hook_file" "$POLARIS_DIR/.claude/hooks/$hook_name" "$hook_name"
done

echo "Settings..."
copy_file "$INSTANCE_DIR/.claude/settings.json" \
          "$POLARIS_DIR/.claude/settings.json" "settings.json"
copy_file "$INSTANCE_DIR/.claude/settings.local.json.example" \
          "$POLARIS_DIR/.claude/settings.local.json.example" "settings.local.json.example"
copy_file "$INSTANCE_DIR/.claude/settings.local.json.sub-repo-example" \
          "$POLARIS_DIR/.claude/settings.local.json.sub-repo-example" "settings.local.json.sub-repo-example"

# ── Step 5: Sync scripts (recursive — supports scripts/env/ etc.) ─

echo "Scripts..."
while IFS= read -r script_file; do
  # Preserve subfolder structure (e.g., scripts/env/_lib.sh)
  rel_path="${script_file#"$INSTANCE_DIR"/}"
  target_path="$POLARIS_DIR/$rel_path"
  target_dir=$(dirname "$target_path")
  mkdir -p "$target_dir"
  copy_file "$script_file" "$target_path" "$rel_path"
done < <(find "$INSTANCE_DIR/scripts" -name "*.sh" -type f -not -path "*/node_modules/*" -not -path "*/e2e-results/*")

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

# ── Step 7: Sync docs/ ───────────────────────────────────────────

if [[ -d "$INSTANCE_DIR/docs" ]]; then
  echo "Docs..."
  for doc in "$INSTANCE_DIR/docs/"*.md; do
    [[ -f "$doc" ]] || continue
    doc_name="$(basename "$doc")"
    copy_file "$doc" "$POLARIS_DIR/docs/$doc_name" "$doc_name"
  done
fi

# ── Step 8: Sync top-level files ──────────────────────────────────

echo "Top-level files..."
copy_file "$INSTANCE_DIR/CHANGELOG.md" "$POLARIS_DIR/CHANGELOG.md" "CHANGELOG.md"
copy_file "$INSTANCE_DIR/VERSION"      "$POLARIS_DIR/VERSION"      "VERSION"
copy_file "$INSTANCE_DIR/README.md"       "$POLARIS_DIR/README.md"       "README.md"
copy_file "$INSTANCE_DIR/README.zh-TW.md" "$POLARIS_DIR/README.zh-TW.md" "README.zh-TW.md"
copy_file "$INSTANCE_DIR/CLAUDE.md"    "$POLARIS_DIR/CLAUDE.md"    "CLAUDE.md"

# ── Step 8b: Sync .github/ (Copilot instructions + workflows) ────

if [[ -d "$INSTANCE_DIR/.github" ]]; then
  echo "GitHub config..."
  mkdir -p "$POLARIS_DIR/.github/.generated" 2>/dev/null || true
  copy_file "$INSTANCE_DIR/.github/copilot-instructions.md" \
            "$POLARIS_DIR/.github/copilot-instructions.md" "copilot-instructions.md"
  copy_file "$INSTANCE_DIR/.github/.generated/copilot-rules-manifest.txt" \
            "$POLARIS_DIR/.github/.generated/copilot-rules-manifest.txt" "copilot-rules-manifest.txt"
fi

# ── Step 9: Auto-commit ──────────────────────────────────────────

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

# ── Step 9a: Auto-genericize company-specific references ──────────
# Apply sed maps from each company directory to the polaris template.
# This runs BEFORE commit so the template never contains company-specific strings.

genericize_count=0
for company in "${COMPANY_DIRS[@]}"; do
  MAP_SED="$INSTANCE_DIR/$company/genericize-map.sed"
  JIRA_SED="$INSTANCE_DIR/$company/genericize-jira.sed"

  if [[ ! -f "$MAP_SED" && ! -f "$JIRA_SED" ]]; then
    continue
  fi

  # Find all .md files in the template (skills, rules, docs, top-level)
  while IFS= read -r -d '' mdfile; do
    original=$(cat "$mdfile")
    modified="$original"

    if [[ -f "$MAP_SED" ]]; then
      modified=$(echo "$modified" | sed -f "$MAP_SED")
    fi
    if [[ -f "$JIRA_SED" ]]; then
      modified=$(echo "$modified" | sed -f "$JIRA_SED")
    fi

    if [[ "$modified" != "$original" ]]; then
      echo "$modified" > "$mdfile"
      genericize_count=$((genericize_count + 1))
    fi
  done < <(find "$POLARIS_DIR/.claude" "$POLARIS_DIR/docs" "$POLARIS_DIR/CLAUDE.md" "$POLARIS_DIR/README.md" "$POLARIS_DIR/README.zh-TW.md" \( -name '*.md' -o -name '*.py' -o -name '*.sh' \) -print0 2>/dev/null)
done

if [[ "$genericize_count" -gt 0 ]]; then
  echo ""
  echo "Auto-genericized $genericize_count file(s) in template."
fi

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

# ── Step 9b: Leak check ──────────────────────────────────────────

if [[ "$AUTO_COMMIT" == true ]]; then
  leak_check "$POLARIS_DIR" "${COMPANY_DIRS[@]}"
fi

# ── Step 10: Auto-push (with account switch) ──────────────────────

if [[ "$AUTO_PUSH" == true ]]; then
  echo ""
  echo "Pushing to remote..."

  # Detect repo slug and if we need to switch GitHub accounts
  REMOTE_URL=$(git -C "$POLARIS_DIR" remote get-url origin 2>/dev/null || true)
  REPO_SLUG=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|')
  CURRENT_USER=$(gh auth status 2>&1 | grep "Active account: true" -B3 | grep "Logged in" | head -1 | sed 's/.*account //' | awk '{print $1}' || true)
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

  # Create GitHub release if tag was created and release doesn't exist
  if [[ -n "$VERSION" ]]; then
    TAG_NAME="v$VERSION"
    RELEASE_EXISTS=$(gh release view "$TAG_NAME" --repo "$REPO_SLUG" --json tagName 2>/dev/null || echo "")
    if [[ -z "$RELEASE_EXISTS" ]]; then
      # Extract changelog section for this version
      RELEASE_NOTES=$(awk -v ver="$VERSION" '
        $0 ~ "^## \\[" ver "\\]" { found=1; next }
        found && /^## \[/ { exit }
        found { print }
      ' "$INSTANCE_DIR/CHANGELOG.md" | sed '/^$/d')
      [[ -z "$RELEASE_NOTES" ]] && RELEASE_NOTES="Release $TAG_NAME"

      gh release create "$TAG_NAME" \
        --repo "$REPO_SLUG" \
        --title "Polaris $TAG_NAME" \
        --notes "$RELEASE_NOTES" \
        --verify-tag 2>/dev/null && echo "✓ Release $TAG_NAME created" || echo "⚠ Release creation failed (non-blocking)"
    fi
  fi

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
