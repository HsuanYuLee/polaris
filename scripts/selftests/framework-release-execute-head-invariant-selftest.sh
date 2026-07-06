#!/usr/bin/env bash
# Purpose: DP-406 regression fixture for framework-release-execute.sh full-tail
#          post-cascade release-head invariant.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="$(mktemp -d -t framework-release-head-invariant.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"
TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-406-fixture/tasks"
LOG="$TMPDIR/head-invariant.log"
HELPER="$REPO/scripts/framework-release-execute.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_task() {
  local file="$TASK_DIR/T1.md"
  local head
  head="$(git -C "$REPO" rev-parse task/DP-406-T1-one)"
  mkdir -p "$TASK_DIR"
  cat >"$file" <<MD
---
deliverable:
  pr_url: https://example.test/pull/4061
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
# T1

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-406 |
| Task ID | DP-406-T1 |
| JIRA key | N/A |
| Base branch | feat/DP-406 |
| Branch chain | feat/DP-406 -> task/DP-406-T1-one |
| Task branch | task/DP-406-T1-one |
| Depends on | N/A |
MD
}

init_repo() {
  git init -q -b main "$REPO"
  (
    cd "$REPO"
    git config user.name "Polaris Selftest"
    git config user.email "polaris-selftest@example.com"
    git config receive.denyCurrentBranch updateInstead
    printf 'language: "zh-TW"\n' > workspace-config.yaml
    printf '3.76.64\n' > VERSION
    printf '{"name":"polaris-framework-workspace","version":"3.76.64"}\n' > package.json
    printf '# Changelog\n' > CHANGELOG.md
    mkdir -p scripts .changeset
    cat >.changeset/dp-406-fixture.md <<'MD'
---
"polaris-framework-workspace": patch
---

DP-406 fixture changeset
MD
    git add workspace-config.yaml VERSION package.json CHANGELOG.md .changeset/dp-406-fixture.md
    git commit -q -m "base"
    git remote add origin "$REPO"
    git fetch -q origin main:refs/remotes/origin/main
    git checkout -q -b feat/DP-406 main
    git checkout -q -b task/DP-406-T1-one feat/DP-406
    printf 't1\n' > t1.txt
    git add t1.txt
    git commit -q -m "t1"
    git checkout -q feat/DP-406
    git fetch -q origin \
      +refs/heads/feat/DP-406:refs/remotes/origin/feat/DP-406 \
      +refs/heads/task/DP-406-T1-one:refs/remotes/origin/task/DP-406-T1-one
  )

  cp "$ROOT/scripts/framework-release-execute.sh" "$HELPER"
  cp -R "$ROOT/scripts/lib" "$REPO/scripts/lib"
  make_task
}

write_stubs() {
  cat >"$REPO/scripts/framework-release-pr-lane.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
repo=""
main=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --main) main="$2"; shift 2 ;;
    *) shift ;;
  esac
done
echo "01 pr-lane land=${HEAD_INVARIANT_LAND:-0}" >>"${HEAD_INVARIANT_LOG:?}"
[[ -n "$repo" && -n "$main" ]] || exit 2
git -C "$repo" checkout -q "$main"
if [[ "${HEAD_INVARIANT_LAND:-0}" == "1" ]]; then
  git -C "$repo" merge --ff-only task/DP-406-T1-one >/dev/null
fi
SH
  cat >"$REPO/scripts/cascade-rebase-chain.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "02 cascade $*" >>"${HEAD_INVARIANT_LOG:?}"
exit 0
SH
  cat >"$TMPDIR/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "03 release-version" >>"${HEAD_INVARIANT_LOG:?}"
exit 0
SH
  cat >"$REPO/scripts/polaris-external-write-gate.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
  cat >"$REPO/scripts/polaris-pr-create.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "04 pr-create" >>"${HEAD_INVARIANT_LOG:?}"
echo "https://github.com/example/repo/pull/406"
SH
  cat >"$REPO/scripts/framework-release-main-promotion.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "05 main-promotion" >>"${HEAD_INVARIANT_LOG:?}"
exit 0
SH
  chmod +x "$HELPER" "$TMPDIR/mise" "$REPO/scripts"/*.sh
}

run_full_tail() {
  bash "$HELPER" --repo "$REPO" --source-id DP-406 --full-tail \
    --task-md "$TASK_DIR/T1.md"
}

init_repo
write_stubs
export HEAD_INVARIANT_LOG="$LOG"
export PATH="$TMPDIR:$PATH"

: >"$LOG"
HEAD_INVARIANT_LAND=1 run_full_tail >"$TMPDIR/happy.out" 2>&1
grep -q "PASS post-cascade release head invariant" "$TMPDIR/happy.out" \
  || fail "happy path did not report post-cascade invariant PASS"
grep -q "03 release-version" "$LOG" \
  || fail "happy path did not reach release-version"

git -C "$REPO" checkout -q feat/DP-406
git -C "$REPO" reset -q --hard main
git -C "$REPO" fetch -q origin \
  +refs/heads/feat/DP-406:refs/remotes/origin/feat/DP-406 \
  +refs/heads/task/DP-406-T1-one:refs/remotes/origin/task/DP-406-T1-one

: >"$LOG"
if HEAD_INVARIANT_LAND=0 run_full_tail >"$TMPDIR/mismatch.out" 2>&1; then
  fail "mismatch path should fail before release-version"
fi
grep -q "POLARIS_FRAMEWORK_RELEASE_EXECUTE_HEAD_INVARIANT" "$TMPDIR/mismatch.out" \
  || fail "mismatch path did not emit head invariant marker"
if grep -q "03 release-version" "$LOG"; then
  fail "mismatch path must not reach release-version"
fi

echo "PASS: framework-release execute head invariant selftest"
