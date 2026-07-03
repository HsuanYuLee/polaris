#!/usr/bin/env bash
# Purpose: exercise framework-release-pr-lane PR lineage, owner-aware release
# preflight, evidence freshness, and bundle fallback fixtures.
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
  local head="${6:-}"
  if [[ -z "$head" ]]; then
    head="$(default_head_for_branch "$branch")"
  fi
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
---
deliverable:
  pr_url: https://example.test/pull/1
  pr_state: OPEN
  head_sha: ${head}
  verification:
    status: PASS
    ac_counts:
      ac_total: 0
      ac_pass: 0
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---
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

default_head_for_branch() {
  case "$1" in
    task/DP-999-T1-one) printf '%s\n' "1111111111111111111111111111111111111111" ;;
    task/DP-999-T2-two) printf '%s\n' "2222222222222222222222222222222222222222" ;;
    task/DP-999-T3-three) printf '%s\n' "3333333333333333333333333333333333333333" ;;
    task/DP-999-TB-blocked) printf '%s\n' "9999999999999999999999999999999999999999" ;;
    codex/generic-publish) printf '%s\n' "1010101010101010101010101010101010101010" ;;
    *) printf '%s\n' "1111111111111111111111111111111111111111" ;;
  esac
}

set_task_deliverable_head() {
  local file="$1"
  local head="$2"
  python3 - "$file" "$head" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
head = sys.argv[2]
text = path.read_text(encoding="utf-8")
text = re.sub(r"(?m)^  head_sha: .*$", f"  head_sha: {head}", text, count=1)
path.write_text(text, encoding="utf-8")
PY
}

refresh_default_deliverables() {
  [[ -n "${TASK_DIR:-}" ]] || return 0
  [[ -f "$TASK_DIR/T1.md" ]] && set_task_deliverable_head "$TASK_DIR/T1.md" "1111111111111111111111111111111111111111"
  [[ -f "$TASK_DIR/T2.md" ]] && set_task_deliverable_head "$TASK_DIR/T2.md" "2222222222222222222222222222222222222222"
  [[ -f "$TASK_DIR/T3.md" ]] && set_task_deliverable_head "$TASK_DIR/T3.md" "3333333333333333333333333333333333333333"
  [[ -f "$TASK_DIR/T3-local-chain.md" ]] && set_task_deliverable_head "$TASK_DIR/T3-local-chain.md" "3333333333333333333333333333333333333333"
  [[ -f "$TASK_DIR/TB.md" ]] && set_task_deliverable_head "$TASK_DIR/TB.md" "9999999999999999999999999999999999999999"
  [[ -f "$TASK_DIR/TG.md" ]] && set_task_deliverable_head "$TASK_DIR/TG.md" "1010101010101010101010101010101010101010"
}

write_state() {
  cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-T1-one	1	OPEN	main	1111111111111111111111111111111111111111	https://example.test/pull/1
task/DP-999-T2-two	2	OPEN	task/DP-999-T1-one	2222222222222222222222222222222222222222	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	task/DP-999-T2-two	3333333333333333333333333333333333333333	https://example.test/pull/3
EOF
  refresh_default_deliverables
}

# DP-270: a bundle member task.md carries the shared bundle_branch_alias in
# YAML frontmatter while still keeping its own per-task Task branch in the table.
make_bundle_task() {
  local file="$1"
  local task_id="$2"
  local branch="$3"
  local alias="$4"
  local head
  case "$alias" in
    bundle-DP-998-v1.0.0) head="2020202020202020202020202020202020202020" ;;
    bundle-DP-998-novers) head="2121212121212121212121212121212121212121" ;;
    bundle-DP-997-vA|bundle-DP-997-vB) head="3030303030303030303030303030303030303030" ;;
    *) head="2020202020202020202020202020202020202020" ;;
  esac
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
---
bundle_branch_alias: ${alias}
deliverable:
  pr_url: https://example.test/pull/20
  pr_state: OPEN
  head_sha: ${head}
  verification:
    status: PASS
    ac_counts:
      ac_total: 0
      ac_pass: 0
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
---
# ${task_id}

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-998 |
| Task ID | ${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> ${branch} |
| Task branch | ${branch} |
| Depends on | N/A |
| References to load | - \`scripts/framework-release-pr-lane.sh\` |
MD
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

    # DP-270 bundle branch (with VERSION bump): all three bundle members point
    # at this single branch. AC3 version gate must PASS on the bundle branch.
    git checkout -q -b bundle-DP-998-v1.0.0 main
    printf '3.76.0\n' > VERSION
    printf 'bundle release touch\n' > scripts/example-release.sh
    git add VERSION scripts/example-release.sh
    git commit -q -m "bundle members"
    git checkout -q main

    # DP-270 bundle branch WITHOUT a VERSION bump but with a release-tooling
    # touch: AC3 version gate must FAIL (signal fires, no VERSION).
    git checkout -q -b bundle-DP-998-novers main
    printf 'bundle release touch no version\n' > scripts/example-release.sh
    git add scripts/example-release.sh
    git commit -q -m "bundle members no version"
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

if [[ "${FRAMEWORK_PR_LANE_REQUIRE_REPO_ARGS:-0}" == "1" ]]; then
  case " $* " in
    *" --repo demo/example "*) ;;
    *)
      echo "expected --repo demo/example for gh $cmd $sub: $*" >&2
      exit 2
      ;;
  esac
fi

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
  if [[ -n "${FRAMEWORK_PR_LANE_GH_LOG:-}" ]]; then
    printf 'merge\t%s\n' "$number" >> "$FRAMEWORK_PR_LANE_GH_LOG"
  fi
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
make_task "$TASK_DIR/T3-local-chain.md" "DP-999-T3" "task/DP-999-T2-two" "task/DP-999-T2-two -> task/DP-999-T3-three" "task/DP-999-T3-three"
make_task "$TASK_DIR/T1-feat-stack.md" "DP-999-T1" "feat/DP-999" "feat/DP-999 -> task/DP-999-T1-one" "task/DP-999-T1-one"
make_task "$TASK_DIR/T2-feat-stack.md" "DP-999-T2" "task/DP-999-T1-one" "feat/DP-999 -> task/DP-999-T1-one -> task/DP-999-T2-two" "task/DP-999-T2-two"
make_task "$TASK_DIR/T3-feat-stack.md" "DP-999-T3" "task/DP-999-T2-two" "feat/DP-999 -> task/DP-999-T1-one -> task/DP-999-T2-two -> task/DP-999-T3-three" "task/DP-999-T3-three"
make_task "$TASK_DIR/TB.md" "DP-999-TB" "main" "main -> task/DP-999-TB-blocked" "task/DP-999-TB-blocked"
make_task "$TASK_DIR/TG.md" "DP-999-TG" "main" "main -> codex/generic-publish" "codex/generic-publish"

if GH_BIN="$TMPDIR/missing-gh" bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" >"$TMPDIR"/missing-gh.out 2>&1; then
  echo "expected missing gh fixture to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_MISSING tool=gh" "$TMPDIR"/missing-gh.out

cat > "$TMPDIR/gh-unauth" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-} ${2:-}" == "auth status" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "$TMPDIR/gh-unauth"
if GH_BIN="$TMPDIR/gh-unauth" bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" >"$TMPDIR"/unauth-gh.out 2>&1; then
  echo "expected unauth gh fixture to fail" >&2
  exit 1
fi
grep -q "POLARIS_TOOL_AUTH_FAILED tool=gh" "$TMPDIR"/unauth-gh.out

export GH_BIN="$TMPDIR/gh"
export FRAMEWORK_PR_LANE_STATE="$TMPDIR/pr-state.tsv"

write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/dryrun.out
write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/default-route.out 2>&1
grep -q "upstream evidence fresh: stage=R2-R6" "$TMPDIR"/default-route.out \
  || { echo "DP-386 T1: default lane must check upstream evidence freshness" >&2; cat "$TMPDIR"/default-route.out >&2; exit 1; }
grep -q "skipping upstream-owned release preflight backstop stages by default" "$TMPDIR"/default-route.out \
  || { echo "DP-386 T1: default lane must declare upstream backstop skip" >&2; cat "$TMPDIR"/default-route.out >&2; exit 1; }
if grep -qE "running governed script test suite|running aggregate selftest corpus|running script header release gate|running script categorization release gate" "$TMPDIR"/default-route.out; then
  echo "DP-386 T1: default lane must not rerun upstream-owned backstop gates" >&2
  cat "$TMPDIR"/default-route.out >&2
  exit 1
fi

write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" --full-backstop >"$TMPDIR"/full-backstop.out 2>&1 || {
  echo "DP-386 T1: --full-backstop fixture must pass" >&2
  cat "$TMPDIR"/full-backstop.out >&2
  exit 1
}
grep -q "running explicit --full-backstop upstream-owned release preflight stages" "$TMPDIR"/full-backstop.out \
  || { echo "DP-386 T1: --full-backstop must announce explicit upstream run" >&2; cat "$TMPDIR"/full-backstop.out >&2; exit 1; }
grep -q "running governed script test suite" "$TMPDIR"/full-backstop.out \
  || { echo "DP-386 T1: --full-backstop must run governed script tests" >&2; cat "$TMPDIR"/full-backstop.out >&2; exit 1; }

write_state
set_task_deliverable_head "$TASK_DIR/T2.md" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/stale-evidence.out 2>&1; then
  echo "DP-386 T1: stale upstream evidence must fail release preflight" >&2
  cat "$TMPDIR"/stale-evidence.out >&2
  exit 1
fi
grep -q "stage=R2-R6" "$TMPDIR"/stale-evidence.out \
  || { echo "DP-386 T1: stale evidence failure must name stage" >&2; cat "$TMPDIR"/stale-evidence.out >&2; exit 1; }
grep -q "owner=upstream:engineering-completion" "$TMPDIR"/stale-evidence.out \
  || { echo "DP-386 T1: stale evidence failure must name owner" >&2; cat "$TMPDIR"/stale-evidence.out >&2; exit 1; }
grep -q "route_back=engineering" "$TMPDIR"/stale-evidence.out \
  || { echo "DP-386 T1: stale evidence failure must name route_back" >&2; cat "$TMPDIR"/stale-evidence.out >&2; exit 1; }
grep -q "evidence_status=stale" "$TMPDIR"/stale-evidence.out \
  || { echo "DP-386 T1: stale evidence failure must name evidence_status" >&2; cat "$TMPDIR"/stale-evidence.out >&2; exit 1; }
if grep -q "running aggregate selftest corpus" "$TMPDIR"/stale-evidence.out; then
  echo "DP-386 T1: stale evidence must route back before full corpus can mask it" >&2
  cat "$TMPDIR"/stale-evidence.out >&2
  exit 1
fi

write_state
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" --execute >"$TMPDIR"/execute.out
awk -F '\t' '$2 == "2" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"
awk -F '\t' '$2 == "3" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"

# DP-384: terminal-task mode must recover the full upstream stack from Base
# branch links even when the terminal task's Branch chain only names its direct
# predecessor. It must also pass --repo through every gh view/edit/merge call.
write_state
FRAMEWORK_PR_LANE_REQUIRE_REPO_ARGS=1 \
  bash "$HELPER" --repo "$REPO" --workspace-repo demo/example \
    --terminal-task-md "$TASK_DIR/T3-local-chain.md" --execute \
    >"$TMPDIR"/terminal-stack-execute.out 2>&1 || {
      echo "DP-384: expected terminal stacked chain execute fixture to PASS" >&2
      cat "$TMPDIR"/terminal-stack-execute.out >&2
      exit 1
    }
awk -F '\t' '$2 == "1" && $3 == "MERGED" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"
awk -F '\t' '$2 == "2" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"
awk -F '\t' '$2 == "3" && $3 == "MERGED" && $4 == "main" { ok=1 } END { exit ok ? 0 : 1 }' "$FRAMEWORK_PR_LANE_STATE"

# DP-398: terminal-task feat stack mode must integrate task PR heads by
# fast-forwarding feat/DP-NNN only. It must not retarget downstream PRs and must
# not call gh pr merge, because GitHub merge commits pollute the release head and
# framework-release-main-promotion.sh rejects them.
T1_SHA="$(git -C "$REPO" rev-parse task/DP-999-T1-one)"
T2_SHA="$(git -C "$REPO" rev-parse task/DP-999-T2-two)"
T3_SHA="$(git -C "$REPO" rev-parse task/DP-999-T3-three)"
set_task_deliverable_head "$TASK_DIR/T1.md" "$T1_SHA"
set_task_deliverable_head "$TASK_DIR/T2.md" "$T2_SHA"
set_task_deliverable_head "$TASK_DIR/T3.md" "$T3_SHA"
set_task_deliverable_head "$TASK_DIR/T1-feat-stack.md" "$T1_SHA"
set_task_deliverable_head "$TASK_DIR/T2-feat-stack.md" "$T2_SHA"
set_task_deliverable_head "$TASK_DIR/T3-feat-stack.md" "$T3_SHA"
git -C "$REPO" branch -f feat/DP-999 main
git -C "$REPO" fetch -q origin +refs/heads/feat/DP-999:refs/remotes/origin/feat/DP-999
cat > "$TMPDIR/pr-state.tsv" <<EOF
task/DP-999-T1-one	1	OPEN	feat/DP-999	${T1_SHA}	https://example.test/pull/1
task/DP-999-T2-two	2	OPEN	task/DP-999-T1-one	${T2_SHA}	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	task/DP-999-T2-two	${T3_SHA}	https://example.test/pull/3
EOF
: > "$TMPDIR/feat-stack-gh.log"
FRAMEWORK_PR_LANE_GH_LOG="$TMPDIR/feat-stack-gh.log" \
  bash "$HELPER" --repo "$REPO" \
    --main feat/DP-999 \
    --task-md "$TASK_DIR/T1-feat-stack.md" \
    --task-md "$TASK_DIR/T2-feat-stack.md" \
    --task-md "$TASK_DIR/T3-feat-stack.md" \
    --execute \
    >"$TMPDIR"/feat-stack-linear-execute.out 2>&1 || {
      echo "DP-398: expected feat stack linear execute fixture to PASS" >&2
      cat "$TMPDIR"/feat-stack-linear-execute.out >&2
      exit 1
    }
[[ "$(git -C "$REPO" rev-parse feat/DP-999)" == "$T3_SHA" ]] \
  || { echo "DP-398: feat aggregation branch did not end at terminal task head" >&2; cat "$TMPDIR"/feat-stack-linear-execute.out >&2; exit 1; }
for upstream in "$T1_SHA" "$T2_SHA"; do
  git -C "$REPO" merge-base --is-ancestor "$upstream" "$T3_SHA" \
    || { echo "DP-398: terminal task head lost upstream ancestry $upstream" >&2; exit 1; }
done
if git -C "$REPO" log --oneline --merges main..feat/DP-999 | grep -q .; then
  echo "DP-398: feat stack execute must not create merge commits" >&2
  git -C "$REPO" log --oneline --graph --decorate main..feat/DP-999 >&2
  exit 1
fi
if grep -q '^merge' "$TMPDIR/feat-stack-gh.log"; then
  echo "DP-398: feat stack execute must not call gh pr merge" >&2
  cat "$TMPDIR/feat-stack-gh.log" >&2
  cat "$TMPDIR"/feat-stack-linear-execute.out >&2
  exit 1
fi
grep -q "fast-forwarding feat/DP-999" "$TMPDIR"/feat-stack-linear-execute.out \
  || { echo "DP-398: expected feat stack fast-forward trace" >&2; cat "$TMPDIR"/feat-stack-linear-execute.out >&2; exit 1; }

# DP-398 negative fixture: a feat branch already polluted with merge commits must
# fail before version compression, even if task heads remain reachable.
git -C "$REPO" branch -f feat/DP-999 "$T1_SHA"
git -C "$REPO" checkout -q feat/DP-999
git -C "$REPO" merge --no-ff -q "$T2_SHA" -m "Merge pull request #2 from task/DP-999-T2-two"
git -C "$REPO" checkout -q main
git -C "$REPO" fetch -q origin +refs/heads/feat/DP-999:refs/remotes/origin/feat/DP-999
cat > "$TMPDIR/pr-state.tsv" <<EOF
task/DP-999-T1-one	1	MERGED	feat/DP-999	${T1_SHA}	https://example.test/pull/1
task/DP-999-T2-two	2	MERGED	feat/DP-999	${T2_SHA}	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	task/DP-999-T2-two	${T3_SHA}	https://example.test/pull/3
EOF
if bash "$HELPER" --repo "$REPO" \
    --main feat/DP-999 \
    --task-md "$TASK_DIR/T1-feat-stack.md" \
    --task-md "$TASK_DIR/T2-feat-stack.md" \
    --task-md "$TASK_DIR/T3-feat-stack.md" \
    >"$TMPDIR"/feat-stack-polluted.out 2>&1; then
  echo "DP-398: polluted feat branch fixture must fail" >&2
  cat "$TMPDIR"/feat-stack-polluted.out >&2
  exit 1
fi
grep -q "contains merge commits in its release range" "$TMPDIR"/feat-stack-polluted.out \
  || { echo "DP-398: polluted feat failure must name merge commits" >&2; cat "$TMPDIR"/feat-stack-polluted.out >&2; exit 1; }

# DP-334 feature-branch release model: task PRs may already be merged into a
# feat/DP-NNN aggregation branch. The release lane validates that state and must
# not require historical task PR metadata to be retargeted to main; the later
# framework-release step opens the single feat/DP-NNN -> main PR.
refresh_default_deliverables
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-T1-one	1	MERGED	feat/DP-999	1111111111111111111111111111111111111111	https://example.test/pull/1
task/DP-999-T2-two	2	MERGED	feat/DP-999	2222222222222222222222222222222222222222	https://example.test/pull/2
task/DP-999-T3-three	3	MERGED	feat/DP-999	3333333333333333333333333333333333333333	https://example.test/pull/3
EOF
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/feat-aggregation.out 2>&1 || {
  echo "DP-334: expected merged feat aggregation fixture to PASS" >&2
  cat "$TMPDIR"/feat-aggregation.out >&2
  exit 1
}
grep -q "already merged into feat/DP-999" "$TMPDIR"/feat-aggregation.out \
  || { echo "DP-334: expected feat aggregation action in plan" >&2; cat "$TMPDIR"/feat-aggregation.out >&2; exit 1; }
grep -q "\[framework-release-pr-lane\] PASS" "$TMPDIR"/feat-aggregation.out

# New feat aggregation task PRs are integrated by fast-forwarding the aggregation
# branch to the validated task head, preserving the evidence-bound task commit
# SHA and avoiding inner "Merge pull request #..." noise before the single
# feat/DP-NNN -> main release merge.
T1_SHA="$(git -C "$REPO" rev-parse task/DP-999-T1-one)"
T2_SHA="$(git -C "$REPO" rev-parse task/DP-999-T2-two)"
T3_SHA="$(git -C "$REPO" rev-parse task/DP-999-T3-three)"
set_task_deliverable_head "$TASK_DIR/T1.md" "$T1_SHA"
set_task_deliverable_head "$TASK_DIR/T2.md" "$T2_SHA"
set_task_deliverable_head "$TASK_DIR/T3.md" "$T3_SHA"
git -C "$REPO" branch -f feat/DP-999 main
git -C "$REPO" fetch -q origin +refs/heads/feat/DP-999:refs/remotes/origin/feat/DP-999
cat > "$TMPDIR/pr-state.tsv" <<EOF
task/DP-999-T1-one	1	OPEN	feat/DP-999	${T1_SHA}	https://example.test/pull/1
task/DP-999-T2-two	2	OPEN	feat/DP-999	${T2_SHA}	https://example.test/pull/2
task/DP-999-T3-three	3	OPEN	feat/DP-999	${T3_SHA}	https://example.test/pull/3
EOF
bash "$HELPER" --repo "$REPO" \
  --task-md "$TASK_DIR/T1.md" \
  --task-md "$TASK_DIR/T2.md" \
  --task-md "$TASK_DIR/T3.md" \
  --execute >"$TMPDIR"/feat-aggregation-ff.out 2>&1 || {
    echo "DP-334: expected feat aggregation fast-forward execute fixture to PASS" >&2
    cat "$TMPDIR"/feat-aggregation-ff.out >&2
    exit 1
  }
[[ "$(git -C "$REPO" rev-parse feat/DP-999)" == "$T3_SHA" ]] \
  || { echo "DP-334: feat aggregation branch did not fast-forward to terminal task head" >&2; cat "$TMPDIR"/feat-aggregation-ff.out >&2; exit 1; }
if git -C "$REPO" log --oneline --merges main..feat/DP-999 | grep -q .; then
  echo "DP-334: feat aggregation fast-forward path must not create inner merge commits" >&2
  git -C "$REPO" log --oneline --graph --decorate main..feat/DP-999 >&2
  exit 1
fi
grep -q "fast-forwarding feat/DP-999" "$TMPDIR"/feat-aggregation-ff.out \
  || { echo "DP-334: expected fast-forward execution trace" >&2; cat "$TMPDIR"/feat-aggregation-ff.out >&2; exit 1; }

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
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/wrong-base.out 2>&1; then
  echo "expected wrong base fixture to fail" >&2
  exit 1
fi
grep -q "expected 'task/DP-999-T1-one'" "$TMPDIR"/wrong-base.out

# DP-295 T6 (AC5): the lane no longer runs a pre-merge VERSION-bump gate.
# The single-task TB fixture (release-tooling touch WITHOUT a VERSION bump) used
# to be BLOCKED by the version-bump gate; under the changeset-driven model the
# version rides the verified PR HEAD (mise run release:version), so the lane must
# now PASS this fixture on lineage + script-governance gates alone.
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-TB-blocked	9	OPEN	main	9999999999999999999999999999999999999999	https://example.test/pull/9
EOF
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TB.md" >"$TMPDIR"/no-version-gate.out 2>&1 || {
  echo "AC5: lane must PASS a no-VERSION-bump fixture (version-bump gate removed)" >&2
  cat "$TMPDIR"/no-version-gate.out >&2; exit 1; }
grep -q "\[framework-release-pr-lane\] PASS" "$TMPDIR"/no-version-gate.out \
  || { echo "AC5: expected PASS on no-VERSION fixture" >&2; cat "$TMPDIR"/no-version-gate.out >&2; exit 1; }
# AC5: the removed gate must NOT have run.
if grep -qiE "version-bump release gate|BLOCKED: release-preflight|missing required VERSION bump" "$TMPDIR"/no-version-gate.out; then
  echo "AC5: version-bump bounce-back gate still firing in the lane" >&2
  cat "$TMPDIR"/no-version-gate.out >&2; exit 1
fi

cat > "$TMPDIR/pr-state.tsv" <<'EOF'
codex/generic-publish	10	OPEN	main	1010101010101010101010101010101010101010	https://example.test/pull/10
EOF
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TG.md" >"$TMPDIR"/generic.out 2>&1; then
  echo "expected generic publish branch fixture to fail" >&2
  exit 1
fi
grep -q "generic GitHub publish branches are not valid release inputs" "$TMPDIR"/generic.out

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
  >"$TMPDIR"/overlay.out 2>&1 || {
    echo "overlay release lane should PASS when task source is outside release worktree" >&2
    cat "$TMPDIR"/overlay.out >&2
    exit 1
  }
if grep -q "no task.md matched" "$TMPDIR"/overlay.out; then
  echo "overlay release lane should resolve canonical task source without scan miss fallback" >&2
  cat "$TMPDIR"/overlay.out >&2
  exit 1
fi
grep -q "\[framework-release-pr-lane\] PASS" "$TMPDIR"/overlay.out

# ---------------------------------------------------------------------------
# DP-270 bundle lane fixtures
# ---------------------------------------------------------------------------
BUNDLE_TASK_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-998-bundle-fixture/tasks"
BUNDLE_ALIAS="bundle-DP-998-v1.0.0"
make_bundle_task "$BUNDLE_TASK_DIR/T1/index.md" "DP-998-T1" "task/DP-998-T1-one" "$BUNDLE_ALIAS"
make_bundle_task "$BUNDLE_TASK_DIR/T2/index.md" "DP-998-T2" "task/DP-998-T2-two" "$BUNDLE_ALIAS"
make_bundle_task "$BUNDLE_TASK_DIR/T3/index.md" "DP-998-T3" "task/DP-998-T3-three" "$BUNDLE_ALIAS"

# AC1 / D2: three members sharing one alias + a single bundle PR (head=alias).
cat > "$TMPDIR/pr-state.tsv" <<EOF
${BUNDLE_ALIAS}	20	OPEN	main	2020202020202020202020202020202020202020	https://example.test/pull/20
EOF
bash "$HELPER" --repo "$REPO" \
  --task-md "$BUNDLE_TASK_DIR/T1/index.md" \
  --task-md "$BUNDLE_TASK_DIR/T2/index.md" \
  --task-md "$BUNDLE_TASK_DIR/T3/index.md" \
  >"$TMPDIR"/bundle.out 2>&1 || {
    echo "expected bundle fixture to PASS" >&2; cat "$TMPDIR"/bundle.out >&2; exit 1; }
grep -q "release lane plan (bundle ${BUNDLE_ALIAS})" "$TMPDIR"/bundle.out \
  || { echo "AC1: bundle plan header missing" >&2; cat "$TMPDIR"/bundle.out >&2; exit 1; }
# AC1: exactly one merge planned for the whole bundle (single "=> bundle PR" line).
bundle_merge_lines="$(grep -c "=> bundle PR #20 .* action=merge into main" "$TMPDIR"/bundle.out || true)"
[[ "$bundle_merge_lines" == "1" ]] \
  || { echo "AC1: expected exactly 1 bundle merge plan line, got $bundle_merge_lines" >&2; cat "$TMPDIR"/bundle.out >&2; exit 1; }
# AC1 adversarial: all 3 members verified (not just the first resolver line).
for m in DP-998-T1 DP-998-T2 DP-998-T3; do
  grep -Eq "member ${m} .*verified against bundle PR #20" "$TMPDIR"/bundle.out \
    || { echo "AC1: bundle member $m not verified" >&2; cat "$TMPDIR"/bundle.out >&2; exit 1; }
done
# AC1: single-merge semantics — there must be NO per-task merge plan lines.
if grep -qE '^\s+- DP-998-T[0-9]+ PR #' "$TMPDIR"/bundle.out; then
  echo "AC1: bundle path leaked per-task merge plan lines" >&2; cat "$TMPDIR"/bundle.out >&2; exit 1
fi
grep -q "\[framework-release-pr-lane\] PASS" "$TMPDIR"/bundle.out

# AC-NEG1: per-task regression — the unchanged per-task dry-run plan (stdout)
# must be byte-identical to the original dry-run plan captured before any
# bundle classification ran, and must contain no bundle text.
write_state
bash "$HELPER" --repo "$REPO" \
  --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" \
  >"$TMPDIR"/pertask-regression.out 2>/dev/null
if grep -qi "bundle" "$TMPDIR"/pertask-regression.out; then
  echo "AC-NEG1: per-task plan leaked bundle text" >&2; cat "$TMPDIR"/pertask-regression.out >&2; exit 1
fi
# AC-NEG1 byte-equivalence: per-task plan (stdout) identical to the original
# dry-run plan (also stdout-only at "$TMPDIR"/dryrun.out).
if ! diff -q "$TMPDIR"/dryrun.out "$TMPDIR"/pertask-regression.out >/dev/null; then
  echo "AC-NEG1: per-task plan diverged from pre-change dry-run plan" >&2
  diff "$TMPDIR"/dryrun.out "$TMPDIR"/pertask-regression.out >&2 || true
  exit 1
fi

# DP-295 T6 (AC5): the bundle path no longer runs a version-bump gate either.
# The no-VERSION bundle branch (release-tooling touch without a VERSION bump) used
# to FAIL the version-bump gate; under the changeset-driven model it must now PASS
# on lineage + script-governance gates alone.
# Member dirs use a `T*` basename so resolve-task-md-by-branch.sh's tasks/T* glob
# resolves the bundle members (the lane now reaches lineage resolution because the
# version-bump gate no longer short-circuits first).
make_bundle_task "$BUNDLE_TASK_DIR/T8/index.md" "DP-998-T8" "task/DP-998-T8-one" "bundle-DP-998-novers"
make_bundle_task "$BUNDLE_TASK_DIR/T9/index.md" "DP-998-T9" "task/DP-998-T9-two" "bundle-DP-998-novers"
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
bundle-DP-998-novers	21	OPEN	main	2121212121212121212121212121212121212121	https://example.test/pull/21
EOF
bash "$HELPER" --repo "$REPO" \
    --task-md "$BUNDLE_TASK_DIR/T8/index.md" \
    --task-md "$BUNDLE_TASK_DIR/T9/index.md" \
    >"$TMPDIR"/bundle-noversion.out 2>&1 || {
  echo "AC5: expected bundle no-VERSION fixture to PASS (version-bump gate removed)" >&2
  cat "$TMPDIR"/bundle-noversion.out >&2; exit 1; }
grep -q "\[framework-release-pr-lane\] PASS" "$TMPDIR"/bundle-noversion.out \
  || { echo "AC5: expected PASS on no-VERSION bundle" >&2; cat "$TMPDIR"/bundle-noversion.out >&2; exit 1; }
# AC5: the removed version-bump gate must NOT have run on the bundle branch.
if grep -qiE "version-bump release gate|BLOCKED: release-preflight" "$TMPDIR"/bundle-noversion.out; then
  echo "AC5: version-bump gate still firing on the bundle branch" >&2
  cat "$TMPDIR"/bundle-noversion.out >&2; exit 1
fi

# AC-NEG2 (a): a declared bundle whose alias branch has NO PR → fail-closed.
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-998-T1-one	1	OPEN	main	1111111111111111111111111111111111111111	https://example.test/pull/1
EOF
if bash "$HELPER" --repo "$REPO" \
    --task-md "$BUNDLE_TASK_DIR/T1/index.md" \
    --task-md "$BUNDLE_TASK_DIR/T2/index.md" \
    --task-md "$BUNDLE_TASK_DIR/T3/index.md" \
    >"$TMPDIR"/bundle-nopr.out 2>&1; then
  echo "AC-NEG2(a): expected bundle-with-no-PR fixture to FAIL" >&2
  cat "$TMPDIR"/bundle-nopr.out >&2; exit 1
fi
grep -q "has no open PR" "$TMPDIR"/bundle-nopr.out \
  || { echo "AC-NEG2(a): expected 'has no open PR' fail-closed reason" >&2; cat "$TMPDIR"/bundle-nopr.out >&2; exit 1; }
# fail-closed must plan NO partial merge.
if grep -q "=> bundle PR" "$TMPDIR"/bundle-nopr.out; then
  echo "AC-NEG2(a): planned a merge despite missing bundle PR" >&2; cat "$TMPDIR"/bundle-nopr.out >&2; exit 1
fi

# AC-NEG2 (b): members declaring inconsistent bundle_branch_alias → fail-closed.
INCONSISTENT_DIR="$REPO/docs-manager/src/content/docs/specs/design-plans/DP-997-inconsistent/tasks"
make_bundle_task "$INCONSISTENT_DIR/T1/index.md" "DP-997-T1" "task/DP-997-T1-one" "bundle-DP-997-vA"
make_bundle_task "$INCONSISTENT_DIR/T2/index.md" "DP-997-T2" "task/DP-997-T2-two" "bundle-DP-997-vB"
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
bundle-DP-997-vA	30	OPEN	main	3030303030303030303030303030303030303030	https://example.test/pull/30
EOF
if bash "$HELPER" --repo "$REPO" \
    --task-md "$INCONSISTENT_DIR/T1/index.md" \
    --task-md "$INCONSISTENT_DIR/T2/index.md" \
    >"$TMPDIR"/bundle-inconsistent.out 2>&1; then
  echo "AC-NEG2(b): expected inconsistent-alias fixture to FAIL" >&2
  cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1
fi
grep -q "inconsistent bundle_branch_alias" "$TMPDIR"/bundle-inconsistent.out \
  || { echo "AC-NEG2(b): expected inconsistent alias fail-closed reason" >&2; cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1; }
if grep -q "=> bundle PR" "$TMPDIR"/bundle-inconsistent.out; then
  echo "AC-NEG2(b): planned a merge despite inconsistent aliases" >&2; cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1
fi

# ---------------------------------------------------------------------------
# DP-295 T6 (AC5 / AC-NEG2 / AC-NEG5): version bounce-back fully removed.
# The lane source must no longer carry the pre-merge VERSION-bump gate, the
# post-merge release-metadata defer flag, or the version-bump checker wiring.
# Version/CHANGELOG now ride the verified PR HEAD (changeset-driven, T1-T5).
# ---------------------------------------------------------------------------
if grep -nE 'DEFER_VERSION_BUMP_TO_METADATA|defer-version-bump-to-release-metadata|run_version_bump_release_gate|VERSION_BUMP_CHECKER|check-version-bump-reminder' "$HELPER" >/dev/null; then
  echo "AC5: framework-release-pr-lane.sh still references the removed version-bump bounce-back mechanism" >&2
  grep -nE 'DEFER_VERSION_BUMP_TO_METADATA|defer-version-bump-to-release-metadata|run_version_bump_release_gate|VERSION_BUMP_CHECKER|check-version-bump-reminder' "$HELPER" >&2
  exit 1
fi
# AC5: the lane must point at the changeset-driven version path (release:version).
grep -qE 'release:version|release-version' "$HELPER" \
  || { echo "AC5: lane does not reference the changeset-driven release:version path" >&2; exit 1; }

echo "[framework-release-pr-lane-selftest] PASS"
