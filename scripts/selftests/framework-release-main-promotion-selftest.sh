#!/usr/bin/env bash
# Purpose: Hermetic selftest for PR-gated fast-forward framework main promotion.
# Inputs:  none.
# Outputs: TAP-like ok/not ok lines.
# Exit:    0 PASS, 1 FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$ROOT_DIR/scripts/framework-release-main-promotion.sh"

TMPROOT="$(mktemp -d -t framework-release-main-promotion.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

ok() {
  printf 'ok %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf 'not ok %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    ok "$label"
  else
    fail "$label"
    printf 'expected: %s\nactual: %s\n' "$expected" "$actual" >&2
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if grep -Fq -- "$needle" <<<"$haystack"; then
    ok "$label"
  else
    fail "$label"
    printf 'missing substring: %s\nactual:\n%s\n' "$needle" "$haystack" >&2
  fi
}

assert_not_grep_file() {
  local label="$1" pattern="$2" file="$3"
  if grep -Eq -- "$pattern" "$file"; then
    fail "$label"
    printf 'forbidden pattern found: %s\n' "$pattern" >&2
  else
    ok "$label"
  fi
}

make_repo() {
  local name="$1"
  local remote="$TMPROOT/${name}-remote.git"
  local repo="$TMPROOT/${name}-repo"
  git init --bare "$remote" >/dev/null
  git clone "$remote" "$repo" >/dev/null 2>&1
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.invalid"
  git -C "$repo" checkout -b main >/dev/null 2>&1
  printf 'base\n' >"$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "base"
  git -C "$repo" push -u origin main >/dev/null 2>&1
  printf '%s\n' "$repo"
}

write_mock_gh() {
  local dir="$1" state="$2" base="$3" head_branch="$4" head_oid="$5" merge_state="$6" is_draft="$7"
  mkdir -p "$dir"
  cat >"$dir/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
  cat <<'JSON'
{"number":999,"state":"$state","mergeStateStatus":"$merge_state","headRefName":"$head_branch","headRefOid":"$head_oid","baseRefName":"$base","url":"https://example.invalid/pull/999","isDraft":$is_draft}
JSON
  exit 0
fi
echo "unexpected gh invocation: \$*" >&2
exit 9
EOF
  chmod +x "$dir/gh"
}

# Case 1: an open feat/DP release PR fast-forwards origin/main without a merge commit.
repo="$(make_repo c1)"
old_main="$(git -C "$repo" rev-parse origin/main)"
git -C "$repo" checkout -q -b feat/DP-999
printf 'release\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "fix(framework): release payload"
printf 'version\n' >"$repo/VERSION"
git -C "$repo" add VERSION
git -C "$repo" commit -q -m "chore(release): v9.99.99"
git -C "$repo" push -u origin feat/DP-999 >/dev/null 2>&1
release_head="$(git -C "$repo" rev-parse origin/feat/DP-999)"
mockbin="$TMPROOT/c1-bin"
write_mock_gh "$mockbin" "OPEN" "main" "feat/DP-999" "$release_head" "CLEAN" "false"

set +e
out="$(GH_BIN="$mockbin/gh" bash "$HELPER" --repo "$repo" --pr 999 --head feat/DP-999 --execute 2>&1)"
rc=$?
set -e
assert_eq "C1 promotion succeeds" "0" "$rc"
assert_contains "C1 reports fast-forward" "$out" "fast-forwarded"
new_main="$(git -C "$repo" rev-parse origin/main)"
assert_eq "C1 origin/main equals release head" "$release_head" "$new_main"
merge_count="$(git -C "$repo" log --merges --format='%H' "${old_main}..origin/main" | wc -l | tr -d ' ')"
assert_eq "C1 no merge commit introduced" "0" "$merge_count"

# Case 2: promotion fails when origin/main advanced after the feat branch split.
repo="$(make_repo c2)"
git -C "$repo" checkout -q -b feat/DP-999
printf 'release\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "fix(framework): release payload"
git -C "$repo" push -u origin feat/DP-999 >/dev/null 2>&1
release_head="$(git -C "$repo" rev-parse origin/feat/DP-999)"
git -C "$repo" checkout -q main
printf 'main advanced\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "docs(framework): advance main"
git -C "$repo" push origin main >/dev/null 2>&1
advanced_main="$(git -C "$repo" rev-parse origin/main)"
mockbin="$TMPROOT/c2-bin"
write_mock_gh "$mockbin" "OPEN" "main" "feat/DP-999" "$release_head" "CLEAN" "false"

set +e
out="$(GH_BIN="$mockbin/gh" bash "$HELPER" --repo "$repo" --pr 999 --head feat/DP-999 --execute 2>&1)"
rc=$?
set -e
assert_eq "C2 non-ancestor blocks" "2" "$rc"
assert_contains "C2 asks for rebase" "$out" "Rebase feat/DP-999 onto origin/main"
assert_eq "C2 origin/main unchanged" "$advanced_main" "$(git -C "$repo" rev-parse origin/main)"

# Case 3: promotion fails when the PR metadata does not match the release head.
repo="$(make_repo c3)"
git -C "$repo" checkout -q -b feat/DP-999
printf 'release\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "fix(framework): release payload"
git -C "$repo" push -u origin feat/DP-999 >/dev/null 2>&1
release_head="$(git -C "$repo" rev-parse origin/feat/DP-999)"
old_main="$(git -C "$repo" rev-parse origin/main)"
mockbin="$TMPROOT/c3-bin"
write_mock_gh "$mockbin" "OPEN" "main" "feat/DP-999" "$old_main" "CLEAN" "false"

set +e
out="$(GH_BIN="$mockbin/gh" bash "$HELPER" --repo "$repo" --pr 999 --head feat/DP-999 --execute 2>&1)"
rc=$?
set -e
assert_eq "C3 mismatched PR head blocks" "2" "$rc"
assert_contains "C3 identifies head oid mismatch" "$out" "head oid"
assert_eq "C3 origin/main unchanged" "$old_main" "$(git -C "$repo" rev-parse origin/main)"

# Case 4: promotion fails when the release head range contains a merge commit.
repo="$(make_repo c4)"
git -C "$repo" checkout -q -b feat/DP-999
printf 'release\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "fix(framework): release payload"
git -C "$repo" checkout -q -b task/DP-999-T1
printf 'task\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m "fix(framework): task payload"
git -C "$repo" checkout -q feat/DP-999
git -C "$repo" merge --no-ff -m "Merge pull request #1 from task/DP-999-T1" task/DP-999-T1 >/dev/null 2>&1
git -C "$repo" push -u origin feat/DP-999 >/dev/null 2>&1
release_head="$(git -C "$repo" rev-parse origin/feat/DP-999)"
old_main="$(git -C "$repo" rev-parse origin/main)"
mockbin="$TMPROOT/c4-bin"
write_mock_gh "$mockbin" "OPEN" "main" "feat/DP-999" "$release_head" "CLEAN" "false"

set +e
out="$(GH_BIN="$mockbin/gh" bash "$HELPER" --repo "$repo" --pr 999 --head feat/DP-999 --execute 2>&1)"
rc=$?
set -e
assert_eq "C4 merge commit blocks" "2" "$rc"
assert_contains "C4 identifies final merge bubble" "$out" "final merge bubble"
assert_eq "C4 origin/main unchanged" "$old_main" "$(git -C "$repo" rev-parse origin/main)"

# Static contract: the helper must not call GitHub merge modes or force-push.
assert_not_grep_file "helper avoids gh merge modes" 'gh pr merge|[[:space:]]--merge([[:space:]]|$)|[[:space:]]--squash([[:space:]]|$)|[[:space:]]--rebase([[:space:]]|$)' "$HELPER"
assert_not_grep_file "helper avoids force push flags" '--force|force-with-lease' "$HELPER"

if [[ "$FAIL" -gt 0 ]]; then
  printf '%d failed, %d passed\n' "$FAIL" "$PASS" >&2
  exit 1
fi

printf 'framework-release-main-promotion selftest: PASS (%d assertions)\n' "$PASS"
