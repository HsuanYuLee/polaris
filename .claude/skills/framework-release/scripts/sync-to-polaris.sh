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
#   - scripts/**/*.sh, scripts/**/*.py, scripts/**/*.mjs, scripts/**/*.md
#     (machine-read data tables + selftest/validator fixtures), and scripts/manifest.json
#   - _template/
#   - docs-manager/ (framework docs browser app, excluding generated outputs)
#   - .gitignore, CHANGELOG.md, VERSION, README.md, CLAUDE.md
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
#   - .changeset/ (本 repo 自己的發版設定，不屬於框架模板)
#
# --commit: auto-commit in template with version from VERSION file
# --push:   auto-push (includes gh auth switch for dual-account setups)
# --no-prune: skip removing stale files in template (prune is ON by default)
# --leak-warn-only: report template leaks without blocking commit/push

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 這支住在某支 skill 的 scripts/ 底下，但它同步的是整個 workspace。從自己的深度
# 往上數會數錯——搬進 skill 之後一度算成 .claude/skills/{skill}，dry-run 顯示它
# 打算 prune 1120 個項目。問 git 拿 repo 根。
INSTANCE_DIR="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
POLARIS_DIR="${HOME}/polaris"
DRY_RUN=false
AUTO_COMMIT=false
AUTO_PUSH=false
PRUNE=true
LEAK_BLOCKING=true
STATUS_ONLY=false

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
# CHANGELOG section is the authoring surface gated here.
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
    # 只讀：印一行「這一趟同步做到哪」。問的是 template checkout 自己，不是任何一份帳。
    # 住在這裡而不是呼叫端，是因為 template 在哪、什麼算「同步完了」是這一支的知識——
    # 呼叫端自己去問 ~/polaris，就是那份知識的第二份（DP-501 T-N1）。
    --status) STATUS_ONLY=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# 只讀模式要能報告「那棵樹不在」，所以它排在解析路徑的前面——`cd` 到一個不存在的目錄
# 會直接讓整支死掉，而一個死掉的探針說不出任何話。
if [[ "$STATUS_ONLY" == true ]]; then
  if [[ ! -d "$POLARIS_DIR/.claude/skills" ]]; then
    echo "unreachable  template checkout 不在 $POLARIS_DIR"
    exit 0
  fi
  POLARIS_DIR="$(cd "$POLARIS_DIR" && pwd)"
  tpl_version="$(cat "$POLARIS_DIR/VERSION" 2>/dev/null || echo unknown)"
  src_version="$(cat "$INSTANCE_DIR/VERSION" 2>/dev/null || echo unknown)"
  dirty="$(git -C "$POLARIS_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  unpushed="$(git -C "$POLARIS_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo unknown)"
  if [[ "$tpl_version" == "$src_version" && "$dirty" == "0" && "$unpushed" == "0" ]]; then
    verdict="in-sync"
  else
    verdict="behind"
  fi
  echo "$verdict  template=$tpl_version instance=$src_version dirty=$dirty unpushed=$unpushed"
  exit 0
fi

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

# 同步到公開 template repo 之前的最後一道。掃描器用同目錄的姊妹路徑找——以前這裡寫的是
# `$INSTANCE_DIR/scripts/scan-template-leaks.sh`（DP-462 之前的佈局），那個檔案不存在，
# 於是每一次同步都走 else 分支改用一條 warn-only 的 legacy 檢查，`--blocking` 從此沒有作用
# 過，而那正是內容變成公開的那一刻（DP-524）。
#
# **缺席不再有 fallback。** 那條 legacy 路徑自己從 workspace-config.yaml 推第二份樣式清單，
# 而它已經漂了（少了公司代號自己，那是真掃描器的第一條樣式），結尾還寫著
# `Continuing push (warn only, not blocking)`。一個把閘降級成警告的 fallback，跟沒有那道閘
# 的差別只有它會印一行字。人明講的 `--leak-warn-only` 留著——那是有人簽過的選擇。
run_template_leak_check() {
  [[ ${#COMPANY_DIRS[@]} -gt 0 ]] || return 0

  local scanner="$SCRIPT_DIR/scan-template-leaks.sh"
  if [[ ! -x "$scanner" ]]; then
    echo "POLARIS_TEMPLATE_LEAK_SCANNER_MISSING" >&2
    echo "sync-to-polaris: 外洩掃描器不在 ${scanner}，同步停下來。" >&2
    echo "sync-to-polaris: 這一步是內容變成公開之前的最後一道，沒有降級的路徑可以走。" >&2
    return 2
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

  # 命名空間目錄自己不是一支 skill，不論它叫什麼、不論裡面有沒有人放了散檔。
  # 判準是形狀（底下有 skill）不是名字——用名字比對就等於用位置判斷公司身分。
  if compgen -G "$skill_dir*/SKILL.md" >/dev/null; then
    echo "  ~ $skill_name/ (namespace, skipped)"
    continue
  fi

  if [[ ! -f "$skill_dir/SKILL.md" ]]; then
    echo "  ~ $skill_name/ (no SKILL.md, skipped)"
    continue
  fi

  # Skip company-specific skills. The declaration is the frontmatter, not the
  # path. Company skills live in .claude/skills/{company}/{name}/ — the repo's
  # convention, and more than one person maintains it — with a depth-one symlink
  # so the runtime registers them at all. That means this loop sees each company
  # skill twice: once through the symlink (has SKILL.md, caught here) and once as
  # the {company}/ namespace directory (no SKILL.md, caught above). Excluding by
  # directory name would only catch one of the two shapes.
  if grep -qE '^[[:space:]]*scope:[[:space:]]*company-only' "$skill_dir/SKILL.md" 2>/dev/null; then
    echo "  ~ $skill_name/ (company-only, skipped)"
    continue
  fi

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
copy_file "$INSTANCE_DIR/.codex/AGENTS.md" \
          "$POLARIS_DIR/.codex/AGENTS.md" "AGENTS.md"

# ── Step 5: Sync scripts (recursive — supports scripts/env/ etc.) ─

echo "Scripts..."
while IFS= read -r script_file; do
  # Preserve subfolder structure (e.g., scripts/env/_lib.sh)
  rel_path="${script_file#"$INSTANCE_DIR"/}"
  target_path="$POLARIS_DIR/$rel_path"
  target_dir=$(dirname "$target_path")
  mkdir -p "$target_dir"
  copy_file "$script_file" "$target_path" "$rel_path"
done < <(find "$INSTANCE_DIR/scripts" \( -name "*.sh" -o -name "*.py" -o -name "*.mjs" -o -name "*.md" -o -name "manifest.json" \) -type f -not -path "*/node_modules/*" -not -path "*/e2e-results/*")

# 這條尾段擁有的頂層檔案。**清單只有這一份**：複製走它，清掉也走它。以前複製是一行
# 一個 copy_file、清掉沒有人做，於是 2026-08-14 刪掉 README.zh-TW.md 之後，模板那邊
# 那一份會永遠留著——而模板正是別人 clone 下來讀到的東西。
TOP_LEVEL_FILES=(
  ".gitignore"
  "CHANGELOG.md"
  "VERSION"
  "README.md"
  "CLAUDE.md"
  "package.json"
  "pnpm-workspace.yaml"
  "pnpm-lock.yaml"
)

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
# issues/ needs no exclusion here on two counts: every sync step copies an
# explicitly named path, so nothing sweeps the repo root, and issues/ is the
# user's own repository which this one ignores. The empty shell ships inside the
# refinement skill (templates/issues/), carried by the skills step — it belongs to
# the station that bootstraps issues/, so it travels wherever that station travels.

# ── Step 8: Sync top-level files ──────────────────────────────────

echo "Top-level files..."
ensure_template_gitignore_allowlist
for top_name in "${TOP_LEVEL_FILES[@]}"; do
  copy_file "$INSTANCE_DIR/$top_name" "$POLARIS_DIR/$top_name" "$top_name"
done

# ── Step 8b: Sync .github/ (Copilot instructions + workflows) ────

if [[ -d "$INSTANCE_DIR/.github" ]]; then
  echo "GitHub config..."
  copy_file "$INSTANCE_DIR/.github/copilot-instructions.md" \
            "$POLARIS_DIR/.github/copilot-instructions.md" "copilot-instructions.md"
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
  done < <(find "$POLARIS_DIR/scripts" \( -name "*.sh" -o -name "*.py" -o -name "*.mjs" -o -name "*.md" -o -name "manifest.json" \) -type f -not -path "*/node_modules/*" 2>/dev/null)

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

  # 8c-6b: Docs — 來源整個不見了就把目錄一起收掉。少了這一步，模板會留下一個空的
  # docs/，而一個空目錄看起來像「還沒同步」，不像「那一層被拿掉了」。
  if [[ -d "$POLARIS_DIR/docs" && ! -d "$INSTANCE_DIR/docs" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$POLARIS_DIR/docs"
    fi
    echo "  ✂ docs/"
    prune_count=$((prune_count + 1))
  fi

  # 8c-6c: 頂層的說明文件——模板有、來源沒有的就是漂。**不能只清 TOP_LEVEL_FILES 裡的
  # 名字**：一個檔案被退休的時候，它正好會從那份清單裡消失，於是模板那一份永遠沒有人
  # 來收（2026-08-14 刪掉 README.zh-TW.md 就是這個形狀）。所以判準是副檔名不是清單：
  # 頂層的 .md 由這條尾段擁有，模板自己的東西（LICENSE 之類）沒有副檔名，碰不到。
  while IFS= read -r -d '' polaris_md; do
    md_name=$(basename "$polaris_md")
    if [[ ! -f "$INSTANCE_DIR/$md_name" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$polaris_md"
      fi
      echo "  ✂ $md_name"
      prune_count=$((prune_count + 1))
    fi
  done < <(find "$POLARIS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)

  # 8c-6d: _template/ 底下——同一件事。複製那一步只往前寫，所以退休的範例會留在模板裡。
  if [[ -d "$POLARIS_DIR/_template" ]]; then
    while IFS= read -r -d '' polaris_tmpl; do
      rel_path="${polaris_tmpl#$POLARIS_DIR/_template/}"
      if [[ ! -e "$INSTANCE_DIR/_template/$rel_path" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
          rm -f "$polaris_tmpl"
        fi
        echo "  ✂ _template/$rel_path"
        prune_count=$((prune_count + 1))
      fi
    done < <(find "$POLARIS_DIR/_template" -type f -print0 2>/dev/null)
  fi

  # 8c-7: Docs-manager — remove retired template app when the source no longer has it.
  if [[ -d "$POLARIS_DIR/docs-manager" && ! -d "$INSTANCE_DIR/docs-manager" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$POLARIS_DIR/docs-manager"
    fi
    echo "  ✂ docs-manager/"
    prune_count=$((prune_count + 1))
  fi

  # 8c-8: 模板不再挾帶任何 repo 的發版工具。.changeset/ 是本 workspace repo
  # 自己的 npm 發版設定，不是框架的一部分；早期 sync 曾把它整套推進模板，
  # 使每個採用 Polaris 的 workspace 都被迫繼承一套它沒選擇的發版機制。
  # 這裡把模板端殘留的 .changeset/ 整個掃掉。
  #
  # 下面這一行是給機器讀的：gate-source-destination.sh 判「宣告 workspace 的單有沒有
  # 檔案落在會出去的位置」時來讀它，而不是在那道閘裡再抄一份路徑清單。抄兩份會漂，
  # 而漂掉的那一刻沒有人在看——DP-525 之前那道閘就是因為不知道這件事，對兩張只改
  # .changeset/ 的單判了假紅，逼得那兩張單把 destination 宣告成不是它真正的樣子。
  # <!-- POLARIS-NOT-SYNCED: .changeset/ — 本 repo 自己的發版設定，不屬於框架模板；模板端殘留的會被下面這段掃掉 -->
  if [[ -d "$POLARIS_DIR/.changeset" ]]; then
    if [[ "$DRY_RUN" == false ]]; then
      rm -rf "$POLARIS_DIR/.changeset"
    fi
    echo "  ✂ .changeset/"
    prune_count=$((prune_count + 1))
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
# 「沒有新變更要同步」與「沒有東西要推」是兩件事。上一版把它們收斂成同一句話，於是一次
# 被中斷後補跑的同步會印「已經是最新的」然後跳過推送——而本機那個 compress commit 還在
# 那裡沒出去。2026-08-09 真的發生過：腳本說最新，remote 停在上一版。
UNPUSHED=$(git -C "$POLARIS_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [[ "$CHANGES" == "0" && "$UNPUSHED" == "0" ]]; then
  echo "No changes to sync, and nothing unpushed — template is already up to date."
  exit 0
fi

if [[ "$CHANGES" == "0" ]]; then
  echo "No changes to sync, but $UNPUSHED commit(s) are not on the remote yet."
  if [[ "$AUTO_PUSH" != true ]]; then
    echo "  Re-run with --push to send them."
    exit 0
  fi
fi

if [[ "$CHANGES" != "0" ]]; then
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
    done < <(find "$POLARIS_DIR/.claude" "$POLARIS_DIR/CLAUDE.md" "$POLARIS_DIR/README.md" \( -name '*.md' -o -name '*.py' -o -name '*.sh' \) -print0 2>/dev/null)
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

fi   # ← 只有真的有變更時才走 9a/9b 與 commit。沒有變更但有未推的 commit 時直接落到推送。

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
