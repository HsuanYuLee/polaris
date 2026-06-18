#!/usr/bin/env bash
set -euo pipefail

# Purpose: Selftest for scripts/gates/gate-pr-title.sh — verifies that the
#          aggregate-release branch lane (FD6, DP-301-T3) accepts the bundle
#          title format `chore(release): bundle DP-NNN -> vX.Y.Z` WITHOUT the
#          POLARIS_SKIP_PR_TITLE_GATE bypass, while the non-aggregate developer
#          title contract stays unchanged (relaxation scoped to aggregate-release
#          only). Aggregate-release detection shares the same source as DP-287
#          gate-work-source: the task.md `bundle_branch_alias` frontmatter field
#          matched against the current branch.
# Inputs:  none (builds a throwaway git repo + task.md fixtures in mktemp).
# Outputs: stdout PASS line; exit 0 = all assertions pass, 1 = a case failed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-pr-title.sh"
TMPDIR="$(mktemp -d -t gate-pr-title.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
  echo "[gate-pr-title-selftest] FAIL: $*" >&2
  exit 1
}

# assert_pass <label> <expected-stderr-substring> -- <command...>
assert_pass() {
  local label="$1"; shift
  local needle="$1"; shift
  [[ "$1" == "--" ]] && shift
  local out="" rc=0
  out="$("$@" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || { echo "$out" >&2; fail "$label expected exit 0, got $rc"; }
  if [[ -n "$needle" ]]; then
    grep -q "$needle" <<<"$out" || { echo "$out" >&2; fail "$label expected stderr to contain '$needle'"; }
  fi
}

# assert_block <label> <expected-stderr-substring> -- <command...>
assert_block() {
  local label="$1"; shift
  local needle="$1"; shift
  [[ "$1" == "--" ]] && shift
  local out="" rc=0
  out="$("$@" 2>&1)" || rc=$?
  [[ "$rc" -eq 2 ]] || { echo "$out" >&2; fail "$label expected exit 2, got $rc"; }
  if [[ -n "$needle" ]]; then
    grep -q "$needle" <<<"$out" || { echo "$out" >&2; fail "$label expected stderr to contain '$needle'"; }
  fi
}

# write_task_md <task_md_path> <task_id> <task_branch> [bundle_branch_alias]
# Produces a minimal canonical task.md whose Operational Context binds the
# delivery_ticket_key (= Task ID, e.g. DP-999-T1) + summary. The H1 uses the
# canonical `# T{n}: {summary} ({SP} pt)` shape parse-task-md requires for the
# summary field. When the fourth arg is supplied, a `bundle_branch_alias:`
# frontmatter line is written (aggregate-release mark).
write_task_md() {
  local task_md="$1"
  local task_id="$2"
  local task_branch="$3"
  local bundle_alias="${4:-}"
  local short_tn="${task_id##*-}"
  mkdir -p "$(dirname "$task_md")"
  {
    echo "---"
    if [[ -n "$bundle_alias" ]]; then
      echo "bundle_branch_alias: $bundle_alias"
    fi
    echo "title: \"Work Order - ${short_tn}: fixture for gate-pr-title selftest (1 pt)\""
    echo "description: \"Fixture task for gate-pr-title selftest.\""
    echo "depends_on: []"
    echo "status: READY"
    echo "---"
    echo ""
    echo "# ${short_tn}: fixture for gate-pr-title selftest (1 pt)"
    echo ""
    echo "> Source: DP-999 | Task: ${task_id} | JIRA: N/A | Repo: fixture"
    echo ""
    echo "## Operational Context"
    echo ""
    echo "| 欄位 | 值 |"
    echo "|------|-----|"
    echo "| Source type | dp |"
    echo "| Source ID | DP-999 |"
    echo "| Task ID | ${task_id} |"
    echo "| JIRA key | N/A |"
    echo "| Base branch | main |"
    echo "| Branch chain | main -> ${task_branch} |"
    echo "| Task branch | ${task_branch} |"
    echo "| Depends on | N/A |"
  } > "$task_md"
}

# Build a throwaway git repo. Aggregate-release detection (shared with DP-287
# gate-work-source) compares the task.md `bundle_branch_alias` frontmatter
# against the repo's current branch, so the repo must be checked out on the
# relevant branch per case.
REPO="$TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email selftest@example.test
git -C "$REPO" config user.name "Self Test"
echo "fixture" > "$REPO/README.md"
git -C "$REPO" add .
git -C "$REPO" commit -q -m init

BUNDLE_BRANCH="bundle-DP-999-v9.9.9"
TASK_BRANCH="task/DP-999-T1-fixture"
git -C "$REPO" branch "$TASK_BRANCH"
git -C "$REPO" branch "$BUNDLE_BRANCH"

# Non-aggregate task fixture: developer title contract applies. The fallback
# developer template is `[{TICKET}] {summary}`; ticket = DP-999-T1.
NON_AGG_TASK="$TMPDIR/specs/dp-999/tasks/T1/index.md"
write_task_md "$NON_AGG_TASK" "DP-999-T1" "$TASK_BRANCH"

# Aggregate-release bundle fixture: bundle_branch_alias matches the bundle
# branch; FD6 relaxation must accept the bundle title without the bypass env.
AGG_TASK="$TMPDIR/specs/dp-999/tasks/T1/agg-index.md"
write_task_md "$AGG_TASK" "DP-999-T1" "$TASK_BRANCH" "$BUNDLE_BRANCH"

# Resolve the developer-format expected title via the gate's own rendering path
# (no hand-authored second source of truth for the summary).
DEV_SUMMARY="$(bash "$ROOT_DIR/scripts/parse-task-md.sh" "$NON_AGG_TASK" --field summary 2>/dev/null || true)"
[[ -n "$DEV_SUMMARY" ]] || fail "could not derive developer summary from fixture task.md"
DEV_TITLE="[DP-999-T1] $DEV_SUMMARY"
BUNDLE_TITLE="chore(release): bundle DP-999 -> v9.9.9"

# --- Case 1 (AC3 positive): aggregate-release branch + valid bundle title →
#     PASS, no POLARIS_SKIP_PR_TITLE_GATE. ---
git -C "$REPO" checkout -q "$BUNDLE_BRANCH"
assert_pass "aggregate-release valid bundle title PASS (no bypass env)" \
  "" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$AGG_TASK" --title "$BUNDLE_TITLE"

# --- Case 1b (AC3 / AC-NF1 negative): aggregate-release branch + ILLEGAL bundle
#     title → still exit 2 with a POLARIS_* marker (relaxation is format-scoped,
#     not a blanket skip). ---
assert_block "aggregate-release illegal bundle title still blocks" \
  "POLARIS_PR_TITLE_GATE_BLOCKED" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$AGG_TASK" --title "[DP-999-T1] wrong developer style title"

# --- Case 2 (AC3 adversarial / scope proof): non-aggregate branch + illegal
#     title → still exit 2. Proves the relaxation does NOT leak to ordinary
#     developer PRs. ---
git -C "$REPO" checkout -q "$TASK_BRANCH"
assert_block "non-aggregate illegal title still blocks (relaxation is scoped)" \
  "POLARIS_PR_TITLE_GATE_BLOCKED" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$NON_AGG_TASK" --title "chore(release): bundle DP-999 -> v9.9.9"

# --- Case 2b (regression): non-aggregate branch + correct developer title →
#     PASS. ---
assert_pass "non-aggregate correct developer title PASS" \
  "Developer format" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$NON_AGG_TASK" --title "$DEV_TITLE"

# --- DP-334 T2 / AC2 / AC5: feat/DP-NNN lifecycle. A feat-lifecycle DP task
#     carries NO bundle_branch_alias, so it falls through to the unchanged
#     developer title contract — the bundle title lane stays scoped to the legacy
#     bootstrap fallback only. ---

# Feat-lifecycle DP task fixture: NO bundle_branch_alias frontmatter (4th arg
# omitted). Reuses the same write_task_md producer; the task branch is the DP
# task branch already created above.
FEAT_TASK="$TMPDIR/specs/dp-999/tasks/T1/feat-index.md"
write_task_md "$FEAT_TASK" "DP-999-T1" "$TASK_BRANCH"
FEAT_DEV_TITLE="[DP-999-T1] $DEV_SUMMARY"

# Case 3 (POSITIVE / target feat): feat-lifecycle DP task, correct developer
# title → PASS (developer contract, not bundle). Proves the feat-lifecycle DP
# task is handled by the developer lane with no bundle coupling.
git -C "$REPO" checkout -q "$TASK_BRANCH"
assert_pass "feat-lifecycle DP task developer title PASS (no bundle coupling)" \
  "Developer format" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$FEAT_TASK" --title "$FEAT_DEV_TITLE"

# Case 3b (NEGATIVE): feat-lifecycle DP task given a bundle-style title → still
# fail-closed. The bundle title contract must NOT leak onto a feat-lifecycle DP
# task that carries no bundle_branch_alias.
assert_block "feat-lifecycle DP task rejects bundle title (no bundle coupling leak)" \
  "POLARIS_PR_TITLE_GATE_BLOCKED" -- \
  env -u POLARIS_SKIP_PR_TITLE_GATE \
  bash "$GATE" --repo "$REPO" --task-md "$FEAT_TASK" --title "chore(release): bundle DP-999 -> v9.9.9"

echo "[gate-pr-title-selftest] PASS"
