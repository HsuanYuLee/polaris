#!/usr/bin/env bash
# Selftest for scripts/cleanup-duplicate-starlight-title.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLEANUP="$SCRIPT_DIR/cleanup-duplicate-starlight-title.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t starlight-title-cleanup.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/specs" "$tmpdir/build/dist"
mkdir -p "$tmpdir/specs/tasks"

cat >"$tmpdir/specs/duplicate.md" <<'MD'
---
title: "Duplicate Title"
description: "Has duplicate H1."
---

# Duplicate Title

Body.
MD

cat >"$tmpdir/specs/non-duplicate.md" <<'MD'
---
title: "Page Title"
description: "Different H1."
---

# Section Title

Body.
MD

cat >"$tmpdir/specs/missing-title.md" <<'MD'
---
description: "Missing title."
---

# Missing Title
MD

cat >"$tmpdir/specs/no-h1.md" <<'MD'
---
title: "No H1"
description: "No body H1."
---

## Section
MD

cat >"$tmpdir/specs/tasks/T1.md" <<'MD'
---
title: "T1: Task Title (1 pt)"
description: "Task fixture."
---

# T1: Task Title (1 pt)

Body.
MD

before="$(sha256sum "$tmpdir/specs/duplicate.md" | awk '{print $1}')"
bash "$CLEANUP" --dry-run "$tmpdir/specs" >"$tmpdir/dry-run.tsv"
after="$(sha256sum "$tmpdir/specs/duplicate.md" | awk '{print $1}')"
[[ "$before" == "$after" ]] || fail "dry-run modified duplicate fixture"
grep -q $'modified\twould-remove-duplicate-h1' "$tmpdir/dry-run.tsv" || fail "dry-run missing modified row"
grep -q $'modified\twould-adjust-task-title' "$tmpdir/dry-run.tsv" || fail "dry-run missing task title adjustment row"
grep -q $'skipped\tnon-duplicate' "$tmpdir/dry-run.tsv" || fail "dry-run missing non-duplicate skip"
grep -q $'skipped\tmissing-title' "$tmpdir/dry-run.tsv" || fail "dry-run missing title skip"
grep -q $'summary\tmanual-needed' "$tmpdir/dry-run.tsv" || fail "dry-run missing manual-needed summary"

bash "$CLEANUP" --apply "$tmpdir/specs" >"$tmpdir/apply.tsv"
! grep -q '^# Duplicate Title$' "$tmpdir/specs/duplicate.md" || fail "apply did not remove duplicate H1"
grep -q '^# T1: Task Title (1 pt)$' "$tmpdir/specs/tasks/T1.md" || fail "apply removed task H1"
grep -q '^title: "Work Order - T1: Task Title (1 pt)"$' "$tmpdir/specs/tasks/T1.md" || fail "apply did not adjust task title"
grep -q '^# Section Title$' "$tmpdir/specs/non-duplicate.md" || fail "apply modified non-duplicate H1"
grep -q $'modified\tremoved-duplicate-h1' "$tmpdir/apply.tsv" || fail "apply missing modified row"

if bash "$CLEANUP" --dry-run "$tmpdir/build/dist" >/tmp/starlight-title-cleanup-dist.out 2>&1; then
  fail "generated output path was accepted"
fi

echo "[selftest] PASS"
