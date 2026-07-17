#!/usr/bin/env bash
# DP-423 T5 — repo-native changeset policy, entry discovery, and staged commit parity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/scripts/gates/gate-changeset.sh"
INSTALLER="$ROOT/scripts/install-git-hooks.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
require() { grep -qF "$2" "$1" || fail "$1 missing: $2"; }
reject() { ! grep -qF "$2" "$1" || fail "$1 still contains retired contract: $2"; }

# AC14/AC15: all source entries resolve the same handbook before exploration;
# framework-specific prose has one live home.
for ref in \
  "$ROOT/.claude/skills/references/refinement-source-mode.md" \
  "$ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" \
  "$ROOT/.claude/skills/references/engineering-entry-resolution.md"
do
  require "$ref" 'resolve-handbook.sh --project polaris-framework'
  require "$ref" 'changeset-convention.md'
  require "$ref" 'validate-handbook-load-gate.sh'
done
[[ -f "$ROOT/polaris-config/polaris-framework/handbook/changeset-convention.md" ]] \
  || fail "framework handbook changeset convention missing"
[[ ! -e "$ROOT/.claude/skills/references/changeset-convention.md" ]] \
  || fail "legacy framework-specific changeset reference still exists"
reject "$ROOT/.claude/skills/references/changeset-convention-default.md" 'polaris-framework-workspace'
reject "$ROOT/.claude/skills/references/changeset-convention-default.md" 'deliverables.changeset.filename_slug'
reject "$ROOT/.claude/skills/references/changeset-convention-default.md" 'Step 6b'

# AC17: derive/readiness no longer manufacture an exact changeset path ceremony.
reject "$ROOT/scripts/derive-task-md-from-refinement-json.sh" 'changeset_allowed_file_path'
reject "$ROOT/scripts/validate-breakdown-ready.sh" 'validate_changeset_scope_contract'
require "$ROOT/scripts/polaris-changeset.sh" 'multi-package ambiguity'

# AC-NEG8: native hook and Codex wrapper delegate the same verifier.
[[ -x "$INSTALLER" ]] || fail "runtime-neutral git hook installer missing/executable bit absent"
require "$INSTALLER" 'gate-changeset.sh" --repo "$REPO_ROOT" --staged'
require "$ROOT/scripts/codex-guarded-git-commit.sh" 'gate-changeset.sh" --repo "$COMMIT_REPO" --staged'
retired_installer='install-'"copilot-hooks.sh"
if rg -l "$retired_installer" \
    "$ROOT/scripts" "$ROOT/.claude/skills/references" "$ROOT/.claude/rules" | grep -q .; then
  fail "live source still references retired runtime-specific hook installer"
fi

TMP="$(mktemp -d -t repo-native-changeset.XXXXXX)"
repo="$TMP/repo"
mkdir -p "$repo/scripts/gates" "$repo/.changeset"
cp "$GATE" "$repo/scripts/gates/gate-changeset.sh"
cp "$INSTALLER" "$repo/scripts/install-git-hooks.sh"
chmod +x "$repo/scripts/gates/gate-changeset.sh" "$repo/scripts/install-git-hooks.sh"
printf '%s\n' '{"baseBranch":"main"}' > "$repo/.changeset/config.json"
printf '%s\n' '{"name":"fixture","version":"1.0.0"}' > "$repo/package.json"
git -C "$repo" init -q
git -C "$repo" config user.email fixture@example.com
git -C "$repo" config user.name Fixture
git -C "$repo" checkout -q -b task/DP-423-T5-fixture
cat > "$repo/.changeset/dp-423-t4-inherited.md" <<'EOF'
---
"fixture": patch
---

fix: inherited sibling changeset
EOF
git -C "$repo" add .
git -C "$repo" commit -q -m 'chore: baseline'
bash "$repo/scripts/install-git-hooks.sh" >/dev/null

head_before="$(git -C "$repo" rev-parse HEAD)"
printf '%s\n' 'console.log("behavior")' > "$repo/feature.js"
git -C "$repo" add feature.js
if GATE_PROJECT_DIR="$repo" bash "$ROOT/scripts/codex-guarded-git-commit.sh" --dry-run \
    -m 'feat: missing changeset' >"$TMP/codex-missing.out" 2>&1; then
  fail "Codex guarded commit diverged: missing changeset passed"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/codex-missing.out" \
  || fail "Codex missing verdict did not come from the single verifier"
if git -C "$repo" commit -m 'feat: missing changeset' >"$TMP/missing.out" 2>&1; then
  fail "behavioral staged commit without changeset passed"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/missing.out" \
  || fail "missing staged changeset marker absent"
[[ "$(git -C "$repo" rev-parse HEAD)" == "$head_before" ]] || fail "blocked commit advanced HEAD"

# A worktree-only changeset is not in the prospective tree and must not satisfy it.
cat > "$repo/.changeset/dp-423-t5-worktree-only.md" <<'EOF'
---
"fixture": patch
---

feat: worktree only
EOF
if git -C "$repo" commit -m 'feat: unstaged changeset' >"$TMP/unstaged.out" 2>&1; then
  fail "unstaged changeset satisfied pre-commit"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/unstaged.out" \
  || fail "unstaged case marker absent"

# A staged, well-shaped changeset with an unknown package scope is not canonical.
cat > "$repo/.changeset/dp-423-t5-worktree-only.md" <<'EOF'
---
"bogus": patch
---

feat: invalid package scope
EOF
git -C "$repo" add .changeset/dp-423-t5-worktree-only.md
if git -C "$repo" commit -m 'feat: bogus scope' >"$TMP/bogus.out" 2>&1; then
  fail "unknown package scope satisfied canonical changeset validation"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/bogus.out" \
  || fail "bogus package scope marker absent"

cat > "$repo/.changeset/dp-423-t5-worktree-only.md" <<'EOF'
---
"fixture": patch
---

feat: staged canonical changeset
EOF
git -C "$repo" add .changeset/dp-423-t5-worktree-only.md

# Unstaged repo metadata must not alter an index-valid verdict.
printf '%s\n' '{"name":"unstaged-renamed","version":"1.0.0"}' > "$repo/package.json"
bash "$repo/scripts/gates/gate-changeset.sh" --repo "$repo" --staged \
  || fail "unstaged package metadata polluted prospective-tree verdict"
printf '%s\n' '{"name":"fixture","version":"1.0.0"}' > "$repo/package.json"

# Conversely, staged package metadata is authoritative even when the worktree is
# changed back after staging.
printf '%s\n' '{"name":"staged-fixture","version":"1.0.0"}' > "$repo/package.json"
git -C "$repo" add package.json
printf '%s\n' '{"name":"fixture","version":"1.0.0"}' > "$repo/package.json"
if bash "$repo/scripts/gates/gate-changeset.sh" --repo "$repo" --staged \
    >"$TMP/staged-metadata.out" 2>&1; then
  fail "worktree package metadata overrode staged package scope"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/staged-metadata.out" \
  || fail "staged metadata divergence marker absent"

cat > "$repo/.changeset/dp-423-t5-worktree-only.md" <<'EOF'
---
"staged-fixture": patch
---

feat: staged canonical changeset
EOF
git -C "$repo" add .changeset/dp-423-t5-worktree-only.md
GATE_PROJECT_DIR="$repo" bash "$ROOT/scripts/codex-guarded-git-commit.sh" --dry-run \
  -m 'feat: staged canonical changeset' >"$TMP/codex-pass.out" 2>&1 \
  || fail "Codex guarded commit diverged: staged canonical changeset blocked"
git -C "$repo" commit -q -m 'feat: staged canonical changeset'

# Once a canonical changeset is in HEAD, later commits need not recreate it.
printf '%s\n' 'console.log("follow-up")' >> "$repo/feature.js"
git -C "$repo" add feature.js
git -C "$repo" commit -q -m 'fix: follow-up'

# Metadata-only commits and repos without Changesets remain normal git commits.
printf '%s\n' '# docs' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m 'docs: metadata only'
repo2="$TMP/no-config"
mkdir -p "$repo2/scripts/gates"
cp "$GATE" "$repo2/scripts/gates/gate-changeset.sh"
git -C "$repo2" init -q
git -C "$repo2" config user.email fixture@example.com
git -C "$repo2" config user.name Fixture
printf '%s\n' 'console.log("no config")' > "$repo2/app.js"
git -C "$repo2" add app.js
bash "$repo2/scripts/gates/gate-changeset.sh" --repo "$repo2" --staged

# Repo handbook Markdown is behavioral policy, not metadata-only prose.
repo3="$TMP/handbook"
mkdir -p "$repo3/scripts/gates" "$repo3/.changeset" \
  "$repo3/polaris-config/polaris-framework/handbook"
cp "$GATE" "$repo3/scripts/gates/gate-changeset.sh"
printf '%s\n' '{"baseBranch":"main"}' > "$repo3/.changeset/config.json"
printf '%s\n' '{"name":"handbook-fixture","version":"1.0.0"}' > "$repo3/package.json"
git -C "$repo3" init -q
git -C "$repo3" config user.email fixture@example.com
git -C "$repo3" config user.name Fixture
git -C "$repo3" checkout -q -b task/DP-500-T1-handbook
git -C "$repo3" add .
git -C "$repo3" commit -q -m 'chore: baseline'
printf '%s\n' '# changed policy' > \
  "$repo3/polaris-config/polaris-framework/handbook/changeset-convention.md"
git -C "$repo3" add polaris-config/polaris-framework/handbook/changeset-convention.md
if bash "$repo3/scripts/gates/gate-changeset.sh" --repo "$repo3" --staged \
    >"$TMP/handbook.out" 2>&1; then
  fail "handbook-only behavioral change passed without task-owned changeset"
fi
grep -q 'POLARIS_CHANGESET_STAGED_MISSING' "$TMP/handbook.out" \
  || fail "handbook behavioral marker absent"

echo "PASS: DP-423 T5 repo-native changeset policy"
