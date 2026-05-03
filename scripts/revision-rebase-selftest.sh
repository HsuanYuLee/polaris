#!/usr/bin/env bash
# scripts/revision-rebase-selftest.sh — backlog #3 selftest harness for revision-rebase.sh
#
# Coverage:
#   1.  --help / usage → exit 2
#   2.  task.md path + clean (rebase not needed) → exit 0 + rebase_status: not_needed
#   3.  task.md path + base ahead, no conflict → exit 0 + rebase_status: clean
#   4.  task.md path + conflict → exit 1 + rebase_status: conflict + rebase-in-progress state
#   5.  task.md path + PR base aligned → pr_base_synced: false + already_aligned: true
#   6.  task.md path + PR base drift → gh pr edit invoked + pr_base_synced: true
#   7.  PR base drift from downstream old base → rebase --onto strips old base commits
#   8.  No task.md → exit 1, no PR base fallback
#   9.  --repo external path resolves correctly
#   10. --pr explicit override
#   11. --task-md explicit override
#   12. fetch failure (broken origin) → exit 1
#   13. resolve-task-base.sh missing → exit 1
#   14. JSON schema completeness (all keys present)
#   15. After conflict + --abort, re-run clean → exit 0
#
# Exit 0 when all assertions PASS. Honors DEBUG=1 for verbose output.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RR="$SCRIPT_DIR/revision-rebase.sh"
WORK_DIR="$(mktemp -d -t polaris-rr-selftest-XXXXXX)"
: "${DEBUG:=0}"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" label="$3"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    [ "$DEBUG" = "1" ] && printf "  [ok] %s (got=%s)\n" "$label" "$got"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — want=%q got=%q\n" "$label" "$want" "$got"
  fi
}

assert_contains() {
  local hay="$1" needle="$2" label="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    [ "$DEBUG" = "1" ] && printf "  [ok] %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s — needle=%q\n" "$label" "$needle"
    printf "    hay (head): %s\n" "$(printf '%s' "$hay" | head -c 400)"
  fi
}

assert_json_eq() {
  local json="$1" key="$2" want="$3" label="$4"
  local got
  got=$(printf '%s' "$json" | python3 -c "import json,sys
d=json.loads(sys.stdin.read() or '{}')
v=d.get('$key')
if v is None: print('null')
elif isinstance(v, bool): print('true' if v else 'false')
else: print(v)" 2>/dev/null)
  assert_eq "$got" "$want" "$label (key=$key)"
}

cleanup() {
  # Best-effort kill any rebase-in-progress
  for repo in "$WORK_DIR"/*/repo; do
    [ -d "$repo/.git" ] && git -C "$repo" rebase --abort >/dev/null 2>&1 || true
  done
  rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────────────────
# Common: build a fake repo with develop + feat/<name> + task/<name> branches
# ────────────────────────────────────────────────────────────────────────────
mk_repo() {
  local repo="$1"
  local feat_branch="${2:-feat/demo}"
  local task_branch="${3:-task/DEMO-1-work}"

  mkdir -p "$repo"
  git -C "$repo" init -q -b develop
  git -C "$repo" config user.email "selftest@example.com"
  git -C "$repo" config user.name  "selftest"
  printf 'init\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m "init"

  # Set up "origin" as a clone.
  local origin="${repo}.origin.git"
  git -C "$repo" remote add origin "$origin"
  git init -q --bare "$origin"
  git -C "$repo" push -q origin develop

  git -C "$repo" checkout -q -b "$feat_branch"
  printf 'feat\n' >> "$repo/file.txt"
  git -C "$repo" commit -q -am "feat"
  git -C "$repo" push -q origin "$feat_branch"

  git -C "$repo" checkout -q -b "$task_branch"
  printf 'task\n' >> "$repo/file.txt"
  git -C "$repo" commit -q -am "task"
  git -C "$repo" push -q origin "$task_branch"
}

# task.md template under repo's parent (mirroring specs/{EPIC}/tasks/T1.md layout)
mk_task_md() {
  local base_dir="$1"     # parent of repo dir
  local repo_name="$2"
  local epic="$3"
  local jira="$4"
  local base_branch="$5"
  local task_branch="$6"

  local f="$base_dir/specs/$epic/tasks/T1.md"
  mkdir -p "$(dirname "$f")"
  cat > "$f" <<EOF
---
status: PLANNED
---

# T1: selftest task (1 pt)

> Epic: $epic | JIRA: $jira | Repo: $repo_name

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | $jira |
| Parent Epic | $epic |
| Base branch | $base_branch |
| Task branch | $task_branch |

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`file.txt\` | modify | selftest |
EOF
  printf '%s' "$f"
}

# Build a fake gh CLI on PATH that:
#   - "gh pr view --json baseRefName,number" returns FAKE_GH_PR_VIEW
#   - "gh pr edit N --base X" appends to FAKE_GH_LOG
#   - "gh -R /local/path ..." fails, matching real gh behavior
#   - any other invocation: exit 1
mk_fake_gh() {
  local bindir="$1"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'EOF'
#!/usr/bin/env bash
# fake gh CLI for revision-rebase selftest
LOG="${FAKE_GH_LOG:-/tmp/fake-gh.log}"
{
  printf 'INVOKED: '
  for a in "$@"; do printf '%q ' "$a"; done
  printf '\n'
} >> "$LOG"

# Strip leading "-R OWNER/REPO" if present. Real gh rejects filesystem paths
# here; keep that behavior in the fake so local-path regressions are caught.
if [ "${1:-}" = "-R" ]; then
  case "${2:-}" in
    /*|.*/*)
      printf 'expected the "[HOST/]OWNER/REPO" format, got "%s"\n' "$2" >&2
      exit 1
      ;;
  esac
  shift 2 || true
fi

case "${1:-}/${2:-}" in
  pr/view)
    if [ -n "${FAKE_GH_PR_VIEW:-}" ] && [ -f "$FAKE_GH_PR_VIEW" ]; then
      cat "$FAKE_GH_PR_VIEW"
    else
      # Empty or missing -> simulate "no PR for branch"
      exit 1
    fi
    ;;
  pr/edit)
    # Always succeed unless FAKE_GH_PR_EDIT_FAIL set
    if [ "${FAKE_GH_PR_EDIT_FAIL:-0}" = "1" ]; then
      printf 'fake gh pr edit fail\n' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    printf 'fake gh: unsupported invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$bindir/gh"
}

# Set FAKE_GH_PR_VIEW to a JSON file describing a fake PR.
write_fake_pr_view() {
  local out="$1" number="$2" base="$3"
  cat > "$out" <<EOF
{"number":$number,"baseRefName":"$base"}
EOF
}

# ────────────────────────────────────────────────────────────────────────────
# Case 1: --help → exit 2
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 1: --help ---\n'
out=$(bash "$RR" --help 2>&1)
rc=$?
assert_eq "$rc" "2" "case1.exit"
assert_contains "$out" "usage:" "case1.usage"

# ────────────────────────────────────────────────────────────────────────────
# Case 2: clean rebase not needed (target ancestor of HEAD)
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 2: rebase not_needed ---\n'
C2="$WORK_DIR/case2"
mkdir -p "$C2"
mk_repo "$C2/repo" "feat/demo" "task/DEMO-1"
TASK_MD2=$(mk_task_md "$C2" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")

# Setup fake gh: PR exists, base aligned with feat/demo
mk_fake_gh "$C2/bin"
FAKE_PR_VIEW="$C2/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 100 "feat/demo"
FAKE_GH_LOG="$C2/gh.log"
: > "$FAKE_GH_LOG"

# task branch was just created from feat/demo with one extra commit, so
# `git merge-base origin/feat/demo HEAD` == origin/feat/demo (which equals local feat/demo).
# Push the same task to origin too — rebase target = origin/feat/demo, ancestor of HEAD.
out=$(PATH="$C2/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C2/repo" --task-md "$TASK_MD2" 2>/tmp/rr-c2-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c2-stderr; }
assert_eq "$rc" "0" "case2.exit"
assert_json_eq "$out" "rebase_status" "not_needed" "case2"
assert_json_eq "$out" "resolved_base" "feat/demo" "case2"
assert_json_eq "$out" "legacy_fallback" "false" "case2"

# ────────────────────────────────────────────────────────────────────────────
# Case 3: base ahead, no conflict → clean rebase
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 3: clean rebase (base advanced) ---\n'
C3="$WORK_DIR/case3"
mkdir -p "$C3"
mk_repo "$C3/repo" "feat/demo" "task/DEMO-1"
TASK_MD3=$(mk_task_md "$C3" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")

# Advance feat/demo on origin (simulate a teammate pushing)
ORIGIN3="$C3/repo.origin.git"
TMPCLONE="$C3/tmp-clone"
git clone -q "$ORIGIN3" "$TMPCLONE"
git -C "$TMPCLONE" config user.email "x@y" && git -C "$TMPCLONE" config user.name "x"
git -C "$TMPCLONE" checkout -q feat/demo
printf 'new-from-feat\n' > "$TMPCLONE/feat-new.txt"
git -C "$TMPCLONE" add feat-new.txt
git -C "$TMPCLONE" commit -q -m "advance feat"
git -C "$TMPCLONE" push -q origin feat/demo

mk_fake_gh "$C3/bin"
FAKE_PR_VIEW="$C3/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 101 "feat/demo"
FAKE_GH_LOG="$C3/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C3/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C3/repo" --task-md "$TASK_MD3" 2>/tmp/rr-c3-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c3-stderr; }
assert_eq "$rc" "0" "case3.exit"
assert_json_eq "$out" "rebase_status" "clean" "case3"

# Sanity: task branch should now contain feat-new.txt
if [ -f "$C3/repo/feat-new.txt" ]; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case3.feat-new.txt present after rebase\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case3.feat-new.txt missing after rebase\n"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 4: conflict → exit 1, rebase_status: conflict, repo in rebase-in-progress
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 4: rebase conflict ---\n'
C4="$WORK_DIR/case4"
mkdir -p "$C4"
mk_repo "$C4/repo" "feat/demo" "task/DEMO-1"
TASK_MD4=$(mk_task_md "$C4" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")

# Modify same file on feat/demo (origin) and on task/DEMO-1 → conflict
ORIGIN4="$C4/repo.origin.git"
TMPCLONE="$C4/tmp-clone"
git clone -q "$ORIGIN4" "$TMPCLONE"
git -C "$TMPCLONE" config user.email "x@y" && git -C "$TMPCLONE" config user.name "x"
git -C "$TMPCLONE" checkout -q feat/demo
printf 'feat\nfeat-side\n' > "$TMPCLONE/file.txt"
git -C "$TMPCLONE" commit -q -am "advance feat (conflicting)"
git -C "$TMPCLONE" push -q origin feat/demo

# task branch has its own diverging change to file.txt already (from mk_repo).
# Now both touch file.txt at end → conflict.

mk_fake_gh "$C4/bin"
FAKE_PR_VIEW="$C4/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 102 "feat/demo"
FAKE_GH_LOG="$C4/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C4/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C4/repo" --task-md "$TASK_MD4" 2>/tmp/rr-c4-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c4-stderr; }
assert_eq "$rc" "1" "case4.exit"
assert_json_eq "$out" "rebase_status" "conflict" "case4"
# Verify rebase-in-progress
if [ -d "$C4/repo/.git/rebase-merge" ] || [ -d "$C4/repo/.git/rebase-apply" ]; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case4.rebase-in-progress\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case4.rebase-in-progress — no .git/rebase-merge or rebase-apply found\n"
fi
# Stderr advisory
stderr_c4=$(cat /tmp/rr-c4-stderr)
assert_contains "$stderr_c4" "Conflict during rebase" "case4.advisory"

# Abort the rebase to clean state (also tests case 14 below)
git -C "$C4/repo" rebase --abort >/dev/null 2>&1 || true

# ────────────────────────────────────────────────────────────────────────────
# Case 5: PR base aligned → pr_base_synced: false, already_aligned: true
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 5: PR base aligned ---\n'
# Reuse case2 outputs — the rebase succeeded (not_needed) and PR is at feat/demo.
# But we need to re-run with explicit PR view aligned. Build a new C5 to keep deterministic.
C5="$WORK_DIR/case5"
mkdir -p "$C5"
mk_repo "$C5/repo" "feat/demo" "task/DEMO-1"
TASK_MD5=$(mk_task_md "$C5" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C5/bin"
FAKE_PR_VIEW="$C5/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 103 "feat/demo"
FAKE_GH_LOG="$C5/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C5/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C5/repo" --task-md "$TASK_MD5" 2>/tmp/rr-c5-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c5-stderr; }
assert_eq "$rc" "0" "case5.exit"
assert_json_eq "$out" "pr_base_synced" "false" "case5"
assert_json_eq "$out" "pr_base_already_aligned" "true" "case5"
# fake gh log should NOT contain "pr edit"
if grep -q "pr edit" "$FAKE_GH_LOG"; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case5.no-pr-edit — gh log contains 'pr edit'\n"
else
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case5.no-pr-edit\n"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 6: PR base drift → gh pr edit invoked + pr_base_synced: true
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 6: PR base drift sync ---\n'
C6="$WORK_DIR/case6"
mkdir -p "$C6"
mk_repo "$C6/repo" "feat/demo" "task/DEMO-1"
TASK_MD6=$(mk_task_md "$C6" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C6/bin"
FAKE_PR_VIEW="$C6/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 104 "develop"   # drift — PR points at develop, task.md says feat/demo
FAKE_GH_LOG="$C6/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C6/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C6/repo" --task-md "$TASK_MD6" 2>/tmp/rr-c6-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c6-stderr; cat "$FAKE_GH_LOG"; }
assert_eq "$rc" "0" "case6.exit"
assert_json_eq "$out" "pr_base_before" "develop" "case6"
assert_json_eq "$out" "pr_base_after" "feat/demo" "case6"
assert_json_eq "$out" "pr_base_synced" "true" "case6"
# Verify gh pr edit was invoked with --base feat/demo
if grep -q "pr edit.*--base.*feat/demo" "$FAKE_GH_LOG"; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case6.gh-pr-edit-invoked\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case6.gh-pr-edit-invoked — log: %s\n" "$(cat "$FAKE_GH_LOG")"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 7: PR old base is downstream of resolved base → strip old base commits
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 7: downstream old base stripped ---\n'
C7="$WORK_DIR/case7"
mkdir -p "$C7"
mkdir -p "$C7/repo"
git -C "$C7/repo" init -q -b develop
git -C "$C7/repo" config user.email "selftest@example.com"
git -C "$C7/repo" config user.name "selftest"
printf 'init\n' > "$C7/repo/file.txt"
git -C "$C7/repo" add file.txt
git -C "$C7/repo" commit -q -m "init"
git -C "$C7/repo" remote add origin "$C7/repo.origin.git"
git init -q --bare "$C7/repo.origin.git"
git -C "$C7/repo" push -q origin develop
git -C "$C7/repo" checkout -q -b feat/old-base
printf 'old base only\n' > "$C7/repo/old-base.txt"
git -C "$C7/repo" add old-base.txt
git -C "$C7/repo" commit -q -m "old base"
git -C "$C7/repo" push -q origin feat/old-base
git -C "$C7/repo" checkout -q -b task/DEMO-1
printf 'task only\n' > "$C7/repo/task-only.txt"
git -C "$C7/repo" add task-only.txt
git -C "$C7/repo" commit -q -m "task"
git -C "$C7/repo" push -q origin task/DEMO-1
TASK_MD7=$(mk_task_md "$C7" "repo" "DEMO-1" "DEMO-1" "develop" "task/DEMO-1")

mk_fake_gh "$C7/bin"
FAKE_PR_VIEW="$C7/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 105 "feat/old-base"
FAKE_GH_LOG="$C7/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C7/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C7/repo" --task-md "$TASK_MD7" 2>/tmp/rr-c7-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c7-stderr; }
assert_eq "$rc" "0" "case7.exit"
assert_json_eq "$out" "resolved_base" "develop" "case7"
assert_json_eq "$out" "pr_base_before" "feat/old-base" "case7"
assert_json_eq "$out" "pr_base_after" "develop" "case7"
assert_json_eq "$out" "pr_base_synced" "true" "case7"
if [ -f "$C7/repo/task-only.txt" ] && [ ! -f "$C7/repo/old-base.txt" ]; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case7.old-base-stripped\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case7.old-base-stripped — task-only/old-base files unexpected\n"
fi
if grep -q "pr edit.*--base.*develop" "$FAKE_GH_LOG"; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case7.gh-pr-edit-invoked\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case7.gh-pr-edit-invoked — log: %s\n" "$(cat "$FAKE_GH_LOG")"
fi

# ────────────────────────────────────────────────────────────────────────────
# Case 8: no task.md → fail loud, no PR base fallback
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 8: no task.md fail-loud ---\n'
C8="$WORK_DIR/case8"
mkdir -p "$C8"
mk_repo "$C8/repo" "feat/demo" "task/DEMO-1"
# Intentionally skip mk_task_md so resolve-task-md-by-branch finds nothing.

mk_fake_gh "$C8/bin"
FAKE_PR_VIEW="$C8/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 106 "feat/demo"
FAKE_GH_LOG="$C8/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C8/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C8/repo" 2>/tmp/rr-c8-stderr)
rc=$?
assert_eq "$rc" "1" "case8.exit"
assert_json_eq "$out" "legacy_fallback" "false" "case8"
assert_json_eq "$out" "task_md" "null" "case8"
assert_json_eq "$out" "resolved_base" "null" "case8"
assert_json_eq "$out" "pr_base_synced" "false" "case8"
if grep -q "pr edit" "$FAKE_GH_LOG"; then
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case8.no-pr-edit — missing task must not invoke pr edit\n"
else
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case8.no-pr-edit\n"
fi
stderr_c8=$(cat /tmp/rr-c8-stderr)
assert_contains "$stderr_c8" "no task.md for current branch" "case8.advisory"

# ────────────────────────────────────────────────────────────────────────────
# Case 9: --repo external path resolution
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 9: --repo external path ---\n'
# Reuse case2 setup
C9="$WORK_DIR/case9"
mkdir -p "$C9"
mk_repo "$C9/repo" "feat/demo" "task/DEMO-1"
TASK_MD9=$(mk_task_md "$C9" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C9/bin"
FAKE_PR_VIEW="$C9/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 109 "feat/demo"
FAKE_GH_LOG="$C9/gh.log"
: > "$FAKE_GH_LOG"

# Run from /tmp (not inside the repo) and supply --repo explicitly
out=$(PATH="$C9/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash -c "cd /tmp && bash '$RR' --repo '$C9/repo' --task-md '$TASK_MD9'" 2>/tmp/rr-c9-stderr)
rc=$?
assert_eq "$rc" "0" "case9.exit"
# git rev-parse --show-toplevel resolves symlinks (macOS /var → /private/var); use the same
# resolved form for comparison.
expected_repo_c9=$(cd "$C9/repo" && git rev-parse --show-toplevel 2>/dev/null)
assert_json_eq "$out" "repo" "$expected_repo_c9" "case9"

# ────────────────────────────────────────────────────────────────────────────
# Case 10: --pr explicit override
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 10: --pr explicit ---\n'
C10="$WORK_DIR/case10"
mkdir -p "$C10"
mk_repo "$C10/repo" "feat/demo" "task/DEMO-1"
TASK_MD10=$(mk_task_md "$C10" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C10/bin"
FAKE_PR_VIEW="$C10/pr-view.json"
# Note: --pr 999 is supplied; fake gh always returns this view regardless
write_fake_pr_view "$FAKE_PR_VIEW" 999 "feat/demo"
FAKE_GH_LOG="$C10/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C10/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C10/repo" --task-md "$TASK_MD10" --pr 999 2>/tmp/rr-c10-stderr)
rc=$?
assert_eq "$rc" "0" "case10.exit"
assert_json_eq "$out" "pr_number" "999" "case10"

# ────────────────────────────────────────────────────────────────────────────
# Case 11: --task-md explicit override
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 11: --task-md explicit ---\n'
# Reuse case2 — explicit --task-md path
C11="$WORK_DIR/case11"
mkdir -p "$C11"
mk_repo "$C11/repo" "feat/demo" "task/DEMO-1"
TASK_MD11=$(mk_task_md "$C11" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C11/bin"
FAKE_PR_VIEW="$C11/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 110 "feat/demo"
FAKE_GH_LOG="$C11/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C11/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C11/repo" --task-md "$TASK_MD11" 2>/tmp/rr-c11-stderr)
rc=$?
assert_eq "$rc" "0" "case11.exit"
assert_json_eq "$out" "task_md" "$TASK_MD11" "case11"

# ────────────────────────────────────────────────────────────────────────────
# Case 12: fetch failure → exit 1
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 12: fetch failure ---\n'
C12="$WORK_DIR/case12"
mkdir -p "$C12"
mk_repo "$C12/repo" "feat/demo" "task/DEMO-1"
TASK_MD12=$(mk_task_md "$C12" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
# Break origin remote
git -C "$C12/repo" remote set-url origin /nonexistent/repo.git
mk_fake_gh "$C12/bin"
FAKE_PR_VIEW="$C12/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 111 "feat/demo"
FAKE_GH_LOG="$C12/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C12/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$RR" --repo "$C12/repo" --task-md "$TASK_MD12" 2>/tmp/rr-c12-stderr)
rc=$?
assert_eq "$rc" "1" "case12.exit"
stderr_c12=$(cat /tmp/rr-c12-stderr)
assert_contains "$stderr_c12" "fetch origin failed" "case12.advisory"

# ────────────────────────────────────────────────────────────────────────────
# Case 13: resolve-task-base.sh missing → exit 1
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 13: helper missing ---\n'
C13="$WORK_DIR/case13"
mkdir -p "$C13/scripts-shadow"
# Copy revision-rebase.sh into a shadow dir without resolve-task-base.sh
cp "$RR" "$C13/scripts-shadow/revision-rebase.sh"
# Also copy resolve-task-md-by-branch.sh so the task.md lookup helper is present
cp "$SCRIPT_DIR/resolve-task-md-by-branch.sh" "$C13/scripts-shadow/"
mk_repo "$C13/repo" "feat/demo" "task/DEMO-1"
TASK_MD13=$(mk_task_md "$C13" "repo" "DEMO-1" "DEMO-1" "feat/demo" "task/DEMO-1")
mk_fake_gh "$C13/bin"
FAKE_PR_VIEW="$C13/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 112 "feat/demo"
FAKE_GH_LOG="$C13/gh.log"
: > "$FAKE_GH_LOG"

out=$(PATH="$C13/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$FAKE_GH_LOG" \
  bash "$C13/scripts-shadow/revision-rebase.sh" --repo "$C13/repo" --task-md "$TASK_MD13" 2>/tmp/rr-c13-stderr)
rc=$?
assert_eq "$rc" "1" "case13.exit"
stderr_c13=$(cat /tmp/rr-c13-stderr)
assert_contains "$stderr_c13" "helper missing" "case13.advisory"

# ────────────────────────────────────────────────────────────────────────────
# Case 14: JSON schema completeness
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 14: JSON schema completeness ---\n'
# Use case2 result — confirm all keys present
expected_keys="repo task_md resolved_base rebase_status pr_number pr_base_before pr_base_after pr_base_synced pr_base_already_aligned legacy_fallback writer at"
out=$(PATH="$C2/bin:$PATH" \
  FAKE_GH_PR_VIEW="$C2/pr-view.json" FAKE_GH_LOG="$C2/gh.log" \
  bash "$RR" --repo "$C2/repo" --task-md "$TASK_MD2" 2>/dev/null)
for k in $expected_keys; do
  if printf '%s' "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if '$k' in d else 1)" 2>/dev/null; then
    PASS=$((PASS + 1))
    [ "$DEBUG" = "1" ] && printf "  [ok] case14.key=%s\n" "$k"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] case14.key missing: %s\n" "$k"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# Case 15: post-conflict re-run (after manual resolution) → clean
# ────────────────────────────────────────────────────────────────────────────
printf '\n--- Case 15: re-run after conflict resolution ---\n'
# After abort in case4, simulate the user manually resolving the conflict:
#   1. abort prior rebase
#   2. reset task branch to feat/demo's tip (taking upstream's resolution)
#   3. add a non-conflicting commit on top
# This produces a state where the rebase target is an ancestor of HEAD →
# rebase_status = "not_needed". That covers the "re-run after fixing the cause"
# case (the script doesn't try to rebase again unnecessarily).
git -C "$C4/repo" rebase --abort >/dev/null 2>&1 || true
git -C "$C4/repo" fetch -q origin
git -C "$C4/repo" reset -q --hard origin/feat/demo
printf 'reapplied-task-work\n' > "$C4/repo/different.txt"
git -C "$C4/repo" add different.txt
git -C "$C4/repo" commit -q -m "reapplied non-conflicting"

mk_fake_gh "$C4/bin"
FAKE_PR_VIEW="$C4/pr-view.json"
write_fake_pr_view "$FAKE_PR_VIEW" 102 "feat/demo"
: > "$C4/gh.log"

out=$(PATH="$C4/bin:$PATH" \
  FAKE_GH_PR_VIEW="$FAKE_PR_VIEW" FAKE_GH_LOG="$C4/gh.log" \
  bash "$RR" --repo "$C4/repo" --task-md "$TASK_MD4" 2>/tmp/rr-c15-stderr)
rc=$?
[ "$DEBUG" = "1" ] && { printf '  out: %s\n' "$out"; cat /tmp/rr-c15-stderr; }
assert_eq "$rc" "0" "case15.exit"
# After manual reset to origin/feat/demo + extra commit, target is ancestor of HEAD
# → rebase is "not_needed". Either "clean" or "not_needed" is acceptable here, since
# both indicate the script handled the recovery case correctly.
got_status=$(printf '%s' "$out" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('rebase_status'))")
if [ "$got_status" = "clean" ] || [ "$got_status" = "not_needed" ]; then
  PASS=$((PASS + 1))
  [ "$DEBUG" = "1" ] && printf "  [ok] case15.rebase_status=%s\n" "$got_status"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] case15.rebase_status — want=clean|not_needed got=%s\n" "$got_status"
fi

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
printf '\n=== revision-rebase selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
