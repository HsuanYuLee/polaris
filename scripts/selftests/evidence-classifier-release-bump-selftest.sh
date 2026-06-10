#!/usr/bin/env bash
# Purpose: DP-295 T5 / AC7 — selftest for evidence-classifier.sh release_bump
#          expansion. Asserts that a changeset-driven release-bump commit
#          (VERSION / CHANGELOG.md / package.json version-only / .changeset/**
#          deletion, in any combination) classifies as release_bump, while
#          adversarial variants (non-version package.json edit, .changeset
#          config/content change, mixed behavioral) stay fail-closed.
# Inputs:  none (hermetic tmp git repo).
# Outputs: PASS/FAIL-status lines; exit 0 (all pass) / 1 (any fail).
# Covers:  package.json version-only -> release_bump; .changeset/*.md deletion ->
#          release_bump; VERSION+package.json+changeset-deletion combo ->
#          release_bump; non-version package.json edit -> behavioral;
#          .changeset/config.json edit -> behavioral; .changeset/*.md add
#          (authoring, not a consumption) -> metadata_only; mixed behavioral ->
#          behavioral; range spanning the full release bump -> release_bump.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLS="$ROOT/scripts/lib/evidence-classifier.sh"
[[ -x "$CLS" ]] || { echo "FAIL-status: missing/not executable: $CLS" >&2; exit 1; }

TMP="$(mktemp -d -t evidence-classifier-release-bump-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL-status: $1" >&2; }

# --- hermetic git repo with changeset scaffolding -----------------------------
R="$TMP/repo"
mkdir -p "$R/.changeset" "$R/scripts"
git -C "$R" init -q -b main
git -C "$R" config user.email selftest@example.com
git -C "$R" config user.name Selftest
echo "seed" >"$R/README.md"
printf '3.75.0\n' >"$R/VERSION"
printf '# changelog\n' >"$R/CHANGELOG.md"
cat >"$R/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.75.0",
  "private": true
}
JSON
printf '{ "changelog": "x" }\n' >"$R/.changeset/config.json"
printf '# Changesets\n' >"$R/.changeset/README.md"
printf -- '---\n"polaris-framework-workspace": patch\n---\n\nbump\n' >"$R/.changeset/lucky-cats-jump.md"
printf '#!/usr/bin/env bash\necho seed\n' >"$R/scripts/x.sh"
git -C "$R" add -A
git -C "$R" commit -q -m "seed"
BASE="$(git -C "$R" rev-parse HEAD)"

classify_head()  { bash "$CLS" classify --repo "$R" --head "$1" 2>/dev/null; }
classify_range() { bash "$CLS" classify --repo "$R" --range "$1" 2>/dev/null; }

# === AC7 positive: package.json version-only bump -> release_bump =============
cat >"$R/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.75.1",
  "private": true
}
JSON
git -C "$R" add -A; git -C "$R" commit -q -m "bump package.json version"
H_PKG="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_PKG")" == "release_bump" ]] && ok || bad "package.json version-only -> release_bump"

# === AC7 positive: .changeset/*.md deletion (consumed) -> release_bump ========
git -C "$R" rm -q "$R/.changeset/lucky-cats-jump.md"
git -C "$R" commit -q -m "consume changeset"
H_DEL="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_DEL")" == "release_bump" ]] && ok || bad ".changeset/*.md deletion -> release_bump"

# === AC7 positive: full release bump combo ===================================
# VERSION + CHANGELOG + package.json version-only + .changeset/*.md deletion.
printf -- '---\n"polaris-framework-workspace": patch\n---\n\nsecond\n' >"$R/.changeset/brave-otters-run.md"
git -C "$R" add -A; git -C "$R" commit -q -m "stage second changeset"
printf '3.75.2\n' >"$R/VERSION"
printf '# changelog\n- 3.75.2\n' >"$R/CHANGELOG.md"
cat >"$R/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.75.2",
  "private": true
}
JSON
git -C "$R" rm -q "$R/.changeset/brave-otters-run.md"
git -C "$R" add -A; git -C "$R" commit -q -m "release bump combo"
H_COMBO="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_COMBO")" == "release_bump" ]] && ok || bad "VERSION+CHANGELOG+pkg-version+changeset-del combo -> release_bump"

# === AC7 negative: non-version package.json edit -> behavioral ================
cat >"$R/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.75.2",
  "private": true,
  "scripts": { "added": "echo behavioral" }
}
JSON
git -C "$R" add -A; git -C "$R" commit -q -m "package.json non-version edit"
H_PKGBEH="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_PKGBEH")" == "behavioral" ]] && ok || bad "package.json non-version edit -> behavioral (fail-closed)"

# === AC7 negative: .changeset/config.json edit -> behavioral =================
printf '{ "changelog": "y" }\n' >"$R/.changeset/config.json"
git -C "$R" add -A; git -C "$R" commit -q -m "changeset config edit"
H_CFG="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_CFG")" == "behavioral" ]] && ok || bad ".changeset/config.json edit -> behavioral (fail-closed)"

# === AC7 boundary: .changeset/*.md ADD (authoring) is NOT a consumption ========
# Only deletion of a changeset entry is a release-bump consumption. Authoring a
# changeset .md (add) is non-behavioral docs-shaped metadata, so it follows the
# existing *.md -> metadata_only path and must NOT be claimed as release_bump.
printf -- '---\n"polaris-framework-workspace": minor\n---\n\nauthoring\n' >"$R/.changeset/new-pandas-clap.md"
git -C "$R" add -A; git -C "$R" commit -q -m "author new changeset"
H_ADD="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_ADD")" == "metadata_only" ]] && ok || bad ".changeset/*.md add (authoring) -> metadata_only (not release_bump)"

# === AC7 negative: version bump MIXED with a behavioral change -> behavioral ==
printf '3.75.3\n' >"$R/VERSION"
printf '#!/usr/bin/env bash\necho mixed\n' >"$R/scripts/x.sh"
git -C "$R" add -A; git -C "$R" commit -q -m "version + behavioral"
H_MIX="$(git -C "$R" rev-parse HEAD)"
[[ "$(classify_head "$H_MIX")" == "behavioral" ]] && ok || bad "VERSION+.sh mixed -> behavioral (fail-closed)"

# === AC7 positive: range spanning package.json bump + changeset deletion ======
# BASE..H_DEL spans the package.json version-only bump and the changeset
# deletion (both release-bump deltas), so the aggregated range stays release_bump.
[[ "$(classify_range "${BASE}..${H_DEL}")" == "release_bump" ]] && ok || bad "range pkg-version+changeset-del -> release_bump"

echo "[evidence-classifier-release-bump-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
