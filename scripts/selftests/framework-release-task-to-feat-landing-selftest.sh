#!/usr/bin/env bash
# Purpose: exercise framework-release-execute.sh task -> feat landing behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SCRIPT_DIR/framework-release-execute.sh"
TMPDIR="$(mktemp -d -t framework-release-task-to-feat.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-347-fixture/tasks"
STATE="$TMPDIR/pr-state.tsv"
GH_LOG="$TMPDIR/gh.log"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_task() {
  local key="$1"
  local base="$2"
  local branch="$3"
  local head="$4"
  local file="$TASK_DIR/${key}.md"
  mkdir -p "$TASK_DIR"
  cat >"$file" <<MD
---
deliverable:
  pr_url: https://example.test/pull/${key#T}
  pr_state: OPEN
  head_sha: ${head}
  verification:
    status: PASS
    ac_counts:
      ac_total: 1
      ac_pass: 1
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---
# ${key}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-347 |
| Task ID | DP-347-${key} |
| JIRA key | N/A |
| Base branch | ${base} |
| Branch chain | feat/DP-347 -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
MD
}

init_repo() {
  git init -q -b main "$REPO"
  (
    cd "$REPO"
    git config user.name "Polaris Selftest"
    git config user.email "polaris-selftest@example.com"
    printf 'base\n' > README.md
    mkdir -p scripts
    cat >scripts/manifest.json <<'JSON'
{
  "$schema": "https://polaris.local/schemas/scripts-manifest.v1.json",
  "version": 1,
  "generated_at": "2026-05-23T00:00:00+08:00",
  "description": "Fixture manifest for framework-release task-to-feat landing selftest.",
  "coverage": {
    "root_patterns": [
      "scripts/*.{sh,py,mjs}"
    ],
    "entrypoint_patterns": []
  },
  "enums": {
    "kind": [
      "gate",
      "writer",
      "resolver",
      "release",
      "selftest",
      "support",
      "legacy",
      "debug"
    ],
    "runner": [
      "bash",
      "python3",
      "node"
    ],
    "lifecycle": [
      "hot_path",
      "support_path",
      "legacy_keep",
      "sunset_candidate",
      "sunset_ready"
    ],
    "relocation": [
      "stay",
      "move_with_wrapper",
      "move_direct",
      "delete_after_gate"
    ]
  },
  "scripts": []
}
JSON
    git add README.md
    git add scripts/manifest.json
    git commit -q -m "base"
    git remote add origin "$REPO"
    git fetch -q origin main:refs/remotes/origin/main

    git checkout -q -b feat/DP-347 main
    git checkout -q -b task/DP-347-T1-one feat/DP-347
    printf 't1\n' > t1.txt
    git add t1.txt
    git commit -q -m "t1"
    git checkout -q -b task/DP-347-T2-two
    printf 't2\n' > t2.txt
    git add t2.txt
    git commit -q -m "t2"
    git checkout -q main
    git fetch -q origin \
      +refs/heads/feat/DP-347:refs/remotes/origin/feat/DP-347 \
      +refs/heads/task/DP-347-T1-one:refs/remotes/origin/task/DP-347-T1-one \
      +refs/heads/task/DP-347-T2-two:refs/remotes/origin/task/DP-347-T2-two
  )
}

write_state() {
  local t1_sha t2_sha
  t1_sha="$(git -C "$REPO" rev-parse task/DP-347-T1-one)"
  t2_sha="$(git -C "$REPO" rev-parse task/DP-347-T2-two)"
  make_task T1 feat/DP-347 task/DP-347-T1-one "$t1_sha"
  make_task T2 task/DP-347-T1-one task/DP-347-T2-two "$t2_sha"
  cat >"$STATE" <<EOF
task/DP-347-T1-one	1	OPEN	feat/DP-347	${t1_sha}	https://example.test/pull/1
task/DP-347-T2-two	2	OPEN	task/DP-347-T1-one	${t2_sha}	https://example.test/pull/2
EOF
}

cat >"$TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
state="${FRAMEWORK_RELEASE_EXECUTE_STATE:?}"
log="${FRAMEWORK_RELEASE_EXECUTE_GH_LOG:?}"
cmd="${1:-}"; shift || true
if [[ "$cmd" == "auth" && "${1:-}" == "status" ]]; then
  exit 0
fi
if [[ "$cmd" == "pr" && "${1:-}" == "view" ]]; then
  ref="${2:-}"
  while [[ $# -gt 0 ]]; do shift || true; done
  awk -F '\t' -v ref="$ref" '
    $1 == ref || $2 == ref {
      printf "{\"number\":%s,\"state\":\"%s\",\"baseRefName\":\"%s\",\"headRefName\":\"%s\",\"headRefOid\":\"%s\",\"mergeStateStatus\":\"CLEAN\",\"url\":\"%s\"}\n", $2, $3, $4, $1, $5, $6
      found=1
    }
    END { exit found ? 0 : 1 }
  ' "$state"
  exit $?
fi
if [[ "$cmd" == "pr" && "${1:-}" == "edit" ]]; then
  echo "edit $*" >>"$log"
  exit 0
fi
if [[ "$cmd" == "pr" && "${1:-}" == "merge" ]]; then
  echo "merge $*" >>"$log"
  exit 0
fi
echo "unsupported gh $cmd $*" >&2
exit 1
SH
chmod +x "$TMPDIR/gh"
export PATH="$TMPDIR:$PATH"
export GH_BIN="$TMPDIR/gh"
export FRAMEWORK_RELEASE_EXECUTE_STATE="$STATE"
export FRAMEWORK_RELEASE_EXECUTE_GH_LOG="$GH_LOG"

init_repo
write_state
: >"$GH_LOG"
bash "$HELPER" --repo "$REPO" --source-id DP-347 --land-tasks-to-feat \
  --task-md "$TASK_DIR/T1.md" \
  --task-md "$TASK_DIR/T2.md" >"$TMPDIR/landing.out" 2>&1
t2_sha="$(git -C "$REPO" rev-parse task/DP-347-T2-two)"
[[ "$(git -C "$REPO" rev-parse feat/DP-347)" == "$t2_sha" ]] \
  || fail "feat/DP-347 did not fast-forward to terminal task head"
[[ ! -s "$GH_LOG" ]] || fail "task -> feat landing must not call gh pr edit/merge"
grep -q "PASS land-tasks-to-feat" "$TMPDIR/landing.out" \
  || fail "missing PASS trace"

# Idempotency: when feat already contains both task heads, rerun is a no-op PASS.
: >"$GH_LOG"
bash "$HELPER" --repo "$REPO" --source-id DP-347 --land-tasks-to-feat \
  --task-md "$TASK_DIR/T1.md" \
  --task-md "$TASK_DIR/T2.md" >"$TMPDIR/idempotent.out" 2>&1
[[ "$(git -C "$REPO" rev-parse feat/DP-347)" == "$t2_sha" ]] \
  || fail "idempotent rerun changed feat head unexpectedly"
[[ ! -s "$GH_LOG" ]] || fail "idempotent rerun must not call gh pr edit/merge"

# Missing feat branch fails before PR mutation.
git -C "$REPO" branch -D feat/DP-347 >/dev/null
if bash "$HELPER" --repo "$REPO" --source-id DP-347 --land-tasks-to-feat \
  --task-md "$TASK_DIR/T1.md" >"$TMPDIR/missing-feat.out" 2>&1; then
  fail "missing feat branch should fail"
fi
grep -q "POLARIS_FRAMEWORK_RELEASE_EXECUTE_BLOCKED" "$TMPDIR/missing-feat.out" \
  || fail "missing feat failure must carry execute marker"

# Dirty repo fails closed.
git -C "$REPO" branch feat/DP-347 main
printf 'dirty\n' >>"$REPO/README.md"
if bash "$HELPER" --repo "$REPO" --source-id DP-347 --land-tasks-to-feat \
  --task-md "$TASK_DIR/T1.md" >"$TMPDIR/dirty.out" 2>&1; then
  fail "dirty repo should fail"
fi
grep -q "repo must be clean" "$TMPDIR/dirty.out" || fail "dirty failure reason missing"
git -C "$REPO" checkout -q -- README.md

# Broken stack ancestry: T2 does not contain T1, so feat cannot fast-forward.
git -C "$REPO" branch -f feat/DP-347 main
git -C "$REPO" branch -f task/DP-347-T2-two main
git -C "$REPO" checkout -q task/DP-347-T2-two
printf 'broken t2\n' >"$REPO/broken-t2.txt"
git -C "$REPO" add broken-t2.txt
git -C "$REPO" commit -q -m "broken t2"
git -C "$REPO" checkout -q main
git -C "$REPO" fetch -q origin +refs/heads/task/DP-347-T2-two:refs/remotes/origin/task/DP-347-T2-two
write_state
if bash "$HELPER" --repo "$REPO" --source-id DP-347 --land-tasks-to-feat \
  --task-md "$TASK_DIR/T1.md" \
  --task-md "$TASK_DIR/T2.md" >"$TMPDIR/broken-stack.out" 2>&1; then
  fail "broken stack ancestry should fail"
fi
grep -q "cannot fast-forward" "$TMPDIR/broken-stack.out" \
  || fail "broken stack failure must name fast-forward blocker"

echo "PASS: framework-release task-to-feat landing selftest"
