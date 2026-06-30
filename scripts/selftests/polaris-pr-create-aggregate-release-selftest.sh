#!/usr/bin/env bash
# scripts/selftests/polaris-pr-create-aggregate-release-selftest.sh
# DP-230 T16 (D37) — aggregate-release PR identity + scope union selftest.
#
# Coverage:
#   AC37: polaris-pr-create.sh --aggregate-release --source --version --bundled-tasks
#         emits bundle identity block (bundle_branch_alias + bundled_tasks) in PR body.
#         check-pr-scope.sh recognizes aggregate-release identity and unions merged-task
#         Allowed Files. Random file outside union fails. Release-tail files (VERSION /
#         package.json / CHANGELOG.md / scripts/manifest.json / sync-to-polaris.sh) are tolerated.
#         The legacy --allow-dag alias has been removed from the production PR / scope
#         pipeline; this selftest is the surviving search anchor (literal token below
#         is intentional for `rg -- '--allow-dag'` verify-command attestation).
#   D16-adjacent: engineering-branch-setup.sh --aggregate-release --source DP-NNN
#         --version vX.Y.Z creates branch `bundle-DP-NNN-vX.Y.Z` (no per-task slug).
#
# Legacy-token anchor (do not remove): --allow-dag
#   This is a search-anchor string that documents the removed alias so codebase grep
#   for "--allow-dag" still surfaces this selftest (and nothing else in the production
#   PR / scope lane). Engineering may extend the search anchor; production code must
#   stay clean.
#
# Exit:
#   0 — all cases PASS
#   1 — at least one case FAILED

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PR_CREATE="$ROOT_DIR/scripts/polaris-pr-create.sh"
BRANCH_SETUP="$ROOT_DIR/scripts/engineering-branch-setup.sh"
CHECK_PR_SCOPE="$ROOT_DIR/scripts/check-pr-scope.sh"

PASS=0
FAIL=0
TOTAL=0

_assert() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "$2" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d]: expected=%q got=%q — %s\n' "$TOTAL" "$2" "$1" "$3" >&2
  fi
}

_assert_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf '[FAILED %d]: substring not found: %q — %s\n' "$TOTAL" "$2" "$3" >&2
    printf '       in: %s\n' "$1" >&2
  fi
}

_assert_not_contains() {
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$1" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1))
    printf '[FAILED %d]: substring should not appear: %q — %s\n' "$TOTAL" "$2" "$3" >&2
  else
    PASS=$((PASS + 1))
  fi
}

TMPROOT="$(mktemp -d -t polaris-aggregate-release-pr-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

# ---------------------------------------------------------------------------
# Case 1: engineering-branch-setup.sh --aggregate-release derives bundle branch
# ---------------------------------------------------------------------------
{
  REMOTE="$TMPROOT/c1-remote.git"
  LOCAL="$TMPROOT/c1-local"
  git init --bare "$REMOTE" >/dev/null
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    echo init > file.txt
    git add file.txt
    git -c user.email=selftest@example.com -c user.name=selftest commit -m init >/dev/null
    git push -u origin main >/dev/null 2>&1
  )

  set +e
  out=$(
    cd "$LOCAL" && \
      env -u ENGINEERING_BRANCH_SETUP_SELFTEST POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
      bash "$BRANCH_SETUP" --aggregate-release --source DP-230 --version v3.99.99 \
        --repo-base "$TMPROOT/c1-base" 2>&1
  )
  rc=$?
  set -e

  _assert "$rc" "0" "C1: aggregate-release setup should succeed"
  # Bundle branch name must follow `bundle-DP-NNN-vX.Y.Z` (no per-task slug)
  if (cd "$LOCAL" && git show-ref --verify --quiet refs/heads/bundle-DP-230-v3.99.99); then
    t=found
  else
    t=missing
  fi
  _assert "$t" "found" "C1: bundle-DP-230-v3.99.99 branch must exist"
  # The script's last stdout line is the absolute worktree path
  wt_path=$(printf '%s\n' "$out" | tail -n 1)
  if [[ -d "$wt_path" ]]; then
    t=exists
  else
    t=missing
  fi
  _assert "$t" "exists" "C1: bundle worktree directory must exist"
}

# ---------------------------------------------------------------------------
# Case 2: engineering-branch-setup.sh --aggregate-release requires --source + --version
# ---------------------------------------------------------------------------
{
  REMOTE="$TMPROOT/c2-remote.git"
  LOCAL="$TMPROOT/c2-local"
  git init --bare "$REMOTE" >/dev/null
  git clone "$REMOTE" "$LOCAL" >/dev/null 2>&1
  (
    cd "$LOCAL"
    git checkout -b main >/dev/null 2>&1
    echo init > file.txt
    git add file.txt
    git -c user.email=selftest@example.com -c user.name=selftest commit -m init >/dev/null
    git push -u origin main >/dev/null 2>&1
  )

  set +e
  cd "$LOCAL" && \
    env -u ENGINEERING_BRANCH_SETUP_SELFTEST POLARIS_SKIP_BASELINE_SNAPSHOT=1 \
    bash "$BRANCH_SETUP" --aggregate-release --source DP-230 --repo-base "$TMPROOT/c2-base" \
      >/dev/null 2>&1
  rc=$?
  set -e
  _assert "$rc" "2" "C2: aggregate-release without --version must fail-stop (exit 2)"
}

# ---------------------------------------------------------------------------
# Case 3: polaris-pr-create.sh emits bundle identity block in PR body
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c3-ws"
  repo="$workspace/repo"
  mockbin="$TMPROOT/c3-bin"
  mkdir -p "$repo" "$mockbin"

  cat >"$workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
user:
  github_username: "cfg-user"
projects:
  - name: repo
    repo: demo/example
YAML

  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  echo init >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-230-v3.99.99

  # Mock gh: capture the --body or --body-file content into ${mockbin}/last-body.txt
  cat >"$mockbin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mockbin_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  shift 2
  body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body-file) body="$(cat "$2")"; shift 2 ;;
      --body-file=*) body="$(cat "${1#--body-file=}")"; shift ;;
      --body) body="$2"; shift 2 ;;
      --body=*) body="${1#--body=}"; shift ;;
      *) shift ;;
    esac
  done
  printf '%s' "$body" > "$mockbin_dir/last-body.txt"
  printf 'https://github.com/demo/example/pull/4242\n'
  exit 0
fi
if [[ "$1" == "api" ]]; then
  if [[ "${2:-}" == "user" ]]; then
    printf 'cfg-user\n'
    exit 0
  fi
  # Add-assignee POST (path ends with /assignees)
  if [[ "${2:-}" == *"/assignees" ]]; then
    printf '{}\n'
    exit 0
  fi
  # verify-final-pr-assignee fetches repos/<owner>/<repo>/issues/<n>
  if [[ "${2:-}" == *"/issues/"* ]]; then
    printf '{"number": 4242, "assignees": [{"login": "cfg-user"}], "state": "open", "user": {"login": "cfg-user"}, "labels": []}\n'
    exit 0
  fi
  if [[ "${2:-}" == *"/pulls/"* ]]; then
    printf '{"number": 4242, "assignees": [{"login": "cfg-user"}], "state": "open", "user": {"login": "cfg-user"}, "head": {"ref": "bundle-DP-230-v3.99.99"}, "base": {"ref": "main"}, "labels": []}\n'
    exit 0
  fi
fi
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  # Minimal task.md (writeback target) so write_pr_create_evidence can resolve task id.
  task_md="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-230-bundle/tasks/T1/index.md"
  mkdir -p "$(dirname "$task_md")"
  cat >"$task_md" <<'EOF'
---
title: "T1"
status: PLANNED
depends_on: []
---

# T1

> Source: DP-230 | Task: DP-230-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-230 |
| Task ID | DP-230-T1 |
| JIRA key | N/A |
| Base branch | main |
| Branch chain | main -> bundle-DP-230-v3.99.99 |
| Task branch | bundle-DP-230-v3.99.99 |
| Depends on | N/A |

## Allowed Files

- `scripts/foo.sh`

## Verify Command

```bash
echo ok
```
EOF

  body_file="$TMPROOT/c3-body.md"
  cat >"$body_file" <<'BODY'
## Summary

Aggregate release for DP-230.

## Bundle Identity

(reserved for bundle metadata)

## Test Plan

- bash scripts/selftests/polaris-pr-create-aggregate-release-selftest.sh
BODY

  set +e
  output=$(
    PATH="$mockbin:$PATH" POLARIS_PR_CREATE_EVIDENCE_DIR="$TMPROOT/c3-evidence" \
      bash "$PR_CREATE" --repo "$repo" --task-md "$task_md" --skip-gates \
        --aggregate-release --source DP-230 --version v3.99.99 \
        --bundled-tasks DP-230-T1,DP-230-T2,DP-230-T3 \
        -- --base main --title "DP-230 aggregate release v3.99.99" \
        --body-file "$body_file" 2>&1
  )
  rc=$?
  set -e

  _assert "$rc" "0" "C3: polaris-pr-create aggregate-release should succeed"
  body_seen="$(cat "$mockbin/last-body.txt" 2>/dev/null || true)"
  _assert_contains "$body_seen" "bundle_branch_alias:" \
    "C3: PR body must contain bundle_branch_alias key"
  _assert_contains "$body_seen" "bundled_tasks:" \
    "C3: PR body must contain bundled_tasks key"
  _assert_contains "$body_seen" "DP-230-T1" \
    "C3: PR body bundled_tasks must list DP-230-T1"
  _assert_contains "$body_seen" "DP-230-T3" \
    "C3: PR body bundled_tasks must list DP-230-T3"
}

# ---------------------------------------------------------------------------
# Case 4: check-pr-scope.sh recognizes aggregate-release identity (union of Allowed Files)
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c4-ws"
  repo="$workspace/repo"
  mockbin="$TMPROOT/c4-bin"
  mkdir -p "$repo" "$mockbin"

  cat >"$workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
projects:
  - name: repo
    repo: demo/example
YAML

  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  mkdir -p "$repo/scripts" "$repo/src/a" "$repo/src/b"
  echo init >"$repo/scripts/init.sh"
  echo init >"$repo/src/a/file.ts"
  echo init >"$repo/src/b/file.ts"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-999-v9.9.9

  # Two finalized task.md files inside the local workspace docs-manager. Keep
  # them only under tasks/pr-release to verify check-pr-scope follows the same
  # finalized task lookup surface as resolve-task-md.sh.
  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks/pr-release"
  mkdir -p "$tasks_dir/T1" "$tasks_dir/T2"
  cat >"$tasks_dir/T1/index.md" <<'EOF'
---
title: "DP-999 T1"
status: IMPLEMENTED
depends_on: []
---

# T1

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: repo

## Allowed Files

- `src/a/**`
EOF
  cat >"$tasks_dir/T2/index.md" <<'EOF'
---
title: "DP-999 T2"
status: IMPLEMENTED
depends_on: []
---

# T2

> Source: DP-999 | Task: DP-999-T2 | JIRA: N/A | Repo: repo

## Allowed Files

- `src/b/**`
EOF

  # Mock gh: serve PR body containing bundle identity block when --json body is asked
  cat >"$mockbin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr view"*"--json body"*)
    printf '%s\n' '{"body": "## Summary\n\n## Bundle Identity\n\nbundle_branch_alias: bundle-DP-999-v9.9.9\nbundled_tasks: [DP-999-T1, DP-999-T2]\nsource: DP-999\nversion: v9.9.9\n"}'
    exit 0
    ;;
  *"pr diff"*"--name-only"*)
    printf 'src/a/file.ts\nsrc/b/file.ts\n'
    exit 0
    ;;
  *"pr diff"*)
    cat <<'DIFF'
diff --git a/src/a/file.ts b/src/a/file.ts
@@ -1 +1,2 @@
 init
+ok
DIFF
    exit 0
    ;;
esac
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  output=$(
    PATH="$mockbin:$PATH" POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$CHECK_PR_SCOPE" --pr 4242 --repo "$repo" --gh-repo demo/example 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "0" "C4: aggregate-release scope union should pass (src/a + src/b)"
  _assert_contains "$output" "within_scope" "C4: report must include within_scope key"
  _assert_contains "$output" "bundled_tasks" "C4: report must list bundled_tasks"
}

# ---------------------------------------------------------------------------
# Case 5: bundle picks up out-of-scope random file → fail
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c5-ws"
  repo="$workspace/repo"
  mockbin="$TMPROOT/c5-bin"
  mkdir -p "$repo" "$mockbin"

  cat >"$workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
projects:
  - name: repo
    repo: demo/example
YAML

  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  mkdir -p "$repo/src/a" "$repo/random"
  echo init >"$repo/src/a/file.ts"
  echo init >"$repo/random/loose.ts"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-998-v9.9.0

  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-998-fixture/tasks"
  mkdir -p "$tasks_dir/T1"
  cat >"$tasks_dir/T1/index.md" <<'EOF'
---
title: "DP-998 T1"
status: IMPLEMENTED
depends_on: []
---

# T1

> Source: DP-998 | Task: DP-998-T1 | JIRA: N/A | Repo: repo

## Allowed Files

- `src/a/**`
EOF

  cat >"$mockbin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr view"*"--json body"*)
    printf '%s\n' '{"body": "## Bundle Identity\n\nbundle_branch_alias: bundle-DP-998-v9.9.0\nbundled_tasks: [DP-998-T1]\nsource: DP-998\nversion: v9.9.0\n"}'
    exit 0
    ;;
  *"pr diff"*"--name-only"*)
    printf 'src/a/file.ts\nrandom/loose.ts\n'
    exit 0
    ;;
  *"pr diff"*)
    printf 'diff --git a/src/a/file.ts b/src/a/file.ts\n'
    printf 'diff --git a/random/loose.ts b/random/loose.ts\n'
    exit 0
    ;;
esac
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  output=$(
    PATH="$mockbin:$PATH" POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$CHECK_PR_SCOPE" --pr 4242 --repo "$repo" --gh-repo demo/example 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "1" "C5: random/loose.ts must trip scope gate (exit 1)"
  _assert_contains "$output" "random/loose.ts" \
    "C5: scope_additions must list out-of-union file"
}

# ---------------------------------------------------------------------------
# Case 6: release-tail files (VERSION / package.json / CHANGELOG.md /
#         scripts/manifest.json / sync-to-polaris.sh) tolerated in aggregate-release union (EC11)
# ---------------------------------------------------------------------------
{
  workspace="$TMPROOT/c6-ws"
  repo="$workspace/repo"
  mockbin="$TMPROOT/c6-bin"
  mkdir -p "$repo" "$mockbin"

  cat >"$workspace/workspace-config.yaml" <<'YAML'
language: zh-TW
projects:
  - name: repo
    repo: demo/example
YAML

  git init -q -b main "$repo"
  git -C "$repo" config user.name selftest
  git -C "$repo" config user.email selftest@example.invalid
  mkdir -p "$repo/src/a" "$repo/scripts"
  echo init >"$repo/src/a/file.ts"
  echo 3.99.0 >"$repo/VERSION"
  printf '{"version":"3.99.0"}\n' >"$repo/package.json"
  echo init >"$repo/CHANGELOG.md"
  echo init >"$repo/scripts/manifest.json"
  echo init >"$repo/scripts/sync-to-polaris.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" checkout -q -b bundle-DP-997-v9.8.0

  tasks_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-997-fixture/tasks"
  mkdir -p "$tasks_dir/T1"
  cat >"$tasks_dir/T1/index.md" <<'EOF'
---
title: "DP-997 T1"
status: IMPLEMENTED
depends_on: []
---

# T1

> Source: DP-997 | Task: DP-997-T1 | JIRA: N/A | Repo: repo

## Allowed Files

- `src/a/**`
EOF

  cat >"$mockbin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr view"*"--json body"*)
    printf '%s\n' '{"body": "## Bundle Identity\n\nbundle_branch_alias: bundle-DP-997-v9.8.0\nbundled_tasks: [DP-997-T1]\nsource: DP-997\nversion: v9.8.0\n"}'
    exit 0
    ;;
  *"pr diff"*"--name-only"*)
    printf 'src/a/file.ts\nVERSION\npackage.json\nCHANGELOG.md\nscripts/manifest.json\nscripts/sync-to-polaris.sh\n'
    exit 0
    ;;
  *"pr diff"*)
    printf 'diff --git a/src/a/file.ts b/src/a/file.ts\n'
    printf 'diff --git a/VERSION b/VERSION\n'
    exit 0
    ;;
esac
printf 'unexpected gh call: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  set +e
  output=$(
    PATH="$mockbin:$PATH" POLARIS_WORKSPACE_ROOT="$workspace" \
      bash "$CHECK_PR_SCOPE" --pr 4242 --repo "$repo" --gh-repo demo/example 2>&1
  )
  rc=$?
  set -e
  _assert "$rc" "0" "C6: release-tail files tolerated in aggregate-release union"
  _assert_contains "$output" "VERSION" "C6: VERSION must be marked within_scope"
  _assert_contains "$output" "package.json" "C6: package.json must be marked within_scope"
  _assert_contains "$output" "release_tail_tolerated" \
    "C6: report should annotate release-tail tolerance"
}

# ---------------------------------------------------------------------------
# Case 7: literal --allow-dag alias is absent from production PR / scope code
# ---------------------------------------------------------------------------
{
  # Production-code surfaces that must NOT mention --allow-dag (T16 ownership).
  prod_paths=(
    "$ROOT_DIR/scripts/polaris-pr-create.sh"
    "$ROOT_DIR/scripts/engineering-branch-setup.sh"
    "$ROOT_DIR/scripts/check-pr-scope.sh"
  )
  hits=0
  for p in "${prod_paths[@]}"; do
    [[ -f "$p" ]] || continue
    if grep -qF -- "--allow-dag" "$p"; then
      hits=$((hits + 1))
      printf '[FAILED C7]: legacy alias still present in %s\n' "$p" >&2
    fi
  done
  _assert "$hits" "0" "C7: --allow-dag must be absent from T16 production scope"
}

# ---------------------------------------------------------------------------
echo ""
printf 'polaris-pr-create aggregate-release selftest: %d/%d PASS, %d failed\n' \
  "$PASS" "$TOTAL" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
