#!/usr/bin/env bash
# Selftest for scripts/archive-spec.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_SPEC="$SCRIPT_DIR/archive-spec.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

write_plan() {
  local file="$1" status="$2" title="$3"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<MD
---
status: ${status}
---

# ${title}
MD
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/archive-spec-selftest.out 2>/tmp/archive-spec-selftest.err; then
    echo "[selftest] command unexpectedly passed: $label" >&2
    cat /tmp/archive-spec-selftest.out >&2 || true
    fail "$label"
  fi
}

tmpdir="$(mktemp -d -t archive-spec-selftest.XXXXXX)"
trap 'rm -rf "$tmpdir" /tmp/archive-spec-selftest.out /tmp/archive-spec-selftest.err' EXIT

mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/design-plans" "$tmpdir/docs-manager/src/content/docs/specs/companies/acme"

# DP by ID.
write_plan "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-999-implemented/plan.md" "IMPLEMENTED" "DP-999"
bash "$ARCHIVE_SPEC" --workspace "$tmpdir" DP-999 >/dev/null
[[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-999-implemented" ]] || fail "active DP remained after archive"
[[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-implemented/plan.md" ]] || fail "archived DP missing"
grep -q 'text: "IMPLEMENTED / P4"' "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-implemented/plan.md" || fail "archived DP sidebar badge was not refreshed"

# Company ticket by key.
write_plan "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/BUG-1/refinement.md" "ABANDONED" "BUG-1"
bash "$ARCHIVE_SPEC" --workspace "$tmpdir" BUG-1 >/dev/null
[[ ! -d "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/BUG-1" ]] || fail "active company spec remained after archive"
[[ -f "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" ]] || fail "archived company spec missing"
grep -q 'text: "ABANDONED"' "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/archive/BUG-1/refinement.md" || fail "archived company sidebar badge was not refreshed"

# Direct path input.
write_plan "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-996-direct-path/plan.md" "IMPLEMENTED" "DP-996"
bash "$ARCHIVE_SPEC" --workspace "$tmpdir" "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-996-direct-path/plan.md" >/dev/null
[[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-996-direct-path/plan.md" ]] || fail "direct path archive missing"

# Status guard.
write_plan "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-locked/plan.md" "LOCKED" "DP-998"
expect_fail "locked DP should not archive" bash "$ARCHIVE_SPEC" --workspace "$tmpdir" DP-998
[[ -d "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-998-locked" ]] || fail "locked DP moved despite guard"

# Missing status guard.
mkdir -p "$tmpdir/docs-manager/src/content/docs/specs/companies/acme/NO-1"
cat >"$tmpdir/docs-manager/src/content/docs/specs/companies/acme/NO-1/refinement.md" <<'MD'
# NO-1
MD
expect_fail "missing status should not archive" bash "$ARCHIVE_SPEC" --workspace "$tmpdir" NO-1

# Duplicate destination guard.
write_plan "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-997-duplicate/plan.md" "IMPLEMENTED" "DP-997 active"
write_plan "$tmpdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-997-duplicate/plan.md" "IMPLEMENTED" "DP-997 archived"
expect_fail "duplicate destination should fail" bash "$ARCHIVE_SPEC" --workspace "$tmpdir" DP-997
[[ -f "$tmpdir/docs-manager/src/content/docs/specs/design-plans/DP-997-duplicate/plan.md" ]] || fail "duplicate source moved despite guard"

# Unknown namespace guard.
mkdir -p "$tmpdir/random"
echo "x" >"$tmpdir/random/file.md"
expect_fail "unknown direct path should fail" bash "$ARCHIVE_SPEC" --workspace "$tmpdir" "$tmpdir/random/file.md"

# Sweep dry-run/apply.
sweepdir="$tmpdir/sweep"
mkdir -p "$sweepdir/docs-manager/src/content/docs/specs/design-plans" "$sweepdir/docs-manager/src/content/docs/specs/companies/acme"
write_plan "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-995-sweep-implemented/plan.md" "IMPLEMENTED" "DP-995"
write_plan "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-994-sweep-abandoned/plan.md" "ABANDONED" "DP-994"
write_plan "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-993-sweep-locked/plan.md" "LOCKED" "DP-993"
mkdir -p "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-992-sweep-missing"
cat >"$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-992-sweep-missing/plan.md" <<'MD'
# DP-992
MD
write_plan "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/DONE-1/refinement.md" "IMPLEMENTED" "DONE-1"
write_plan "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/SKIP-1/refinement.md" "DISCUSSION" "SKIP-1"
mkdir -p "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/NO-2"
cat >"$sweepdir/docs-manager/src/content/docs/specs/companies/acme/NO-2/refinement.md" <<'MD'
# NO-2
MD

bash "$ARCHIVE_SPEC" --workspace "$sweepdir" --sweep --dry-run >"$sweepdir/dry-run.tsv"
grep -q 'TYPE[[:space:]]STATUS[[:space:]]ACTION[[:space:]]SOURCE' "$sweepdir/dry-run.tsv" || fail "sweep dry-run header missing"
grep -q 'DP-995-sweep-implemented' "$sweepdir/dry-run.tsv" || fail "sweep dry-run omitted implemented DP"
grep -q 'DONE-1' "$sweepdir/dry-run.tsv" || fail "sweep dry-run omitted implemented company spec"
grep -q 'missing status' "$sweepdir/dry-run.tsv" || fail "sweep dry-run omitted missing-status skip"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-995-sweep-implemented" ]] || fail "dry-run moved implemented DP"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/DONE-1" ]] || fail "dry-run moved implemented company spec"

bash "$ARCHIVE_SPEC" --workspace "$sweepdir" --sweep --apply >"$sweepdir/apply.tsv"
[[ -f "$sweepdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-995-sweep-implemented/plan.md" ]] || fail "sweep apply did not archive implemented DP"
[[ -f "$sweepdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-994-sweep-abandoned/plan.md" ]] || fail "sweep apply did not archive abandoned DP"
[[ -f "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/archive/DONE-1/refinement.md" ]] || fail "sweep apply did not archive implemented company spec"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-993-sweep-locked" ]] || fail "sweep apply moved locked DP"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/design-plans/DP-992-sweep-missing" ]] || fail "sweep apply moved missing-status DP"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/SKIP-1" ]] || fail "sweep apply moved discussion company spec"
[[ -d "$sweepdir/docs-manager/src/content/docs/specs/companies/acme/NO-2" ]] || fail "sweep apply moved missing-status company spec"

# Sweep duplicate destination guard.
dupdir="$tmpdir/sweep-duplicate"
mkdir -p "$dupdir/docs-manager/src/content/docs/specs/design-plans"
write_plan "$dupdir/docs-manager/src/content/docs/specs/design-plans/DP-991-duplicate/plan.md" "IMPLEMENTED" "DP-991 active"
write_plan "$dupdir/docs-manager/src/content/docs/specs/design-plans/archive/DP-991-duplicate/plan.md" "IMPLEMENTED" "DP-991 archived"
expect_fail "sweep duplicate destination should fail" bash "$ARCHIVE_SPEC" --workspace "$dupdir" --sweep --dry-run

echo "[selftest] PASS"
