#!/usr/bin/env bash
# Purpose: DP-305 T6 / AC8 + AC-NEG4 — selftest for gate-changeset.sh release-bump
#          carve-out. Asserts that when a resolved member task.md has no pending
#          changeset, the gate exempts release_bump / metadata_only push deltas
#          (exit 0) via the shared scripts/lib/evidence-classifier.sh, while a
#          behavioral delta missing its changeset stays fail-closed (exit 2) and
#          an already-authored changeset passes through the normal path (exit 0).
# Inputs:  none (hermetic tmp git repos with .changeset scaffolding).
# Outputs: PASS/FAIL lines per scenario; exit 0 (all pass) / 1 (any fail).
# Covers:  (1) release_bump delta, no pending changeset -> exempt exit 0 (AC8);
#          (2) metadata_only delta, no pending changeset -> exempt exit 0 (AC8);
#          (3) behavioral delta, no changeset -> BLOCKED exit 2 (AC-NEG4);
#          (4) behavioral delta WITH changeset present -> normal pass exit 0.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/scripts/gates/gate-changeset.sh"
PCS="$ROOT/scripts/polaris-changeset.sh"
[[ -x "$GATE" ]] || { echo "FAIL: missing/not executable: $GATE" >&2; exit 1; }
[[ -x "$PCS" ]] || { echo "FAIL: missing/not executable: $PCS" >&2; exit 1; }

TMP="$(mktemp -d -t gate-changeset-release-bump-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

# Build a hermetic git repo with changeset scaffolding and a seeded origin/main.
# Emits the repo path on stdout. After this returns, HEAD == origin/main == seed.
make_repo() {
  local name="$1"
  local r="$TMP/$name"
  mkdir -p "$r/.changeset" "$r/scripts" "$r/specs/tasks/T6"
  git -C "$r" init -q -b main
  git -C "$r" config user.email selftest@example.com
  git -C "$r" config user.name Selftest
  echo "seed" >"$r/README.md"
  printf '3.76.0\n' >"$r/VERSION"
  printf '# changelog\n' >"$r/CHANGELOG.md"
  cat >"$r/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.76.0",
  "private": true
}
JSON
  cat >"$r/.changeset/config.json" <<'JSON'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
JSON
  printf '# Changesets\n' >"$r/.changeset/README.md"
  printf '#!/usr/bin/env bash\necho seed\n' >"$r/scripts/x.sh"
  # Member task.md: derives ticket DP-305-T6 + title -> expected changeset slug.
  cat >"$r/specs/tasks/T6/index.md" <<'MD'
---
status: IN_PROGRESS
---

# T6: gate-changeset release bump carve out (2 pt)

> Source: DP-305 | Task: DP-305-T6 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task ID | DP-305-T6 |
| Base branch | main |
| Task branch | task/DP-305-T6-gate-changeset |

## Allowed Files

- `scripts/gates/gate-changeset.sh`
MD
  git -C "$r" add -A
  git -C "$r" commit -q -m "seed"
  # Establish origin/main as a real ref so merge-base origin/main..HEAD resolves.
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s\n' "$r"
}

TASK_REL="specs/tasks/T6/index.md"

# ── Scenario 1: release_bump delta, no pending changeset -> exempt (exit 0) ────
# Stage a consumable changeset, then a release-bump commit (VERSION + CHANGELOG +
# package.json version-only + .changeset/*.md deletion). The member's own
# task-bound changeset is absent, so polaris-changeset check fails, but the push
# delta classifies as release_bump -> gate must exit 0.
R1="$(make_repo repo1)"
printf -- '---\n"polaris-framework-workspace": patch\n---\n\nrelease bump combo\n' >"$R1/.changeset/lucky-cats-jump.md"
git -C "$R1" add -A
git -C "$R1" commit -q -m "stage changeset to consume"
git -C "$R1" update-ref refs/remotes/origin/main HEAD
printf '3.76.1\n' >"$R1/VERSION"
printf '# changelog\n- 3.76.1\n' >"$R1/CHANGELOG.md"
cat >"$R1/package.json" <<'JSON'
{
  "name": "polaris-framework-workspace",
  "version": "3.76.1",
  "private": true
}
JSON
git -C "$R1" rm -q "$R1/.changeset/lucky-cats-jump.md"
git -C "$R1" add -A
git -C "$R1" commit -q -m "release bump v3.76.1"
set +e
bash "$GATE" --repo "$R1" --task-md "$R1/$TASK_REL" >/dev/null 2>&1
rc1=$?
set -e
[[ "$rc1" -eq 0 ]] && ok "release_bump delta, no pending changeset -> exit 0 (AC8)" \
  || bad "release_bump delta should exempt (exit 0); got exit $rc1"

# ── Scenario 2: metadata_only delta, no pending changeset -> exempt (exit 0) ───
# A docs-only / metadata delta (non-behavioral *.md outside .changeset content
# rules) classifies as metadata_only -> gate must exit 0.
R2="$(make_repo repo2)"
printf '# Release notes\n\nMetadata-only docs change.\n' >"$R2/RELEASE_NOTES.md"
git -C "$R2" add -A
git -C "$R2" commit -q -m "metadata-only docs"
set +e
bash "$GATE" --repo "$R2" --task-md "$R2/$TASK_REL" >/dev/null 2>&1
rc2=$?
set -e
[[ "$rc2" -eq 0 ]] && ok "metadata_only delta, no pending changeset -> exit 0 (AC8)" \
  || bad "metadata_only delta should exempt (exit 0); got exit $rc2"

# ── Scenario 3: behavioral delta, no changeset -> BLOCKED (exit 2) ─────────────
# A .sh logic change with no task-bound changeset classifies as behavioral, so
# the carve-out must NOT fire and the gate stays fail-closed (AC-NEG4).
R3="$(make_repo repo3)"
printf '#!/usr/bin/env bash\necho behavioral change\n' >"$R3/scripts/x.sh"
git -C "$R3" add -A
git -C "$R3" commit -q -m "behavioral .sh change without changeset"
set +e
err3="$(bash "$GATE" --repo "$R3" --task-md "$R3/$TASK_REL" 2>&1 >/dev/null)"
rc3=$?
set -e
if [[ "$rc3" -eq 2 ]]; then
  ok "behavioral delta, no changeset -> exit 2 (AC-NEG4)"
else
  bad "behavioral delta should BLOCK (exit 2); got exit $rc3"
fi
if grep -q "BLOCKED" <<<"$err3"; then
  ok "behavioral block stderr contains BLOCKED"
else
  bad "behavioral block stderr should contain BLOCKED; got: $err3"
fi

# ── Scenario 4: behavioral delta WITH changeset present -> normal pass (exit 0) ─
# Same behavioral delta, but the task-bound changeset is authored. The normal
# polaris-changeset check passes before the classifier is reached -> exit 0.
R4="$(make_repo repo4)"
printf '#!/usr/bin/env bash\necho behavioral change\n' >"$R4/scripts/x.sh"
git -C "$R4" add -A
git -C "$R4" commit -q -m "behavioral .sh change"
# Author the task-bound changeset via the canonical producer.
bash "$PCS" new --task-md "$R4/$TASK_REL" --repo "$R4" >/dev/null 2>&1
git -C "$R4" add -A
git -C "$R4" commit -q -m "author task changeset"
set +e
bash "$GATE" --repo "$R4" --task-md "$R4/$TASK_REL" >/dev/null 2>&1
rc4=$?
set -e
[[ "$rc4" -eq 0 ]] && ok "behavioral delta WITH changeset -> exit 0 (normal path)" \
  || bad "behavioral delta with changeset should pass (exit 0); got exit $rc4"

echo ""
echo "[gate-changeset-release-bump-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
