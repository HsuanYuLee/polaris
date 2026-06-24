#!/usr/bin/env bash
set -euo pipefail

# Purpose: selftest for DP-262 T3 task_shape carve-out in check-delivery-completion.sh,
#          updated for DP-360 T7. Audit/confirmation tasks now complete via the
#          task.md `deliverable.verification.status == PASS` block (the head-sha
#          completion_gate marker is retired); implementation tasks keep the PR
#          gate. Covers AC3 (task.md block PASS), AC-NEG1 (no branch ref),
#          AC-NEG2 (no marker file), and the implementation PR gate.
# Inputs:  none (builds tmpdir fixtures).
# Outputs: TAP-ish lines to stdout; exit 0 when all cases pass, 1 otherwise.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-delivery-completion.sh"
WRITE_REPORT="$SCRIPT_DIR/write-task-verify-report.sh"
TMPROOT="$(mktemp -d -t completion-gate-task-shape-XXXXXX)"
PASS=0
TOTAL=0

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

assert_rc() {
  local label="$1"
  local got="$2"
  local want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
    printf '  output: %s\n' "$haystack" >&2
  fi
}

# DP-345 D1/AC4: delegate baseline-snapshot writing to the canonical CLI
# (refresh-baseline-snapshot.sh, which reads via parse-task-md.sh) instead of
# embedding a buggy naive `text.find("## heading")` parser copy here. The
# canonical writer derives task_id from the task.md identity and emits to
# {repo}/.polaris/evidence/baseline-snapshot/{task_id}-{head_sha}.json — the
# same path this selftest previously wrote by hand.
# Signature kept for callsite compatibility; $3 (task_id) is unused because the
# canonical writer derives identity from the task.md.
write_baseline_snapshot() {
  local repo="$1"
  local task_md="$2"
  local head_sha="$4"

  bash "$SCRIPT_DIR/refresh-baseline-snapshot.sh" \
    --repo "$repo" --task-md "$task_md" --head-sha "$head_sha" >/dev/null
}

setup_repo() {
  local repo="$1"
  mkdir -p "$repo/.github"
  cat > "$repo/workspace-config.yaml" <<'EOF'
language: zh-TW
projects:
  - name: example
    repo: demo/example
EOF
  cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

## Changed

## Screenshots (Test Plan)

## Related documents

## QA notes
EOF
  git -C "$repo" init -q
  git -C "$repo" checkout -q -b task/DP-999-T1-task-shape-fixture
  git -C "$repo" config user.email "polaris@example.test"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" remote add origin https://github.com/demo/example.git
  touch "$repo/README.md"
  git -C "$repo" add README.md workspace-config.yaml .github/pull_request_template.md
  git -C "$repo" commit -q -m "init"
}

# Writes a DP task.md. $5 = task_shape value ("audit"|"confirmation"|"implementation"|"");
# $6 = verification status for the audit/confirmation deliverable block (empty =>
# omit the verification sub-block entirely, modelling "finalize never ran").
# When implementation/empty shape, includes a deliverable PR block, otherwise omits pr_url.
write_task() {
  local repo="$1"
  local head_sha="$2"
  local task_id="$3"      # e.g. DP-999-T9
  local task_n="$4"       # e.g. T9
  local task_shape="$5"
  local vstatus="${6:-}"
  local task_md="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-task-shape/tasks/${task_n}.md"
  mkdir -p "$(dirname "$task_md")"

  local shape_line=""
  if [[ -n "$task_shape" ]]; then
    shape_line="task_shape: ${task_shape}"$'\n'
  fi

  local deliverable_block
  if [[ "$task_shape" == "audit" || "$task_shape" == "confirmation" ]]; then
    # DP-360 T7 no-PR shape: head_sha for freshness binding + a verification block
    # carrying the PASS/FAIL status (no pr_url). The verification sub-block is
    # omitted entirely when $vstatus is empty (models "finalize never ran").
    deliverable_block="deliverable:
  head_sha: $head_sha"
    if [[ -n "$vstatus" ]]; then
      deliverable_block="${deliverable_block}
  verification:
    status: ${vstatus}
    ac_counts:
      ac_total: 1
      ac_pass: 1
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0"
    fi
  else
    deliverable_block="deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: $head_sha"
  fi

  cat > "$task_md" <<EOF
---
${shape_line}${deliverable_block}
status: IN_PROGRESS
depends_on: []
---

# ${task_n}: task_shape fixture (1 pt)

> Source: DP-999 | Task: ${task_id} | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | ${task_id} |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-999-${task_n}-task-shape-fixture |
| Task branch | task/DP-999-${task_n}-task-shape-fixture |
| Depends on | N/A |

## Allowed Files

- \`docs-manager/**\`

## Test Command

\`\`\`bash
echo ok
\`\`\`

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo ok
\`\`\`
EOF
  write_baseline_snapshot "$repo" "$task_md" "$task_id" "$head_sha"
  printf '%s\n' "$task_md"
}

write_task_verify_report() {
  local repo="$1"
  local task_id="$2"
  local task_md="$3"
  local head_sha="$4"
  bash "$WRITE_REPORT" \
    --repo "$repo" \
    --ticket "$task_id" \
    --task-md "$task_md" \
    --head-sha "$head_sha" \
    --status PASS >/dev/null
}

# Install a gh mock that records whether `gh pr view` is ever called.
install_gh_recorder() {
  local mockbin="$1"
  mkdir -p "$mockbin"
  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
echo "gh-called: \$*" >> "$mockbin/gh-calls.log"
exit 1
EOF
  chmod +x "$mockbin/gh"
}

run_check() {
  local repo="$1"
  local ticket="$2"
  local extra_path="${3:-}"
  local out rc
  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 PATH="${extra_path:+$extra_path:}$PATH" \
    "$CHECK" --repo "$repo" --ticket "$ticket" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  return "$rc"
}

# ---------------------------------------------------------------------------
# Case 1 (AC3): confirmation task + task.md deliverable.verification.status=PASS,
#   no marker file anywhere => PASS.
# ---------------------------------------------------------------------------
case_confirmation_block_passes() {
  local label="confirmation-block-passes"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T9" "T9" "confirmation" "PASS")"
  write_task_verify_report "$repo" "DP-999-T9" "$task_md" "$head_sha"

  [[ ! -d "$repo/.polaris/evidence/completion-gate" ]] || \
    { printf 'not ok %s: marker dir should not exist (AC-NEG2)\n' "$label" >&2; }

  set +e
  out="$(run_check "$repo" "DP-999-T9")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "0"
  assert_contains "$label message" "$out" "deliverable block"
}

# ---------------------------------------------------------------------------
# Case 2 (AC3): audit task + task.md deliverable.verification.status=PASS => PASS
# ---------------------------------------------------------------------------
case_audit_block_passes() {
  local label="audit-block-passes"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T8" "T8" "audit" "PASS")"
  write_task_verify_report "$repo" "DP-999-T8" "$task_md" "$head_sha"

  set +e
  out="$(run_check "$repo" "DP-999-T8")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "0"
  assert_contains "$label message" "$out" "audit task completion gate satisfied"
}

# ---------------------------------------------------------------------------
# Case 3 (AC4): confirmation task with NO deliverable PR + NO gh mock completes
#               without ever calling gh — proves it is excluded from required PR set.
# ---------------------------------------------------------------------------
case_confirmation_excluded_from_required_pr_set() {
  local label="confirmation-excluded-from-required-pr-set"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  install_gh_recorder "$mockbin"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T7" "T7" "confirmation" "PASS")"
  write_task_verify_report "$repo" "DP-999-T7" "$task_md" "$head_sha"

  set +e
  out="$(run_check "$repo" "DP-999-T7" "$mockbin")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "0"
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$mockbin/gh-calls.log" ]]; then
    PASS=$((PASS + 1))
    printf 'ok %s no-gh-pr-query\n' "$label"
  else
    printf 'not ok %s no-gh-pr-query: gh was called: %s\n' "$label" "$(cat "$mockbin/gh-calls.log")" >&2
  fi
}

# ---------------------------------------------------------------------------
# Case 4 (AC3 adversarial): confirmation task with NO deliverable.verification
#   block at all => BLOCKED (models "finalize never wrote the verification block").
# ---------------------------------------------------------------------------
case_confirmation_missing_block_blocks() {
  local label="confirmation-missing-block-blocks"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  # vstatus empty => no verification sub-block emitted.
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T6" "T6" "confirmation" "")"
  write_task_verify_report "$repo" "DP-999-T6" "$task_md" "$head_sha"

  set +e
  out="$(run_check "$repo" "DP-999-T6")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "missing deliverable.verification.status"
}

# ---------------------------------------------------------------------------
# Case 5 (AC3 adversarial): deliverable.verification.status != PASS => BLOCKED.
# ---------------------------------------------------------------------------
case_confirmation_block_not_pass_blocks() {
  local label="confirmation-block-not-pass-blocks"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T5" "T5" "confirmation" "IN_PROGRESS")"
  write_task_verify_report "$repo" "DP-999-T5" "$task_md" "$head_sha"

  set +e
  out="$(run_check "$repo" "DP-999-T5")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "(need PASS)"
}

# ---------------------------------------------------------------------------
# Case 6 (AC-NEG2): a stray completion_gate marker on disk must NOT override a
#   non-PASS task.md block — the reader never consults a marker file. FAIL block +
#   PASS marker still BLOCKS.
# ---------------------------------------------------------------------------
case_confirmation_stray_marker_ignored() {
  local label="confirmation-stray-marker-ignored"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T4" "T4" "confirmation" "FAIL")"
  write_task_verify_report "$repo" "DP-999-T4" "$task_md" "$head_sha"
  # Plant a PASS completion_gate marker on disk; the reader must ignore it.
  mkdir -p "$repo/.polaris/evidence/completion-gate"
  python3 - "$repo/.polaris/evidence/completion-gate/DP-999-T4-${head_sha}.json" "$head_sha" <<'PY'
import json, sys
out, head = sys.argv[1:3]
json.dump({"schema_version": 1, "marker_kind": "completion_gate", "work_item_id": "DP-999-T4",
           "status": "PASS", "freshness": {"head_sha": head}}, open(out, "w"))
open(out, "a").write("\n")
PY

  set +e
  out="$(run_check "$repo" "DP-999-T4")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "(need PASS)"
}

# ---------------------------------------------------------------------------
# Case 7 (AC-NEG2): implementation task (draft / missing PR) still blocks.
#   Uses task_shape: implementation with a deliverable pr_url but gh mock returns a
#   draft PR — the PR gate must NOT be relaxed.
# ---------------------------------------------------------------------------
install_draft_gh() {
  local mockbin="$1"
  local body_file="$2"
  local head_sha="$3"
  mkdir -p "$mockbin"
  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "pr view" ]]; then
  python3 - <<'PY'
import json
from pathlib import Path
print(json.dumps({
    "assignees": [{"login": "polaris-selftest"}],
    "body": Path("$body_file").read_text(encoding="utf-8"),
    "isDraft": True,
    "labels": [],
    "mergeStateStatus": "CLEAN",
    "number": 1,
    "reviewDecision": "REVIEW_REQUIRED",
    "state": "OPEN",
    "url": "https://github.com/demo/example/pull/1",
    "headRefName": "task/DP-999-T3-task-shape-fixture",
    "headRefOid": "$head_sha",
    "baseRefName": "main",
}))
PY
  exit 0
fi
if [[ "\$1" == "api" ]]; then
  echo '[]'
  exit 0
fi
exit 0
EOF
  chmod +x "$mockbin/gh"
}

case_implementation_draft_pr_blocks() {
  local label="implementation-draft-pr-still-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T3" "T3" "implementation")"
  write_task_verify_report "$repo" "DP-999-T3" "$task_md" "$head_sha"
  cat > "$body_file" <<'EOF'
## Description

任務說明。

## Changed

- 變更。

## Screenshots (Test Plan)

- 已測。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_draft_gh "$mockbin" "$body_file" "$head_sha"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T3 2>&1)"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "deliverable PR is draft"
}

case_confirmation_block_passes
case_audit_block_passes
case_confirmation_excluded_from_required_pr_set
case_confirmation_missing_block_blocks
case_confirmation_block_not_pass_blocks
case_confirmation_stray_marker_ignored
case_implementation_draft_pr_blocks

printf '\n=== check-delivery-completion task_shape selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
