#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUBJECT="$ROOT_DIR/scripts/sync-to-polaris.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

init_fixture() {
  local source_dir="$1"
  local polaris_dir="$2"

  mkdir -p "$source_dir/scripts"
  mkdir -p "$source_dir/.claude/skills/sample"
  mkdir -p "$source_dir/.claude/skills/references"
  mkdir -p "$polaris_dir"

  cp "$SUBJECT" "$source_dir/scripts/sync-to-polaris.sh"
  chmod +x "$source_dir/scripts/sync-to-polaris.sh"

  cat > "$source_dir/scripts/tracked-marker.sh" <<'MARKER'
#!/usr/bin/env bash
echo original
MARKER
  chmod +x "$source_dir/scripts/tracked-marker.sh"

  cat > "$source_dir/.claude/skills/sample/SKILL.md" <<'SKILL'
---
name: sample
description: sample fixture skill
---

# Sample
SKILL

  cat > "$source_dir/.claude/skills/references/sample.md" <<'REF'
# Sample Reference
REF

  git -C "$source_dir" init -q
  git -C "$source_dir" config user.email "selftest@example.invalid"
  git -C "$source_dir" config user.name "Selftest"
  git -C "$source_dir" add -A
  git -C "$source_dir" commit -q -m "fixture source"

  cp -R "$source_dir/.claude" "$polaris_dir/.claude"
  mkdir -p "$polaris_dir/scripts"
  cp "$source_dir/scripts/sync-to-polaris.sh" "$polaris_dir/scripts/sync-to-polaris.sh"
  cp "$source_dir/scripts/tracked-marker.sh" "$polaris_dir/scripts/tracked-marker.sh"
  mkdir -p "$polaris_dir/.agents"
  ln -s "../.claude/skills" "$polaris_dir/.agents/skills"

  git -C "$polaris_dir" init -q
  git -C "$polaris_dir" config user.email "selftest@example.invalid"
  git -C "$polaris_dir" config user.name "Selftest"
  git -C "$polaris_dir" add -A
  git -C "$polaris_dir" commit -q -m "fixture template"
}

new_fixture() {
  local name="$1"
  local source_dir="$TMP_DIR/$name/source"
  local polaris_dir="$TMP_DIR/$name/polaris"

  init_fixture "$source_dir" "$polaris_dir"
  printf '%s\n%s\n' "$source_dir" "$polaris_dir"
}

assert_clean_polaris() {
  local polaris_dir="$1"
  local status
  status="$(git -C "$polaris_dir" status --porcelain)"
  [[ -z "$status" ]] || fail "expected clean polaris fixture, got: $status"
}

dirty_push_fails_before_template_copy() {
  local fixture source_dir polaris_dir output status marker
  fixture="$(new_fixture dirty-push)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  echo '# dirty tracked change' >> "$source_dir/scripts/tracked-marker.sh"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" --push 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "dirty tracked --push unexpectedly succeeded"
  grep -q 'dirty tracked' <<<"$output" || fail "dirty tracked message missing"
  grep -Eq 'commit|stash|clean worktree' <<<"$output" || fail "remediation message missing"

  marker="$(cat "$polaris_dir/scripts/tracked-marker.sh")"
  [[ "$marker" == $'#!/usr/bin/env bash\necho original' ]] \
    || fail "template marker changed before clean-source gate stopped sync"
  assert_clean_polaris "$polaris_dir"
}

clean_push_reaches_existing_sync_path() {
  local fixture source_dir polaris_dir output status
  fixture="$(new_fixture clean-push)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" --push 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "clean --push failed: $output"
  grep -q 'No changes detected' <<<"$output" || fail "clean --push did not reach existing sync path"
  assert_clean_polaris "$polaris_dir"
}

untracked_only_source_is_allowed() {
  local fixture source_dir polaris_dir output status
  fixture="$(new_fixture untracked-only)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  echo scratch > "$source_dir/scratch.tmp"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" --push 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "untracked-only --push was blocked: $output"
  grep -q 'No changes detected' <<<"$output" || fail "untracked-only --push did not reach existing sync path"
  assert_clean_polaris "$polaris_dir"
}

dry_run_does_not_require_clean_source() {
  local fixture source_dir polaris_dir output status
  fixture="$(new_fixture dry-run)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  echo '# dirty tracked change' >> "$source_dir/scripts/tracked-marker.sh"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" --dry-run --push 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "dirty tracked dry-run was blocked: $output"
  grep -q 'DRY RUN complete' <<<"$output" || fail "dry-run did not complete"
  assert_clean_polaris "$polaris_dir"
}

non_push_sync_is_not_blocked() {
  local fixture source_dir polaris_dir output status
  fixture="$(new_fixture non-push)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  echo '# dirty tracked change' >> "$source_dir/scripts/tracked-marker.sh"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "non-push sync was blocked: $output"
  grep -q 'file(s) changed in template' <<<"$output" || fail "non-push sync did not reach template mutation path"
}

docs_manager_sync_filters_generated_outputs() {
  local fixture source_dir polaris_dir output status
  fixture="$(new_fixture docs-manager-sync)"
  source_dir="$(printf '%s\n' "$fixture" | sed -n '1p')"
  polaris_dir="$(printf '%s\n' "$fixture" | sed -n '2p')"

  mkdir -p "$source_dir/docs-manager/src/content/docs/specs/design-plans/DP-001"
  mkdir -p "$source_dir/docs-manager/src/content/docs/specs/design-plans/DP-002"
  mkdir -p "$source_dir/docs-manager/.astro" "$source_dir/docs-manager/dist" "$source_dir/docs-manager/node_modules/pkg"
  cat > "$source_dir/docs-manager/package.json" <<'PKG'
{"name":"docs-manager"}
PKG
  echo 'source config' > "$source_dir/docs-manager/astro.config.mjs"
  echo 'generated sidebar' > "$source_dir/docs-manager/_sidebar.md"
  echo 'generated astro' > "$source_dir/docs-manager/.astro/settings.json"
  echo 'generated dist' > "$source_dir/docs-manager/dist/index.html"
  echo 'generated dependency' > "$source_dir/docs-manager/node_modules/pkg/index.js"
  echo 'generated mirror' > "$source_dir/docs-manager/src/content/docs/specs/design-plans/DP-001/plan.md"
  echo 'local canonical specs' > "$source_dir/docs-manager/src/content/docs/specs/design-plans/DP-002/plan.md"

  git -C "$source_dir" add docs-manager/package.json docs-manager/astro.config.mjs
  git -C "$source_dir" commit -q -m "add docs-manager source"

  set +e
  output="$("$source_dir/scripts/sync-to-polaris.sh" --polaris "$polaris_dir" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "docs-manager sync failed: $output"
  [[ -f "$polaris_dir/docs-manager/package.json" ]] || fail "docs-manager package was not synced"
  [[ -f "$polaris_dir/docs-manager/astro.config.mjs" ]] || fail "docs-manager config was not synced"
  [[ ! -e "$polaris_dir/docs-manager/_sidebar.md" ]] || fail "generated sidebar was synced"
  [[ ! -e "$polaris_dir/docs-manager/.astro/settings.json" ]] || fail ".astro output was synced"
  [[ ! -e "$polaris_dir/docs-manager/dist/index.html" ]] || fail "dist output was synced"
  [[ ! -e "$polaris_dir/docs-manager/node_modules/pkg/index.js" ]] || fail "node_modules output was synced"
  [[ ! -e "$polaris_dir/docs-manager/src/content/docs/specs/design-plans/DP-001/plan.md" ]] || fail "mirror specs content was synced"
  [[ ! -e "$polaris_dir/docs-manager/src/content/docs/specs/design-plans/DP-002/plan.md" ]] || fail "local canonical specs content was synced"
}

dirty_push_fails_before_template_copy
clean_push_reaches_existing_sync_path
untracked_only_source_is_allowed
dry_run_does_not_require_clean_source
non_push_sync_is_not_blocked
docs_manager_sync_filters_generated_outputs

echo "PASS: sync-to-polaris clean-source selftest"
