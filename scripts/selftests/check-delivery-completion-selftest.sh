#!/usr/bin/env bash
set -euo pipefail

# scripts/check-delivery-completion-selftest.sh — selftest for Developer completion PR readiness.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-delivery-completion.sh"
WRITE_REPORT="$SCRIPT_DIR/write-task-verify-report.sh"
TMPROOT="$(mktemp -d -t completion-gate-selftest-XXXXXX)"
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

write_task() {
  local repo="$1"
  local head_sha="$2"
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks"
  cat > "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks/T1.md" <<EOF
---
deliverable:
  pr_url: https://github.com/demo/example/pull/1
  pr_state: OPEN
  head_sha: $head_sha
status: IN_PROGRESS
depends_on: []
---

# T1: completion gate fixture (1 pt)

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
| Branch chain | main -> task/DP-999-T1-completion-gate-fixture |
| Task branch | task/DP-999-T1-completion-gate-fixture |
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

write_task_without_deliverable() {
  local repo="$1"
  mkdir -p "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks"
  cat > "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks/T1.md" <<'EOF'
---
status: IN_PROGRESS
depends_on: []
---

# T1: stale worktree copy (1 pt)

> Source: DP-999 | Task: DP-999-T1 | JIRA: N/A | Repo: example

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-999 |
| Task ID | DP-999-T1 |
| JIRA key | N/A |
| Base branch | main |
| Branch chain | main -> task/DP-999-T1-completion-gate-fixture |
| Task branch | task/DP-999-T1-completion-gate-fixture |

## Allowed Files

- `scripts/**`

## Test Command

```bash
echo ok
```

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo ok
```
EOF
}

write_task_with_behavior_contract() {
  local repo="$1"
  local head_sha="$2"
  write_task "$repo" "$head_sha"
  python3 - "$repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks/T1.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
insert = """verification:
  behavior_contract:
    applies: true
    mode: parity
    source_of_truth: existing_behavior
    fixture_policy: mockoon_required
    baseline_ref: main
    flow: "completion gate fixture"
    assertions:
      - "existing user-visible behavior remains stable"
    allowed_differences: []
"""
if "verification:" not in text:
    text = text.replace("---\n\n# T1:", f"{insert}---\n\n# T1:", 1)
path.write_text(text, encoding="utf-8")
PY
}

write_task_verify_report() {
  local task_repo="$1"
  local evidence_repo="$2"
  local head_sha="$3"

  bash "$WRITE_REPORT" \
    --repo "$evidence_repo" \
    --ticket DP-999-T1 \
    --task-md "$task_repo/docs-manager/src/content/docs/specs/design-plans/DP-999-completion-gate/tasks/T1.md" \
    --head-sha "$head_sha" \
    --status PASS >/dev/null
}

setup_repo() {
  local repo="$1"

  mkdir -p "$repo/.github"
  cat > "$repo/workspace-config.yaml" <<'EOF'
language: zh-TW
projects:
  - name: example
    repo: demo/example
    delivery:
      pr_review_label:
        policy: required
        labels:
          - "👀 need review"
          - ":eyes: need review"
EOF
  cat > "$repo/.github/pull_request_template.md" <<'EOF'
## Description

## Changed

## Screenshots (Test Plan)

## Related documents

## QA notes
EOF

  git -C "$repo" init -q
  git -C "$repo" checkout -q -b task/DP-999-T1-completion-gate-fixture
  git -C "$repo" config user.email "polaris@example.test"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" remote add origin https://github.com/demo/example.git
  touch "$repo/README.md"
  git -C "$repo" add README.md workspace-config.yaml .github/pull_request_template.md
  git -C "$repo" commit -q -m "init"
}

install_mock_gh() {
  local mockbin="$1"
  local body_file="$2"
  local state="$3"
  local is_draft="$4"
  local head_sha="$5"
  local comments_file="${6:-}"
  local threads_file="${7:-}"
  local assignee="${8:-polaris-selftest}"
  local merge_state="${9:-CLEAN}"
  local review_label="${10:-👀 need review}"

  mkdir -p "$mockbin"
  if [[ -z "$comments_file" ]]; then
    comments_file="$TMPROOT/empty-comments.json"
    printf '[]\n' > "$comments_file"
  fi
  if [[ -z "$threads_file" ]]; then
    threads_file="$TMPROOT/no-active-review-threads.json"
    cat > "$threads_file" <<'EOF'
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
EOF
  fi
  local python_draft="False"
  if [[ "$is_draft" == "true" ]]; then
    python_draft="True"
  fi
  local rest_state
  rest_state="$(printf '%s' "$state" | tr '[:upper:]' '[:lower:]')"
  local assignees_json='[]'
  if [[ "$assignee" != "none" ]]; then
    assignees_json="[{\"login\":\"$assignee\"}]"
  fi
  local labels_json='[]'
  if [[ "$review_label" != "none" ]]; then
    labels_json="[{\"name\":\"$review_label\"}]"
  fi

  cat > "$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "pr view" ]]; then
  python3 - <<'PY'
import json
from pathlib import Path

body = Path("$body_file").read_text(encoding="utf-8")
print(json.dumps({
    "assignees": $assignees_json,
    "body": body,
    "isDraft": $python_draft,
    "labels": $labels_json,
    "mergeStateStatus": "$merge_state",
    "number": 1,
    "reviewDecision": "REVIEW_REQUIRED",
    "state": "$state",
    "url": "https://github.com/demo/example/pull/1",
    "headRefName": "task/DP-999-T1-completion-gate-fixture",
    "headRefOid": "$head_sha",
    "baseRefName": "main",
}))
PY
  exit 0
fi
if [[ "\$1" == "api" ]]; then
  if [[ "\$2" == "graphql" ]]; then
    cat "$threads_file"
    exit 0
  fi
  if [[ "\$2" == "repos/demo/example/issues/1" ]]; then
    python3 - <<'PY'
import json
print(json.dumps({"assignees": $assignees_json, "labels": $labels_json}))
PY
    exit 0
  fi
  if [[ "\$2" == "repos/demo/example/pulls/1" ]]; then
    python3 - <<'PY'
import json
from pathlib import Path

body = Path("$body_file").read_text(encoding="utf-8")
print(json.dumps({
    "assignees": $assignees_json,
    "labels": $labels_json,
    "number": 1,
    "title": "Fixture PR",
    "body": body,
    "state": "$rest_state",
    "draft": $python_draft,
    "html_url": "https://github.com/demo/example/pull/1",
    "head": {
        "ref": "task/DP-999-T1-completion-gate-fixture",
        "sha": "$head_sha"
    },
    "base": {"ref": "main"},
    "mergeable_state": "$merge_state",
    "user": {"login": "polaris-selftest"}
}))
PY
    exit 0
  fi
  cat "$comments_file"
  exit 0
fi
if [[ "\$1 \$2" == "pr comment" ]]; then
  exit 0
fi
echo "unexpected gh call: \$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"
}

write_review_thread_disposition() {
  local repo="$1"
  local head_sha="$2"
  mkdir -p "$repo/.polaris/evidence/review-thread-disposition"
  cat > "$repo/.polaris/evidence/review-thread-disposition/polaris-review-thread-disposition-DP-999-T1-${head_sha}.json" <<'EOF'
{
  "version": 1,
  "pr": "https://github.com/demo/example/pull/1",
  "threads": [
    {
      "thread_id": "PRRT_active_1",
      "disposition": "fixed",
      "reason": "implemented reviewer requested guard and pushed verification"
    }
  ]
}
EOF
}

write_behavior_evidence() {
  local repo="$1"
  local with_video="$2"

  mkdir -p "$repo/.polaris/evidence/playwright/DP-999-T1"
  if [[ "$with_video" == "true" ]]; then
    cat > "$repo/.polaris/evidence/playwright/DP-999-T1/playwright-behavior-video.json" <<'EOF'
{
  "writer": "playwright-behavior-recorder",
  "ticket": "DP-999-T1",
  "flow": "lightbox carousel",
  "video_path": ".polaris/evidence/playwright/DP-999-T1/lightbox-carousel.webm"
}
EOF
    printf 'fake-video\n' > "$repo/.polaris/evidence/playwright/DP-999-T1/lightbox-carousel.webm"
  else
    cat > "$repo/.polaris/evidence/playwright/DP-999-T1/playwright-behavior-video.json" <<'EOF'
{
  "writer": "playwright-behavior-recorder",
  "ticket": "DP-999-T1",
  "flow": "lightbox carousel"
}
EOF
  fi
}

write_generic_behavior_evidence() {
  local repo="$1"
  local head_sha="$2"

  mkdir -p "$repo/.polaris/evidence/behavior/DP-999-T1/compare-abc123"
  printf 'fake-screenshot\n' > "$repo/.polaris/evidence/behavior/DP-999-T1/compare-abc123/lightbox-carousel.png"
  cat > "$repo/.polaris/evidence/behavior/DP-999-T1/polaris-behavior-DP-999-T1-${head_sha}-abc123.json" <<EOF
{
  "schema_version": 1,
  "ticket": "DP-999-T1",
  "head_sha": "${head_sha}",
  "writer": "run-behavior-contract.sh",
  "mode": "compare",
  "behavior_mode": "parity",
  "status": "PASS",
  "at": "2026-05-05T00:00:00Z",
  "context_hash": "abc123",
  "screenshots": ["$repo/.polaris/evidence/behavior/DP-999-T1/compare-abc123/lightbox-carousel.png"],
  "videos": [],
  "assertion_results": [
    {
      "assertion": "lightbox opens",
      "status": "PASS",
      "source": "selftest screenshot evidence"
    }
  ]
}
EOF
}

write_verify_evidence() {
  local repo="$1"
  local head_sha="$2"
  mkdir -p "$repo/.polaris/evidence/verify"
  cat > "/tmp/polaris-verified-DP-999-T1-${head_sha}.json" <<EOF
{
  "ticket": "DP-999-T1",
  "head_sha": "${head_sha}",
  "writer": "run-verify-command.sh",
  "exit_code": 0,
  "at": "2026-05-06T00:00:00Z"
}
EOF
  cp "/tmp/polaris-verified-DP-999-T1-${head_sha}.json" "$repo/.polaris/evidence/verify/polaris-verified-DP-999-T1-${head_sha}.json"
}

run_case() {
  local label="$1"
  local state="$2"
  local is_draft="$3"
  local body_kind="$4"
  local want_rc="$5"
  local want_text="$6"

  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  if [[ "$body_kind" == "valid" ]]; then
    cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  elif [[ "$body_kind" == "english" ]]; then
    cat > "$body_file" <<'EOF'
## Description

This is a full English pull request body that should fail the zh-TW language policy.

## Changed

- Script gate update.

## Screenshots (Test Plan)

- Selftest.

## Related documents

- DP-999

## QA notes

- N/A
EOF
  else
    cat > "$body_file" <<'EOF'
## Summary

- Selftest body.

## Verification

- Selftest.
EOF
  fi

  install_mock_gh "$mockbin" "$body_file" "$state" "$is_draft" "$head_sha"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "$want_rc"
  assert_contains "$label message" "$out" "$want_text"
}

run_case "draft-blocks" "OPEN" "true" "valid" "2" "deliverable PR is draft"
run_case "closed-blocks" "CLOSED" "false" "valid" "2" "deliverable PR must be OPEN"
run_case "invalid-body-blocks" "OPEN" "false" "invalid" "2" "does not preserve repo template headings"
run_case "english-body-blocks" "OPEN" "false" "english" "2" "PR text violates workspace language policy"
run_case "ready-pr-passes" "OPEN" "false" "valid" "0" "PR readiness/body/language/evidence publication/review-thread gates passed"

run_assignee_case() {
  local label="missing-assignee-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "" "" "none"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "final PR assignee metadata is empty"
}

run_assignee_case

run_review_label_case() {
  local label="missing-review-label-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "" "" "polaris-selftest" "CLEAN" "none"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "configured review label is missing"
}

run_review_label_case

run_behind_case() {
  local label="behind-merge-state-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "" "" "polaris-selftest" "BEHIND"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "PR shared readiness check failed"
}

run_behind_case

run_pending_ci_snapshot_case() {
  local label="pending-ci-unstable-snapshot"
  local repo="$TMPROOT/$label/repo"
  local pr_json="$TMPROOT/$label/pr.json"
  local checks_json="$TMPROOT/$label/checks.json"
  local snapshot=""
  mkdir -p "$TMPROOT/$label"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"

  cat > "$pr_json" <<EOF
{
  "number": 1,
  "url": "https://github.com/demo/example/pull/1",
  "state": "OPEN",
  "headRefName": "task/DP-999-T1-completion-gate-fixture",
  "headRefOid": "$head_sha",
  "baseRefName": "main",
  "mergeStateStatus": "UNSTABLE",
  "reviewDecision": "REVIEW_REQUIRED"
}
EOF
  cat > "$checks_json" <<'EOF'
[
  {"name": "ci", "state": "PENDING", "conclusion": null}
]
EOF

  snapshot="$(bash "$SCRIPT_DIR/pr-state-snapshot.sh" --repo "$repo" --pr-json "$pr_json" --checks-json "$checks_json" --intent read-only)"
  assert_contains "$label mergeability" "$snapshot" '"mergeability":"clean"'
  assert_contains "$label reason" "$snapshot" '"readiness_reason":"pending_ci"'
}

run_pending_ci_snapshot_case

run_missing_report_case() {
  local label="missing-task-verify-report-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "missing task-bound verify report"
}

run_missing_report_case

run_publication_case() {
  local label="$1"
  local comments_kind="$2"
  local with_video="$3"
  local want_rc="$4"
  local want_text="$5"

  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  local comments_file="$TMPROOT/$label/comments.json"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_behavior_evidence "$repo" "$with_video"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF

  if [[ "$comments_kind" == "marker" ]]; then
    cat > "$comments_file" <<EOF
[
  {
    "body": "<!-- polaris-evidence-publication:v1 ticket=DP-999-T1 head=${head_sha} manifest_sha256=fixture -->\\n## Polaris evidence publication"
  }
]
EOF
  elif [[ "$comments_kind" == "report" ]]; then
    cat > "$comments_file" <<EOF
[
  {
    "body": "polaris-verify-report:v1 ticket=DP-999-T1 head=${head_sha} report=https://example.test/specs/verify-report/"
  }
]
EOF
  elif [[ "$comments_kind" == "jira" ]]; then
    cat > "$comments_file" <<EOF
[
  {
    "body": "polaris-jira-evidence:v1 ticket=DP-999-T1 head=${head_sha} url=https://example.atlassian.net/rest/api/3/attachment/content/10001"
  }
]
EOF
  else
    printf '[]\n' > "$comments_file"
  fi

  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "$comments_file"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "$want_rc"
  assert_contains "$label message" "$out" "$want_text"
}

run_publication_case "publication-missing-marker-blocks" "none" "true" "2" "No PR-visible evidence publication proof"
run_publication_case "publication-marker-passes" "marker" "true" "0" "PR-visible evidence publication proof found"
run_publication_case "publication-report-marker-passes" "report" "true" "0" "PR-visible evidence publication proof found"
run_publication_case "publication-jira-marker-passes" "jira" "true" "0" "PR-visible evidence publication proof found"
run_publication_case "behavior-without-video-blocks" "marker" "false" "2" "Playwright behavior evidence requires video reference"

run_generic_behavior_screenshot_case() {
  local label="generic-behavior-screenshot-marker-passes"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  local comments_file="$TMPROOT/$label/comments.json"
  mkdir -p "$(dirname "$repo")"
  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_generic_behavior_evidence "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF

  cat > "$comments_file" <<EOF
[
  {
    "body": "<!-- polaris-evidence-publication:v1 ticket=DP-999-T1 head=${head_sha} manifest_sha256=fixture -->\\n## Polaris evidence publication"
  }
]
EOF

  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "$comments_file"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "0"
  assert_contains "$label message" "$out" "PR-visible evidence publication proof found"
}

run_generic_behavior_screenshot_case

run_overlay_case() {
  local label="overlay-prefers-main-task"
  local main_repo="$TMPROOT/$label/main"
  local worktree_repo="$TMPROOT/$label/worktree"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$TMPROOT/$label"

  setup_repo "$main_repo"
  git -C "$main_repo" branch main
  git -C "$main_repo" checkout -q main
  git -C "$main_repo" worktree add -q "$worktree_repo" task/DP-999-T1-completion-gate-fixture

  local head_sha
  head_sha="$(git -C "$worktree_repo" rev-parse HEAD)"
  write_task "$main_repo" "$head_sha"
  write_task_verify_report "$main_repo" "$worktree_repo" "$head_sha"
  write_task_without_deliverable "$worktree_repo"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_EVIDENCE=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$worktree_repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "0"
  assert_contains "$label message" "$out" "PR readiness/body/language/evidence publication/review-thread gates passed"
}

run_overlay_case

run_review_thread_case() {
  local label="$1"
  local with_manifest="$2"
  local want_rc="$3"
  local want_text="$4"

  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  local comments_file="$TMPROOT/$label/comments.json"
  local threads_file="$TMPROOT/$label/threads.json"
  mkdir -p "$TMPROOT/$label"

  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task "$repo" "$head_sha"
  write_verify_evidence "$repo" "$head_sha"
  if [[ "$with_manifest" == "true" ]]; then
    write_review_thread_disposition "$repo" "$head_sha"
  fi
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  printf '[]\n' > "$comments_file"
  cat > "$threads_file" <<'EOF'
{
  "data": {
    "repository": {
      "pullRequest": {
        "url": "https://github.com/demo/example/pull/1",
        "reviewThreads": {
          "nodes": [
            {
              "id": "PRRT_active_1",
              "isResolved": false,
              "isOutdated": false,
              "path": "src/a.ts",
              "line": 10,
              "comments": {"nodes": [{"url": "https://github.com/demo/example/pull/1#discussion_r1"}]}
            }
          ]
        }
      }
    }
  }
}
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha" "$comments_file" "$threads_file"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "$want_rc"
  assert_contains "$label message" "$out" "$want_text"
}

run_review_thread_case "review-thread-missing-disposition-blocks" "false" "2" "unresolved PR review threads require explicit disposition evidence"
run_review_thread_case "review-thread-disposition-passes" "true" "0" "review-thread gates passed"

run_behavior_contract_case() {
  local label="behavior-contract-missing-evidence-blocks"
  local repo="$TMPROOT/$label/repo"
  local mockbin="$TMPROOT/$label/bin"
  local body_file="$TMPROOT/$label/body.md"
  mkdir -p "$TMPROOT/$label"

  setup_repo "$repo"
  local head_sha
  head_sha="$(git -C "$repo" rev-parse HEAD)"
  write_task_with_behavior_contract "$repo" "$head_sha"
  write_verify_evidence "$repo" "$head_sha"
  write_task_verify_report "$repo" "$repo" "$head_sha"

  cat > "$body_file" <<'EOF'
## Description

這是 completion gate selftest 內容。

## Changed

- 補齊 completion gate 檢查。

## Screenshots (Test Plan)

- 已執行 selftest。

## Related documents

- DP-999

## QA notes

- N/A
EOF
  install_mock_gh "$mockbin" "$body_file" "OPEN" "false" "$head_sha"

  set +e
  out="$(POLARIS_SKIP_CI_LOCAL=1 POLARIS_SKIP_PR_TITLE_GATE=1 POLARIS_SKIP_CHANGESET_GATE=1 PATH="$mockbin:$PATH" "$CHECK" --repo "$repo" --ticket DP-999-T1 2>&1)"
  rc=$?
  set -e

  assert_rc "$label rc" "$rc" "2"
  assert_contains "$label message" "$out" "No behavior contract evidence"
}

run_behavior_contract_case

printf '\n=== check-delivery-completion selftest: %d/%d PASS ===\n' "$PASS" "$TOTAL"
[[ "$PASS" -eq "$TOTAL" ]]
