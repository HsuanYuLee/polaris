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

main_repo="$TMPROOT/workspace"
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

if printf '%s\n' "$out" | grep -qE 'getcwd|cannot access parent directories'; then
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

# DP-301 T4 (FD3 / AC4): finalize must auto-write the engineering-owned
# completion_gate marker as a deterministic side effect. The marker anchors at the
# main checkout under .polaris/evidence/completion-gate/<work-item>-<sha>.json.
marker_path="$main_repo/.polaris/evidence/completion-gate/DP-999-T1-${head_sha}.json"
if [[ ! -f "$marker_path" ]]; then
  echo "not ok finalize did not auto-write completion_gate marker (expected $marker_path)" >&2
  exit 1
fi

# Marker must be a PASS completion_gate roll-up bound to the finalized head sha.
if ! python3 - "$marker_path" "$head_sha" <<'PY'
import json
import sys
from pathlib import Path

marker_path, head_sha = sys.argv[1:3]
data = json.loads(Path(marker_path).read_text(encoding="utf-8"))
assert data.get("marker_kind") == "completion_gate", data.get("marker_kind")
assert data.get("status") == "PASS", data.get("status")
assert data.get("work_item_id") == "DP-999-T1", data.get("work_item_id")
freshness = data.get("freshness") or {}
marker_head = str(freshness.get("head_sha") or "")
assert marker_head == head_sha or head_sha.startswith(marker_head) or marker_head.startswith(head_sha), marker_head
PY
then
  echo "not ok completion_gate marker has wrong kind/status/work_item_id/head_sha" >&2
  exit 1
fi

# AC4 idempotency (adversarial): a second completion_gate auto-write for the same
# {work_item_id}-{head_sha} must NOT mutate the marker. finalize's idempotency guard
# detects the existing marker and no-ops, so the marker stays byte-identical even
# though write-completion-gate-marker.sh itself re-stamps `at` on every direct call
# (refinement EC4: no drift on same head-sha re-write).
marker_before="$(python3 - "$marker_path" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

# Re-run finalize against the now-finalized (pr-release) task. resolve-task-md.sh still
# resolves it, the mock PR is still OPEN, and the completion_gate auto-write must hit
# the idempotency guard rather than overwrite the marker.
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

if [[ ! -f "$marker_path" ]]; then
  printf '%s\n' "$out2" >&2
  echo "not ok completion_gate marker vanished after second finalize" >&2
  exit 1
fi

marker_after="$(python3 - "$marker_path" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"

if [[ "$marker_before" != "$marker_after" ]]; then
  printf '%s\n' "$out2" >&2
  echo "not ok completion_gate marker drifted on idempotent re-run (before=$marker_before after=$marker_after)" >&2
  exit 1
fi

if ! printf '%s\n' "$out2" | grep -q 'auto-write is a no-op'; then
  printf '%s\n' "$out2" >&2
  echo "not ok second finalize did not report idempotent no-op for completion_gate marker" >&2
  exit 1
fi

echo "[finalize-engineering-delivery-selftest] PASS"
