#!/usr/bin/env bash
# scripts/polaris-changeset-selftest.sh — DP-032 Wave β D24 selftest
#
# Coverage:
#   - usage / missing args
#   - .changeset/ absent → no-op exit 0
#   - single package + default bump → frontmatter + body correct
#   - --bump minor override
#   - --bump invalid value → exit 2
#   - multi-package without declaration → fail-loud exit 1
#   - title with [TICKET] prefix → strip
#   - title with TICKET: prefix → strip
#   - title with emoji / unicode → preserve / kebab safely
#   - title overflow → truncate at word boundary
#   - same slug exists → idempotent skip
#   - ticket-prefix kebab (TASK-3788 → task-3788)
#
# Run: bash scripts/polaris-changeset-selftest.sh   (DEBUG=1 verbose)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCS="$SCRIPT_DIR/polaris-changeset.sh"
WORK_DIR="$(mktemp -d -t polaris-pcs-selftest-XXXXXX)"
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

assert_contains_file() {
  local f="$1" needle="$2" label="$3"
  if [[ -f "$f" ]] && grep -qF -- "$needle" "$f"; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — needle=%s file=%s\n" "$label" "$needle" "$f"
    [[ -f "$f" ]] && printf "    file contents:\n%s\n" "$(cat "$f")" || printf "    file missing\n"
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

# assert_contains_str: PASS when $1 contains substring $2 (DP-344 slug parity).
assert_contains_str() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — needle=%s not in: %s\n" "$label" "$needle" "$haystack"
  fi
}

cleanup() { rm -rf "$WORK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

# Helper: build a fake repo with optional .changeset/, package.json, and pnpm-workspace.yaml
make_fake_repo() {
  local parent="$1" repo_name="$2" mode="$3"  # mode: single-pkg | multi-pkg | no-changeset
  local repo_dir="$parent/$repo_name"
  mkdir -p "$repo_dir"
  if [[ "$mode" != "no-changeset" ]]; then
    mkdir -p "$repo_dir/.changeset"
    cat > "$repo_dir/.changeset/config.json" <<'EOF'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": true} }
EOF
  fi
  if [[ "$mode" == "single-pkg" ]]; then
    cat > "$repo_dir/package.json" <<'EOF'
{ "name": "@selftest/single-pkg", "version": "0.0.1" }
EOF
  elif [[ "$mode" == "multi-pkg" ]]; then
    mkdir -p "$repo_dir/apps/main" "$repo_dir/apps/admin"
    cat > "$repo_dir/pnpm-workspace.yaml" <<'EOF'
packages:
  - apps/*
EOF
    cat > "$repo_dir/apps/main/package.json" <<'EOF'
{ "name": "@selftest/main", "version": "0.0.1" }
EOF
    cat > "$repo_dir/apps/admin/package.json" <<'EOF'
{ "name": "@selftest/admin", "version": "0.0.1" }
EOF
  fi
  printf '%s\n' "$repo_dir"
}

make_task_md() {
  local repo_dir="$1" repo_name="$2" task_path="$3" ticket="$4" title="$5"
  mkdir -p "$(dirname "$task_path")"
  cat > "$task_path" <<EOF
---
status: PLANNED
---

# T1: ${title} (1 pt)

> Epic: SELFTEST-001 | JIRA: ${ticket} | Repo: ${repo_name}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | ${ticket} |
| Parent Epic | SELFTEST-001 |
| AC 驗收單 | SELFTEST-100 |
| Base branch | main |
| Task branch | task/${ticket}-test |

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`README.md\` | modify | selftest |

## 估點理由

selftest

## Test Environment

- **Level**: static
- **Dev env config**: \`workspace-config.yaml\` → \`projects[${repo_name}].dev_environment\`
- **Fixtures**: N/A

## Test Command

\`\`\`bash
echo test
\`\`\`

## Verify Command

\`\`\`bash
echo verify
\`\`\`

## Allowed Files

- \`README.md\`
EOF
}

# ────────────────────────────────────────────────────────────────────────────
echo "=== usage ==="
"$PCS" >/dev/null 2>&1; assert_eq "$?" "2" "no args → exit 2"
"$PCS" new >/dev/null 2>&1; assert_eq "$?" "2" "new without --task-md → exit 2"
"$PCS" bogus --task-md /dev/null >/dev/null 2>&1; assert_eq "$?" "2" "unknown subcommand → exit 2"
"$PCS" new --task-md /nonexistent >/dev/null 2>&1; assert_eq "$?" "1" "missing task.md → exit 1"
"$PCS" new --task-md /dev/null --bump bogus >/dev/null 2>&1; assert_eq "$?" "2" "bogus --bump → exit 2"

# ────────────────────────────────────────────────────────────────────────────
echo "=== .changeset/ absent → no-op exit 0 ==="
PARENT_NC="$WORK_DIR/no-changeset"
mkdir -p "$PARENT_NC"
REPO_NC="$(make_fake_repo "$PARENT_NC" "myrepo" "no-changeset")"
TASK_NC="$PARENT_NC/specs/SELFTEST-001/tasks/T1.md"
make_task_md "$REPO_NC" "myrepo" "$TASK_NC" "PCS-1" "[PCS-1] selftest no-changeset"
"$PCS" new --task-md "$TASK_NC" >/dev/null 2>&1
assert_eq "$?" "0" ".changeset/ missing → exit 0 (no-op)"

# ────────────────────────────────────────────────────────────────────────────
echo "=== single package + default bump (patch) ==="
PARENT_S="$WORK_DIR/single"
mkdir -p "$PARENT_S"
REPO_S="$(make_fake_repo "$PARENT_S" "myrepo" "single-pkg")"
TASK_S="$PARENT_S/specs/SELFTEST-001/tasks/T1.md"
make_task_md "$REPO_S" "myrepo" "$TASK_S" "PCS-2" "[PCS-2] add nice feature"

"$PCS" new --task-md "$TASK_S" >/dev/null 2>&1
RC=$?
assert_eq "$RC" "0" "single-pkg + default bump → exit 0"

EXPECTED_S="$REPO_S/.changeset/pcs-2-add-nice-feature.md"
assert_file_exists "$EXPECTED_S" "single-pkg changeset file with derived slug"
assert_contains_file "$EXPECTED_S" '"@selftest/single-pkg": patch' "frontmatter contains correct package + bump"
assert_contains_file "$EXPECTED_S" "add nice feature" "body contains stripped title"

# Verify [PCS-2] prefix is stripped
if grep -q "\[PCS-2\]" "$EXPECTED_S"; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL] body still contains [PCS-2] prefix\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] [TICKET] prefix stripped from body\n"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== --bump minor override ==="
TASK_MINOR="$PARENT_S/specs/SELFTEST-001/tasks/T_minor.md"
make_task_md "$REPO_S" "myrepo" "$TASK_MINOR" "PCS-3" "[PCS-3] minor bump test"

"$PCS" new --task-md "$TASK_MINOR" --bump minor >/dev/null 2>&1
assert_eq "$?" "0" "--bump minor → exit 0"

EXPECTED_MINOR="$REPO_S/.changeset/pcs-3-minor-bump-test.md"
assert_file_exists "$EXPECTED_MINOR" "minor changeset file"
assert_contains_file "$EXPECTED_MINOR" '"@selftest/single-pkg": minor' "frontmatter shows minor"

# ────────────────────────────────────────────────────────────────────────────
echo "=== --bump major override ==="
TASK_MAJOR="$PARENT_S/specs/SELFTEST-001/tasks/T_major.md"
make_task_md "$REPO_S" "myrepo" "$TASK_MAJOR" "PCS-4" "[PCS-4] breaking change"
"$PCS" new --task-md "$TASK_MAJOR" --bump major >/dev/null 2>&1
assert_eq "$?" "0" "--bump major → exit 0"
EXPECTED_MAJOR="$REPO_S/.changeset/pcs-4-breaking-change.md"
assert_contains_file "$EXPECTED_MAJOR" '"@selftest/single-pkg": major' "frontmatter shows major"

# ────────────────────────────────────────────────────────────────────────────
echo "=== TICKET: prefix strip ==="
TASK_COLON="$PARENT_S/specs/SELFTEST-001/tasks/T_colon.md"
make_task_md "$REPO_S" "myrepo" "$TASK_COLON" "PCS-5" "PCS-5: refactor utils"
"$PCS" new --task-md "$TASK_COLON" >/dev/null 2>&1
EXPECTED_COLON="$REPO_S/.changeset/pcs-5-refactor-utils.md"
assert_file_exists "$EXPECTED_COLON" "TICKET: prefix changeset file"
if grep -q "PCS-5:" "$EXPECTED_COLON"; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL] body still contains TICKET: prefix\n"
else
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] TICKET: prefix stripped from body\n"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== title with emoji / unicode preserved (no error) ==="
TASK_UNI="$PARENT_S/specs/SELFTEST-001/tasks/T_uni.md"
make_task_md "$REPO_S" "myrepo" "$TASK_UNI" "PCS-6" "[PCS-6] 產品頁 改善 with emoji"
"$PCS" new --task-md "$TASK_UNI" >/dev/null 2>&1
assert_eq "$?" "0" "unicode title → no error"
# slug should start with pcs-6-
shopt -s nullglob
matched=("$REPO_S"/.changeset/pcs-6-*.md)
shopt -u nullglob
if [[ ${#matched[@]} -ge 1 ]]; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] unicode slug file created: %s\n" "${matched[0]}"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] unicode slug file not created\n"
fi

# Body should contain the unicode characters
if [[ ${#matched[@]} -ge 1 ]]; then
  if grep -q "產品頁" "${matched[0]}" 2>/dev/null; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] body preserves unicode\n"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] body does not preserve unicode\n    file: %s\n" "$(cat "${matched[0]}" 2>/dev/null)"
  fi
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== title overflow → truncate at word boundary ==="
LONG_TITLE="this is a very long task title that should definitely exceed sixty characters in the kebab cased slug output"
TASK_LONG="$PARENT_S/specs/SELFTEST-001/tasks/T_long.md"
make_task_md "$REPO_S" "myrepo" "$TASK_LONG" "PCS-7" "[PCS-7] $LONG_TITLE"
"$PCS" new --task-md "$TASK_LONG" >/dev/null 2>&1
assert_eq "$?" "0" "long title → exit 0"
shopt -s nullglob
matched_long=("$REPO_S"/.changeset/pcs-7-*.md)
shopt -u nullglob
if [[ ${#matched_long[@]} -ge 1 ]]; then
  base="$(basename "${matched_long[0]}" .md)"
  # Filename slug should be ≤ ticket-prefix + "-" + 60 chars short kebab
  # ticket="pcs-7" + "-" = 6 chars → slug body ≤ 60 → total ≤ 66
  if [[ ${#base} -le 70 ]]; then
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] slug truncated (length=%d): %s\n" "${#base}" "$base"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] slug not truncated (length=%d): %s\n" "${#base}" "$base"
  fi
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] long-title file not created\n"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== same slug exists → idempotent skip ==="
# Re-run on the original PCS-2 task → should skip silently exit 0
"$PCS" new --task-md "$TASK_S" >/dev/null 2>&1
RC_DUP=$?
assert_eq "$RC_DUP" "0" "idempotent re-run → exit 0"
# Modify file content; re-run; content should stay (skip didn't overwrite)
echo "USER_EDITED" >> "$EXPECTED_S"
"$PCS" new --task-md "$TASK_S" >/dev/null 2>&1
if grep -q "USER_EDITED" "$EXPECTED_S"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] idempotent skip preserves user edits\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] idempotent skip overwrote user edits\n"
fi

# ────────────────────────────────────────────────────────────────────────────
echo "=== ticket prefix kebab — TASK-3788 → task-3788 ==="
TASK_KB="$PARENT_S/specs/SELFTEST-001/tasks/T_kb.md"
make_task_md "$REPO_S" "myrepo" "$TASK_KB" "TASK-3788" "[TASK-3788] product heading"
"$PCS" new --task-md "$TASK_KB" >/dev/null 2>&1
assert_eq "$?" "0" "TASK ticket → exit 0"
EXPECTED_KB="$REPO_S/.changeset/task-3788-product-heading.md"
assert_file_exists "$EXPECTED_KB" "task-3788-* slug created"

# ────────────────────────────────────────────────────────────────────────────
echo "=== multi-package without declaration → fail-loud ==="
PARENT_M="$WORK_DIR/multi"
mkdir -p "$PARENT_M"
REPO_M="$(make_fake_repo "$PARENT_M" "myrepo" "multi-pkg")"
TASK_M="$PARENT_M/specs/SELFTEST-001/tasks/T1.md"
make_task_md "$REPO_M" "myrepo" "$TASK_M" "PCS-9" "[PCS-9] multi-pkg test"

ERR_OUT="$WORK_DIR/multi.err"
"$PCS" new --task-md "$TASK_M" >/dev/null 2>"$ERR_OUT"
RC_M=$?
assert_eq "$RC_M" "1" "multi-pkg without declaration → exit 1"
if grep -q "multi-package changeset requires" "$ERR_OUT" 2>/dev/null; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] multi-pkg fail-loud message present\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] multi-pkg fail-loud message wrong\n    err: %s\n" "$(cat "$ERR_OUT")"
fi
# Should mention candidates discovered
if grep -q "@selftest/main" "$ERR_OUT" && grep -q "@selftest/admin" "$ERR_OUT"; then
  PASS=$((PASS + 1))
  [[ "$DEBUG" == "1" ]] && printf "  [ok] multi-pkg lists candidates\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] multi-pkg should list both candidate packages\n    err: %s\n" "$(cat "$ERR_OUT")"
fi

# Existing hand-authored multi-package changesets are valid for `check` when
# they cover every discovered package for the task ticket.
cat > "$REPO_M/.changeset/pcs-9-multi-pkg-test.md" <<'EOF'
---
"@selftest/main": patch
"@selftest/admin": patch
---

fix: [PCS-9] multi package coverage
EOF
"$PCS" check --task-md "$TASK_M" >/dev/null 2>&1
assert_eq "$?" "0" "multi-pkg existing coverage changeset → check exit 0"

# ────────────────────────────────────────────────────────────────────────────
echo "=== all-private explicit packages + tag:false → root package scope ==="
PARENT_PRIVATE="$WORK_DIR/all-private"
mkdir -p "$PARENT_PRIVATE"
REPO_PRIVATE="$PARENT_PRIVATE/myrepo"
mkdir -p "$REPO_PRIVATE/.changeset" "$REPO_PRIVATE/packages/a" "$REPO_PRIVATE/packages/b"
cat > "$REPO_PRIVATE/.changeset/config.json" <<'EOF'
{ "$schema": "x", "changelog": "@changesets/cli/changelog", "commit": false, "fixed": [], "linked": [], "access": "restricted", "baseBranch": "main", "updateInternalDependencies": "patch", "ignore": [], "privatePackages": {"tag": false}, "packages": ["packages/*"] }
EOF
cat > "$REPO_PRIVATE/package.json" <<'EOF'
{ "name": "polaris-framework-workspace", "version": "0.0.1", "private": true }
EOF
cat > "$REPO_PRIVATE/packages/a/package.json" <<'EOF'
{ "name": "@selftest/private-a", "version": "0.0.1", "private": true }
EOF
cat > "$REPO_PRIVATE/packages/b/package.json" <<'EOF'
{ "name": "@selftest/private-b", "version": "0.0.1", "private": true }
EOF
TASK_PRIVATE="$PARENT_PRIVATE/specs/SELFTEST-001/tasks/T_private.md"
make_task_md "$REPO_PRIVATE" "myrepo" "$TASK_PRIVATE" "PCS-10" "[PCS-10] all private package scope"
"$PCS" new --task-md "$TASK_PRIVATE" >/dev/null 2>&1
assert_eq "$?" "0" "all-private tag:false explicit packages → exit 0"
EXPECTED_PRIVATE="$REPO_PRIVATE/.changeset/pcs-10-all-private-package-scope.md"
assert_file_exists "$EXPECTED_PRIVATE" "all-private root-scope changeset file"
assert_contains_file "$EXPECTED_PRIVATE" '"polaris-framework-workspace": patch' "all-private uses root package scope"

# ────────────────────────────────────────────────────────────────────────────
# DP-344 D3 — `slug` subcommand is the single slug source that derive-task-md
# reuses. These cases assert: slug print, path print, CJK preservation, error
# handling, and parity between `slug --print path` and the filename that `new`
# actually writes (so derive's injected Allowed-Files entry == the real file).
# ────────────────────────────────────────────────────────────────────────────

# slug --print slug (default) emits the deterministic kebab slug, no dir/ext.
SLUG_OUT="$("$PCS" slug --ticket "DP-344-T1" --title "changeset allowed files derive" --print slug)"
assert_eq "$SLUG_OUT" "dp-344-t1-changeset-allowed-files-derive" "slug --print slug → kebab slug"

# slug --print path emits .changeset/{slug}.md.
PATH_OUT="$("$PCS" slug --ticket "DP-344-T1" --title "changeset allowed files derive" --print path)"
assert_eq "$PATH_OUT" ".changeset/dp-344-t1-changeset-allowed-files-derive.md" "slug --print path → .changeset path"

# Default --print is slug.
DEFAULT_OUT="$("$PCS" slug --ticket "DP-344-T1" --title "changeset allowed files derive")"
assert_eq "$DEFAULT_OUT" "dp-344-t1-changeset-allowed-files-derive" "slug default print → slug"

# DP-362: CJK in title must be DROPPED so the slug stays machine-matchable
# (validate-breakdown-ready contract). The canonical slug source keeps only ASCII
# alphanumeric; CJK / punctuation / emoji are silently dropped.
CJK_OUT="$("$PCS" slug --ticket "DP-344-T1" --title "changeset 注入 移除" --print path)"
assert_eq "$CJK_OUT" ".changeset/dp-344-t1-changeset.md" "slug all-ASCII-after-dropping-CJK"
case "$CJK_OUT" in
  *注入* | *移除*)
    FAIL=$((FAIL + 1))
    printf "  [FAIL] slug must not contain CJK — got: %s\n" "$CJK_OUT"
    ;;
  *)
    PASS=$((PASS + 1))
    [[ "$DEBUG" == "1" ]] && printf "  [ok] slug CJK dropped\n"
    ;;
esac

# Mixed CJK+ASCII title → slug is pure ASCII, keeps the ASCII tokens, no CJK,
# no double-hyphen.
MIXED_OUT="$("$PCS" slug --ticket "DP-362-T1" --title "changeset 注入 cleanup" --print slug)"
assert_eq "$MIXED_OUT" "dp-362-t1-changeset-cleanup" "slug mixed CJK+ASCII → pure ASCII tokens"

# Pure-CJK title → kebab(title) is empty, so the slug source falls back to
# {ticket}-change.
PURE_CJK_OUT="$("$PCS" slug --ticket "DP-362-T1" --title "注入移除" --print slug)"
assert_eq "$PURE_CJK_OUT" "dp-362-t1-change" "slug pure-CJK title → {ticket}-change fallback"

# Missing required flag → exit 2 (contract violation).
"$PCS" slug --ticket "DP-344-T1" >/dev/null 2>&1
assert_eq "$?" "2" "slug without --title → exit 2"

# Invalid --print value → exit 2.
"$PCS" slug --ticket "DP-344-T1" --title "x" --print bogus >/dev/null 2>&1
assert_eq "$?" "2" "slug --print bogus → exit 2"

# Parity: `slug --print path` basename == the file `new` actually writes for the
# same ticket+title. Reuse the existing fake-repo / task.md helpers so the task.md
# shape matches what parse-task-md.sh expects (repo / task_jira_key / summary).
PARITY_PARENT="$WORK_DIR/dp344-parity"
mkdir -p "$PARITY_PARENT"
PARITY_REPO="$(make_fake_repo "$PARITY_PARENT" "myrepo" "single-pkg")"
PARITY_TASK="$PARITY_PARENT/specs/SELFTEST-001/tasks/T1.md"
make_task_md "$PARITY_REPO" "myrepo" "$PARITY_TASK" "DP-344-T1" "changeset parity case"

# The slug source consumes the parsed summary; read it back the same way `new` does.
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
PARITY_SUMMARY="$("$PARSE_TASK_MD" --field summary "$PARITY_TASK" 2>/dev/null || true)"
PARITY_PATH="$("$PCS" slug --ticket "DP-344-T1" --title "$PARITY_SUMMARY" --print path)"

"$PCS" new --task-md "$PARITY_TASK" >/dev/null 2>&1 || true
PARITY_WRITTEN="$(find "$PARITY_REPO/.changeset" -maxdepth 1 -name '*.md' 2>/dev/null | head -1 || true)"
if [[ -n "$PARITY_WRITTEN" ]]; then
  assert_eq ".changeset/$(basename "$PARITY_WRITTEN")" "$PARITY_PATH" "slug --print path == filename new writes (parity)"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] DP-344 parity — new did not write a changeset file\n"
fi

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
