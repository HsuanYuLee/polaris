#!/usr/bin/env bash
# Purpose: Hermetic selftest for sync-to-polaris.sh changeset-mechanism boundary (DP-295 T7).
# Inputs:  none (builds a self-contained instance + template under a tmpdir)
# Outputs: stdout PASS lines; exit 0 on success, non-zero on first failed assertion
# Side effects: creates and removes a tmpdir; never touches the live ~/polaris template
#
# Covers:
#   AC11    — changeset mechanism (config.json + README + .cjs formatter) syncs to template
#   AC-NEG4 — unconsumed .changeset/*.md entries do NOT leak into the template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$SCRIPT_DIR/sync-to-polaris.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

[[ -f "$SYNC" ]] || fail "sync-to-polaris.sh not found at $SYNC"

tmpdir="$(mktemp -d -t sync-changeset.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

INSTANCE="$tmpdir/instance"
TEMPLATE="$tmpdir/template"

# ── Minimal instance scaffolding ──────────────────────────────────
# The full sync iterates skills/references/rules/hooks/scripts via globs that
# tolerate emptiness; we only need the pieces relevant to the changeset step
# plus the sync script itself (so scripts/ sync stays a no-op-safe glob).
mkdir -p "$INSTANCE/.claude/skills" "$INSTANCE/.claude/rules" \
         "$INSTANCE/.claude/hooks" "$INSTANCE/scripts" "$INSTANCE/.changeset"
printf '3.99.999\n' >"$INSTANCE/VERSION"
# Copy the script under test INTO the synthetic instance and run it from there.
# sync-to-polaris derives INSTANCE_DIR from its own location ($SCRIPT_DIR/..),
# so it must run from inside $INSTANCE for this test to stay hermetic — running
# the worktree copy directly would sync the worktree's real .changeset/ instead.
INSTANCE_SYNC="$INSTANCE/scripts/sync-to-polaris.sh"
cp "$SYNC" "$INSTANCE_SYNC"

# Changeset mechanism files that MUST reach the template.
cat >"$INSTANCE/.changeset/config.json" <<'JSON'
{
  "$schema": "https://unpkg.com/@changesets/config@3.1.1/schema.json",
  "changelog": "./changelog-keepachangelog.cjs",
  "commit": false,
  "privatePackages": { "version": true, "tag": false }
}
JSON
cat >"$INSTANCE/.changeset/README.md" <<'MD'
# Changesets

Polaris single-package changeset config. Synced to the template repo.
MD
cat >"$INSTANCE/.changeset/changelog-keepachangelog.cjs" <<'CJS'
// Keep a Changelog custom formatter (DP-295 T3). Synced to template.
module.exports = { getReleaseLine: async () => "" };
CJS

# Unconsumed changeset ENTRY — instance-local, must NOT leak to template.
cat >"$INSTANCE/.changeset/dp-295-t7-unconsumed-entry.md" <<'MD'
---
"polaris-framework-workspace": patch
---

unconsumed changeset entry that must stay out of the template
MD

# ── Minimal template scaffolding ──────────────────────────────────
# Only the guard requirement ($POLARIS_DIR/.claude/skills) is mandatory.
mkdir -p "$TEMPLATE/.claude/skills"
git -C "$TEMPLATE" init -q
git -C "$TEMPLATE" config user.email selftest@example.com
git -C "$TEMPLATE" config user.name selftest

# Pre-seed a STALE changeset entry in the template to prove sync prunes leaks
# left behind by an earlier run.
mkdir -p "$TEMPLATE/.changeset"
cat >"$TEMPLATE/.changeset/stale-leaked-entry.md" <<'MD'
---
"polaris-framework-workspace": patch
---

stale leaked entry from a previous sync that should be pruned
MD

# ── Run sync (no commit/push → no gh/git account side effects) ────
bash "$INSTANCE_SYNC" --polaris "$TEMPLATE" >/tmp/sync-changeset.out 2>/tmp/sync-changeset.err \
  || { cat /tmp/sync-changeset.err >&2; fail "sync-to-polaris exited non-zero"; }

# ── AC11: mechanism files synced ──────────────────────────────────
[[ -f "$TEMPLATE/.changeset/config.json" ]] \
  || fail "AC11: .changeset/config.json was not synced to template"
grep -q 'changelog-keepachangelog.cjs' "$TEMPLATE/.changeset/config.json" \
  || fail "AC11: synced config.json content mismatch"
[[ -f "$TEMPLATE/.changeset/README.md" ]] \
  || fail "AC11: .changeset/README.md was not synced to template"
[[ -f "$TEMPLATE/.changeset/changelog-keepachangelog.cjs" ]] \
  || fail "AC11: .changeset/changelog-keepachangelog.cjs (formatter) was not synced to template"
echo "[selftest] PASS: AC11 — changeset mechanism (config + README + .cjs) synced"

# ── AC-NEG4: unconsumed changeset entry must NOT leak ─────────────
[[ ! -f "$TEMPLATE/.changeset/dp-295-t7-unconsumed-entry.md" ]] \
  || fail "AC-NEG4: unconsumed .changeset entry leaked into template"

# ── AC-NEG4 (prune): stale leaked entry must be removed ───────────
[[ ! -f "$TEMPLATE/.changeset/stale-leaked-entry.md" ]] \
  || fail "AC-NEG4: stale leaked .changeset entry was not pruned from template"

# Belt-and-suspenders: no changeset ENTRY .md (anything that is not README.md)
# should remain in the template .changeset dir.
leaked="$(find "$TEMPLATE/.changeset" -maxdepth 1 -type f -name '*.md' \
  ! -name 'README.md' 2>/dev/null || true)"
[[ -z "$leaked" ]] \
  || fail "AC-NEG4: unexpected changeset entry .md present in template: $leaked"
echo "[selftest] PASS: AC-NEG4 — no unconsumed/stale changeset entry leaked"

echo "[selftest] PASS"
