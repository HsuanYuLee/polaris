#!/usr/bin/env bash
set -euo pipefail

# Purpose: DP-325 T5 / AC8 + DP-360 T7 — selftest for D-class reader resilience to
#          a moved task.md. DP-360 T7 retires the head-sha completion_gate /
#          ac_verification markers; the delivery evidence is now the task.md
#          `deliverable` block. Move-resilience is therefore intrinsic to task.md
#          resolution (resolve-task-md.sh --include-archive) rather than marker
#          relocation. This asserts both reader sites still pass after the task.md
#          moves to pr-release/, with NO marker file present (AC3 / AC-NEG2), and
#          that a non-PASS block still fails closed after the move (no laundering):
#            - scripts/check-delivery-completion.sh (audit/confirmation reader),
#            - scripts/lib/evidence-classifier.sh marker-pass (shared reader).
# Inputs:  none (builds tmp git fixture repos + task.md deliverable blocks).
# Outputs: TAP-ish lines; exit 0 when all cases pass, 1 otherwise.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-delivery-completion.sh"
CLASSIFIER="$SCRIPT_DIR/lib/evidence-classifier.sh"
TMPROOT="$(mktemp -d -t marker-move-resilience-XXXXXX)"
PASS=0
TOTAL=0

cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

assert_rc() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
    printf '  output: %s\n' "$haystack" >&2
  fi
}

assert_no_marker() {
  local label="$1" repo="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -d "$repo/.polaris/evidence/completion-gate" && ! -d "$repo/.polaris/evidence/ac-verification" ]]; then
    PASS=$((PASS + 1)); printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: marker dir present (AC-NEG2 expects none)\n' "$label" >&2
  fi
}

# Build the planner-owned baseline snapshot the completion gate expects, mirroring
# the canonical writer in engineering-branch-setup.sh exactly (it extracts
# planner-owned fields via parse-task-md.sh so the digests round-trip with
# validate-task-md.sh --snapshot).
PARSE="$SCRIPT_DIR/parse-task-md.sh"
write_baseline_snapshot() {
  local repo="$1" task_md="$2" task_id="$3" head_sha="$4"
  mkdir -p "$repo/.polaris/evidence/baseline-snapshot"
  python3 - "$PARSE" "$task_md" "$head_sha" \
    "$repo/.polaris/evidence/baseline-snapshot/${task_id}-${head_sha}.json" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
parser, task_md, head_sha, out_path = sys.argv[1:5]
proc = subprocess.run(["bash", parser, task_md, "--no-resolve"], text=True,
                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
data = json.loads(proc.stdout)
identity = data.get("identity") or {}
op = data.get("operational_context") or {}
task_id = identity.get("work_item_id") or op.get("task_id") or op.get("task_jira_key")
def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
planner_owned = {
    "verify_command": data.get("verify_command") or "",
    "depends_on": (data.get("frontmatter") or {}).get("depends_on") or [],
    "base_branch": op.get("base_branch") or "",
    "allowed_files": data.get("allowed_files") or [],
}
snapshot = {
    "schema_version": 1, "writer": "marker-move-resilience-selftest", "task_id": task_id,
    "task_md": str(Path(task_md).resolve()), "head_sha": head_sha, "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
    "task_artifact_sha256": hashlib.sha256(Path(task_md).read_bytes()).hexdigest(),
}
Path(out_path).write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

setup_repo() {
  local repo="$1"
  mkdir -p "$repo/.github"
  printf 'language: en\nprojects:\n  - name: example\n    repo: demo/example\n' > "$repo/workspace-config.yaml"
  printf '## Description\n\n## Changed\n\n## QA notes\n' > "$repo/.github/pull_request_template.md"
  git -C "$repo" init -q
  git -C "$repo" checkout -q -b task/DP-999-T9-move-fixture
  git -C "$repo" config user.email "polaris@example.test"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" remote add origin https://github.com/demo/example.git
  touch "$repo/README.md"
  git -C "$repo" add README.md workspace-config.yaml .github/pull_request_template.md
  git -C "$repo" commit -q -m "init"
}

# Writes a confirmation-shape DP task.md at $rel_dir/$task_n/index.md, carrying the
# DP-360 deliverable block (head_sha + verification.status). $6 = verification status.
write_task() {
  local repo="$1" head_sha="$2" task_id="$3" task_n="$4" rel_dir="$5" vstatus="${6:-PASS}"
  local task_md="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-move/${rel_dir}/${task_n}/index.md"
  mkdir -p "$(dirname "$task_md")"
  cat > "$task_md" <<EOF
---
task_shape: confirmation
deliverable:
  head_sha: $head_sha
  verification:
    status: $vstatus
    ac_counts:
      ac_total: 1
      ac_pass: 1
      ac_fail: 0
      ac_manual_required: 0
      ac_uncertain: 0
status: IN_PROGRESS
depends_on: []
---

# ${task_n}: move-resilience fixture (1 pt)

> Source: DP-999 | Task: ${task_id} | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | ${task_id} |
| Base branch | main |
| Task branch | task/DP-999-${task_n}-move-fixture |

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
  printf '%s\n' "$task_md"
}

run_check() {
  local repo="$1" ticket="$2" out rc
  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 "$CHECK" --repo "$repo" --ticket "$ticket" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  return "$rc"
}

# ---------------------------------------------------------------------------
# Case A: audit/confirmation completion (check-delivery-completion.sh) passes
# after the task.md moves to pr-release/, reading the task.md deliverable block
# with NO marker file present.
# ---------------------------------------------------------------------------
case_check_delivery_completion_after_move() {
  local repo="$TMPROOT/check-move/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T9" "T9" "tasks" "PASS")"
  write_baseline_snapshot "$repo" "$task_md" "DP-999-T9" "$head_sha"
  bash "$SCRIPT_DIR/write-task-verify-report.sh" --repo "$repo" --ticket "DP-999-T9" \
    --task-md "$task_md" --head-sha "$head_sha" --status PASS >/dev/null

  assert_no_marker "caseA: AC-NEG2 no marker dir created" "$repo"

  # Sanity: the completion gate passes while the task.md is in place.
  set +e; out="$(run_check "$repo" "DP-999-T9")"; rc=$?; set -e
  assert_rc "caseA-pre: gate passes with live task.md" "$rc" "0"

  # Move the whole task dir to pr-release/ (closeout pattern). The completion gate
  # resolves task.md by work_item_id (resolve-task-md.sh --include-archive), so a
  # plain mv mirrors the closeout move without advancing HEAD (which would break
  # the unrelated deliverable.head_sha == HEAD freshness check).
  local tasks_dir="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-move/tasks"
  mkdir -p "$tasks_dir/pr-release"
  mv "$tasks_dir/T9" "$tasks_dir/pr-release/T9"

  set +e; out="$(run_check "$repo" "DP-999-T9")"; rc=$?; set -e
  assert_rc "caseA: completion gate passes after task.md moved to pr-release/" "$rc" "0"
  assert_contains "caseA: gate satisfied via task.md deliverable block" "$out" "deliverable block"
}

# ---------------------------------------------------------------------------
# Case B: evidence-classifier marker-pass relocates a moved task.md via
# work_item_id, with NO marker file present.
# ---------------------------------------------------------------------------
case_evidence_classifier_after_move() {
  local repo="$TMPROOT/classifier-move/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T9" "T9" "tasks" "PASS")"

  assert_no_marker "caseB: AC-NEG2 no marker dir created" "$repo"

  # Pre-move: marker-pass resolves the live task.md block.
  set +e
  out="$(bash "$CLASSIFIER" marker-pass --repo "$repo" --work-item-id DP-999-T9 --head-sha "$head_sha" 2>&1)"
  rc=$?
  set -e
  assert_rc "caseB-pre: marker-pass with live task.md" "$rc" "0"

  # Move and re-check: the reader must relocate via work_item_id.
  local moved="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-move/tasks/pr-release/T9/index.md"
  mkdir -p "$(dirname "$moved")"
  mv "$task_md" "$moved"

  set +e
  out="$(bash "$CLASSIFIER" marker-pass --repo "$repo" --work-item-id DP-999-T9 --head-sha "$head_sha" 2>&1)"
  rc=$?
  set -e
  assert_rc "caseB: marker-pass relocates moved task.md" "$rc" "0"
}

# ---------------------------------------------------------------------------
# Case C: a non-PASS deliverable.verification.status fails closed even after the
# task.md moves — relocation must NOT launder a FAIL block into a pass.
# ---------------------------------------------------------------------------
case_non_pass_block_fails_closed_after_move() {
  local repo="$TMPROOT/non-pass/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T9" "T9" "tasks" "FAIL")"

  local moved="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-move/tasks/pr-release/T9/index.md"
  mkdir -p "$(dirname "$moved")"
  mv "$task_md" "$moved"

  set +e
  out="$(bash "$CLASSIFIER" marker-pass --repo "$repo" --work-item-id DP-999-T9 --head-sha "$head_sha" 2>&1)"
  rc=$?
  set -e
  assert_rc "caseC: non-PASS block fails closed after move" "$rc" "2"
  assert_contains "caseC: status != PASS reason" "$out" "status != PASS"
}

case_check_delivery_completion_after_move
case_evidence_classifier_after_move
case_non_pass_block_fails_closed_after_move

printf '\n%s/%s checks passed\n' "$PASS" "$TOTAL"
[[ "$PASS" == "$TOTAL" ]]
