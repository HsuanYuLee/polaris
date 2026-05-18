#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/framework-release-preflight.sh"
TMPROOT="$(mktemp -d -t framework-release-preflight.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

HEAD_SHA="1111111111111111111111111111111111111111"
PR_URL="https://github.com/demo/example/pull/189"

write_fixture() {
  local name="$1"
  local ac_status="$2"
  local disposition="$3"
  local summary="$4"
  local with_evidence="$5"
  local dirty="${6:-clean}"

  local root="$TMPROOT/$name"
  local repo="$root/repo"
  local evidence_dir="$root/evidence/pr-create"
  local preflight_dir="$root/evidence/preflight"
  local mockbin="$root/bin"
  local task_md="$repo/docs-manager/src/content/docs/specs/design-plans/DP-189-preflight/tasks/pr-release/T1/index.md"
  local v_md="$repo/docs-manager/src/content/docs/specs/design-plans/DP-189-preflight/tasks/V1/index.md"

  mkdir -p "$(dirname "$task_md")" "$(dirname "$v_md")" "$evidence_dir" "$preflight_dir" "$mockbin"
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.invalid"

  cat >"$task_md" <<EOF
---
title: "DP-189-T1: release preflight selftest"
description: "selftest"
status: IMPLEMENTED
deliverable:
  pr_url: $PR_URL
  pr_state: OPEN
  head_sha: $HEAD_SHA
---

# T1: release preflight selftest

> Source: DP-189 | Task: DP-189-T1 | JIRA: N/A | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-189 |
| Task ID | DP-189-T1 |
| JIRA key | N/A |
| Task branch | task/DP-189-T1-release-preflight |
EOF

  cat >"$v_md" <<EOF
---
title: "DP-189-V1: selftest"
status: IMPLEMENTED
ac_verification:
  status: $ac_status
  human_disposition: $disposition
  summary: "$summary"
---

# V1
EOF

  cat >"$mockbin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
  printf '%s\n' "$HEAD_SHA"
  exit 0
fi
printf 'unexpected gh call: %s\n' "\$*" >&2
exit 1
EOF
  chmod +x "$mockbin/gh"

  if [[ "$with_evidence" == "yes" ]]; then
    cat >"$evidence_dir/DP-189-T1-$HEAD_SHA.json" <<EOF
{
  "writer": "polaris-pr-create.sh",
  "task_id": "DP-189-T1",
  "task_artifact_sha256": "fixture",
  "head_sha": "$HEAD_SHA",
  "pr_url": "$PR_URL",
  "pr_number": 189,
  "gate_summary": {"evidence": "passed"}
}
EOF
  fi

  git -C "$repo" add .
  git -C "$repo" commit -q -m "fixture"
  if [[ "$dirty" == "dirty" ]]; then
    printf 'dirty\n' >>"$repo/README.md"
  fi

  printf '%s\t%s\t%s\t%s\n' "$repo" "$task_md" "$evidence_dir" "$preflight_dir"
}

run_expect_pass() {
  local label="$1"
  local fixture="$2"
  local repo task_md evidence_dir preflight_dir
  IFS=$'\t' read -r repo task_md evidence_dir preflight_dir <<<"$fixture"
  PATH="$(dirname "$repo")/bin:$PATH" \
    POLARIS_PR_CREATE_EVIDENCE_DIR="$evidence_dir" \
    POLARIS_RELEASE_PREFLIGHT_DIR="$preflight_dir" \
    bash "$PREFLIGHT" --repo "$repo" --task-md "$task_md" --pr-url "$PR_URL" >/tmp/preflight-pass.out
  ls "$preflight_dir"/*.json >/dev/null
  echo "ok $label"
}

run_expect_fail() {
  local label="$1"
  local fixture="$2"
  local expected="$3"
  local repo task_md evidence_dir preflight_dir rc output
  IFS=$'\t' read -r repo task_md evidence_dir preflight_dir <<<"$fixture"
  set +e
  output="$(
    PATH="$(dirname "$repo")/bin:$PATH" \
      POLARIS_PR_CREATE_EVIDENCE_DIR="$evidence_dir" \
      POLARIS_RELEASE_PREFLIGHT_DIR="$preflight_dir" \
      bash "$PREFLIGHT" --repo "$repo" --task-md "$task_md" --pr-url "$PR_URL" 2>&1
  )"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: $label unexpectedly passed" >&2
    exit 1
  fi
  grep -q "$expected" <<<"$output" || {
    echo "FAIL: $label missing expected output: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  }
  echo "ok $label"
}

run_expect_pass "pass" "$(write_fixture pass PASS passed ok yes)"
run_expect_fail "generic publisher without evidence" "$(write_fixture no-evidence PASS passed ok no)" "missing head-bound PR create evidence"
run_expect_fail "post-hoc marker without evidence" "$(write_fixture body-marker PASS passed 'PR body marker is not authority' no)" "missing head-bound PR create evidence"
run_expect_fail "missing verify-AC disposition" "$(write_fixture missing-disposition PASS '' ok yes)" "verify-AC disposition"
run_expect_fail "uncertain blocks release" "$(write_fixture uncertain UNCERTAIN pending unclear yes)" "verify-AC disposition"
run_expect_fail "blocked env blocks release" "$(write_fixture blocked-env BLOCKED_ENV pending env yes)" "verify-AC disposition"
run_expect_fail "in progress blocks release" "$(write_fixture in-progress IN_PROGRESS pending running yes)" "verify-AC disposition"
run_expect_fail "fail blocks release" "$(write_fixture fail FAIL failed broken yes)" "verify-AC disposition"
run_expect_fail "dirty worktree" "$(write_fixture dirty PASS passed ok yes dirty)" "release worktree must be clean"

echo "PASS: framework-release-preflight selftest"
