#!/usr/bin/env bash
# Purpose: Hermetic selftest for the DP-334 feature-branch release model layered
#          onto scripts/release-version.sh: at a feat/DP-NNN HEAD, multiple
#          accumulated changesets (all belonging to ONE DP) compress into a SINGLE
#          version bump; CHANGELOG accumulates every changeset line; the consumed
#          changesets are deleted; and pending changesets spanning MORE THAN ONE
#          distinct DP fail-loud (AC-NEG2 — no cross-DP version stacking).
# Inputs:  none (builds tmpdir fixtures; injects a stub changeset CLI via
#          POLARIS_RELEASE_CHANGESET_CMD so no network / pnpm install is required).
# Outputs: stdout PASS/FAIL per assertion + summary; exit 0 all pass, 1 on any failure.
# Side effects: creates and removes a tmpdir under $TMPDIR.
#
# Coverage (AC3 / AC4 / AC6 / AC-NEG2):
#   - feat HEAD with N changesets (same DP) -> single version bump, VERSION mirror,
#     CHANGELOG block accumulates all N lines, all N changesets consumed (AC3).
#   - re-run after consumption is a no-op (single version, no second bump).
#   - pending changesets spanning two distinct DPs -> fail-loud
#     POLARIS_RELEASE_VERSION_MULTI_DP_STACKING, version NOT advanced (AC-NEG2).
#   - changesets with no DP marker do not trip the guard (guard scoped to DP slugs).

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RV="$SCRIPT_DIR/release-version.sh"
WORK_DIR="$(mktemp -d -t polaris-relver-feat-selftest-XXXXXX)"
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
# Stub changeset CLI generator (feat-HEAD flavor).
#
# Emulates the observable @changesets/cli contract for the feat-HEAD compression:
#   - consumes ALL .changeset/*.md (keeping README.md + config.json)
#   - bumps package.json "version" to $NEW_VERSION
#   - appends ONE accumulated "## <version>" CHANGELOG block whose body lists a
#     formatter-tagged line per consumed changeset (so the production collator must
#     accumulate every accumulated changeset, AC3). The stub reads each consumed
#     changeset body to derive its line, faithfully modelling accumulation.
# ────────────────────────────────────────────────────────────────────────────
make_feat_stub_cli() {
  local path="$1" new_version="$2"
  cat > "$path" <<STUB
#!/usr/bin/env bash
set -euo pipefail
REPO="\$(pwd)"
NEW_VERSION="$new_version"

# Collect one tagged CHANGELOG line per pending changeset (accumulation).
lines=()
i=0
for f in "\$REPO"/.changeset/*.md; do
  [[ -e "\$f" ]] || continue
  base="\$(basename "\$f")"
  [[ "\$base" == "README.md" ]] && continue
  body="\$(grep -v '^---' "\$f" | grep -v '^"' | grep -v '^[[:space:]]*\$' | head -n1)"
  [[ -n "\$body" ]] || body="\$base"
  lines+=("- [Changed] c0ffee\$i: \$body")
  i=\$((i + 1))
  rm -f "\$f"
done

# bump package.json version
python3 - "\$REPO/package.json" "\$NEW_VERSION" <<'PY'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["version"] = v
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY

# Append a single accumulated version block.
{
  printf '\n## %s\n\n### Patch Changes\n\n' "\$NEW_VERSION"
  for ln in "\${lines[@]}"; do
    printf '%s\n' "\$ln"
  done
} >> "\$REPO/CHANGELOG.md"
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

# add_changeset <repo> <slug> <body>
add_changeset() {
  local repo="$1" slug="$2" body="$3"
  cat > "$repo/.changeset/$slug.md" <<EOF
---
"polaris-framework-workspace": patch
---

$body
EOF
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== AC3: feat HEAD accumulates N same-DP changesets into ONE version ==="
REPO_FEAT="$WORK_DIR/feat-head"
make_fixture_repo "$REPO_FEAT" "1.0.0"
# Three changesets all belonging to DP-334 (the feat/DP-334 aggregation).
add_changeset "$REPO_FEAT" "dp-334-t1-engineering-branch-setup-feat-aggregation" "T1 feat aggregation"
add_changeset "$REPO_FEAT" "dp-334-t2-release-gate-lifecycle-feat" "T2 gate lifecycle"
add_changeset "$REPO_FEAT" "dp-334-t3-release-tail-feat-head" "T3 release tail"
STUB_FEAT="$WORK_DIR/stub-feat.sh"
make_feat_stub_cli "$STUB_FEAT" "1.0.1"
OUT_FEAT="$WORK_DIR/feat.out"
POLARIS_RELEASE_CHANGESET_CMD="$STUB_FEAT" "$RV" --repo "$REPO_FEAT" >"$OUT_FEAT" 2>&1
RC_FEAT=$?
assert_eq "$RC_FEAT" "0" "feat HEAD multi-changeset → exit 0"
assert_eq "$(python3 -c 'import json;print(json.load(open("'"$REPO_FEAT"'/package.json"))["version"])')" "1.0.1" "single version bump 1.0.0 -> 1.0.1 (AC3)"
assert_eq "$(cat "$REPO_FEAT/VERSION")" "1.0.1" "VERSION mirror == 1.0.1 (AC3)"
# Exactly one "## [version]" release heading: a single version for the DP (AC4 shape).
assert_eq "$(grep -cE '^## \[1\.0\.1\]' "$REPO_FEAT/CHANGELOG.md")" "1" "exactly ONE version block produced (one DP one version)"
# CHANGELOG accumulates a line for EACH of the three changesets (AC3 accumulation).
assert_grep "$REPO_FEAT/CHANGELOG.md" "T1 feat aggregation" "CHANGELOG accumulated T1 line (AC3)"
assert_grep "$REPO_FEAT/CHANGELOG.md" "T2 gate lifecycle" "CHANGELOG accumulated T2 line (AC3)"
assert_grep "$REPO_FEAT/CHANGELOG.md" "T3 release tail" "CHANGELOG accumulated T3 line (AC3)"
# All three changesets consumed (AC3).
assert_file_absent "$REPO_FEAT/.changeset/dp-334-t1-engineering-branch-setup-feat-aggregation.md" "T1 changeset consumed (AC3)"
assert_file_absent "$REPO_FEAT/.changeset/dp-334-t2-release-gate-lifecycle-feat.md" "T2 changeset consumed (AC3)"
assert_file_absent "$REPO_FEAT/.changeset/dp-334-t3-release-tail-feat-head.md" "T3 changeset consumed (AC3)"

echo "=== AC3: re-run after consumption → no-op (single version, no second bump) ==="
OUT_RR="$WORK_DIR/feat-rerun.out"
POLARIS_RELEASE_CHANGESET_CMD="/bin/true" "$RV" --repo "$REPO_FEAT" >"$OUT_RR" 2>&1
assert_eq "$?" "0" "re-run no pending → exit 0"
assert_eq "$(cat "$REPO_FEAT/VERSION")" "1.0.1" "VERSION stable on re-run (no double bump)"
assert_grep "$OUT_RR" "no pending changeset" "re-run no-op message present"

# ────────────────────────────────────────────────────────────────────────────
echo "=== AC-NEG2: pending changesets spanning TWO distinct DPs → fail-loud ==="
REPO_MULTI="$WORK_DIR/multi-dp"
make_fixture_repo "$REPO_MULTI" "2.0.0"
add_changeset "$REPO_MULTI" "dp-334-t1-feat-aggregation" "DP-334 work"
add_changeset "$REPO_MULTI" "dp-291-t2-some-other-dp" "DP-291 work"
STUB_MULTI="$WORK_DIR/stub-multi.sh"
make_feat_stub_cli "$STUB_MULTI" "2.0.1"
OUT_MULTI="$WORK_DIR/multi.out"
POLARIS_RELEASE_CHANGESET_CMD="$STUB_MULTI" "$RV" --repo "$REPO_MULTI" >"$OUT_MULTI" 2>&1
RC_MULTI=$?
if [[ "$RC_MULTI" -ne 0 ]]; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] AC-NEG2 cross-DP stacking fail-loud (rc=%s)\n" "$RC_MULTI"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] AC-NEG2 — expected non-zero exit on cross-DP stacking, got 0\n    out: %s\n" "$(cat "$OUT_MULTI")"
fi
assert_grep "$OUT_MULTI" "POLARIS_RELEASE_VERSION_MULTI_DP_STACKING" "AC-NEG2 emits multi-DP stacking marker"
assert_eq "$(cat "$REPO_MULTI/VERSION")" "2.0.0" "AC-NEG2 version NOT advanced on cross-DP stacking"
# The guard fails BEFORE consuming changesets — both must survive for a retry.
assert_eq "$(ls "$REPO_MULTI/.changeset"/dp-*.md 2>/dev/null | wc -l | tr -d ' ')" "2" "AC-NEG2 changesets NOT consumed on fail-loud"

# ────────────────────────────────────────────────────────────────────────────
echo "=== guard scope: changesets with NO DP marker do not trip the guard ==="
REPO_NODP="$WORK_DIR/no-dp"
make_fixture_repo "$REPO_NODP" "3.0.0"
add_changeset "$REPO_NODP" "ad-hoc-changeset-one" "ad-hoc one"
add_changeset "$REPO_NODP" "ad-hoc-changeset-two" "ad-hoc two"
STUB_NODP="$WORK_DIR/stub-nodp.sh"
make_feat_stub_cli "$STUB_NODP" "3.0.1"
OUT_NODP="$WORK_DIR/nodp.out"
POLARIS_RELEASE_CHANGESET_CMD="$STUB_NODP" "$RV" --repo "$REPO_NODP" >"$OUT_NODP" 2>&1
assert_eq "$?" "0" "no-DP-marker changesets → guard no-op, exit 0"
assert_eq "$(cat "$REPO_NODP/VERSION")" "3.0.1" "no-DP-marker changesets bump normally"

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
