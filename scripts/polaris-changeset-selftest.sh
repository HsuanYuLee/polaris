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
#   - ticket-prefix kebab (KB2CW-3788 → kb2cw-3788)
#
# Run: bash scripts/polaris-changeset-selftest.sh   (DEBUG=1 verbose)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
echo "=== ticket prefix kebab — KB2CW-3788 → kb2cw-3788 ==="
TASK_KB="$PARENT_S/specs/SELFTEST-001/tasks/T_kb.md"
make_task_md "$REPO_S" "myrepo" "$TASK_KB" "KB2CW-3788" "[KB2CW-3788] product heading"
"$PCS" new --task-md "$TASK_KB" >/dev/null 2>&1
assert_eq "$?" "0" "KB2CW ticket → exit 0"
EXPECTED_KB="$REPO_S/.changeset/kb2cw-3788-product-heading.md"
assert_file_exists "$EXPECTED_KB" "kb2cw-3788-* slug created"

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
echo ""
echo "=== Summary ==="
TOTAL=$((PASS + FAIL))
echo "PASS=$PASS  FAIL=$FAIL  TOTAL=$TOTAL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
echo "All assertions passed."
exit 0
