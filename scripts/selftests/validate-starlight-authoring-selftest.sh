#!/usr/bin/env bash
# Selftest for scripts/validate-starlight-authoring.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-starlight-authoring.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >/tmp/starlight-authoring-selftest.out 2>/tmp/starlight-authoring-selftest.err; then
    fail "$label unexpectedly passed"
  fi
}

tmpdir="$(mktemp -d -t starlight-authoring.XXXXXX)"
trap 'rm -rf "$tmpdir" /tmp/starlight-authoring-selftest.out /tmp/starlight-authoring-selftest.err' EXIT

# Rendered Starlight pages live under a docs-manager content collection root.
# Anchor the fixtures there so the directory-walk exclusions are genuinely
# exercised (a tmpdir outside the collection root renders nothing).
SPECS="$tmpdir/docs-manager/src/content/docs/specs"
mkdir -p "$SPECS/nested" "$tmpdir/docs-manager/dist"

cat >"$SPECS/valid.md" <<'MD'
---
title: "Valid Page"
description: "A valid Starlight docs page."
---

## Summary

```bash
echo ok
```
MD

cat >"$SPECS/nested/also-valid.md" <<'MD'
---
title: "Also Valid"
description: "Another valid Starlight docs page."
---

# Different H1
MD

cat >"$SPECS/invalid.md" <<'MD'
---
title: "Invalid Page"
---

# Invalid Page

```
echo missing language
```
MD

cat >"$SPECS/legacy-link.md" <<'MD'
---
title: "Legacy Link"
description: "Contains an old source link."
---

See [old source](docs-viewer/src/content/docs/specs/old/path.md).
MD

cat >"$tmpdir/docs-manager/dist/generated.md" <<'MD'
---
title: "Generated"
description: "Generated output."
---
MD

bash "$VALIDATOR" check "$SPECS/valid.md" >/tmp/starlight-authoring-selftest.out
grep -q "PASS: Starlight authoring check" /tmp/starlight-authoring-selftest.out || fail "valid file did not pass"

bash "$VALIDATOR" check "$SPECS/nested" >/tmp/starlight-authoring-selftest.out
grep -q "PASS: Starlight authoring check" /tmp/starlight-authoring-selftest.out || fail "container check did not pass"

expect_fail "invalid file" bash "$VALIDATOR" check "$SPECS/invalid.md"
grep -q "missing-description" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing description finding"
grep -q "duplicate H1" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing duplicate finding"
grep -q "code-fence-language" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing code fence finding"

bash "$VALIDATOR" legacy-report "$SPECS" >"$tmpdir/legacy.tsv"
grep -q "deterministic" "$tmpdir/legacy.tsv" || fail "legacy report missing deterministic row"
grep -q "manual-needed" "$tmpdir/legacy.tsv" || fail "legacy report missing manual-needed row"
grep -q "duplicate" "$tmpdir/legacy.tsv" || fail "legacy report missing duplicate summary"

expect_fail "generated output path" bash "$VALIDATOR" check "$tmpdir/docs-manager/dist"

# --- Dir-walk exclusion alignment with content.config.ts (DP-289-T4) ---
# The docs collection GLOB-excludes these path globs from rendering, so a
# directory walk must skip them (they never become Starlight pages):
#   **/{escalations,jira-comments,refinement-inbox,tests}/**
#   **/artifacts/external-writes/**
#   **/artifacts/research/**
#   files whose basename starts with "_"
# Explicit file arguments must STILL be validated even under an excluded dir.

mkdir -p \
  "$SPECS/excl/refinement-inbox" \
  "$SPECS/excl/escalations" \
  "$SPECS/excl/jira-comments" \
  "$SPECS/excl/tests" \
  "$SPECS/excl/artifacts/external-writes" \
  "$SPECS/excl/artifacts/research" \
  "$SPECS/excl/artifacts/auto-pass" \
  "$SPECS/excl/a/_b"

# A valid rendered page so the dir is non-empty for the walk.
cat >"$SPECS/excl/rendered.md" <<'MD'
---
title: "Rendered Page"
description: "A rendered Starlight page in the excl tree."
---

# Different H1
MD

# Pipeline-artifact .md files that the OLD validator would flag (no
# frontmatter) but the fixed validator must SKIP during a directory walk.
for d in refinement-inbox escalations jira-comments tests; do
  cat >"$SPECS/excl/$d/note.md" <<'MD'
no frontmatter pipeline note
MD
done
cat >"$SPECS/excl/artifacts/external-writes/note.md" <<'MD'
no frontmatter external-write note
MD
cat >"$SPECS/excl/artifacts/research/note.md" <<'MD'
no frontmatter research note
MD
# Underscore-prefixed file (excluded from rendering by the [^_] glob).
cat >"$SPECS/excl/_partial.md" <<'MD'
no frontmatter underscore partial
MD

# An artifacts/auto-pass file IS rendered (only external-writes/research are
# excluded under artifacts/), so it must still be validated. Keep it valid.
cat >"$SPECS/excl/artifacts/auto-pass/report.md" <<'MD'
---
title: "Auto Pass Report"
description: "A rendered auto-pass artifact page."
---

# Auto Pass Detail
MD

# Underscore as an intermediate directory does NOT exclude the file (the
# [^_] glob only constrains the filename). This file IS rendered, keep valid.
cat >"$SPECS/excl/a/_b/inside.md" <<'MD'
---
title: "Inside Underscore Dir"
description: "A rendered page under an underscore directory."
---

# Inside Detail
MD

# Dir-walk over the excl tree must PASS: every excluded pipeline-artifact .md
# is skipped, and the genuinely-rendered pages are valid.
bash "$VALIDATOR" check "$SPECS/excl" >/tmp/starlight-authoring-selftest.out 2>/tmp/starlight-authoring-selftest.err \
  || { cat /tmp/starlight-authoring-selftest.err >&2; fail "dir-walk over excluded subtree did not pass"; }
grep -q "PASS: Starlight authoring check" /tmp/starlight-authoring-selftest.out || fail "dir-walk excl did not report PASS"

# Explicit file argument under an excluded dir must STILL be validated.
expect_fail "explicit excluded-dir file" bash "$VALIDATOR" check "$SPECS/excl/refinement-inbox/note.md"
grep -q "missing-frontmatter" /tmp/starlight-authoring-selftest.err || fail "explicit excluded-dir file was not validated"

# --- Non-rendered tree alignment (DP-289-T4) ---
# Files outside any docs-manager/src/content/docs/ collection root are never
# rendered as Starlight pages (e.g. .claude/skills/references, .claude/rules/
# handbook). A directory walk there must skip them so the check only covers
# genuinely-rendered pages. Explicit file arguments are still validated.

mkdir -p "$tmpdir/non-rendered/references"
cat >"$tmpdir/non-rendered/references/agent-ref.md" <<'MD'
# Agent Reference

An agent-loaded reference doc with no Starlight frontmatter.
MD

# Dir-walk over a non-content-root tree skips the frontmatter-less reference and
# reports no markdown files (exit 2 from "no markdown files found"), proving the
# tree is treated as containing zero rendered pages rather than failing on it.
if bash "$VALIDATOR" check "$tmpdir/non-rendered" >/tmp/starlight-authoring-selftest.out 2>/tmp/starlight-authoring-selftest.err; then
  fail "non-rendered dir-walk unexpectedly returned a pass with files"
fi
grep -q "no markdown files found" /tmp/starlight-authoring-selftest.err \
  || { cat /tmp/starlight-authoring-selftest.err >&2; fail "non-rendered dir-walk should skip all files (no markdown found)"; }
grep -q "missing-frontmatter" /tmp/starlight-authoring-selftest.err \
  && fail "non-rendered dir-walk must not flag frontmatter on non-page reference"

# Explicit non-content-root file argument is STILL validated (not skipped).
expect_fail "explicit non-rendered file" bash "$VALIDATOR" check "$tmpdir/non-rendered/references/agent-ref.md"
grep -q "missing-frontmatter" /tmp/starlight-authoring-selftest.err || fail "explicit non-rendered file was not validated"

echo "[selftest] PASS"
