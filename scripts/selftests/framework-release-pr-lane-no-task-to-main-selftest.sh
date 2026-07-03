#!/usr/bin/env bash
# Purpose: prove framework-release-pr-lane no longer executes task -> main merges.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$SCRIPT_DIR/framework-release-pr-lane.sh"
TMPDIR="$(mktemp -d -t framework-release-no-task-main.XXXXXX)"
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
| Branch chain | main -> ${branch} |
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
    mkdir -p scripts
    printf 'base\n' > README.md
    cat >scripts/manifest.json <<'JSON'
{
  "$schema": "https://polaris.local/schemas/scripts-manifest.v1.json",
  "version": 1,
  "generated_at": "2026-05-23T00:00:00+08:00",
  "description": "Fixture manifest for no task-to-main release lane selftest.",
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
    git add README.md scripts/manifest.json
    git commit -q -m "base"
    git remote add origin "$REPO"
    git fetch -q origin main:refs/remotes/origin/main

    git checkout -q -b task/DP-347-T1-one main
    printf 't1\n' > t1.txt
    git add t1.txt
    git commit -q -m "t1"
    git checkout -q -b task/DP-347-T2-two
    printf 't2\n' > t2.txt
    git add t2.txt
    git commit -q -m "t2"
    git checkout -q main
    git fetch -q origin \
      +refs/heads/task/DP-347-T1-one:refs/remotes/origin/task/DP-347-T1-one \
      +refs/heads/task/DP-347-T2-two:refs/remotes/origin/task/DP-347-T2-two
  )
}

cat >"$TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
state="${FRAMEWORK_RELEASE_NO_TASK_MAIN_STATE:?}"
log="${FRAMEWORK_RELEASE_NO_TASK_MAIN_GH_LOG:?}"
cmd="${1:-}"; shift || true
if [[ "$cmd" == "auth" && "${1:-}" == "status" ]]; then
  exit 0
fi
if [[ "$cmd" == "pr" && "${1:-}" == "view" ]]; then
  ref="${2:-}"
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
export GH_BIN="$TMPDIR/gh"
export FRAMEWORK_RELEASE_NO_TASK_MAIN_STATE="$STATE"
export FRAMEWORK_RELEASE_NO_TASK_MAIN_GH_LOG="$GH_LOG"

init_repo
t1_sha="$(git -C "$REPO" rev-parse task/DP-347-T1-one)"
t2_sha="$(git -C "$REPO" rev-parse task/DP-347-T2-two)"
make_task T1 main task/DP-347-T1-one "$t1_sha"
make_task T2 task/DP-347-T1-one task/DP-347-T2-two "$t2_sha"
cat >"$STATE" <<EOF
task/DP-347-T1-one	1	OPEN	main	${t1_sha}	https://example.test/pull/1
task/DP-347-T2-two	2	OPEN	task/DP-347-T1-one	${t2_sha}	https://example.test/pull/2
EOF

bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" \
  >"$TMPDIR/dryrun.out" 2>&1
grep -q "validate lineage only; task-to-main execute disabled" "$TMPDIR/dryrun.out" \
  || fail "dry-run plan must not advertise task-to-main merge/retarget"

: >"$GH_LOG"
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" \
  --execute >"$TMPDIR/execute.out" 2>&1; then
  fail "task-to-main --execute should fail closed"
fi
grep -q "task-to-main execute is disabled" "$TMPDIR/execute.out" \
  || fail "execute failure must name disabled task-to-main path"
[[ ! -s "$GH_LOG" ]] || fail "task-to-main execute must not call gh pr edit/merge"

: >"$GH_LOG"
if bash "$HELPER" --repo "$REPO" --allow-dag --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" \
  --execute >"$TMPDIR/dag-execute.out" 2>&1; then
  fail "DAG task-to-main --execute should fail closed"
fi
grep -q "task-to-main execute is disabled" "$TMPDIR/dag-execute.out" \
  || fail "DAG execute failure must name disabled task-to-main path"
[[ ! -s "$GH_LOG" ]] || fail "DAG task-to-main execute must not call gh pr edit/merge"

echo "PASS: framework-release pr-lane no task-to-main selftest"
