#!/usr/bin/env bash
# Purpose: Verify the check that stands between deleting a duplicate and deleting
#          the only copy of something.
# Inputs:  Plain text fixtures under mktemp.
# Outputs: PASS when a file whose every line exists elsewhere may go, a file
#          carrying lines found nowhere else is held back and names them, blank
#          lines never count as content, near-miss lines are not treated as
#          matches, and a missing argument file fails loudly.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-knowledge-face-removal.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "check-knowledge-face-removal selftest"

# A pure copy is safe to delete: the reader loses nothing.
printf 'alpha\nbeta\n' > "$WORK/removing-subset.md"
printf 'alpha\nbeta\ngamma\n' > "$WORK/available-superset.md"
bash "$CHECK" --removing "$WORK/removing-subset.md" \
  --available "$WORK/available-superset.md" >/dev/null 2>&1 \
  || fail "a file whose every line exists elsewhere should be removable"
echo "  ok  pure copy may be removed"

# The case this check exists for: a file that looks like a duplicate but grew
# sections that exist nowhere else. Deleting it destroys them silently.
printf 'alpha\nhard-won lesson\n' > "$WORK/removing-unique.md"
out="$(bash "$CHECK" --removing "$WORK/removing-unique.md" \
  --available "$WORK/available-superset.md" 2>&1 || true)"
printf '%s' "$out" | grep -q 'hard-won lesson' \
  || fail "a held-back file must name the lines only it has"
if bash "$CHECK" --removing "$WORK/removing-unique.md" \
     --available "$WORK/available-superset.md" >/dev/null 2>&1; then
  fail "a file carrying content found nowhere else should be held back"
fi
echo "  ok  unique content held back and named"

# Blank lines are layout, not knowledge; counting them would block every removal.
printf 'alpha\n\n\nbeta\n' > "$WORK/removing-blanks.md"
bash "$CHECK" --removing "$WORK/removing-blanks.md" \
  --available "$WORK/available-superset.md" >/dev/null 2>&1 \
  || fail "blank lines must not count as content"
echo "  ok  blank lines are not content"

# Whole-line matching, not substring: a line that merely contains a match is a
# different sentence and its difference is the part worth keeping.
printf 'alpha and then some\n' > "$WORK/removing-near.md"
if bash "$CHECK" --removing "$WORK/removing-near.md" \
     --available "$WORK/available-superset.md" >/dev/null 2>&1; then
  fail "a line that only contains a match must not count as covered"
fi
echo "  ok  near-miss lines are not matches"

# A renumbered section is the same section. When the other side inserts a chapter,
# every later heading shifts by one and whole-line matching would report the whole
# table of contents as content available nowhere.
printf '## 7. 注意事項\n### 7.1 類型錯誤\n2. 範例\n' > "$WORK/removing-renumbered.md"
printf '## 9. 注意事項\n### 5.1 類型錯誤\n3. 範例\n' > "$WORK/available-renumbered.md"
bash "$CHECK" --removing "$WORK/removing-renumbered.md" \
  --available "$WORK/available-renumbered.md" >/dev/null 2>&1 \
  || fail "a heading that differs only in its ordinal must count as covered"
echo "  ok  renumbered headings count as covered"

# The relaxation is the ordinal and nothing else: different heading text is
# different knowledge, however similar the numbering.
printf '## 7. 型別安全慣例\n' > "$WORK/removing-othertext.md"
if bash "$CHECK" --removing "$WORK/removing-othertext.md" \
     --available "$WORK/available-renumbered.md" >/dev/null 2>&1; then
  fail "a heading whose text differs must still be held back"
fi
echo "  ok  ordinal relaxation does not cover different heading text"

# Stripping the ordinal must not let a heading match a plain prose line that
# happens to read the same — the haystack side has to carry an ordinal too.
printf '## 3. 注意事項\n' > "$WORK/removing-heading.md"
printf '注意事項\n' > "$WORK/available-prose.md"
if bash "$CHECK" --removing "$WORK/removing-heading.md" \
     --available "$WORK/available-prose.md" >/dev/null 2>&1; then
  fail "a stripped heading must not match an unnumbered prose line"
fi
echo "  ok  stripped needles only match ordinal-bearing lines"

# A typo in a path must not read as "nothing unique found, safe to delete".
if bash "$CHECK" --removing "$WORK/does-not-exist.md" \
     --available "$WORK/available-superset.md" >/dev/null 2>&1; then
  fail "a missing --removing file should fail, not pass vacuously"
fi
if bash "$CHECK" --removing "$WORK/removing-subset.md" \
     --available "$WORK/does-not-exist.md" >/dev/null 2>&1; then
  fail "a missing --available file should fail, not pass vacuously"
fi
echo "  ok  missing files fail loudly"

echo "PASS: check-knowledge-face-removal"
