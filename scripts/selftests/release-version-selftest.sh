#!/usr/bin/env bash
# Purpose: Hermetic selftest for scripts/release-version.sh (DP-295 T2 — 壓版本 wrapper).
# Inputs:  none (builds tmpdir fixtures; injects a stub changeset CLI via
#          POLARIS_RELEASE_CHANGESET_CMD so no network / pnpm install is required).
# Outputs: stdout PASS/FAIL per assertion + summary; exit 0 all pass, 1 on any failure.
# Side effects: creates and removes a tmpdir under $TMPDIR.
#
# Coverage (AC2 / AC3 / AC-NEG3 + edge cases):
#   - no pending changeset → no-op exit 0, version unchanged (EC1)
#   - pending changeset → changeset version runs, package.json bumped,
#     VERSION mirror == package.json version, CHANGELOG has new version block,
#     consumed changeset deleted (AC2 / AC3)
#   - pending changeset but version did NOT advance → fail-loud exit non-zero
#     (AC-NEG3: must not silently pass)
#   - idempotent re-run after consumption → no-op (no second bump)
#   - usage / missing repo path → exit 2 / exit 1

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RV="$SCRIPT_DIR/release-version.sh"
WORK_DIR="$(mktemp -d -t polaris-relver-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — want=%s got=%s\n" "$label" "$want" "$got"
  fi
}

assert_file_exists() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s exists\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — file missing: %s\n" "$label" "$f"
  fi
}

assert_file_absent() {
  local f="$1" label="$2"
  if [[ ! -f "$f" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s absent (as expected)\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — file should be absent: %s\n" "$label" "$f"
  fi
}

assert_grep() {
  local file="$1" pat="$2" label="$3"
  if grep -q "$pat" "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — pattern %q not in %s\n" "$label" "$pat" "$file"
  fi
}

cleanup() { rm -rf "$WORK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────────────────
# Stub changeset CLI generator.
#
# The real wrapper delegates "changeset version" to @changesets/cli. To stay
# hermetic (no pnpm install / network), the selftest injects a stub command via
# POLARIS_RELEASE_CHANGESET_CMD that emulates the observable contract:
#   - consumes .changeset/*.md (deletes them, keeping README.md + config.json)
#   - bumps package.json "version" to $NEW_VERSION
#   - appends a Keep-a-Changelog-ish version block to CHANGELOG.md
# A second stub flavor ("noop") emulates a broken/misconfigured CLI that does
# NOT advance the version, to exercise the AC-NEG3 fail-loud guard.
# ────────────────────────────────────────────────────────────────────────────
make_stub_cli() {
  local path="$1" mode="$2" new_version="$3"
  cat > "$path" <<STUB
#!/usr/bin/env bash
set -euo pipefail
REPO="\$(pwd)"
MODE="$mode"
NEW_VERSION="$new_version"
if [[ "\$MODE" == "version-bump" ]]; then
  # consume changesets
  for f in "\$REPO"/.changeset/*.md; do
    [[ -e "\$f" ]] || continue
    base="\$(basename "\$f")"
    [[ "\$base" == "README.md" ]] && continue
    rm -f "\$f"
  done
  # bump package.json version (line-based; fixture package.json is simple)
  python3 - "\$REPO/package.json" "\$NEW_VERSION" <<'PY'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["version"] = v
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
  # Append a CHANGELOG version block that faithfully emulates the production
  # path: changeset version writes the custom formatter's section-tagged release
  # lines ("- [<Section>] ...", see changelog-keepachangelog.cjs) under the
  # changesets default "### Patch Changes" subheading. The release-version.sh
  # collator must regroup these tagged lines into Keep a Changelog sections.
  printf '\n## %s\n\n### Patch Changes\n\n- [Added] abc1234: selftest added line\n- [Fixed] def5678: selftest fixed line\n- [Changed] 9abcdef: selftest changed line\n' "\$NEW_VERSION" >> "\$REPO/CHANGELOG.md"
elif [[ "\$MODE" == "noop" ]]; then
  # broken CLI: consumes changesets but does NOT bump version (AC-NEG3 trap)
  for f in "\$REPO"/.changeset/*.md; do
    [[ -e "\$f" ]] || continue
    base="\$(basename "\$f")"
    [[ "\$base" == "README.md" ]] && continue
    rm -f "\$f"
  done
fi
exit 0
STUB
  chmod +x "$path"
}

make_fixture_repo() {
  local repo="$1" version="$2"
  mkdir -p "$repo/.changeset" "$repo/scripts"
  cat > "$repo/package.json" <<EOF
{
  "name": "polaris-framework-workspace",
  "version": "$version",
  "private": true
}
EOF
  printf '%s\n' "$version" > "$repo/VERSION"
  # Mirror the production config shape: the changelog points at the Keep a
  # Changelog custom formatter via the CONFIG-DIR-RELATIVE path (bug 2 fix —
  # @changesets/cli resolves "changelog" relative to .changeset/, so the value is
  # "./changelog-keepachangelog.cjs", not "./.changeset/..."). The hermetic stub
  # injects the changeset CLI via POLARIS_RELEASE_CHANGESET_CMD and does not load
  # this file, so its value is documentary — it keeps the fixture faithful to the
  # real .changeset/config.json.
  cat > "$repo/.changeset/config.json" <<'EOF'
{ "changelog": "./changelog-keepachangelog.cjs", "commit": false }
EOF
  cat > "$repo/.changeset/README.md" <<'EOF'
# Changesets
EOF
  cat > "$repo/CHANGELOG.md" <<'EOF'
# Changelog
EOF
}

add_changeset() {
  local repo="$1" slug="$2"
  cat > "$repo/.changeset/$slug.md" <<'EOF'
---
"polaris-framework-workspace": patch
---

selftest change
EOF
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== usage / arg validation ==="
"$RV" >/dev/null 2>&1; assert_eq "$?" "2" "no args → exit 2"
"$RV" --repo /nonexistent/dir/xyz >/dev/null 2>&1; assert_eq "$?" "1" "nonexistent --repo → exit 1"

# ────────────────────────────────────────────────────────────────────────────
echo "=== EC1: no pending changeset → no-op, version unchanged ==="
REPO_NP="$WORK_DIR/no-pending"
make_fixture_repo "$REPO_NP" "1.0.0"
OUT_NP="$WORK_DIR/np.out"
POLARIS_RELEASE_CHANGESET_CMD="/bin/true" "$RV" --repo "$REPO_NP" >"$OUT_NP" 2>&1
assert_eq "$?" "0" "no pending → exit 0"
assert_eq "$(cat "$REPO_NP/VERSION")" "1.0.0" "VERSION unchanged on no-op"
assert_eq "$(python3 -c 'import json;print(json.load(open("'"$REPO_NP"'/package.json"))["version"])')" "1.0.0" "package.json unchanged on no-op"
assert_grep "$OUT_NP" "no pending changeset" "no-op message present (case-insensitive expected)"

# ────────────────────────────────────────────────────────────────────────────
echo "=== AC2/AC3: pending changeset → bump + VERSION mirror + CHANGELOG block + consume ==="
REPO_OK="$WORK_DIR/bump-ok"
make_fixture_repo "$REPO_OK" "1.0.0"
add_changeset "$REPO_OK" "dp-295-t2-test"
STUB_OK="$WORK_DIR/stub-ok.sh"
make_stub_cli "$STUB_OK" "version-bump" "1.0.1"
OUT_OK="$WORK_DIR/ok.out"
POLARIS_RELEASE_CHANGESET_CMD="$STUB_OK" "$RV" --repo "$REPO_OK" >"$OUT_OK" 2>&1
assert_eq "$?" "0" "pending → exit 0"
assert_eq "$(python3 -c 'import json;print(json.load(open("'"$REPO_OK"'/package.json"))["version"])')" "1.0.1" "package.json bumped to 1.0.1"
assert_eq "$(cat "$REPO_OK/VERSION")" "1.0.1" "VERSION mirror == package.json version (AC3)"
assert_grep "$REPO_OK/CHANGELOG.md" "1.0.1" "CHANGELOG has new version block (AC3)"
assert_file_absent "$REPO_OK/.changeset/dp-295-t2-test.md" "consumed changeset deleted (AC2)"
assert_file_exists "$REPO_OK/.changeset/README.md" "README.md preserved"
assert_file_exists "$REPO_OK/.changeset/config.json" "config.json preserved"

# ────────────────────────────────────────────────────────────────────────────
# AC10 production-path assertion: the wired-in release-version.sh collator must
# transform the new version block into Keep a Changelog "### <section>" structure
# (NOT merely leave the formatter's "- [<Section>] ..." tagged lines or the
# changesets default "### Patch Changes" subheading). This is the gap V1 surfaced:
# the formatter + module unit test passed, but the production CHANGELOG was never
# collated because config.json + the wrapper were not wired together. Asserting on
# the real CHANGELOG output (not module shape) closes that gap.
echo "=== AC10: new version block collated into Keep a Changelog structure ==="
# The version heading must be rewritten from the changesets default "## <version>"
# into the Keep a Changelog release heading "## [<version>] - <date>" (AC10:
# "## [X.Y.Z] - date"). Assert the bracketed-version + ISO-date shape; the plain
# "## <version>" default must be gone.
assert_grep "$REPO_OK/CHANGELOG.md" "^## \[1.0.1\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" "version heading rewritten to '## [X.Y.Z] - date' (AC10)"
if grep -qE '^## 1\.0\.1[[:space:]]*$' "$REPO_OK/CHANGELOG.md" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL-status] AC10 — plain '## 1.0.1' default heading should be rewritten to '## [1.0.1] - <date>'\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC10 plain default heading rewritten away\n"
fi
assert_grep "$REPO_OK/CHANGELOG.md" "### Added" "collated CHANGELOG has ### Added (AC10)"
assert_grep "$REPO_OK/CHANGELOG.md" "### Fixed" "collated CHANGELOG has ### Fixed (AC10)"
assert_grep "$REPO_OK/CHANGELOG.md" "### Changed" "collated CHANGELOG has ### Changed (AC10)"
# The "[<Section>]" tag must be stripped from each release line once collated.
if grep -q '\[Added\]' "$REPO_OK/CHANGELOG.md" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL-status] AC10 — section tag '[Added]' should be stripped after collation\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC10 section tag stripped after collation\n"
fi
# The changesets default "### Patch Changes" subheading must be replaced by the
# Keep a Changelog sections (not left alongside them).
if grep -q '### Patch Changes' "$REPO_OK/CHANGELOG.md" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL-status] AC10 — default '### Patch Changes' subheading should be collated away\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC10 default subheading collated away\n"
fi
# Idempotent: re-running the wrapper after consumption is a no-op and must NOT
# mangle the already-collated block (no duplicate sections, tags stay stripped).
OUT_COLLATE_RR="$WORK_DIR/collate-rerun.out"
POLARIS_RELEASE_CHANGESET_CMD="/bin/true" "$RV" --repo "$REPO_OK" >"$OUT_COLLATE_RR" 2>&1
assert_eq "$?" "0" "AC10 re-run no pending → exit 0 (collator idempotent)"
assert_eq "$(grep -c '^### Added' "$REPO_OK/CHANGELOG.md")" "1" "AC10 no duplicate ### Added after re-run"
if grep -q '\[Added\]' "$REPO_OK/CHANGELOG.md" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL-status] AC10 — tag reappeared after idempotent re-run\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC10 still tag-free after idempotent re-run\n"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== AC-NEG3: pending changeset but version did NOT advance → fail-loud ==="
REPO_NEG="$WORK_DIR/neg3"
make_fixture_repo "$REPO_NEG" "1.0.0"
add_changeset "$REPO_NEG" "dp-295-t2-neg"
STUB_NOOP="$WORK_DIR/stub-noop.sh"
make_stub_cli "$STUB_NOOP" "noop" ""
OUT_NEG="$WORK_DIR/neg.out"
POLARIS_RELEASE_CHANGESET_CMD="$STUB_NOOP" "$RV" --repo "$REPO_NEG" >"$OUT_NEG" 2>&1
RC_NEG=$?
if [[ "$RC_NEG" -ne 0 ]]; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC-NEG3 fail-loud (rc=%s)\n" "$RC_NEG"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] AC-NEG3 — expected non-zero exit, got 0\n    out: %s\n" "$(cat "$OUT_NEG")"
fi
assert_eq "$(cat "$REPO_NEG/VERSION")" "1.0.0" "VERSION not silently advanced on AC-NEG3"

# ────────────────────────────────────────────────────────────────────────────
echo "=== idempotent: re-run after consumption → no-op (no second bump) ==="
# REPO_OK already had its changeset consumed above; re-running must be a no-op.
OUT_RR="$WORK_DIR/rerun.out"
POLARIS_RELEASE_CHANGESET_CMD="/bin/true" "$RV" --repo "$REPO_OK" >"$OUT_RR" 2>&1
assert_eq "$?" "0" "re-run no pending → exit 0"
assert_eq "$(cat "$REPO_OK/VERSION")" "1.0.1" "VERSION stable on re-run (no double bump)"
assert_grep "$OUT_RR" "no pending changeset" "re-run no-op message present"

# ────────────────────────────────────────────────────────────────────────────
# GENUINE END-TO-END (NOT the POLARIS_RELEASE_CHANGESET_CMD stub, NOT changelog:false).
#
# Every stub-based assertion above injects a fake changeset CLI, and the earlier
# real-CLI smoke used "changelog": false — both DODGED the custom Keep a Changelog
# formatter. That dodge is exactly why the first real dogfood caught bugs the
# tests missed:
#   - bug 2: config "changelog" was "./.changeset/<file>" → @changesets/cli
#     resolves it relative to .changeset/ → .changeset/.changeset/<file> →
#     MODULE_NOT_FOUND → press aborts.
#   - bug 3: the collator preserved the changesets-default "## <version>" heading
#     instead of the Keep a Changelog "## [X.Y.Z] - date" heading (AC10).
#
# This block runs the REAL production path end-to-end: it copies the REAL
# .changeset/config.json (with the custom "changelog" formatter) and the REAL
# .changeset/changelog-keepachangelog.cjs into the fixture, runs the REAL
# `pnpm exec changeset version` VIA scripts/release-version.sh (no stub), and
# asserts the produced CHANGELOG is genuine Keep a Changelog output:
#   (a) version pressed, (b) heading "## [X.Y.Z] - <date>", (c) "### <Section>"
#   headings, (d) no leftover "[Section]" tags, (e) changeset consumed.
#
# Strengthening, not relaxation: it ADDS the formatter-driven coverage the old
# changelog:false smoke skipped. It skips cleanly (pass-by-skip) ONLY when an
# input the production path genuinely needs is unavailable in this checkout:
#   - the real @changesets/cli binary is not installed (run 'pnpm install'), or
#   - the T3-owned formatter .changeset/changelog-keepachangelog.cjs is not
#     present in this tree (it lands at bundle time; T2-in-isolation has no copy).
# When BOTH inputs are present (the real dogfood / bundle condition) the hard
# assertions run and this test FAILS against pre-fix config + collator.
echo "=== REAL e2e: custom formatter config + collator press Keep a Changelog block ==="
# Resolve the real changeset binary from the workspace node_modules (the
# production path the wrapper uses). Walk up from this script to find it.
REAL_CHANGESET_DIR=""
_probe_dir="$SCRIPT_DIR"
while [[ "$_probe_dir" != "/" ]]; do
  if [[ -x "$_probe_dir/node_modules/.bin/changeset" ]]; then
    REAL_CHANGESET_DIR="$_probe_dir"
    break
  fi
  _probe_dir="$(dirname "$_probe_dir")"
done

# Resolve the REAL custom formatter + config from the workspace (T3-owned files).
# Walk up from this script to find a .changeset/ that carries the custom formatter.
REAL_FORMATTER=""
REAL_CONFIG=""
_probe_dir="$SCRIPT_DIR"
while [[ "$_probe_dir" != "/" ]]; do
  if [[ -f "$_probe_dir/.changeset/changelog-keepachangelog.cjs" \
     && -f "$_probe_dir/.changeset/config.json" ]]; then
    REAL_FORMATTER="$_probe_dir/.changeset/changelog-keepachangelog.cjs"
    REAL_CONFIG="$_probe_dir/.changeset/config.json"
    break
  fi
  _probe_dir="$(dirname "$_probe_dir")"
done

read_ver() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$1/package.json"; }

if [[ -z "$REAL_CHANGESET_DIR" ]]; then
  PASS=$((PASS + 1))
  printf "  [skip] real @changesets/cli binary not installed — run 'pnpm install' to exercise the production path\n"
elif [[ -z "$REAL_FORMATTER" ]]; then
  PASS=$((PASS + 1))
  printf "  [skip] real custom formatter .changeset/changelog-keepachangelog.cjs not in this tree (T3-owned; lands at bundle) — production formatter path not exercised here\n"
else
  # Build an isolated single-package workspace fixture WITH the root '.' in
  # pnpm-workspace.yaml AND the REAL custom-formatter config + formatter, then run
  # the production wrapper (real `pnpm exec changeset version` + collator).
  REPO_E2E="$WORK_DIR/real-e2e"
  mkdir -p "$REPO_E2E/.changeset"
  cat > "$REPO_E2E/package.json" <<EOF
{ "name": "polaris-framework-workspace", "version": "1.0.0", "private": true }
EOF
  printf '1.0.0\n' > "$REPO_E2E/VERSION"
  printf 'packages:\n  - .\n' > "$REPO_E2E/pnpm-workspace.yaml"
  printf '# Changelog\n' > "$REPO_E2E/CHANGELOG.md"
  printf '# Changesets\n' > "$REPO_E2E/.changeset/README.md"
  # Copy the REAL config + REAL formatter (no changelog:false dodge).
  cp "$REAL_CONFIG" "$REPO_E2E/.changeset/config.json"
  cp "$REAL_FORMATTER" "$REPO_E2E/.changeset/changelog-keepachangelog.cjs"
  # Two changesets of different Conventional Commits types so the collator must
  # produce more than one Keep a Changelog section.
  cat > "$REPO_E2E/.changeset/e2e-feat.md" <<'EOF'
---
"polaris-framework-workspace": minor
---

feat: real e2e added capability
EOF
  cat > "$REPO_E2E/.changeset/e2e-fix.md" <<'EOF'
---
"polaris-framework-workspace": patch
---

fix: real e2e corrected behaviour
EOF
  # Make the real changeset binary resolvable to the production wrapper. The
  # wrapper prefers `pnpm exec changeset`; inject the resolved binary directly so
  # the e2e does not depend on pnpm being on PATH inside the fixture.
  OUT_E2E="$WORK_DIR/real-e2e.out"
  POLARIS_RELEASE_CHANGESET_CMD="$REAL_CHANGESET_DIR/node_modules/.bin/changeset" \
    "$RV" --repo "$REPO_E2E" >"$OUT_E2E" 2>&1
  RC_E2E=$?
  if [[ "$RC_E2E" -ne 0 ]]; then
    FAIL=$((FAIL + 1))
    printf "  [FAIL] real e2e: release-version.sh exited %s\n    out: %s\n" "$RC_E2E" "$(cat "$OUT_E2E")"
  else
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] real e2e: release-version.sh exit 0\n"
  fi
  # MODULE_NOT_FOUND on the formatter (bug 2) must NOT occur.
  if grep -qi "MODULE_NOT_FOUND\|Cannot find module" "$OUT_E2E" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf "  [FAIL] real e2e: formatter not resolved (bug 2 path)\n    out: %s\n" "$(cat "$OUT_E2E")"
  else
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] real e2e: no MODULE_NOT_FOUND (formatter resolved)\n"
  fi
  # (a) version pressed (1.0.0 -> 1.1.0 because of the minor changeset).
  assert_eq "$(read_ver "$REPO_E2E")" "1.1.0" "real e2e: version pressed 1.0.0 -> 1.1.0 (minor)"
  assert_eq "$(cat "$REPO_E2E/VERSION")" "1.1.0" "real e2e: VERSION mirror == 1.1.0"
  # (b) Keep a Changelog heading "## [X.Y.Z] - <date>" (bug 3 / AC10).
  assert_grep "$REPO_E2E/CHANGELOG.md" "^## \[1.1.0\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" "real e2e: heading is '## [1.1.0] - <date>' (AC10)"
  if grep -qE '^## 1\.1\.0[[:space:]]*$' "$REPO_E2E/CHANGELOG.md" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf "  [FAIL-status] real e2e: plain '## 1.1.0' default heading not rewritten (bug 3)\n    changelog:\n%s\n" "$(cat "$REPO_E2E/CHANGELOG.md")"
  else
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] real e2e: default heading rewritten away\n"
  fi
  # (c) "### <Section>" Keep a Changelog headings present (Added from feat, Fixed from fix).
  assert_grep "$REPO_E2E/CHANGELOG.md" "^### Added$" "real e2e: ### Added section (from feat)"
  assert_grep "$REPO_E2E/CHANGELOG.md" "^### Fixed$" "real e2e: ### Fixed section (from fix)"
  # (d) no leftover "[Section]" tags after collation.
  if grep -qE '\[(Added|Changed|Fixed|Removed|Deprecated|Security)\]' "$REPO_E2E/CHANGELOG.md" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf "  [FAIL-status] real e2e: leftover '[Section]' tag after collation\n    changelog:\n%s\n" "$(cat "$REPO_E2E/CHANGELOG.md")"
  else
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] real e2e: no leftover section tags\n"
  fi
  # changesets default "### Minor Changes" / "### Patch Changes" must be collated away.
  if grep -qE '^### (Minor|Patch|Major) Changes' "$REPO_E2E/CHANGELOG.md" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf "  [FAIL-status] real e2e: changesets default subheading not collated away\n    changelog:\n%s\n" "$(cat "$REPO_E2E/CHANGELOG.md")"
  else
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] real e2e: default subheadings collated away\n"
  fi
  # (e) both changesets consumed.
  assert_file_absent "$REPO_E2E/.changeset/e2e-feat.md" "real e2e: feat changeset consumed"
  assert_file_absent "$REPO_E2E/.changeset/e2e-fix.md" "real e2e: fix changeset consumed"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "PASS=$PASS  FAIL=$FAIL  TOTAL=$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
