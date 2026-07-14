#!/usr/bin/env bash
# sync-to-polaris.sh — Push framework changes from working instance to Polaris template
#
# This is the reverse of sync-from-polaris.sh. It copies framework-level files
# from your working instance back to the Polaris template repo.
#
# Usage:
#   ./scripts/sync-to-polaris.sh [--polaris ~/polaris] [--dry-run] [--commit] [--push] [--no-prune] [--leak-warn-only]
#
# What it syncs:
#   - .claude/skills/ (only generic skills; company-specific excluded)
#   - .claude/skills/references/
#   - .claude/rules/*.md (L1 rules only, not {company}/ subdirs)
#   - .agents/skills symlink (Codex runtime alias)
#   - .codex/AGENTS.md + .codex/.generated/
#   - .claude/hooks/*.sh (all hook scripts)
#   - .claude/settings.json
#   - .claude/settings.local.json.example
#   - .claude/settings.local.json.sub-repo-example
#   - .github/copilot-instructions.md + .github/.generated/
#   - scripts/**/*.sh, scripts/**/*.py, scripts/**/*.mjs, and scripts/manifest.json
#   - .changeset/ mechanism only: config.json, README.md, *.cjs formatter
#   - _template/
#   - docs-manager/ (framework docs browser app, excluding generated outputs)
#   - .gitignore, CHANGELOG.md, VERSION, README.md, README.zh-TW.md, CLAUDE.md
#   - root package metadata: package.json, pnpm-workspace.yaml, pnpm-lock.yaml
#
# What it does NOT sync:
#   - {company}/ directories (config, mapping, docs, CLAUDE.md)
#   - .claude/rules/{company}/ (L2 rules — instance-specific)
#   - .claude/skills/{company}/ (company-specific skills)
#   - .claude/polaris-backlog.md (instance-specific)
#   - workspace-config.yaml (instance-specific)
#   - .claude/settings.local.json (personal settings)
#   - docs-manager/src/content/docs/specs/ (local canonical specs source)
#   - .changeset/*.md entries (unconsumed changesets — instance/PR-local, never leak)
#
# --commit: auto-commit in template with version from VERSION file
# --push:   auto-push (includes gh auth switch for dual-account setups)
# --no-prune: skip removing stale files in template (prune is ON by default)
# --leak-warn-only: report template leaks without blocking commit/push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTANCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
POLARIS_DIR="${HOME}/polaris"
DRY_RUN=false
AUTO_COMMIT=false
AUTO_PUSH=false
PRUNE=true
LEAK_BLOCKING=true

read_workspace_language() {
  local start="${1:-$INSTANCE_DIR}"
  local dir=""
  local highest=""
  local config_path=""

  if [[ -d "$start" ]]; then
    dir="$(cd "$start" 2>/dev/null && pwd || true)"
  else
    dir="$(cd "$(dirname "$start")" 2>/dev/null && pwd || true)"
  fi
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -f "$dir/workspace-config.yaml" ]]; then
      highest="$dir"
    fi
    dir="$(dirname "$dir")"
  done
  [[ -n "$highest" ]] && config_path="$highest/workspace-config.yaml"
  [[ -n "$config_path" && -f "$config_path" ]] || return 0
  awk -F ':' '
    /^[[:space:]]*language[[:space:]]*:/ {
      v=$2
      sub(/#.*/, "", v)
      gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", v)
      if (v != "") print v
      exit
    }
  ' "$config_path"
}

is_zh_language() {
  case "$1" in
    zh|zh-*|zh_*) return 0 ;;
    *) return 1 ;;
  esac
}

release_notes_fallback() {
  local tag_name="$1"
  if is_zh_language "$(read_workspace_language "$INSTANCE_DIR")"; then
    printf 'Polaris %s 發版。\n' "$tag_name"
  else
    printf 'Release %s\n' "$tag_name"
  fi
}

# gate_release_notes: DP-421 T3 — the GitHub release notes are a DERIVED VIEW of
# CHANGELOG.md. Per canonical-contract-governance § Derived Artifact Read
# Boundary, the business language gate must read the AUTHORITATIVE source (the
# CHANGELOG version section), NOT the mechanically-derived release-notes view. The
# changeset body was already gated at authoring time
# (scripts/gates/gate-changeset.sh); CHANGELOG is assembled from those changesets.
# This source-conformance / parity check verifies the CHANGELOG section conforms to
# the workspace authoring gate — if it passes, the derived release notes pass by
# construction; a tampered / non-conformant CHANGELOG section is still caught here.
# The prior independent --blocking language gate on the derived notes file is
# removed (it duplicated a check the gated source already guarantees).
gate_release_notes() {
  local version="$1"
  local changelog="${2:-$INSTANCE_DIR/CHANGELOG.md}"
  local language="${3:-}"
  local section_file rc
  [[ -f "$changelog" ]] || return 0
  [[ -n "$language" ]] || language="$(read_workspace_language "$INSTANCE_DIR")"
  section_file="$(mktemp -t sync-to-polaris-changelog-section.XXXXXX.md)"
  awk -v ver="$version" '
    $0 ~ "^## \\[" ver "\\]" { found=1; next }
    found && /^## \[/ { exit }
    found { print }
  ' "$changelog" >"$section_file"
  # Empty section — this version has no CHANGELOG entry, so the release notes fall
  # back to a producer-generated default already in the workspace language.
  # Nothing is derived from CHANGELOG here, so parity holds trivially.
  if [[ ! -s "$section_file" ]]; then
    rm -f "$section_file"
    return 0
  fi
  local gate_args=(--blocking --mode artifact)
  [[ -n "$language" ]] && gate_args+=(--language "$language")
  if bash "$SCRIPT_DIR/validate-language-policy.sh" "${gate_args[@]}" "$section_file" >/dev/null 2>&1; then
    rc=0
  else
    rc=$?
  fi
  rm -f "$section_file"
  return "$rc"
}

# DP-421 T3: hermetic parity probe. Runs ONLY the CHANGELOG source-conformance /
# parity check used by the release tail, so the contract is deterministically
# testable without git/gh side effects. Handled before the main arg parser and the
# POLARIS_DIR resolution so no template checkout is required.
if [[ "${1:-}" == "--check-release-notes-parity" ]]; then
  shift
  probe_version=""
  probe_changelog=""
  probe_language=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) probe_version="${2:-}"; shift 2 ;;
      --changelog) probe_changelog="${2:-}"; shift 2 ;;
      --language) probe_language="${2:-}"; shift 2 ;;
      *) echo "sync-to-polaris: unknown --check-release-notes-parity arg: $1" >&2; exit 2 ;;
    esac
  done
  [[ -n "$probe_version" ]] || { echo "sync-to-polaris: --check-release-notes-parity requires --version" >&2; exit 2; }
  if gate_release_notes "$probe_version" "${probe_changelog:-$INSTANCE_DIR/CHANGELOG.md}" "$probe_language"; then
    echo "sync-to-polaris: release-notes source parity PASS for $probe_version" >&2
    exit 0
  else
    echo "sync-to-polaris: release-notes source parity FAIL for $probe_version" >&2
    exit 1
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --polaris) POLARIS_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --commit) AUTO_COMMIT=true; shift ;;
    --push) AUTO_PUSH=true; AUTO_COMMIT=true; shift ;;
    --prune) PRUNE=true; shift ;;
    --no-prune) PRUNE=false; shift ;;
    --leak-blocking) LEAK_BLOCKING=true; shift ;;
    --leak-warn-only) LEAK_BLOCKING=false; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

POLARIS_DIR="$(cd "$POLARIS_DIR" && pwd)"

if [[ ! -d "$POLARIS_DIR/.claude/skills" ]]; then
  echo "Polaris not found at $POLARIS_DIR" >&2
  echo "Use --polaris <path> to specify location" >&2
  exit 1
fi

require_clean_tracked_source() {
  local dirty

  if ! git -C "$INSTANCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: release sync source must be a clean git worktree: $INSTANCE_DIR" >&2
    echo "Commit your release changes, stash local edits, or run from a clean worktree before using --commit/--push." >&2
    exit 1
  fi

  dirty="$(git -C "$INSTANCE_DIR" status --porcelain --untracked-files=no)"
  if [[ -n "$dirty" ]]; then
    echo "ERROR: dirty tracked source tree detected before template sync." >&2
    echo "Commit the tracked changes, stash them, or run sync-to-polaris from a clean worktree before using --commit/--push." >&2
    echo "" >&2
    echo "Dirty tracked files:" >&2
    printf '%s\n' "$dirty" | sed 's/^/  /' >&2
    exit 1
  fi
}

if [[ "$AUTO_COMMIT" == true && "$DRY_RUN" == false ]]; then
  require_clean_tracked_source
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
[[ "$PRUNE" == true ]] && echo "Prune:     ON (will remove stale files)"
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

    # JIRA project keys as ticket patterns (e.g., DEMO-\d+, SAMPLE-\d+)
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

    # Domain names (e.g., exampleco.com, sit.exampleco.com)
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

    # Slack channel IDs (e.g., C0123456789)
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

    # GitHub org (e.g., example-org)
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

run_template_leak_check() {
  [[ ${#COMPANY_DIRS[@]} -gt 0 ]] || return 0

  local scanner="$INSTANCE_DIR/scripts/scan-template-leaks.sh"
  if [[ ! -x "$scanner" ]]; then
    echo "⚠  Template leak scanner missing; falling back to legacy warn-only check."
    leak_check "$POLARIS_DIR" "${COMPANY_DIRS[@]}"
    return 0
  fi

  echo ""
  echo "Template leak check..."
  if [[ "$LEAK_BLOCKING" == true ]]; then
    "$scanner" --workspace "$INSTANCE_DIR" --template "$POLARIS_DIR" --source template --format summary --blocking
  else
    "$scanner" --workspace "$INSTANCE_DIR" --template "$POLARIS_DIR" --source template --format summary || true
  fi
}

copy_dir() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -d "$src" ]]; then return; fi
  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    find "$dst" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    find "$dst" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
  fi
  echo "  + $label/"
}

copy_dir_filtered() {
  local src="$1" dst="$2" label="$3"
  shift 3
  local exclude_args=("$@")
  local find_args=()

  if [[ ! -d "$src" ]]; then return; fi

  for pattern in "${exclude_args[@]}"; do
    find_args+=(-not -path "$pattern")
  done

  if [[ "$DRY_RUN" == false ]]; then
    rm -rf "$dst"
    mkdir -p "$dst"
    while IFS= read -r -d '' file; do
      local rel_path target_path
      rel_path="${file#"$src"/}"
      target_path="$dst/$rel_path"
      mkdir -p "$(dirname "$target_path")"
      cp -p "$file" "$target_path"
    done < <(find "$src" -type f "${find_args[@]}" -print0)
  fi
  echo "  + $label/"
}

ensure_template_gitignore_allowlist() {
  local gitignore="$POLARIS_DIR/.gitignore"

  [[ "$DRY_RUN" == false ]] || return 0
  [[ -f "$gitignore" ]] || return 0

  if grep -q '^!docs-manager/$' "$gitignore" \
    && grep -q '^!.github/$' "$gitignore" \
    && grep -q '^!.agents/$' "$gitignore" \
    && grep -q '^!.codex/$' "$gitignore"; then
    return 0
  fi

  cat >> "$gitignore" <<'EOF'

# ── docs-manager/ specs browser (Starlight app) ──
!docs-manager/
!docs-manager/**
docs-manager/_sidebar.md
docs-manager/.astro/
docs-manager/dist/
docs-manager/node_modules/
docs-manager/public/evidence/
docs-manager/src/content/docs/specs/

# ── GitHub config (Copilot instructions + generated manifests) ──
!.github/
!.github/**

# ── Codex compatibility files ──
!.agents/
!.agents/skills
!.agents/skills/**
!.codex/
!.codex/AGENTS.md
!.codex/.generated/
!.codex/.generated/**
EOF
}

create_symlink() {
  local target="$1" link_path="$2" label="$3"
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$link_path")"
    rm -rf "$link_path"
    ln -s "$target" "$link_path"
  fi
  echo "  + $label -> $target"
}

# ── Step 1: Sync skills (exclude company-specific) ─────────────────

echo "Skills..."
for skill_dir in "$INSTANCE_DIR"/.claude/skills/*/; do
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == "references" ]] && continue
  if [[ ! -f "$skill_dir/SKILL.md" ]]; then
    echo "  ~ $skill_name/ (namespace/no SKILL.md, skipped)"
    continue
  fi

  # Skip company-specific skill directories
  skip=false
  if [[ ${#COMPANY_DIRS[@]} -gt 0 ]]; then
    for company in "${COMPANY_DIRS[@]}"; do
      [[ "$skill_name" == "$company" ]] && skip=true && break
    done
  fi
  [[ "$skip" == true ]] && continue

  # Skip maintainer-only skills (scope: maintainer-only in SKILL.md frontmatter)
  if grep -q 'scope:.*maintainer-only' "$skill_dir/SKILL.md" 2>/dev/null; then
    echo "  ~ $skill_name/ (maintainer-only, skipped)"
    continue
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

# ── Step 4b: Sync Codex generated outputs / runtime alias ──────────

echo "Codex compatibility..."
create_symlink "../.claude/skills" "$POLARIS_DIR/.agents/skills" ".agents/skills"
mkdir -p "$POLARIS_DIR/.codex/.generated" 2>/dev/null || true
copy_file "$INSTANCE_DIR/.codex/AGENTS.md" \
          "$POLARIS_DIR/.codex/AGENTS.md" "AGENTS.md"
copy_file "$INSTANCE_DIR/.codex/.generated/rules-manifest.txt" \
          "$POLARIS_DIR/.codex/.generated/rules-manifest.txt" "rules-manifest.txt"

# ── Step 5: Sync scripts (recursive — supports scripts/env/ etc.) ─

echo "Scripts..."
while IFS= read -r script_file; do
  # Preserve subfolder structure (e.g., scripts/env/_lib.sh)
  rel_path="${script_file#"$INSTANCE_DIR"/}"
  target_path="$POLARIS_DIR/$rel_path"
  target_dir=$(dirname "$target_path")
  mkdir -p "$target_dir"
  copy_file "$script_file" "$target_path" "$rel_path"
done < <(find "$INSTANCE_DIR/scripts" \( -name "*.sh" -o -name "*.py" -o -name "*.mjs" -o -name "manifest.json" \) -type f -not -path "*/node_modules/*" -not -path "*/e2e-results/*")

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

# ── Step 7b: Sync docs-manager app ─────────────────────────────────

if [[ -d "$INSTANCE_DIR/docs-manager" ]]; then
  echo "Docs-manager..."
  copy_dir_filtered "$INSTANCE_DIR/docs-manager" "$POLARIS_DIR/docs-manager" "docs-manager" \
    "$INSTANCE_DIR/docs-manager/.astro/*" \
    "$INSTANCE_DIR/docs-manager/dist/*" \
    "$INSTANCE_DIR/docs-manager/node_modules/*" \
    "$INSTANCE_DIR/docs-manager/_sidebar.md" \
    "$INSTANCE_DIR/docs-manager/public/evidence/*" \
    "$INSTANCE_DIR/docs-manager/src/content/docs/specs/*"
fi

# ── Step 8: Sync top-level files ──────────────────────────────────

echo "Top-level files..."
ensure_template_gitignore_allowlist
copy_file "$INSTANCE_DIR/.gitignore" "$POLARIS_DIR/.gitignore" ".gitignore"
copy_file "$INSTANCE_DIR/CHANGELOG.md" "$POLARIS_DIR/CHANGELOG.md" "CHANGELOG.md"
copy_file "$INSTANCE_DIR/VERSION"      "$POLARIS_DIR/VERSION"      "VERSION"
copy_file "$INSTANCE_DIR/README.md"       "$POLARIS_DIR/README.md"       "README.md"
copy_file "$INSTANCE_DIR/README.zh-TW.md" "$POLARIS_DIR/README.zh-TW.md" "README.zh-TW.md"
copy_file "$INSTANCE_DIR/CLAUDE.md"    "$POLARIS_DIR/CLAUDE.md"    "CLAUDE.md"
copy_file "$INSTANCE_DIR/package.json" "$POLARIS_DIR/package.json" "package.json"
copy_file "$INSTANCE_DIR/pnpm-workspace.yaml" "$POLARIS_DIR/pnpm-workspace.yaml" "pnpm-workspace.yaml"
copy_file "$INSTANCE_DIR/pnpm-lock.yaml" "$POLARIS_DIR/pnpm-lock.yaml" "pnpm-lock.yaml"

# ── Step 8b: Sync .github/ (Copilot instructions + workflows) ────

if [[ -d "$INSTANCE_DIR/.github" ]]; then
  echo "GitHub config..."
  mkdir -p "$POLARIS_DIR/.github/.generated" 2>/dev/null || true
  copy_file "$INSTANCE_DIR/.github/copilot-instructions.md" \
            "$POLARIS_DIR/.github/copilot-instructions.md" "copilot-instructions.md"
  copy_file "$INSTANCE_DIR/.github/.generated/copilot-rules-manifest.txt" \
            "$POLARIS_DIR/.github/.generated/copilot-rules-manifest.txt" "copilot-rules-manifest.txt"
fi

# ── Step 8d: Sync .changeset/ mechanism (NOT unconsumed entries) ──
# Sync the changeset machinery to the template — config.json, README.md, and the
# Keep a Changelog custom formatter (*.cjs). Unconsumed changeset ENTRY files
# (.changeset/*.md other than README.md) are instance/PR-local; they must never
# leak into the template (AC-NEG4). Steady state after release-version is config
# + README + formatter only, so the template should hold exactly those.

is_changeset_entry() {
  # A changeset ENTRY is any *.md under .changeset/ that is not README.md.
  local name
  name="$(basename "$1")"
  [[ "$name" == *.md && "$name" != "README.md" ]]
}

if [[ -d "$INSTANCE_DIR/.changeset" ]]; then
  echo "Changeset mechanism..."
  mkdir -p "$POLARIS_DIR/.changeset" 2>/dev/null || true
  for cs_file in "$INSTANCE_DIR/.changeset/"*; do
    [[ -f "$cs_file" ]] || continue
    if is_changeset_entry "$cs_file"; then
      # Unconsumed changeset entry — instance/PR-local, do not sync (AC-NEG4).
      echo "  ~ .changeset/$(basename "$cs_file") (unconsumed entry, not synced)"
      continue
    fi
    copy_file "$cs_file" "$POLARIS_DIR/.changeset/$(basename "$cs_file")" \
      ".changeset/$(basename "$cs_file")"
  done
fi

# ── Step 8c: Prune — remove files in template that no longer exist ─

if [[ "$PRUNE" == true ]]; then
  echo "Pruning stale files..."
  prune_count=0

  # 8c-1: Skills — remove dirs in polaris/.claude/skills/ not in instance
  for polaris_skill in "$POLARIS_DIR"/.claude/skills/*/; do
    [[ -d "$polaris_skill" ]] || continue
    skill_name=$(basename "$polaris_skill")
    [[ "$skill_name" == "references" ]] && continue
    instance_skill_dir="$INSTANCE_DIR/.claude/skills/$skill_name"
    if [[ ! -d "$instance_skill_dir" || ! -f "$instance_skill_dir/SKILL.md" ]] \
      || grep -q 'scope:.*maintainer-only' "$instance_skill_dir/SKILL.md" 2>/dev/null; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -rf "$polaris_skill"
      fi
      echo "  ✂ skills/$skill_name/"
      prune_count=$((prune_count + 1))
    fi
  done

  # 8c-2: References — remove files in polaris that don't exist in instance
  for polaris_ref in "$POLARIS_DIR"/.claude/skills/references/*.md; do
    [[ -f "$polaris_ref" ]] || continue
    ref_name=$(basename "$polaris_ref")
    if [[ ! -f "$INSTANCE_DIR/.claude/skills/references/$ref_name" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$polaris_ref"
      fi
      echo "  ✂ references/$ref_name"
      prune_count=$((prune_count + 1))
    fi
  done

  # 8c-3: L1 Rules — remove rule files in polaris that don't exist in instance
  for polaris_rule in "$POLARIS_DIR"/.claude/rules/*.md; do
    [[ -f "$polaris_rule" ]] || continue
    rule_name=$(basename "$polaris_rule")
    if [[ ! -f "$INSTANCE_DIR/.claude/rules/$rule_name" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$polaris_rule"
      fi
      echo "  ✂ rules/$rule_name"
      prune_count=$((prune_count + 1))
    fi
  done

  # 8c-3b: Rule subdirectories — template only syncs root L1 .claude/rules/*.md.
  # Company / project rule overlays are instance-local and must not survive as
  # stale template subtrees from earlier sync implementations.
  for polaris_rule_dir in "$POLARIS_DIR"/.claude/rules/*/; do
    [[ -d "$polaris_rule_dir" ]] || continue
    rule_dir_name=$(basename "$polaris_rule_dir")
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$polaris_rule_dir"
    fi
    echo "  ✂ rules/$rule_dir_name/"
    prune_count=$((prune_count + 1))
  done

  # 8c-4: Hooks — remove hook files in polaris that don't exist in instance
  for polaris_hook in "$POLARIS_DIR"/.claude/hooks/*.sh; do
    [[ -f "$polaris_hook" ]] || continue
    hook_name=$(basename "$polaris_hook")
    if [[ ! -f "$INSTANCE_DIR/.claude/hooks/$hook_name" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$polaris_hook"
      fi
      echo "  ✂ hooks/$hook_name"
      prune_count=$((prune_count + 1))
    fi
  done

  # 8c-5: Scripts — remove synced script files in polaris/scripts/ that don't exist in instance
  while IFS= read -r polaris_script; do
    [[ -f "$polaris_script" ]] || continue
    rel_path="${polaris_script#"$POLARIS_DIR"/}"
    if [[ ! -f "$INSTANCE_DIR/$rel_path" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$polaris_script"
      fi
      echo "  ✂ $rel_path"
      prune_count=$((prune_count + 1))
    fi
  done < <(find "$POLARIS_DIR/scripts" \( -name "*.sh" -o -name "*.py" -o -name "*.mjs" -o -name "manifest.json" \) -type f -not -path "*/node_modules/*" 2>/dev/null)

  # 8c-5b: Codex generated files — remove stale files in polaris/.codex/.generated
  if [[ -d "$POLARIS_DIR/.codex/.generated" ]]; then
    while IFS= read -r polaris_codex_file; do
      [[ -f "$polaris_codex_file" ]] || continue
      rel_path="${polaris_codex_file#"$POLARIS_DIR"/}"
      if [[ ! -f "$INSTANCE_DIR/$rel_path" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
          rm -f "$polaris_codex_file"
        fi
        echo "  ✂ $rel_path"
        prune_count=$((prune_count + 1))
      fi
    done < <(find "$POLARIS_DIR/.codex/.generated" -type f 2>/dev/null)
  fi

  # 8c-6: Docs — remove .md files in polaris/docs/ that don't exist in instance
  if [[ -d "$POLARIS_DIR/docs" ]]; then
    for polaris_doc in "$POLARIS_DIR/docs/"*.md; do
      [[ -f "$polaris_doc" ]] || continue
      doc_name=$(basename "$polaris_doc")
      if [[ ! -f "$INSTANCE_DIR/docs/$doc_name" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
          rm -f "$polaris_doc"
        fi
        echo "  ✂ docs/$doc_name"
        prune_count=$((prune_count + 1))
      fi
    done
  fi

  # 8c-7: Docs-manager — remove retired template app when the source no longer has it.
  if [[ -d "$POLARIS_DIR/docs-manager" && ! -d "$INSTANCE_DIR/docs-manager" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$POLARIS_DIR/docs-manager"
    fi
    echo "  ✂ docs-manager/"
    prune_count=$((prune_count + 1))
  fi

  # 8c-8: Changeset — remove any .changeset entry (or stale config/formatter) in
  # the template that isn't a synced mechanism file. This sweeps out unconsumed
  # changeset entries that leaked from an earlier sync (AC-NEG4) and stale
  # mechanism files removed from the instance.
  if [[ -d "$POLARIS_DIR/.changeset" ]]; then
    for polaris_cs in "$POLARIS_DIR/.changeset/"*; do
      [[ -f "$polaris_cs" ]] || continue
      cs_name="$(basename "$polaris_cs")"
      # Entry .md is never a synced mechanism file → always prune.
      # Mechanism files (config.json / README.md / *.cjs) prune only when the
      # instance no longer has them.
      if is_changeset_entry "$polaris_cs" \
        || [[ ! -f "$INSTANCE_DIR/.changeset/$cs_name" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
          rm -f "$polaris_cs"
        fi
        echo "  ✂ .changeset/$cs_name"
        prune_count=$((prune_count + 1))
      fi
    done
  fi

  if [[ "$prune_count" -eq 0 ]]; then
    echo "  (nothing to prune)"
  else
    echo "  Pruned $prune_count stale item(s)."
  fi
fi

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
if [[ ${#COMPANY_DIRS[@]} -gt 0 ]]; then
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
fi

if [[ "$genericize_count" -gt 0 ]]; then
  echo ""
  echo "Auto-genericized $genericize_count file(s) in template."
fi

# ── Step 9b: Leak check before template commit ────────────────────

if [[ "$AUTO_COMMIT" == true ]]; then
  run_template_leak_check
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
      [[ -z "$RELEASE_NOTES" ]] && RELEASE_NOTES="$(release_notes_fallback "$TAG_NAME")"
      RELEASE_NOTES_FILE="$(mktemp -t sync-to-polaris-release-notes.XXXXXX.md)"
      printf '%s\n' "$RELEASE_NOTES" >"$RELEASE_NOTES_FILE"
      # DP-421 T3: gate the AUTHORITATIVE CHANGELOG source section, not the derived
      # RELEASE_NOTES_FILE. If the source conforms, the mechanically-derived notes
      # conform by construction (Derived Artifact Read Boundary).
      gate_release_notes "$VERSION"

      gh release create "$TAG_NAME" \
        --repo "$REPO_SLUG" \
        --title "Polaris $TAG_NAME" \
        --notes-file "$RELEASE_NOTES_FILE" \
        --verify-tag 2>/dev/null && echo "✓ Release $TAG_NAME created" || echo "⚠ Release creation failed (non-blocking)"
      rm -f "$RELEASE_NOTES_FILE"
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
