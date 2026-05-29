#!/usr/bin/env bash
# validate-script-header-comment-selftest.sh — D26 header gate selftest.
#
# Covers AC3 (header window = first 20 lines), AC7 (--mode diff vs --mode
# audit semantics), AC-NEG2 (generated target exclusion), and the
# adversarial pass for AC3 (comment at line 30 still fails).
#
# Cases:
#   1. compliant fixture passes --mode diff (--file)
#   2. missing-header fixture fails --mode diff with marker
#   3. comment-at-line-30 fixture fails --mode diff with marker
#   4. .py docstring header passes
#   5. .py without docstring/comment fails with marker
#   6. audit mode never exits non-zero, even with violations
#   7. generated targets (CLAUDE.md / AGENTS.md etc.) excluded by suffix
#      and explicit path glob
#   8. fixtures under scripts/fixtures/script-header-comment/** excluded
#      so the intentionally-bad missing-header-sample.sh does not block
#      audit / diff scans of the wider tree

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/validate-script-header-comment.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: validator not executable: $SCRIPT" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# ------------------------------------------------------------------
# Case 1: compliant fixture passes diff mode.
# ------------------------------------------------------------------
compliant="$ROOT/scripts/fixtures/script-header-comment/compliant-sample.sh"
if [[ ! -f "$compliant" ]]; then
  echo "FAIL: compliant fixture missing: $compliant" >&2
  exit 1
fi
# Use a tmp root that does NOT have the fixture-excluded path, so the
# fixture is treated as an in-scope script.
tmproot1="$tmpdir/case1"
mkdir -p "$tmproot1/scripts"
cp "$compliant" "$tmproot1/scripts/sample.sh"
if ! bash "$SCRIPT" --root "$tmproot1" --mode diff \
    --file "$tmproot1/scripts/sample.sh" >/dev/null; then
  echo "FAIL: case 1 — compliant fixture rejected" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 2: missing-header fixture fails diff mode with marker.
# ------------------------------------------------------------------
missing="$ROOT/scripts/fixtures/script-header-comment/missing-header-sample.sh"
if [[ ! -f "$missing" ]]; then
  echo "FAIL: missing-header fixture missing: $missing" >&2
  exit 1
fi
tmproot2="$tmpdir/case2"
mkdir -p "$tmproot2/scripts"
cp "$missing" "$tmproot2/scripts/bad.sh"
out2="$tmpdir/out2"
if bash "$SCRIPT" --root "$tmproot2" --mode diff \
    --file "$tmproot2/scripts/bad.sh" >"$out2" 2>&1; then
  echo "FAIL: case 2 — missing-header fixture incorrectly passed" >&2
  cat "$out2" >&2 || true
  exit 1
fi
if ! grep -q "POLARIS_SCRIPT_HEADER_MISSING:" "$out2"; then
  echo "FAIL: case 2 — missing marker POLARIS_SCRIPT_HEADER_MISSING:" >&2
  cat "$out2" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 3: comment-at-line-30 fixture (adversarial AC3) still fails.
# ------------------------------------------------------------------
late_comment="$tmpdir/case3/scripts/late.sh"
mkdir -p "$(dirname "$late_comment")"
{
  printf '#!/usr/bin/env bash\n'
  for i in $(seq 1 28); do
    printf '\n'
  done
  printf '# late comment that should NOT count\n'
  printf 'echo body\n'
} > "$late_comment"
out3="$tmpdir/out3"
if bash "$SCRIPT" --root "$tmpdir/case3" --mode diff \
    --file "$late_comment" >"$out3" 2>&1; then
  echo "FAIL: case 3 — comment at line 30 incorrectly passed" >&2
  cat "$out3" >&2 || true
  exit 1
fi
if ! grep -q "POLARIS_SCRIPT_HEADER_MISSING:" "$out3"; then
  echo "FAIL: case 3 — missing marker for late-comment fixture" >&2
  cat "$out3" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 4: .py docstring header passes.
# ------------------------------------------------------------------
py_ok="$tmpdir/case4/scripts/ok.py"
mkdir -p "$(dirname "$py_ok")"
cat >"$py_ok" <<'PY'
#!/usr/bin/env python3
"""ok.py — fixture: module docstring counts as a valid header."""

print("ok")
PY
if ! bash "$SCRIPT" --root "$tmpdir/case4" --mode diff \
    --file "$py_ok" >/dev/null; then
  echo "FAIL: case 4 — .py docstring rejected" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 5: .py without docstring or comment fails.
# ------------------------------------------------------------------
py_bad="$tmpdir/case5/scripts/bad.py"
mkdir -p "$(dirname "$py_bad")"
cat >"$py_bad" <<'PY'
#!/usr/bin/env python3
import sys
print(sys.argv)
PY
out5="$tmpdir/out5"
if bash "$SCRIPT" --root "$tmpdir/case5" --mode diff \
    --file "$py_bad" >"$out5" 2>&1; then
  echo "FAIL: case 5 — .py without header incorrectly passed" >&2
  cat "$out5" >&2 || true
  exit 1
fi
if ! grep -q "POLARIS_SCRIPT_HEADER_MISSING:" "$out5"; then
  echo "FAIL: case 5 — missing marker for .py no-header fixture" >&2
  cat "$out5" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 6: audit mode never exits non-zero.
# ------------------------------------------------------------------
tmproot6="$tmpdir/case6"
mkdir -p "$tmproot6/scripts"
cp "$missing" "$tmproot6/scripts/legacy-debt.sh"
cp "$compliant" "$tmproot6/scripts/compliant.sh"
out6="$tmpdir/out6"
if ! bash "$SCRIPT" --root "$tmproot6" --mode audit >"$out6" 2>&1; then
  echo "FAIL: case 6 — audit mode exited non-zero" >&2
  cat "$out6" >&2 || true
  exit 1
fi
if ! grep -q "legacy-debt: scripts/legacy-debt.sh" "$out6"; then
  echo "FAIL: case 6 — audit did not report legacy-debt entry" >&2
  cat "$out6" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 7: generated targets are excluded.
#
# CLAUDE.md / AGENTS.md are .md (out of HOT_PATH_EXTS), so they are
# never scanned. We still assert: passing them via --file does not
# emit a violation marker — the validator must filter by extension.
# ------------------------------------------------------------------
tmproot7="$tmpdir/case7"
mkdir -p "$tmproot7"
cat >"$tmproot7/CLAUDE.md" <<'MD'
# Bootstrap

(generated target — no header rule applies)
MD
cat >"$tmproot7/AGENTS.md" <<'MD'
# Agents

(generated target — no header rule applies)
MD
out7="$tmpdir/out7"
if ! bash "$SCRIPT" --root "$tmproot7" --mode diff \
    --file "$tmproot7/CLAUDE.md" \
    --file "$tmproot7/AGENTS.md" >"$out7" 2>&1; then
  echo "FAIL: case 7 — generated target raised a violation" >&2
  cat "$out7" >&2 || true
  exit 1
fi
if grep -q "POLARIS_SCRIPT_HEADER_MISSING:" "$out7"; then
  echo "FAIL: case 7 — generated target produced unexpected marker" >&2
  cat "$out7" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Case 8: fixtures under scripts/fixtures/script-header-comment/**
#   are excluded — running audit against the live repo must not block
#   on the intentionally bad missing-header-sample.sh.
# ------------------------------------------------------------------
out8="$tmpdir/out8"
if ! bash "$SCRIPT" --root "$ROOT" --mode audit >"$out8" 2>&1; then
  echo "FAIL: case 8 — audit on live repo exited non-zero" >&2
  tail -20 "$out8" >&2 || true
  exit 1
fi
if grep -q "scripts/fixtures/script-header-comment/missing-header-sample.sh" \
    "$out8"; then
  echo "FAIL: case 8 — exclusion glob did not skip the fixture" >&2
  grep "script-header-comment" "$out8" >&2 || true
  exit 1
fi

echo "PASS: validate-script-header-comment selftest"
