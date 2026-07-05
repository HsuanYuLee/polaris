#!/usr/bin/env bash
# Purpose: DP-231 T9 regression for codex-guarded-gh-pr-create no-bypass.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$ROOT/scripts/codex-guarded-gh-pr-create.sh"
TMP="$(mktemp -d -t codex-guarded-gh-pr-create.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

if "$WRAPPER" --dry-run --skip-gates --base main >/dev/null 2>"$TMP/skip.err"; then
  echo "FAIL: --skip-gates unexpectedly passed" >&2
  exit 1
fi
grep -Fq "POLARIS_ENGINEERING_NO_BYPASS" "$TMP/skip.err" || {
  echo "FAIL: missing no-bypass marker for --skip-gates" >&2
  cat "$TMP/skip.err" >&2
  exit 1
}

if grep -q -- "--skip-gates" "$WRAPPER"; then
  # The only allowed occurrence is the explicit block case / diagnostic.
  if ! grep -Fq "is not allowed for Codex PR creation" "$WRAPPER"; then
    echo "FAIL: wrapper still appears to support --skip-gates" >&2
    exit 1
  fi
fi

grep -Fq "polaris-pr-create.sh" "$WRAPPER" || {
  echo "FAIL: wrapper must still delegate to polaris-pr-create.sh" >&2
  exit 1
}

echo "PASS: codex guarded gh pr create selftest"
