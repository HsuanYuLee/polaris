#!/usr/bin/env bash
# Purpose: DP-303-T3 / AC4 — assert scan-template-leaks.sh scope converges to the
#          sync-to-polaris.sh copy set: gitignored runtime state (e.g.
#          .claude/active-thread.md) carrying a live company slug is NOT flagged,
#          while a file that actually syncs into the template carrying a live slug
#          stays fail-closed. Single source of truth = git tracked-ness, which is
#          exactly what sync-to-polaris copies, so scanner and sync cannot drift.
# Inputs:  none (builds a hermetic temp git workspace fixture)
# Outputs: stdout PASS line; exit 0 on pass, exit 1 on any assertion failure
# Side effects: creates/removes a temp dir under $TMPDIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCANNER="$SCRIPT_DIR/scan-template-leaks.sh"

tmpdir="$(mktemp -d -t scan-template-leaks-sync-set.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

workspace="$tmpdir/workspace"
mkdir -p \
  "$workspace/acme" \
  "$workspace/.claude" \
  "$workspace/.claude/skills/references" \
  "$workspace/scripts"

# Hermetic git repo so scanner's tracked-vs-gitignored resolution mirrors the
# real workspace (sync-to-polaris requires a clean tracked tree before copy).
git -C "$workspace" init -q
git -C "$workspace" config user.email selftest@example.com
git -C "$workspace" config user.name selftest

cat > "$workspace/acme/workspace-config.yaml" <<'YAML'
jira:
  instance: acme.atlassian.net
  projects:
    - key: ACME
github:
  org: acme-inc
web_urls:
  production: https://www.acme.example
slack:
  channels:
    dev: C0123456789
YAML

# .gitignore marks the runtime session-state file as ignored → never tracked →
# never copied by sync-to-polaris. The scanner must therefore not flag it even
# though it carries a live slug.
cat > "$workspace/.gitignore" <<'IGNORE'
.claude/active-thread.md
IGNORE

# (1) gitignored runtime state carrying a live slug — MUST NOT be flagged.
cat > "$workspace/.claude/active-thread.md" <<'MD'
parked work for ACME-123 in progress
MD

# (2) a tracked, template-surface file carrying a live slug — MUST stay flagged.
cat > "$workspace/.claude/skills/references/leaky.md" <<'MD'
This shared reference leaks ACME-999 into the template.
MD

git -C "$workspace" add -A

assert_block() {
  local out="$1"
  if [[ "$out" -eq 0 ]]; then
    echo "selftest failed: scan should fail-closed on tracked template-surface live slug" >&2
    exit 1
  fi
}

# ── State A: tracked synced file with live slug → fail-closed ──────────────
set +e
"$SCANNER" --workspace "$workspace" --source workspace --blocking \
  >"$tmpdir/scan.out" 2>"$tmpdir/scan.err"
rc=$?
set -e
assert_block "$rc"

if ! grep -q ".claude/skills/references/leaky.md" "$tmpdir/scan.out"; then
  echo "selftest failed: expected tracked synced-set leak (leaky.md) to be flagged" >&2
  cat "$tmpdir/scan.out" >&2
  exit 1
fi

# ── State B: gitignored runtime state with live slug → NOT flagged ─────────
if grep -q ".claude/active-thread.md" "$tmpdir/scan.out"; then
  echo "selftest failed: gitignored runtime state (active-thread.md) must not be flagged" >&2
  cat "$tmpdir/scan.out" >&2
  exit 1
fi

# ── State C: remove the tracked leak → scan is clean (scope did not over-flag) ──
git -C "$workspace" rm -qf ".claude/skills/references/leaky.md"
"$SCANNER" --workspace "$workspace" --source workspace --blocking \
  >"$tmpdir/scan-clean.out" 2>"$tmpdir/scan-clean.err"

if grep -q "active-thread.md" "$tmpdir/scan-clean.out"; then
  echo "selftest failed: gitignored runtime state must remain excluded after cleanup" >&2
  exit 1
fi

# ── State D: single-source-of-truth guard ─────────────────────────────────
# A runtime-state file that gitignore does NOT cover (e.g. settings.local.json
# absent from .gitignore) must NOT be silently skipped by a separate hardcoded
# path list. Gitignore is the single authority for the "does NOT sync" set
# (mirrors sync-to-polaris.sh "What it does NOT sync"); a hardcoded duplicate
# would drift from .gitignore. When such a file carries a live slug and is not
# gitignored, the scanner must still fail-closed.
cat > "$workspace/.claude/settings.local.json" <<'JSON'
{ "note": "leaks ACME-777 but is NOT in .gitignore here" }
JSON
git -C "$workspace" add -f ".claude/settings.local.json"

set +e
"$SCANNER" --workspace "$workspace" --source workspace --blocking \
  >"$tmpdir/scan-sot.out" 2>"$tmpdir/scan-sot.err"
rc=$?
set -e
assert_block "$rc"

if ! grep -q ".claude/settings.local.json" "$tmpdir/scan-sot.out"; then
  echo "selftest failed: non-gitignored runtime-state file with live slug must not be" >&2
  echo "  silently skipped by a hardcoded list — gitignore is the single authority" >&2
  cat "$tmpdir/scan-sot.out" >&2
  exit 1
fi

echo "PASS: scan-template-leaks sync-set scope selftest"
