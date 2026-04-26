#!/usr/bin/env bash
# scripts/changeset-clean-inherited-selftest.sh — DP-032 Wave β D24 selftest
#
# Coverage:
#   - usage / missing args
#   - --repo path not directory → exit 1
#   - .changeset/ absent → no-op exit 0
#   - empty diff (no changes vs base) → "No inherited changesets found"
#   - one inherited (different ticket) → removed
#   - one current ticket changeset → preserved
#   - multiple inherited + one current → only inherited removed
#   - ticket key extraction (kb2cw-3788-* → KB2CW-3788)
#   - ticket key extraction (gt-521-* → GT-521)
#   - file without parseable ticket → preserved (conservative)
#   - --base override
#
# Run: bash scripts/changeset-clean-inherited-selftest.sh   (DEBUG=1 verbose)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCI="$SCRIPT_DIR/changeset-clean-inherited.sh"
WORK_DIR="$(mktemp -d -t polaris-cci-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — want=%s got=%s\n" "$label" "$want" "$got"
  fi
}

assert_file_exists() {
  local f="$1" label="$2"
  if [[ -f "$f" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s exists\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — file missing: %s\n" "$label" "$f"
  fi
}

assert_file_absent() {
  local f="$1" label="$2"
  if [[ ! -f "$f" ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s absent (as expected)\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — file should be removed: %s\n" "$label" "$f"
  fi
}

cleanup() { rm -rf "$WORK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# Build a fake repo with `main` branch + initial commit, then a feature branch
# with various .changeset/*.md files committed.
make_fake_repo_with_inherited() {
  local repo="$1"; shift
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t.t -c user.name=t commit --allow-empty -q -m init
  # Switch to feature branch
  git -C "$repo" checkout -q -b feat/test
  mkdir -p "$repo/.changeset"
  # Add files specified via positional args
  for fname in "$@"; do
    local fpath="$repo/.changeset/$fname"
    cat > "$fpath" <<EOF
---
"@selftest/pkg": patch
---

selftest content for $fname
EOF
  done
  git -C "$repo" add . >/dev/null
  git -C "$repo" -c user.email=t@t.t -c user.name=t commit -q -m "add changesets"
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== usage ==="
"$CCI" >/dev/null 2>&1; assert_eq "$?" "2" "no args → exit 2"
"$CCI" --repo /tmp >/dev/null 2>&1; assert_eq "$?" "2" "missing --current-ticket → exit 2"
"$CCI" --current-ticket FOO-1 >/dev/null 2>&1; assert_eq "$?" "2" "missing --repo → exit 2"
"$CCI" --repo /nonexistent/dir --current-ticket FOO-1 >/dev/null 2>&1; assert_eq "$?" "1" "nonexistent --repo → exit 1"

# ────────────────────────────────────────────────────────────────────────────
echo "=== .changeset/ absent → no-op exit 0 ==="
REPO_NC="$WORK_DIR/no-changeset"
mkdir -p "$REPO_NC"
git -C "$REPO_NC" init -q -b main
git -C "$REPO_NC" -c user.email=t@t.t -c user.name=t commit --allow-empty -q -m init
"$CCI" --repo "$REPO_NC" --current-ticket FOO-1 >/dev/null 2>&1
assert_eq "$?" "0" ".changeset/ missing → exit 0"

# ────────────────────────────────────────────────────────────────────────────
echo "=== empty diff → no inherited found ==="
REPO_E="$WORK_DIR/empty"
mkdir -p "$REPO_E/.changeset"
git -C "$REPO_E" init -q -b main
echo '{}' > "$REPO_E/.changeset/config.json"
git -C "$REPO_E" add . >/dev/null
git -C "$REPO_E" -c user.email=t@t.t -c user.name=t commit -q -m init
git -C "$REPO_E" checkout -q -b feat/test

OUT_E="$WORK_DIR/empty.out"
"$CCI" --repo "$REPO_E" --current-ticket FOO-1 --base main >"$OUT_E" 2>&1
assert_eq "$?" "0" "empty diff → exit 0"
if grep -q "No inherited changesets found" "$OUT_E"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] empty diff message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] empty diff message wrong\n    out: %s\n" "$(cat "$OUT_E")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== one inherited changeset (different ticket) → removed ==="
REPO_1="$WORK_DIR/one-inherited"
make_fake_repo_with_inherited "$REPO_1" "kb2cw-1000-old-task.md"

OUT_1="$WORK_DIR/one.out"
"$CCI" --repo "$REPO_1" --current-ticket KB2CW-2000 --base main >"$OUT_1" 2>&1
assert_eq "$?" "0" "one inherited → exit 0"
assert_file_absent "$REPO_1/.changeset/kb2cw-1000-old-task.md" "inherited file removed"
if grep -q "Cleaned 1 inherited" "$OUT_1"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] cleaned summary present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] cleaned summary wrong\n    out: %s\n" "$(cat "$OUT_1")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== one current ticket changeset → preserved ==="
REPO_C="$WORK_DIR/current-only"
make_fake_repo_with_inherited "$REPO_C" "kb2cw-3788-product-heading.md"

OUT_C="$WORK_DIR/current.out"
"$CCI" --repo "$REPO_C" --current-ticket KB2CW-3788 --base main >"$OUT_C" 2>&1
assert_eq "$?" "0" "current ticket only → exit 0"
assert_file_exists "$REPO_C/.changeset/kb2cw-3788-product-heading.md" "current ticket file preserved"
if grep -q "No inherited changesets found" "$OUT_C"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] no-inherited message when current matches\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] expected 'No inherited' message\n    out: %s\n" "$(cat "$OUT_C")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== multiple inherited + one current → only inherited removed ==="
REPO_MIX="$WORK_DIR/mix"
make_fake_repo_with_inherited "$REPO_MIX" \
  "kb2cw-1000-old-a.md" \
  "kb2cw-2000-old-b.md" \
  "gt-500-old-c.md" \
  "kb2cw-3788-current.md"

OUT_MIX="$WORK_DIR/mix.out"
"$CCI" --repo "$REPO_MIX" --current-ticket KB2CW-3788 --base main >"$OUT_MIX" 2>&1
assert_eq "$?" "0" "mixed → exit 0"
assert_file_exists "$REPO_MIX/.changeset/kb2cw-3788-current.md" "current preserved"
assert_file_absent "$REPO_MIX/.changeset/kb2cw-1000-old-a.md" "inherited a removed"
assert_file_absent "$REPO_MIX/.changeset/kb2cw-2000-old-b.md" "inherited b removed"
assert_file_absent "$REPO_MIX/.changeset/gt-500-old-c.md" "inherited gt-500-c removed"
if grep -q "Cleaned 3 inherited" "$OUT_MIX"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] cleaned 3 summary present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] expected 'Cleaned 3'\n    out: %s\n" "$(cat "$OUT_MIX")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== file without parseable ticket → preserved ==="
REPO_NP="$WORK_DIR/non-parseable"
make_fake_repo_with_inherited "$REPO_NP" "chore-bump-deps.md" "fix-typo.md" "kb2cw-1000-inherited.md"

OUT_NP="$WORK_DIR/np.out"
"$CCI" --repo "$REPO_NP" --current-ticket KB2CW-3788 --base main >"$OUT_NP" 2>&1
assert_eq "$?" "0" "non-parseable mix → exit 0"
assert_file_exists "$REPO_NP/.changeset/chore-bump-deps.md" "non-parseable chore preserved"
assert_file_exists "$REPO_NP/.changeset/fix-typo.md" "non-parseable fix preserved"
assert_file_absent "$REPO_NP/.changeset/kb2cw-1000-inherited.md" "parseable inherited removed"
if grep -q "Cleaned 1 inherited" "$OUT_NP"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] cleaned 1 with non-parseable preserved\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] expected 'Cleaned 1' (non-parseable preserved)\n    out: %s\n" "$(cat "$OUT_NP")"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== ticket key extraction: GT-521 ==="
REPO_GT="$WORK_DIR/gt"
make_fake_repo_with_inherited "$REPO_GT" "gt-521-breadcrumblist-seo.md" "kb2cw-3788-current.md"

"$CCI" --repo "$REPO_GT" --current-ticket KB2CW-3788 --base main >/dev/null 2>&1
assert_file_absent "$REPO_GT/.changeset/gt-521-breadcrumblist-seo.md" "GT-521 inherited removed"
assert_file_exists "$REPO_GT/.changeset/kb2cw-3788-current.md" "KB2CW-3788 preserved"

# Reverse: when current = GT-521, kb2cw-3788 should be removed
REPO_GT2="$WORK_DIR/gt2"
make_fake_repo_with_inherited "$REPO_GT2" "gt-521-current.md" "kb2cw-3788-inherited.md"

"$CCI" --repo "$REPO_GT2" --current-ticket GT-521 --base main >/dev/null 2>&1
assert_file_exists "$REPO_GT2/.changeset/gt-521-current.md" "GT-521 preserved"
assert_file_absent "$REPO_GT2/.changeset/kb2cw-3788-inherited.md" "KB2CW-3788 inherited removed"

# ────────────────────────────────────────────────────────────────────────────
echo "=== --base inferred from git config ==="
REPO_DEF="$WORK_DIR/inferred-base"
make_fake_repo_with_inherited "$REPO_DEF" "kb2cw-9000-old.md"
git -C "$REPO_DEF" config init.defaultBranch main

"$CCI" --repo "$REPO_DEF" --current-ticket KB2CW-3788 >/dev/null 2>&1
RC_DEF=$?
assert_eq "$RC_DEF" "0" "--base inferred → exit 0"
assert_file_absent "$REPO_DEF/.changeset/kb2cw-9000-old.md" "inferred-base inherited removed"

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "PASS=$PASS  FAIL=$FAIL  TOTAL=$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
