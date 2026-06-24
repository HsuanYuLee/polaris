#!/usr/bin/env bash
set -euo pipefail

# Purpose: selftest for scripts/write-ac-verification.sh — covers the V*.md
#          ac_verification lifecycle frontmatter writer. DP-360 T7 retired the
#          head-sha-keyed ac_verification proof marker (D4 — no dual-write); the
#          V*.md frontmatter is the single canonical delivery verification record.
#          This selftest asserts the CONTRACT: the writer updates the V*.md
#          frontmatter + log, the verification gate reads that frontmatter, and NO
#          .polaris/evidence/ac-verification marker file is ever created (NEG2).
# Inputs:  none (builds hermetic fixtures under a tmpdir).
# Outputs: "PASS: write-ac-verification selftest" + exit 0 on success; first
#          failing assertion exits non-zero with a diagnostic message.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/write-ac-verification.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
GATE="$ROOT_DIR/scripts/check-verification-passed.sh"

tmpdir="$(mktemp -d -t write-ac-verification-selftest.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Anti-laundering guard: DP-360 T7 retires the ac_verification marker entirely.
# A passing run must never leave a marker directory behind for ANY work item.
assert_no_marker_dir() {
  local repo="$1"
  if [[ -e "$repo/.polaris/evidence/ac-verification" ]]; then
    fail "NEG2: retired ac-verification marker dir was created at $repo/.polaris/evidence/ac-verification"
  fi
}

# ---------------------------------------------------------------------------
# Fixture: a git "main checkout" repo with a V*/index.md task file.
# ---------------------------------------------------------------------------
repo="$tmpdir/main-checkout"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "polaris@example.invalid"
git -C "$repo" config user.name "Polaris Selftest"
printf 'fixture\n' >"$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m "init"

make_v_task() {
  # make_v_task <path>
  local task="$1"
  mkdir -p "$(dirname "$task")"
  cat >"$task" <<'MD'
---
title: "Work Order - V1: AC verification fixture (1 pt)"
description: "Fixture for write-ac-verification lifecycle metadata."
status: IN_PROGRESS
task_kind: V
---

# V1: AC verification fixture (1 pt)

> Epic: EP-999 | JIRA: CHK-9 | Repo: fake-repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | CHK-9 |
| Parent Epic | EP-999 |
| Implementation tasks | T1 |
| Base branch | feat/ep-999-fixture |
| Depends on | N/A |
| References to load | - `skills/references/task-md-schema.md` |

## Verification Handoff

驗收委派 verify-AC。

## 目標

驗證 ac_verification writer。

## 驗收項目

- AC-1: fixture

## 估點理由

1 pt - selftest fixture。

## 驗收計畫（AC level）

- 驗證 ac_verification lifecycle。

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## 驗收步驟

```bash
echo "verify-AC executes this fixture"
```
MD
}

task="$repo/spec/tasks/V1/index.md"
make_v_task "$task"

HEAD_SHA="$(git -C "$repo" rev-parse HEAD)"
SOURCE_ID="DP-999"
WORK_ITEM_ID="DP-999-V1"

# ---------------------------------------------------------------------------
# AC1: original FAIL → gate-blocks lifecycle still works, recorded in the V*.md
# ac_verification frontmatter (the canonical record). NO marker file is written.
# --source-id / --work-item-id / --head-sha are accepted (back-compat) but only
# feed the frontmatter.
# ---------------------------------------------------------------------------
bash "$SCRIPT" "$task" \
  --status FAIL \
  --last-run-at 2026-05-09T01:02:03Z \
  --ac-total 2 \
  --ac-pass 1 \
  --ac-fail 1 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition rejected \
  --summary "first run failed" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA" >/dev/null

bash "$VALIDATOR" "$task" >/dev/null
bash "$GATE" --task-md "$task" --repo "$repo" >"$tmpdir/gate.out" 2>/dev/null && {
  fail "failed verification should not pass gate"
}
grep -q "status=FAIL" "$tmpdir/gate.out" || fail "gate output did not report status=FAIL"

# The FAIL verdict lives in the V*.md ac_verification frontmatter — not a marker.
python3 - "$task" <<'PY' || fail "AC1: FAIL not recorded in V*.md ac_verification frontmatter"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
end = text.find("\n---\n", 4)
fm = text[4:end]
in_block = False
status = ""
for line in fm.splitlines():
    if line == "ac_verification:":
        in_block = True
        continue
    if in_block and line and not line[0].isspace():
        break
    if in_block:
        m = re.match(r"\s+status:\s*(\S+)", line)
        if m:
            status = m.group(1)
            break
assert status == "FAIL", f"ac_verification.status={status!r}"
PY
assert_no_marker_dir "$repo"

# ---------------------------------------------------------------------------
# AC2: terminal PASS updates frontmatter + appends a log entry; gate now passes.
# Still no marker file (NEG2).
# ---------------------------------------------------------------------------
bash "$SCRIPT" "$task" \
  --status PASS \
  --last-run-at 2026-05-09T02:03:04Z \
  --ac-total 2 \
  --ac-pass 2 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition passed \
  --summary "second run passed" \
  --source-id "$SOURCE_ID" \
  --work-item-id "$WORK_ITEM_ID" \
  --head-sha "$HEAD_SHA" >/dev/null

bash "$VALIDATOR" "$task" >/dev/null
bash "$GATE" --task-md "$task" --repo "$repo" >/dev/null

grep -q "last_run_at: 2026-05-09T02:03:04Z" "$task" || fail "frontmatter last_run_at not updated"
grep -q "summary: \"first run failed\"" "$task" || fail "log entry for first run missing"
grep -q "summary: \"second run passed\"" "$task" || fail "log entry for second run missing"

python3 - "$task" <<'PY' || fail "AC2: PASS not recorded in V*.md ac_verification frontmatter"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
end = text.find("\n---\n", 4)
fm = text[4:end]
in_block = False
status = ""
disposition = ""
for line in fm.splitlines():
    if line == "ac_verification:":
        in_block = True
        continue
    if in_block and line and not line[0].isspace():
        break
    if in_block:
        m = re.match(r"\s+status:\s*(\S+)", line)
        if m and not status:
            status = m.group(1)
        d = re.match(r"\s+human_disposition:\s*(\S+)", line)
        if d:
            disposition = d.group(1)
assert status == "PASS", f"ac_verification.status={status!r}"
assert disposition == "passed", f"human_disposition={disposition!r}"
PY
assert_no_marker_dir "$repo"

# ---------------------------------------------------------------------------
# AC3: calling inside a linked git worktree updates the worktree-local V*.md
# frontmatter and STILL writes no marker anywhere (NEG2, both checkouts).
# ---------------------------------------------------------------------------
worktree="$tmpdir/linked-worktree"
git -C "$repo" worktree add -q "$worktree" -b wt-branch >/dev/null 2>&1
wt_task="$worktree/spec/tasks/V1/index.md"
make_v_task "$wt_task"
[[ -f "$wt_task" ]] || fail "AC3: worktree task fixture missing"

wt_head="$(git -C "$worktree" rev-parse HEAD)"
wt_work_item="DP-999-V2"

bash "$SCRIPT" "$wt_task" \
  --status PASS \
  --last-run-at 2026-05-09T03:04:05Z \
  --ac-total 1 \
  --ac-pass 1 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition passed \
  --source-id "$SOURCE_ID" \
  --work-item-id "$wt_work_item" \
  --head-sha "$wt_head" >/dev/null

grep -q "last_run_at: 2026-05-09T03:04:05Z" "$wt_task" || fail "AC3: worktree frontmatter not updated"
assert_no_marker_dir "$repo"
assert_no_marker_dir "$worktree"

# ---------------------------------------------------------------------------
# AC4: IN_PROGRESS updates frontmatter and writes no marker (NEG2). Also no
# --human-disposition is required for IN_PROGRESS / PASS.
# ---------------------------------------------------------------------------
ip_task="$repo/spec/tasks/V3/index.md"
make_v_task "$ip_task"

bash "$SCRIPT" "$ip_task" \
  --status IN_PROGRESS \
  --last-run-at 2026-05-09T04:05:06Z \
  --ac-total 2 \
  --ac-pass 1 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 1 >/dev/null

grep -q "last_run_at: 2026-05-09T04:05:06Z" "$ip_task" || fail "AC4: IN_PROGRESS frontmatter not updated"
assert_no_marker_dir "$repo"

# ---------------------------------------------------------------------------
# AC5: writer runs with no POLARIS_* env (pure file I/O on the V*.md).
# ---------------------------------------------------------------------------
noenv_task="$repo/spec/tasks/V4/index.md"
make_v_task "$noenv_task"

env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" "$noenv_task" \
  --status PASS \
  --last-run-at 2026-05-09T05:06:07Z \
  --ac-total 1 \
  --ac-pass 1 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition passed \
  --source-id "$SOURCE_ID" \
  --work-item-id "DP-999-V4" \
  --head-sha "$HEAD_SHA" >/dev/null

grep -q "status: PASS" "$noenv_task" || fail "AC5: PASS frontmatter not written under no-POLARIS-env invocation"
assert_no_marker_dir "$repo"

# ---------------------------------------------------------------------------
# AC-NEG1: a non-PASS/non-IN_PROGRESS status still requires --human-disposition
# (input validation retained — the writer fail-stops on missing required input).
# ---------------------------------------------------------------------------
neg_task="$repo/spec/tasks/V5/index.md"
make_v_task "$neg_task"

if bash "$SCRIPT" "$neg_task" \
  --status FAIL \
  --last-run-at 2026-05-09T06:07:08Z \
  --ac-total 1 --ac-pass 0 --ac-fail 1 --ac-manual-required 0 --ac-uncertain 0 \
  >/dev/null 2>"$tmpdir/neg1.err"; then
  fail "AC-NEG1: FAIL status missing --human-disposition should fail-stop, but exited 0"
fi
grep -qi "human-disposition" "$tmpdir/neg1.err" || fail "AC-NEG1: error for missing --human-disposition not explicit"
assert_no_marker_dir "$repo"

# ---------------------------------------------------------------------------
# AC-NEG2: inconsistent ac_counts (ac_pass+ac_fail+... != ac_total) → invalid
# input, exit 2.
# ---------------------------------------------------------------------------
neg2_task="$repo/spec/tasks/V6/index.md"
make_v_task "$neg2_task"

set +e
bash "$SCRIPT" "$neg2_task" \
  --status PASS \
  --last-run-at 2026-05-09T07:08:09Z \
  --ac-total 5 --ac-pass 1 --ac-fail 0 --ac-manual-required 0 --ac-uncertain 0 \
  >/dev/null 2>"$tmpdir/neg2.err"
neg2_rc=$?
set -e
[[ "$neg2_rc" -eq 2 ]] || fail "AC-NEG2: inconsistent ac_counts must exit 2, got $neg2_rc"
assert_no_marker_dir "$repo"

echo "PASS: write-ac-verification selftest"
