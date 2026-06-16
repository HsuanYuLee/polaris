#!/usr/bin/env bash
set -euo pipefail

# Purpose: selftest for DP-262 T3 task_shape carve-out in check-delivery-completion.sh.
#          Verifies audit/confirmation tasks complete via completion_gate marker + evidence
#          artifact path (no deliverable PR required), while implementation tasks keep the
#          PR gate. Covers AC3, AC4, AC-NEG2.
# Inputs:  none (builds tmpdir fixtures).
# Outputs: TAP-ish lines to stdout; exit 0 when all cases pass, 1 otherwise.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-delivery-completion.sh"
WRITE_REPORT="$SCRIPT_DIR/write-task-verify-report.sh"
WRITE_MARKER="$SCRIPT_DIR/write-completion-gate-marker.sh"
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

write_baseline_snapshot() {
  local repo="$1"
  local task_md="$2"
  local task_id="$3"
  local head_sha="$4"

  mkdir -p "$repo/.polaris/evidence/baseline-snapshot"
  python3 - "$task_md" "$repo/.polaris/evidence/baseline-snapshot/${task_id}-${head_sha}.json" "$task_id" "$head_sha" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

task_path = Path(sys.argv[1])
snapshot_path = Path(sys.argv[2])
task_id = sys.argv[3]
head_sha = sys.argv[4]

def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

def section(text, heading):
    marker = f"## {heading}"
    start = text.find(marker)
    if start == -1:
        return ""
    start = text.find("\n", start)
    if start == -1:
        return ""
    end = text.find("\n## ", start + 1)
    return text[start + 1:] if end == -1 else text[start + 1:end]

def first_fence(block):
    match = re.search(r"```[^\n]*\n(.*?)\n```", block, re.S)
    return match.group(1).strip() if match else ""

def table_value(text, field):
    for raw in text.splitlines():
        if not raw.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in raw.split("|")]
        if len(cells) >= 4 and cells[1] == field:
            return cells[2]
    return ""

def frontmatter_depends_on(text):
    if not text.startswith("---\n"):
        return []
    end = text.find("\n---\n", 4)
    if end == -1:
        return []
    fm = text[4:end]
    for raw in fm.splitlines():
        if raw.startswith("depends_on:"):
            value = raw.split(":", 1)[1].strip()
            if value in ("", "[]"):
                return []
            if value.startswith("[") and value.endswith("]"):
                return [item.strip().strip("'\"") for item in value[1:-1].split(",") if item.strip()]
            return [value.strip("'\"")]
    return []

def allowed_files(text):
    values = []
    for raw in section(text, "Allowed Files").splitlines():
        stripped = raw.strip()
        if stripped.startswith("- "):
            values.append(stripped[2:].strip())
    return values

text = task_path.read_text(encoding="utf-8")
planner_owned = {
    "verify_command": first_fence(section(text, "Verify Command")),
    "depends_on": frontmatter_depends_on(text),
    "base_branch": table_value(text, "Base branch"),
    "allowed_files": allowed_files(text),
}
snapshot = {
    "schema_version": 1,
    "writer": "check-delivery-completion-task-shape-selftest",
    "task_id": task_id,
    "task_md": str(task_path),
    "head_sha": head_sha,
    "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
}
snapshot_path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
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
# when implementation/empty, includes a deliverable PR block, otherwise omits pr_url.
write_task() {
  local repo="$1"
  local head_sha="$2"
  local task_id="$3"      # e.g. DP-999-T9
  local task_n="$4"       # e.g. T9
  local task_shape="$5"
  local task_md="$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-task-shape/tasks/${task_n}.md"
  mkdir -p "$(dirname "$task_md")"

  local shape_line=""
  if [[ -n "$task_shape" ]]; then
    shape_line="task_shape: ${task_shape}"$'\n'
  fi

  local deliverable_block
  if [[ "$task_shape" == "audit" || "$task_shape" == "confirmation" ]]; then
    # no-PR shape: only head_sha for freshness binding, no pr_url.
    deliverable_block="deliverable:
  head_sha: $head_sha"
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
# Case 1 (AC3): confirmation task + completion_gate marker(PASS) + evidence path => PASS
# ---------------------------------------------------------------------------
case_confirmation_marker_passes() {
  local label="confirmation-marker-passes"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T9" "T9" "confirmation")"
  write_task_verify_report "$repo" "DP-999-T9" "$task_md" "$head_sha"
  bash "$WRITE_MARKER" --source-id DP-999 --work-item-id DP-999-T9 --head-sha "$head_sha" \
    --status PASS --task-md "$task_md" --out "$repo/.polaris/evidence/completion-gate/DP-999-T9-${head_sha}.json" >/dev/null

  set +e
  out="$(run_check "$repo" "DP-999-T9")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "0"
  assert_contains "$label message" "$out" "confirmation task completion gate satisfied"
}

# ---------------------------------------------------------------------------
# Case 2 (AC3): audit task + marker(PASS) => PASS
# ---------------------------------------------------------------------------
case_audit_marker_passes() {
  local label="audit-marker-passes"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T8" "T8" "audit")"
  write_task_verify_report "$repo" "DP-999-T8" "$task_md" "$head_sha"
  bash "$WRITE_MARKER" --source-id DP-999 --work-item-id DP-999-T8 --head-sha "$head_sha" \
    --status PASS --task-md "$task_md" --out "$repo/.polaris/evidence/completion-gate/DP-999-T8-${head_sha}.json" >/dev/null

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
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T7" "T7" "confirmation")"
  write_task_verify_report "$repo" "DP-999-T7" "$task_md" "$head_sha"
  bash "$WRITE_MARKER" --source-id DP-999 --work-item-id DP-999-T7 --head-sha "$head_sha" \
    --status PASS --task-md "$task_md" --out "$repo/.polaris/evidence/completion-gate/DP-999-T7-${head_sha}.json" >/dev/null

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
# Case 4 (AC3 adversarial): confirmation task missing completion_gate marker => BLOCKED
# ---------------------------------------------------------------------------
case_confirmation_missing_marker_blocks() {
  local label="confirmation-missing-marker-blocks"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T6" "T6" "confirmation")"
  write_task_verify_report "$repo" "DP-999-T6" "$task_md" "$head_sha"

  set +e
  out="$(run_check "$repo" "DP-999-T6")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "missing completion_gate marker"
}

# ---------------------------------------------------------------------------
# Case 5 (AC3 adversarial): marker present but status != PASS => BLOCKED
# ---------------------------------------------------------------------------
case_confirmation_marker_not_pass_blocks() {
  local label="confirmation-marker-not-pass-blocks"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T5" "T5" "confirmation")"
  write_task_verify_report "$repo" "DP-999-T5" "$task_md" "$head_sha"
  bash "$WRITE_MARKER" --source-id DP-999 --work-item-id DP-999-T5 --head-sha "$head_sha" \
    --status IN_PROGRESS --task-md "$task_md" --out "$repo/.polaris/evidence/completion-gate/DP-999-T5-${head_sha}.json" >/dev/null

  set +e
  out="$(run_check "$repo" "DP-999-T5")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "stale or not PASS"
}

# ---------------------------------------------------------------------------
# Case 6 (AC3 adversarial / AC8): marker PASS but evidence artifact is truly
#   unresolvable => BLOCKED. After the DP-325 T5 reader change (existence-only =>
#   resolve-by-id), a path-corrupt-but-id-resolvable marker correctly PASSes
#   (asserted by the move-resilience selftest). To keep asserting the fail-closed
#   invariant here, the marker must be genuinely non-resolvable: corrupt the frozen
#   source_artifact path AND drop task_artifact_sha256 AND point the bound work
#   item at a non-existent task id so resolve-by-id cannot relocate it.
# ---------------------------------------------------------------------------
case_confirmation_marker_missing_evidence_blocks() {
  local label="confirmation-marker-missing-evidence-blocks"
  local repo="$TMPROOT/$label/repo"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha task_md marker
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  task_md="$(write_task "$repo" "$head_sha" "DP-999-T4" "T4" "confirmation")"
  write_task_verify_report "$repo" "DP-999-T4" "$task_md" "$head_sha"
  marker="$repo/.polaris/evidence/completion-gate/DP-999-T4-${head_sha}.json"
  bash "$WRITE_MARKER" --source-id DP-999 --work-item-id DP-999-T4 --head-sha "$head_sha" \
    --status PASS --task-md "$task_md" --out "$marker" >/dev/null
  # Make the marker truly unresolvable: corrupt source_artifact to a non-existent
  # path and drop task_artifact_sha256 so resolve-by-id has nothing to verify
  # against — the path-only-and-stale case must still fail closed.
  python3 - "$marker" <<'PY'
import json
import sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["freshness"]["source_artifact"] = "/nonexistent/evidence/artifact.md"
data["freshness"].pop("evidence_artifact", None)
data["freshness"].pop("task_artifact_sha256", None)
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  set +e
  out="$(run_check "$repo" "DP-999-T4")"
  rc=$?
  set -e
  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "lacks a resolvable evidence artifact path"
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

case_confirmation_marker_passes
case_audit_marker_passes
case_confirmation_excluded_from_required_pr_set
case_confirmation_missing_marker_blocks
case_confirmation_marker_not_pass_blocks
case_confirmation_marker_missing_evidence_blocks
case_implementation_draft_pr_blocks

printf '\n=== check-delivery-completion task_shape selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
