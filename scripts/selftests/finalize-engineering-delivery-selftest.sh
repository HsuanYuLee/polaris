#!/usr/bin/env bash
set -euo pipefail

# Selftest for finalize-engineering-delivery.sh stable-cwd cleanup behavior.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FINALIZE="$SCRIPT_DIR/finalize-engineering-delivery.sh"
WRITE_REPORT="$SCRIPT_DIR/write-task-verify-report.sh"
REFRESH_SNAPSHOT="$SCRIPT_DIR/refresh-baseline-snapshot.sh"
TMPROOT="$(mktemp -d -t finalize-delivery-selftest-XXXXXX)"
TMPROOT="$(cd "$TMPROOT" && pwd -P)"

cleanup() {
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

write_pr_template() {
  local repo="$1"
  mkdir -p "$repo/.github"
  cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

## Changed

## Screenshots (Test Plan)

## Related documents

## QA notes
EOF
}

write_task() {
  local workspace="$1"
  local head_sha="$2"
  local task_dir="$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks"
  mkdir -p "$task_dir"
  cat > "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/index.md" <<'EOF'
---
title: "DP-999: Finalize cwd selftest"
status: LOCKED
locked_at: 2026-05-03
---

# DP-999

## Implementation Checklist

- [ ] T1: finalize cwd selftest

## Work Orders

- [T1](tasks/T1.md)
EOF
  cat > "$task_dir/T1.md" <<EOF
---
deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: $head_sha
status: IN_PROGRESS
depends_on: []
---

# T1: finalize cwd selftest (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-finalize-cwd |
| Task branch | task/DP-999-T1-finalize-cwd |
| Depends on | N/A |

## Allowed Files

- \`scripts/**\`

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
}

install_mock_gh() {
  local mockbin="$1"
  local head_sha="$2"
  mkdir -p "$mockbin"
  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "pr view" ]]; then
  python3 - <<'PY'
import json
print(json.dumps({
    "body": "## Description\\n\\nSelftest.\\n\\n## Changed\\n\\n- finalize\\n\\n## Screenshots (Test Plan)\\n\\n- selftest\\n\\n## Related documents\\n\\n- DP-999\\n\\n## QA notes\\n\\n- N/A\\n",
    "isDraft": False,
    "state": "OPEN",
    "url": "https://github.com/demo/example/pull/1",
    "headRefName": "task/DP-999-T1-finalize-cwd",
    "headRefOid": "$head_sha",
    "baseRefName": "main",
    "mergeStateStatus": "CLEAN",
    "assignees": [{"login": "polaris-selftest"}],
    "labels": [],
}))
PY
  exit 0
fi
if [[ "\$1" == "api" && "\$2" == "graphql" ]]; then
  cat <<'JSON'
{
  "data": {
    "repository": {
      "pullRequest": {
        "url": "https://github.com/demo/example/pull/1",
        "reviewThreads": {"nodes": []}
      }
    }
  }
}
JSON
  exit 0
fi
echo "unexpected gh call: \$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"
}

write_verify_evidence() {
  local head_sha="$1"
  cat > "/tmp/polaris-verified-DP-999-T1-${head_sha}.json" <<EOF
{
  "ticket": "DP-999-T1",
  "head_sha": "${head_sha}",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "at": "2026-05-09T00:00:00Z"
}
EOF
}

write_task_verify_report() {
  local workspace="$1"
  local evidence_repo="$2"
  local head_sha="$3"

  bash "$WRITE_REPORT" \
    --repo "$evidence_repo" \
    --ticket DP-999-T1 \
    --task-md "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks/T1.md" \
    --head-sha "$head_sha" \
    --status PASS >/dev/null
}

write_baseline_snapshot() {
  local repo="$1"
  local workspace="$2"
  local head_sha="$3"

  # Reuse the canonical baseline-snapshot producer (refresh-baseline-snapshot.sh)
  # so finalize's planner-owned snapshot gate (check_planner_baseline_snapshot) has
  # the same snapshot engineering-branch-setup.sh would have written for a real run.
  bash "$REFRESH_SNAPSHOT" \
    --repo "$repo" \
    --task-md "$workspace/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks/T1.md" \
    --head-sha "$head_sha" >/dev/null
}

# Keep a hostile ancestor named `specs`: archive authority must be resolved
# relative to the workspace's canonical docs-manager specs root, not by the
# first matching path component.
main_repo="$TMPROOT/specs/workspace"
worktree_repo="$TMPROOT/.worktrees/finalize-cwd"
mockbin="$TMPROOT/bin"

mkdir -p "$main_repo"
git -C "$main_repo" init -q
git -C "$main_repo" checkout -q -b main
git -C "$main_repo" config user.email "polaris@example.test"
git -C "$main_repo" config user.name "Polaris Selftest"
git -C "$main_repo" remote add origin https://github.com/demo/example.git
cat > "$main_repo/workspace-config.yaml" <<'EOF'
language: zh-TW
EOF
write_pr_template "$main_repo"
touch "$main_repo/README.md"
git -C "$main_repo" add README.md workspace-config.yaml .github/pull_request_template.md
git -C "$main_repo" commit -q -m init
git -C "$main_repo" checkout -q -b task/DP-999-T1-finalize-cwd
git -C "$main_repo" checkout -q main
git -C "$main_repo" worktree add -q "$worktree_repo" task/DP-999-T1-finalize-cwd

head_sha="$(git -C "$worktree_repo" rev-parse HEAD)"
write_task "$main_repo" "$head_sha"
install_mock_gh "$mockbin" "$head_sha"
write_verify_evidence "$head_sha"
write_baseline_snapshot "$worktree_repo" "$main_repo" "$head_sha"
set +e
out="$(
  cd "$worktree_repo" &&
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$worktree_repo" --ticket DP-999-T1 --workspace "$main_repo" 2>&1
)"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  printf '%s\n' "$out" >&2
  echo "not ok finalize exited $rc" >&2
  exit 1
fi

if grep -qE 'getcwd|cannot access parent directories' <<< "$out"; then
  printf '%s\n' "$out" >&2
  echo "not ok finalize emitted deleted-cwd noise" >&2
  exit 1
fi

if [[ -d "$worktree_repo" ]]; then
  echo "not ok implementation worktree still exists" >&2
  exit 1
fi

task_path="$main_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks/pr-release/T1.md"
if [[ ! -f "$task_path" ]] || ! grep -q '^status: IMPLEMENTED$' "$task_path"; then
  echo "not ok finalized task missing or status not implemented" >&2
  exit 1
fi

report_path="$main_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd/tasks/T1/verify-report.md"
if [[ ! -f "$report_path" ]] || ! grep -q "$head_sha" "$report_path"; then
  echo "not ok auto-generated verify report missing or stale" >&2
  exit 1
fi

# DP-360 T7 (AC3 / NEG2): finalize must record the delivery PASS into the
# canonical task.md `deliverable.verification` block — NOT a head-sha-keyed
# completion_gate marker. The block is the single delivery-evidence source; no
# marker file may be written (no dual-source steady state).
if [[ -e "$main_repo/.polaris/evidence/completion-gate" ]]; then
  echo "not ok finalize wrote a retired completion-gate marker dir (NEG2 dual-source)" >&2
  exit 1
fi

# The deliverable.verification.status must be PASS, bound to the finalized head
# sha recorded in deliverable.head_sha (artifact field, never a branch ref).
if ! python3 - "$task_path" "$head_sha" <<'PY'
import sys
from pathlib import Path

task_path, head_sha = sys.argv[1:3]
text = Path(task_path).read_text(encoding="utf-8")
assert text.startswith("---\n"), "no frontmatter"
end = text.find("\n---\n", 4)
assert end != -1, "unterminated frontmatter"
fm = text[4:end]

# Walk the deliverable block and its nested verification sub-block.
recorded_head = ""
ver_status = ""
in_deliverable = False
in_verification = False
for line in fm.splitlines():
    if line.rstrip() == "deliverable:":
        in_deliverable = True
        continue
    if in_deliverable and line and not line.startswith(" "):
        break
    if not in_deliverable:
        continue
    if line.startswith("  ") and not line.startswith("    "):
        in_verification = line.strip().startswith("verification:")
        s = line.strip()
        if s.startswith("head_sha:"):
            recorded_head = s.split(":", 1)[1].strip()
        continue
    if in_verification and line.strip().startswith("status:"):
        ver_status = line.split(":", 1)[1].strip()

assert ver_status == "PASS", f"deliverable.verification.status={ver_status!r}"
assert recorded_head and (
    recorded_head == head_sha
    or head_sha.startswith(recorded_head)
    or recorded_head.startswith(head_sha)
), f"deliverable.head_sha={recorded_head!r} not bound to {head_sha!r}"
PY
then
  echo "not ok deliverable.verification block missing PASS bound to finalized head sha" >&2
  exit 1
fi

# AC3 idempotency (adversarial): a second finalize for the same head must leave
# the task.md byte-identical (the stamp is a no-op when status is already PASS),
# and must still write no marker file.
task_before="$(python3 - "$task_path" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

# Re-run finalize against the now-finalized (pr-release) task. resolve-task-md.sh still
# resolves it, the mock PR is still OPEN, and the deliverable.verification stamp must
# be a byte-identical no-op rather than re-stamp / duplicate the block.
set +e
out2="$(
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$main_repo" --ticket DP-999-T1 --workspace "$main_repo" 2>&1
)"
set -e

if [[ -e "$main_repo/.polaris/evidence/completion-gate" ]]; then
  printf '%s\n' "$out2" >&2
  echo "not ok second finalize wrote a retired completion-gate marker dir (NEG2)" >&2
  exit 1
fi

task_after="$(python3 - "$task_path" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

if [[ "$task_before" != "$task_after" ]]; then
  printf '%s\n' "$out2" >&2
  echo "not ok deliverable.verification block drifted on idempotent re-run (before=$task_before after=$task_after)" >&2
  exit 1
fi

if ! grep -q 'deliverable.verification already PASS; no-op' <<< "$out2"; then
  printf '%s\n' "$out2" >&2
  echo "not ok second finalize did not report idempotent no-op for deliverable.verification" >&2
  exit 1
fi

# Post-archive revision idempotency: once the source parent is terminal and the
# whole container has moved, finalize must treat parent closeout as complete
# instead of re-entering an active-only close-parent resolver after cleanup.
container="$main_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-finalize-cwd"
python3 - "$container/index.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"^status:.*$", "status: IMPLEMENTED", text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")
PY
mkdir -p "$main_repo/docs-manager/src/content/docs/specs/design-plans/archive"
mv "$container" "$main_repo/docs-manager/src/content/docs/specs/design-plans/archive/"

set +e
out3="$(
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$main_repo" --ticket DP-999-T1 --workspace "$main_repo" 2>&1
)"
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  printf '%s\n' "$out3" >&2
  echo "not ok archived idempotent finalize exited $rc" >&2
  exit 1
fi
if ! grep -q 'archived parent closeout already complete' <<< "$out3"; then
  printf '%s\n' "$out3" >&2
  echo "not ok archived parent terminal state was not recognized" >&2
  exit 1
fi

# A DP refinement.md is never a canonical parent fallback. Even when terminal,
# it must not be accepted in place of the DP index.md -> plan.md precedence.
archived_container="$main_repo/docs-manager/src/content/docs/specs/design-plans/archive/DP-999-finalize-cwd"
mv "$archived_container/index.md" "$archived_container/refinement.md"
set +e
out4="$(
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$main_repo" --ticket DP-999-T1 --workspace "$main_repo" 2>&1
)"
set -e
if grep -q 'archived parent closeout already complete' <<< "$out4"; then
  printf '%s\n' "$out4" >&2
  echo "not ok terminal DP refinement.md was accepted as canonical parent" >&2
  exit 1
fi
if ! grep -q 'parent refinement.md/plan.md not found' <<< "$out4"; then
  printf '%s\n' "$out4" >&2
  echo "not ok DP refinement-only fixture did not fall through canonical parent resolution" >&2
  exit 1
fi

# Company precedence is index.md -> refinement.md -> plan.md. A terminal plan
# must not shadow a present non-terminal refinement parent. The legal company
# slug `tasks` also proves every consumer selects the structural task segment,
# not the first path component with that spelling.
company_container="$main_repo/docs-manager/src/content/docs/specs/companies/tasks/archive/GT-ARCH"
mkdir -p "$(dirname "$company_container")"
mv "$archived_container" "$company_container"
company_task="$company_container/tasks/pr-release/T1.md"
python3 - "$company_container/refinement.md" "$company_task" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"^status:.*$", "status: LOCKED", text, count=1, flags=re.M)
path.write_text(text, encoding="utf-8")

task = Path(sys.argv[2])
text = task.read_text(encoding="utf-8")
text = text.replace("Source: DP-999", "Source: GT-ARCH")
text = text.replace("Task: DP-999-T1", "Task: GT-ARCH-T1")
text = text.replace("| Source type | dp |", "| Source type | jira |")
text = text.replace("| Source ID | DP-999 |", "| Source ID | GT-ARCH |")
text = text.replace("| Task ID | DP-999-T1 |", "| Task ID | GT-ARCH-T1 |")
text = text.replace("| Task ID | GT-ARCH-T1 |", "| Task ID | GT-ARCH-T1 |\n| Work item ID | GT-ARCH-T1 |")
text = text.replace("| JIRA key | N/A |", "| JIRA key | GT-ARCH |")
task.write_text(text, encoding="utf-8")
PY
cat > "$company_container/plan.md" <<'EOF'
---
title: "DP-999 terminal non-authoritative plan"
status: IMPLEMENTED
---

# Non-authoritative plan fixture
EOF
cat > "/tmp/polaris-verified-GT-ARCH-${head_sha}.json" <<EOF
{
  "ticket": "GT-ARCH",
  "head_sha": "${head_sha}",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "at": "2026-05-09T00:00:00Z"
}
EOF
bash "$WRITE_REPORT" \
  --repo "$main_repo" \
  --ticket GT-ARCH \
  --task-md "$company_task" \
  --head-sha "$head_sha" \
  --status PASS >/dev/null
bash "$REFRESH_SNAPSHOT" \
  --repo "$main_repo" \
  --task-md "$company_task" \
  --head-sha "$head_sha" >/dev/null
set +e
out5="$(
    POLARIS_COMPLETION_TASK_MD="$company_task" \
    POLARIS_SKIP_CI_LOCAL=1 \
    POLARIS_SKIP_EVIDENCE=1 \
    POLARIS_SKIP_PR_TITLE_GATE=1 \
    POLARIS_SKIP_CHANGESET_GATE=1 \
    PATH="$mockbin:$PATH" \
    "$FINALIZE" --repo "$main_repo" --ticket GT-ARCH --workspace "$main_repo" 2>&1
)"
set -e
if grep -q 'archived parent closeout already complete' <<< "$out5"; then
  printf '%s\n' "$out5" >&2
  echo "not ok company plan.md overrode present refinement.md authority" >&2
  exit 1
fi
if ! grep -q 'archived parent is not terminal: .*refinement.md (LOCKED)' <<< "$out5"; then
  printf '%s\n' "$out5" >&2
  echo "not ok company refinement.md precedence or company-named-tasks parsing drifted" >&2
  exit 1
fi

# The production finalizer may execute from the implementation worktree it
# removes. Parent closeout must run before cleanup; release-completed must use a
# stable helper and run after cleanup so it can prove no residual worktree.
python3 - "$FINALIZE" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
load = text.index('. "${SCRIPT_DIR}/lib/specs-root.sh"')
cleanup = text.index('bash "${SCRIPT_DIR}/engineering-clean-worktree.sh"')
parent_closeout = text.index('if archived_parent_closeout_complete "$TASK_MD_PATH"')
release_completed = text.index('bash "$CHECK_RELEASE_COMPLETED"')
unsafe_helper_guard = text.index('release-completed helper must live outside the implementation worktree')
first_mutating_phase = text.index("prepare_no_pr_deliverable\nensure_task_verify_report")
assert text.count('. "${SCRIPT_DIR}/lib/specs-root.sh"') == 1
assert load < parent_closeout < cleanup < release_completed
assert unsafe_helper_guard < first_mutating_phase
PY

# DP-422 T2: finalize must select the canonical no-PR writer from task_shape
# only after current HEAD-bound verification evidence has passed. These source
# assertions guard the orchestration binding; writer/validator/consumer behavior
# is exercised by their dedicated selftests.
grep -q 'prepare_no_pr_deliverable' "$FINALIZE"
grep -q 'check-verification-passed.sh' "$FINALIZE"
grep -q 'write-deliverable.sh.*--no-pr' "$FINALIZE"
bash "$SCRIPT_DIR/selftests/write-deliverable-selftest.sh" >/dev/null

echo "[finalize-engineering-delivery-selftest] PASS"
