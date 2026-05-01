#!/usr/bin/env bash
# Selftest for scripts/validate-starlight-authoring.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

mkdir -p "$tmpdir/specs/nested" "$tmpdir/docs-manager/dist"

cat >"$tmpdir/specs/valid.md" <<'MD'
---
title: "Valid Page"
description: "A valid Starlight docs page."
---

## Summary

```bash
echo ok
```
MD

cat >"$tmpdir/specs/nested/also-valid.md" <<'MD'
---
title: "Also Valid"
description: "Another valid Starlight docs page."
---

# Different H1
MD

cat >"$tmpdir/specs/invalid.md" <<'MD'
---
title: "Invalid Page"
---

# Invalid Page

```
echo missing language
```
MD

cat >"$tmpdir/specs/legacy-link.md" <<'MD'
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

bash "$VALIDATOR" check "$tmpdir/specs/valid.md" >/tmp/starlight-authoring-selftest.out
grep -q "PASS: Starlight authoring check" /tmp/starlight-authoring-selftest.out || fail "valid file did not pass"

bash "$VALIDATOR" check "$tmpdir/specs/nested" >/tmp/starlight-authoring-selftest.out
grep -q "PASS: Starlight authoring check" /tmp/starlight-authoring-selftest.out || fail "container check did not pass"

expect_fail "invalid file" bash "$VALIDATOR" check "$tmpdir/specs/invalid.md"
grep -q "missing-description" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing description finding"
grep -q "duplicate H1" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing duplicate finding"
grep -q "code-fence-language" /tmp/starlight-authoring-selftest.err || fail "invalid stderr missing code fence finding"

bash "$VALIDATOR" legacy-report "$tmpdir/specs" >"$tmpdir/legacy.tsv"
grep -q "deterministic" "$tmpdir/legacy.tsv" || fail "legacy report missing deterministic row"
grep -q "manual-needed" "$tmpdir/legacy.tsv" || fail "legacy report missing manual-needed row"
grep -q "duplicate" "$tmpdir/legacy.tsv" || fail "legacy report missing duplicate summary"

expect_fail "generated output path" bash "$VALIDATOR" check "$tmpdir/docs-manager/dist"

echo "[selftest] PASS"
