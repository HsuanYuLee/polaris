#!/usr/bin/env bash
# write-deliverable-selftest.sh — 驗證 deliverable writer 的 PR 與 no-PR 契約。
#
# 覆蓋 durable verify evidence、task-bound report、原子寫入與冪等性。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WRITER="$ROOT/scripts/write-deliverable.sh"
REPORT_WRITER="$ROOT/scripts/write-task-verify-report.sh"
TMPROOT="$(mktemp -d -t write-deliverable-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

write_task() {
  local path="$1" shape="$2" source_type="${3:-dp}" source_id="${4:-DP-422}"
  local work_item_id="${5:-DP-422-T1}" jira_key="${6:-N/A}"
  cat >"$path" <<EOF
---
title: "${source_id} writer fixture"
description: "task_shape-first no-PR writer fixture."
status: IN_PROGRESS
task_kind: T
task_shape: $shape
verification:
  behavior_contract:
    applies: false
    reason: "framework selftest fixture"
---

# T1: writer fixture (1 pt)

> Source: ${source_id} | Task: ${work_item_id} | JIRA: ${jira_key} | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | ${source_type} |
| Source ID | ${source_id} |
| Work item ID | ${work_item_id} |
| Task ID | ${work_item_id} |
| JIRA key | ${jira_key} |
| Test sub-tasks | N/A - self-contained |
| AC 驗收單 | N/A - self-contained |
| Base branch | main |
| Branch chain | main -> task/DP-422-T1-fixture |
| Task branch | task/DP-422-T1-fixture |
| Depends on | N/A |
| References to load | - \`scripts/write-deliverable.sh\` |

## 目標

驗證 no-PR writer。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| \`scripts/write-deliverable.sh\` | modify | fixture |

## Allowed Files

- \`scripts/write-deliverable.sh\`

## 估點理由

1 pt - fixture。

## 測試計畫（code-level）

- 執行 writer 與 validator。

## Test Command

\`\`\`bash
echo PASS
\`\`\`

## Test Environment

- **Level**: build
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

\`\`\`bash
echo PASS
\`\`\`
EOF
}

write_evidence() {
  local repo="$1" head="$2" exit_code="${3:-0}" ticket="${4:-DP-422-T1}"
  local path="$repo/.polaris/evidence/verify/polaris-verified-${ticket}-${head}.json"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<EOF
{"ticket":"$ticket","head_sha":"$head","writer":"run-verify-command.sh","exit_code":$exit_code,"at":"2026-07-16T00:00:00Z"}
EOF
}

setup_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email polaris@example.test
  git -C "$repo" config user.name "Polaris Selftest"
  printf 'fixture\n' >"$repo/fixture.txt"
  git -C "$repo" add fixture.txt
  git -C "$repo" commit -q -m init
}

audit_task="$TMPROOT/audit.md"
audit_repo="$TMPROOT/audit-repo"
setup_repo "$audit_repo"
audit_head="$(git -C "$audit_repo" rev-parse HEAD)"
write_task "$audit_task" audit
write_evidence "$audit_repo" "$audit_head"
bash "$WRITER" --no-pr "$audit_task" "$audit_head" --repo "$audit_repo"

grep -q "^  head_sha: ${audit_head}$" "$audit_task"
grep -q '^    status: PASS$' "$audit_task"
if grep -qE '^  pr_(url|state):' "$audit_task"; then
  echo "FAIL: no-PR writer emitted PR metadata" >&2
  exit 1
fi

before="$(shasum -a 256 "$audit_task" | awk '{print $1}')"
bash "$WRITER" --no-pr "$audit_task" "$audit_head" --repo "$audit_repo"
after="$(shasum -a 256 "$audit_task" | awk '{print $1}')"
[[ "$before" == "$after" ]] || { echo "FAIL: no-PR writer is not idempotent" >&2; exit 1; }

implementation_task="$TMPROOT/implementation.md"
write_task "$implementation_task" implementation
if bash "$WRITER" --no-pr "$implementation_task" "$audit_head" --repo "$audit_repo" >/dev/null 2>&1; then
  echo "FAIL: implementation task accepted no-PR writer" >&2
  exit 1
fi

failed_task="$TMPROOT/failed.md"
failed_repo="$TMPROOT/failed-repo"
setup_repo "$failed_repo"
failed_head="$(git -C "$failed_repo" rev-parse HEAD)"
write_task "$failed_task" confirmation
write_evidence "$failed_repo" "$failed_head" 1
if bash "$WRITER" --no-pr "$failed_task" "$failed_head" --repo "$failed_repo" >/dev/null 2>&1; then
  echo "FAIL: no-PR writer accepted failing verification evidence" >&2
  exit 1
fi

tmp_only_task="$TMPROOT/tmp-only.md"
tmp_only_repo="$TMPROOT/tmp-only-repo"
setup_repo "$tmp_only_repo"
tmp_only_head="$(git -C "$tmp_only_repo" rev-parse HEAD)"
write_task "$tmp_only_task" audit
tmp_only_path="/tmp/polaris-verified-DP-422-T1-${tmp_only_head}.json"
cat >"$tmp_only_path" <<EOF
{"ticket":"DP-422-T1","head_sha":"$tmp_only_head","writer":"run-verify-command.sh","exit_code":0,"at":"2026-07-16T00:00:00Z"}
EOF
if bash "$WRITER" --no-pr "$tmp_only_task" "$tmp_only_head" --repo "$tmp_only_repo" >/dev/null 2>&1; then
  rm -f "$tmp_only_path"
  echo "FAIL: no-PR writer accepted tmp-only verification evidence" >&2
  exit 1
fi
rm -f "$tmp_only_path"

invalid_task="$TMPROOT/invalid-schema.md"
invalid_repo="$TMPROOT/invalid-schema-repo"
setup_repo "$invalid_repo"
invalid_head="$(git -C "$invalid_repo" rev-parse HEAD)"
write_task "$invalid_task" audit
python3 - "$invalid_task" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("## Test Command", "## Missing Test Command", 1), encoding="utf-8")
PY
write_evidence "$invalid_repo" "$invalid_head"
invalid_before="$(shasum -a 256 "$invalid_task" | awk '{print $1}')"
if bash "$WRITER" --no-pr "$invalid_task" "$invalid_head" --repo "$invalid_repo" >/dev/null 2>&1; then
  echo "FAIL: no-PR writer accepted task schema failure" >&2
  exit 1
fi
invalid_after="$(shasum -a 256 "$invalid_task" | awk '{print $1}')"
[[ "$invalid_before" == "$invalid_after" ]] || { echo "FAIL: schema failure mutated original task.md" >&2; exit 1; }
if find "$TMPROOT" -maxdepth 2 -type d -name '.write-deliverable.*' | grep -q .; then
  echo "FAIL: no-PR writer left unique temp directories behind" >&2
  exit 1
fi

non_git_task="$TMPROOT/non-git.md"
non_git_repo="$TMPROOT/non-git-repo"
mkdir -p "$non_git_repo"
write_task "$non_git_task" audit
if bash "$WRITER" --no-pr "$non_git_task" "$audit_head" --repo "$non_git_repo" >/dev/null 2>&1; then
  echo "FAIL: no-PR writer accepted non-Git repository" >&2
  exit 1
fi

stale_task="$TMPROOT/stale.md"
stale_repo="$TMPROOT/stale-repo"
setup_repo "$stale_repo"
stale_head="$(git -C "$stale_repo" rev-parse HEAD)"
write_task "$stale_task" confirmation
write_evidence "$stale_repo" "$stale_head"
printf 'new head\n' >>"$stale_repo/fixture.txt"
git -C "$stale_repo" add fixture.txt
git -C "$stale_repo" commit -q -m advance
if bash "$WRITER" --no-pr "$stale_task" "$stale_head" --repo "$stale_repo" >/dev/null 2>&1; then
  echo "FAIL: no-PR writer accepted stale repository HEAD" >&2
  exit 1
fi

bash "$WRITER" "$implementation_task" https://github.com/demo/example/pull/1 OPEN bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
grep -q '^  pr_url: https://github.com/demo/example/pull/1$' "$implementation_task"
grep -q '^  pr_state: OPEN$' "$implementation_task"
grep -q '^  head_sha: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb$' "$implementation_task"

# PR task 的 PASS 必須由同一 head 的 durable evidence 與 task-bound report 支撐。
verified_pr_task="$TMPROOT/verified-pr.md"
verified_pr_repo="$TMPROOT/verified-pr-repo"
setup_repo "$verified_pr_repo"
verified_pr_head="$(git -C "$verified_pr_repo" rev-parse HEAD)"
write_task "$verified_pr_task" implementation
write_evidence "$verified_pr_repo" "$verified_pr_head"
bash "$REPORT_WRITER" --repo "$verified_pr_repo" --ticket DP-422-T1 --task-md "$verified_pr_task" --head-sha "$verified_pr_head" --status PASS
bash "$WRITER" --verification-pass "$verified_pr_task" https://github.com/demo/example/pull/2 OPEN "$verified_pr_head" --repo "$verified_pr_repo"
grep -q '^  pr_url: https://github.com/demo/example/pull/2$' "$verified_pr_task"
grep -q "^  head_sha: ${verified_pr_head}$" "$verified_pr_task"
grep -q '^    status: PASS$' "$verified_pr_task"
for field in \
  deliverable_verification_ac_total \
  deliverable_verification_ac_pass \
  deliverable_verification_ac_fail \
  deliverable_verification_ac_manual_required \
  deliverable_verification_ac_uncertain; do
  actual="$(bash "$ROOT/scripts/parse-task-md.sh" "$verified_pr_task" --no-resolve --field "$field")"
  [[ "$actual" == "0" ]] || { echo "FAIL: verification-pass writer emitted non-canonical $field=$actual" >&2; exit 1; }
done

verified_pr_before="$(shasum -a 256 "$verified_pr_task" | awk '{print $1}')"
bash "$WRITER" --verification-pass "$verified_pr_task" https://github.com/demo/example/pull/2 OPEN "$verified_pr_head" --repo "$verified_pr_repo"
verified_pr_after="$(shasum -a 256 "$verified_pr_task" | awk '{print $1}')"
[[ "$verified_pr_before" == "$verified_pr_after" ]] || { echo "FAIL: verification-pass writer is not idempotent" >&2; exit 1; }

# Bug/JIRA sources use the real delivery ticket, not the internal work item marker.
bug_task="$TMPROOT/bug-pr.md"
bug_repo="$TMPROOT/bug-pr-repo"
setup_repo "$bug_repo"
bug_head="$(git -C "$bug_repo" rev-parse HEAD)"
write_task "$bug_task" implementation jira PROJ-422 PROJ-422-T1 PROJ-422
write_evidence "$bug_repo" "$bug_head" 1 PROJ-422-T1
write_evidence "$bug_repo" "$bug_head" 0 PROJ-422
bash "$REPORT_WRITER" --repo "$bug_repo" --ticket PROJ-422 --task-md "$bug_task" --head-sha "$bug_head" --status PASS
bash "$WRITER" --verification-pass "$bug_task" https://github.com/demo/example/pull/22 OPEN "$bug_head" --repo "$bug_repo"
grep -q '^    status: PASS$' "$bug_task"

missing_report_task="$TMPROOT/missing-report.md"
missing_report_repo="$TMPROOT/missing-report-repo"
setup_repo "$missing_report_repo"
missing_report_head="$(git -C "$missing_report_repo" rev-parse HEAD)"
write_task "$missing_report_task" implementation
write_evidence "$missing_report_repo" "$missing_report_head"
if bash "$WRITER" --verification-pass "$missing_report_task" https://github.com/demo/example/pull/3 OPEN "$missing_report_head" --repo "$missing_report_repo" >/dev/null 2>&1; then
  echo "FAIL: verification-pass writer accepted a missing task-bound report" >&2
  exit 1
fi

failed_report_task="$TMPROOT/failed-report.md"
failed_report_repo="$TMPROOT/failed-report-repo"
setup_repo "$failed_report_repo"
failed_report_head="$(git -C "$failed_report_repo" rev-parse HEAD)"
write_task "$failed_report_task" implementation
write_evidence "$failed_report_repo" "$failed_report_head"
bash "$REPORT_WRITER" --repo "$failed_report_repo" --ticket DP-422-T1 --task-md "$failed_report_task" --head-sha "$failed_report_head" --status FAIL
failed_report_before="$(shasum -a 256 "$failed_report_task" | awk '{print $1}')"
if bash "$WRITER" --verification-pass "$failed_report_task" https://github.com/demo/example/pull/4 OPEN "$failed_report_head" --repo "$failed_report_repo" >/dev/null 2>&1; then
  echo "FAIL: verification-pass writer accepted a FAIL task-bound report" >&2
  exit 1
fi
failed_report_after="$(shasum -a 256 "$failed_report_task" | awk '{print $1}')"
[[ "$failed_report_before" == "$failed_report_after" ]] || { echo "FAIL: FAIL report mutated task.md" >&2; exit 1; }

echo "write-deliverable selftest: PASS"
