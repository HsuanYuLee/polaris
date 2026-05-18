#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/framework-release-pr-lane.sh"
TMPDIR="$(mktemp -d -t framework-release-pr-lane.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT
REPO="$TMPDIR/repo"

make_task() {
  local file="$1"
  local task_id="$2"
  local base="$3"
  local chain="$4"
  local branch="$5"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
# ${task_id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | ${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | ${base} |
| Branch chain | ${chain} |
| Task branch | ${branch} |
| Depends on | N/A |
| References to load | - \`scripts/framework-release-pr-lane.sh\` |
MD
}

write_state() {
  cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-T1-one	1	OPEN	main	1111111111111111111111111111111111111111	https://example.test/pull/1
task/DP-999-T2-two	2	OPEN	task/DP-999-T1-one	2222222222222222222222222222222222222222	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	task/DP-999-T2-two	3333333333333333333333333333333333333333	https://example.test/pull/3
EOF
}

init_repo() {
  git init -q -b main "$REPO"
  (
    cd "$REPO"
    git config user.name "Polaris Selftest"
    git config user.email "polaris-selftest@example.com"
    mkdir -p scripts docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks
    printf '3.75.8\n' > VERSION
    printf '# Changelog\n' > CHANGELOG.md
    printf 'base\n' > scripts/example-release.sh
    cat > scripts/manifest.json <<'JSON'
{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/example-release.sh",
      "kind": "release",
      "runner": "bash",
      "owner_surface": "release_flow",
      "selftest": "N/A",
      "selftest_reason": "framework-release-pr-lane selftest fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ]
}
JSON
    git add VERSION CHANGELOG.md scripts/example-release.sh scripts/manifest.json docs-manager
    git commit -q -m "base"
    git remote add origin "$REPO"
    git fetch -q origin main:refs/remotes/origin/main

    git checkout -q -b task/DP-999-T1-one
    printf '3.75.9\n' > VERSION
    printf 'release touch\n' > scripts/example-release.sh
    git add VERSION scripts/example-release.sh
    git commit -q -m "t1"

    git checkout -q -b task/DP-999-T2-two
    printf 't2\n' > t2.txt
    git add t2.txt
    git commit -q -m "t2"

    git checkout -q -b task/DP-999-T3-three
    printf 't3\n' > t3.txt
    git add t3.txt
    git commit -q -m "t3"

    git checkout -q main
    git checkout -q -b task/DP-999-TB-blocked
    printf 'blocked\n' > scripts/example-release.sh
    git add scripts/example-release.sh
    git commit -q -m "blocked"
    git checkout -q main
    git checkout -q -b codex/generic-publish
    printf '3.75.10\n' > VERSION
    printf 'generic\n' > scripts/example-release.sh
    git add VERSION scripts/example-release.sh
    git commit -q -m "generic"
    git checkout -q main
  )
}

cat > "$TMPDIR/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
STATE="${FRAMEWORK_PR_LANE_STATE:?}"

cmd="${1:-}"; shift || true
sub="${1:-}"; shift || true
if [[ "$cmd $sub" == "auth status" ]]; then
  exit 0
fi
[[ "$cmd $sub" == "pr view" || "$cmd $sub" == "pr edit" || "$cmd $sub" == "pr merge" ]] || {
  echo "unexpected gh command: $cmd $sub $*" >&2
  exit 2
}

if [[ "$cmd $sub" == "pr view" ]]; then
  branch="$1"
  awk -F '\t' -v branch="$branch" '
    $1 == branch {
      printf "{\"number\":%s,\"state\":\"%s\",\"baseRefName\":\"%s\",\"headRefName\":\"%s\",\"headRefOid\":\"%s\",\"mergeStateStatus\":\"CLEAN\",\"url\":\"%s\"}\n", $2, $3, $4, $1, $5, $6
      found=1
    }
    END { if (!found) exit 1 }
  ' "$STATE"
  exit 0
fi

if [[ "$cmd $sub" == "pr edit" ]]; then
  number="$1"; shift
  base=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="$2"; shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$base" ]] || exit 2
  python3 - "$STATE" "$number" "$base" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
number = sys.argv[2]
base = sys.argv[3]
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == number:
        parts[3] = base
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
  exit 0
fi

if [[ "$cmd $sub" == "pr merge" ]]; then
  number="$1"
  python3 - "$STATE" "$number" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
number = sys.argv[2]
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == number:
        parts[2] = "MERGED"
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
  exit 0
fi
SH
chmod +x "$TMPDIR/gh"

init_repo

TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks"
make_task "$TASK_DIR/T1.md" "DP-999-T1" "main" "main -> task/DP-999-T1-one" "task/DP-999-T1-one"
make_task "$TASK_DIR/T2.md" "DP-999-T2" "task/DP-999-T1-one" "main -> task/DP-999-T1-one -> task/DP-999-T2-two" "task/DP-999-T2-two"
make_task "$TASK_DIR/T3.md" "DP-999-T3" "task/DP-999-T2-two" "main -> task/DP-999-T1-one -> task/DP-999-T2-two -> task/DP-999-T3-three" "task/DP-999-T3-three"
make_task "$TASK_DIR/TB.md" "DP-999-TB" "main" "main -> task/DP-999-TB-blocked" "task/DP-999-TB-blocked"
make_task "$TASK_DIR/TG.md" "DP-999-TG" "main" "main -> codex/generic-publish" "codex/generic-publish"

if GH_BIN="$TMPDIR/missing-gh" bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" >/tmp/framework-pr-lane-missing-gh.out 2>&1; then
  echo "expected missing gh fixture to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_MISSING tool=gh" /tmp/framework-pr-lane-missing-gh.out

cat > "$TMPDIR/gh-unauth" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == "auth status" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "$TMPDIR/gh-unauth"
if GH_BIN="$TMPDIR/gh-unauth" bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" >/tmp/framework-pr-lane-unauth-gh.out 2>&1; then
  echo "expected unauth gh fixture to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_AUTH_FAILED tool=gh" /tmp/framework-pr-lane-unauth-gh.out

export GH_BIN="$TMPDIR/gh"
export FRAMEWORK_PR_LANE_STATE="$TMPDIR/pr-state.tsv"

write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >/tmp/framework-pr-lane-dryrun.out

write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" --execute >/tmp/framework-pr-lane-execute.out
awk -F '\t' '$2 == "2" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"
awk -F '\t' '$2 == "3" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"

write_state
python3 - "$FRAMEWORK_PR_LANE_STATE" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
rows = []
for line in path.read_text().splitlines():
    parts = line.split("\t")
    if parts[1] == "2":
        parts[3] = "main"
    rows.append("\t".join(parts))
path.write_text("\n".join(rows) + "\n")
PY
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >/tmp/framework-pr-lane-wrong-base.out 2>&1; then
  echo "expected wrong base fixture to fail" >&2
  exit 1
fi
grep -q "expected 'task/DP-999-T1-one'" /tmp/framework-pr-lane-wrong-base.out

cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-TB-blocked	9	OPEN	main	9999999999999999999999999999999999999999	https://example.test/pull/9
EOF
if env -u POLARIS_ALLOW_MISSING_VERSION_BUMP bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TB.md" >/tmp/framework-pr-lane-blocked.out 2>&1; then
  echo "expected missing VERSION bump fixture to fail" >&2
  exit 1
fi
grep -q "BLOCKED: release-preflight" /tmp/framework-pr-lane-blocked.out

POLARIS_ALLOW_MISSING_VERSION_BUMP=1 bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TB.md" >/tmp/framework-pr-lane-override.out 2>&1
grep -q "override accepted" /tmp/framework-pr-lane-override.out

cat > "$TMPDIR/pr-state.tsv" <<'EOF'
codex/generic-publish	10	OPEN	main	1010101010101010101010101010101010101010	https://example.test/pull/10
EOF
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TG.md" >/tmp/framework-pr-lane-generic.out 2>&1; then
  echo "expected generic publish branch fixture to fail" >&2
  exit 1
fi
grep -q "generic GitHub publish branches are not valid release inputs" /tmp/framework-pr-lane-generic.out

OVERLAY_REPO="$TMPDIR/overlay-repo"
git init -q -b main "$OVERLAY_REPO"
(
  cd "$OVERLAY_REPO"
  git config user.name "Polaris Selftest"
  git config user.email "polaris-selftest@example.com"
  cat > workspace-config.yaml <<'YAML'
language: zh-TW
YAML
  mkdir -p scripts
  cat > scripts/manifest.json <<'JSON'
{
  "version": 1,
  "scripts": []
}
JSON
  git add workspace-config.yaml scripts/manifest.json
  git commit -q -m "init"
  git remote add origin "$OVERLAY_REPO"
  git fetch -q origin main:refs/remotes/origin/main
  git checkout -q -b task/DP-999-T1-one main
  printf 't1\n' > t1.txt
  git add t1.txt
  git commit -q -m "t1"
  git checkout -q -b task/DP-999-T2-two main
  printf 't2\n' > t2.txt
  git add t2.txt
  git commit -q -m "t2"
  git checkout -q -b task/DP-999-T3-three main
  printf 't3\n' > t3.txt
  git add t3.txt
  git commit -q -m "t3"
  git checkout -q main
)

OVERLAY_TASK_DIR="$OVERLAY_REPO/docs-manager/src/content/docs/specs/design-plans/DP-999-fixture/tasks"
make_task "$OVERLAY_TASK_DIR/T1/index.md" "DP-999-T1" "main" "main -> task/DP-999-T1-one" "task/DP-999-T1-one"
make_task "$OVERLAY_TASK_DIR/T2/index.md" "DP-999-T2" "task/DP-999-T1-one" "main -> task/DP-999-T1-one -> task/DP-999-T2-two" "task/DP-999-T2-two"
make_task "$OVERLAY_TASK_DIR/T3/index.md" "DP-999-T3" "task/DP-999-T2-two" "main -> task/DP-999-T1-one -> task/DP-999-T2-two -> task/DP-999-T3-three" "task/DP-999-T3-three"

OVERLAY_WORKTREE="$TMPDIR/overlay-worktree"
git -C "$OVERLAY_REPO" worktree add -q "$OVERLAY_WORKTREE" HEAD
rm -rf "$OVERLAY_WORKTREE/docs-manager/src/content/docs/specs"

write_state
bash "$HELPER" \
  --repo "$OVERLAY_WORKTREE" \
  --terminal-task-md "$OVERLAY_TASK_DIR/T3/index.md" \
  >/tmp/framework-pr-lane-overlay.out 2>&1
if grep -q "no task.md matched" /tmp/framework-pr-lane-overlay.out; then
  echo "overlay release lane should resolve canonical task source without scan miss fallback" >&2
  cat /tmp/framework-pr-lane-overlay.out >&2
  exit 1
fi
grep -q "\[framework-release-pr-lane\] PASS" /tmp/framework-pr-lane-overlay.out

echo "[framework-release-pr-lane-selftest] PASS"
