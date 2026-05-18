#!/usr/bin/env bash
# Selftest for migrate-specs-artifact-frontmatter.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATE="$SCRIPT_DIR/migrate-specs-artifact-frontmatter.sh"
VALIDATOR="$SCRIPT_DIR/validate-specs-collection-shape.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t migrate-specs-artifact.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

specs="$tmpdir/docs-manager/src/content/docs/specs"
mkdir -p \
  "$specs/design-plans/archive/DP-178-docs-viewer-lifecycle-user-ownership/artifacts/external-writes" \
  "$specs/design-plans/DP-190-sample/artifacts/research" \
  "$specs/companies/kkday/GT-567/artifacts/external-writes/20260513" \
  "$specs/design-plans/DP-999-manual/artifacts/external-writes"

cat >"$specs/design-plans/archive/DP-178-docs-viewer-lifecycle-user-ownership/artifacts/external-writes/20260515-dp178-pr-body.md" <<'MD'
## Description

PR body.
MD

cat >"$specs/design-plans/DP-190-sample/artifacts/research/2026-05-18-note.md" <<'MD'
## Note
MD

cat >"$specs/companies/kkday/GT-567/artifacts/external-writes/20260513/GT-567-jira-note-20260513.md" <<'MD'
## JIRA note
MD

cat >"$specs/design-plans/DP-999-manual/artifacts/external-writes/no-date.md" <<'MD'
## Manual
MD

report="$tmpdir/manual-fix-required.txt"
if bash "$MIGRATE" --workspace "$tmpdir" --report "$report" >/tmp/migrate.out 2>/tmp/migrate.err; then
  fail "migration with manual item should fail"
fi

grep -q 'DP-999-manual/artifacts/external-writes/no-date.md' "$report" || fail "manual report missing no-date file"
! grep -R -q 'artifact_type: unknown' "$specs" || fail "unknown placeholder was written"

grep -q 'artifact_type: external-write' "$specs/design-plans/archive/DP-178-docs-viewer-lifecycle-user-ownership/artifacts/external-writes/20260515-dp178-pr-body.md" || fail "DP-178 artifact_type missing"
grep -q 'source: DP-178' "$specs/design-plans/archive/DP-178-docs-viewer-lifecycle-user-ownership/artifacts/external-writes/20260515-dp178-pr-body.md" || fail "DP-178 source missing"
grep -q 'created: 2026-05-15' "$specs/design-plans/archive/DP-178-docs-viewer-lifecycle-user-ownership/artifacts/external-writes/20260515-dp178-pr-body.md" || fail "DP-178 created missing"

rm -f "$specs/design-plans/DP-999-manual/artifacts/external-writes/no-date.md"
bash "$MIGRATE" --workspace "$tmpdir" --report "$report" >/dev/null
bash "$VALIDATOR" --workspace "$tmpdir" --all >/dev/null

before="$(find "$specs" -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum)"
bash "$MIGRATE" --workspace "$tmpdir" --report "$report" >/dev/null
after="$(find "$specs" -type f -name '*.md' -print0 | sort -z | xargs -0 shasum | shasum)"
[[ "$before" == "$after" ]] || fail "migration is not idempotent"

echo "[selftest] PASS"

