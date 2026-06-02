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

# DP-270: a bundle member task.md carries the shared bundle_branch_alias in
# YAML frontmatter while still keeping its own per-task Task branch in the table.
make_bundle_task() {
  local file="$1"
  local task_id="$2"
  local branch="$3"
  local alias="$4"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<MD
---
bundle_branch_alias: ${alias}
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
bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" --execute >"$TMPDIR"/execute.out
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
if bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/T1.md" --task-md "$TASK_DIR/T2.md" --task-md "$TASK_DIR/T3.md" >"$TMPDIR"/wrong-base.out 2>&1; then
  echo "expected wrong base fixture to fail" >&2
  exit 1
fi
grep -q "expected 'task/DP-999-T1-one'" "$TMPDIR"/wrong-base.out

cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-999-TB-blocked	9	OPEN	main	9999999999999999999999999999999999999999	https://example.test/pull/9
EOF
if env -u POLARIS_ALLOW_MISSING_VERSION_BUMP bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TB.md" >"$TMPDIR"/blocked.out 2>&1; then
  echo "expected missing VERSION bump fixture to fail" >&2
  exit 1
fi
grep -q "BLOCKED: release-preflight" "$TMPDIR"/blocked.out

POLARIS_ALLOW_MISSING_VERSION_BUMP=1 bash "$HELPER" --repo "$REPO" --task-md "$TASK_DIR/TB.md" >"$TMPDIR"/override.out 2>&1
grep -q "override accepted" "$TMPDIR"/override.out

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
  >"$TMPDIR"/overlay.out 2>&1
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

# AC3: version gate runs on the bundle branch. The no-VERSION bundle branch
# fires the version-bump signal without a VERSION bump → FAIL.
make_bundle_task "$BUNDLE_TASK_DIR/NV1/index.md" "DP-998-NV1" "task/DP-998-NV1-one" "bundle-DP-998-novers"
make_bundle_task "$BUNDLE_TASK_DIR/NV2/index.md" "DP-998-NV2" "task/DP-998-NV2-two" "bundle-DP-998-novers"
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
bundle-DP-998-novers	21	OPEN	main	2121212121212121212121212121212121212121	https://example.test/pull/21
EOF
if env -u POLARIS_ALLOW_MISSING_VERSION_BUMP bash "$HELPER" --repo "$REPO" \
    --task-md "$BUNDLE_TASK_DIR/NV1/index.md" \
    --task-md "$BUNDLE_TASK_DIR/NV2/index.md" \
    >"$TMPDIR"/bundle-noversion.out 2>&1; then
  echo "AC3: expected bundle missing-VERSION fixture to FAIL" >&2
  cat "$TMPDIR"/bundle-noversion.out >&2; exit 1
fi
grep -q "BLOCKED: release-preflight" "$TMPDIR"/bundle-noversion.out \
  || { echo "AC3: expected release-preflight block on bundle branch" >&2; cat "$TMPDIR"/bundle-noversion.out >&2; exit 1; }
# AC3: the gate must have evaluated the BUNDLE branch, not a per-task branch.
grep -q "version-bump release gate on bundle-DP-998-novers" "$TMPDIR"/bundle-noversion.out \
  || { echo "AC3: version gate did not target the bundle branch" >&2; cat "$TMPDIR"/bundle-noversion.out >&2; exit 1; }

# AC-NEG2 (a): a declared bundle whose alias branch has NO PR → fail-closed.
cat > "$TMPDIR/pr-state.tsv" <<'EOF'
task/DP-998-T1-one	1	OPEN	main	1111111111111111111111111111111111111111	https://example.test/pull/1
EOF
if bash "$HELPER" --repo "$REPO" \
    --task-md "$BUNDLE_TASK_DIR/T1/index.md" \
    --task-md "$BUNDLE_TASK_DIR/T2/index.md" \
    --task-md "$BUNDLE_TASK_DIR/T3/index.md" \
    --defer-version-bump-to-release-metadata \
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
    --defer-version-bump-to-release-metadata \
    >"$TMPDIR"/bundle-inconsistent.out 2>&1; then
  echo "AC-NEG2(b): expected inconsistent-alias fixture to FAIL" >&2
  cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1
fi
grep -q "inconsistent bundle_branch_alias" "$TMPDIR"/bundle-inconsistent.out \
  || { echo "AC-NEG2(b): expected inconsistent alias fail-closed reason" >&2; cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1; }
if grep -q "=> bundle PR" "$TMPDIR"/bundle-inconsistent.out; then
  echo "AC-NEG2(b): planned a merge despite inconsistent aliases" >&2; cat "$TMPDIR"/bundle-inconsistent.out >&2; exit 1
fi

echo "[framework-release-pr-lane-selftest] PASS"
