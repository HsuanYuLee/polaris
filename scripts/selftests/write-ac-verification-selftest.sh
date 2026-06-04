#!/usr/bin/env bash
set -euo pipefail

# Purpose: selftest for scripts/write-ac-verification.sh — covers the original
#          V*.md lifecycle metadata writer behaviour PLUS the DP-281
#          ac_verification proof marker contract (AC1-6 + AC-NEG1-2).
# Inputs:  none (builds hermetic fixtures under a tmpdir).
# Outputs: "PASS: write-ac-verification selftest" + exit 0 on success; first
#          failing assertion exits non-zero with a diagnostic message.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/write-ac-verification.sh"
VALIDATOR="$ROOT_DIR/scripts/validate-task-md.sh"
GATE="$ROOT_DIR/scripts/check-verification-passed.sh"
PROBE="$ROOT_DIR/scripts/auto-pass-probe.sh"

tmpdir="$(mktemp -d -t write-ac-verification-selftest.XXXXXX)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Fixture: a git "main checkout" repo with a V*/index.md task file. The repo is
# a real git repo so resolve_main_checkout can anchor the marker, and so we can
# add a linked worktree later for AC2.
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

# Stable fake head sha used across marker / probe assertions.
HEAD_SHA="$(git -C "$repo" rev-parse HEAD)"
SOURCE_ID="DP-999"
WORK_ITEM_ID="DP-999-V1"
marker_path="$repo/.polaris/evidence/ac-verification/${WORK_ITEM_ID}-${HEAD_SHA}.json"

# ---------------------------------------------------------------------------
# Backward-compatibility: original FAIL → gate-blocks → PASS lifecycle still
# works (now with the marker flags supplied for terminal statuses).
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

# FAIL is a terminal verdict → marker must exist with status FAIL.
[[ -f "$marker_path" ]] || fail "FAIL marker not written at $marker_path"
python3 - "$marker_path" <<'PY' || fail "FAIL marker payload mismatch"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "FAIL", data.get("status")
assert data["marker_kind"] == "ac_verification", data.get("marker_kind")
PY

# ---------------------------------------------------------------------------
# AC1: terminal PASS marker schema (D5) at the main-checkout path.
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

[[ -f "$marker_path" ]] || fail "AC1: PASS marker not written at $marker_path"
python3 - "$marker_path" "$SOURCE_ID" "$WORK_ITEM_ID" "$HEAD_SHA" <<'PY' || fail "AC1: marker schema mismatch"
import json, re, sys
path, source_id, work_item_id, head_sha = sys.argv[1:5]
data = json.load(open(path, encoding="utf-8"))
assert data["schema_version"] == 1, data.get("schema_version")
assert data["marker_kind"] == "ac_verification", data.get("marker_kind")
assert data["writer"] == "verify-AC", data.get("writer")
assert data["owning_skill"] == "verify-AC", data.get("owning_skill")
assert data["source_id"] == source_id, data.get("source_id")
assert data["work_item_id"] == work_item_id, data.get("work_item_id")
assert data["status"] == "PASS", data.get("status")
assert data["human_disposition"] == "passed", data.get("human_disposition")
counts = data["ac_counts"]
assert counts == {"ac_total": 2, "ac_pass": 2, "ac_fail": 0,
                  "ac_manual_required": 0, "ac_uncertain": 0}, counts
fr = data["freshness"]
assert fr["head_sha"] == head_sha, fr.get("head_sha")
assert "source_artifact" in fr, fr
assert data["summary"] == "second run passed", data.get("summary")
# ISO8601 UTC timestamp (offset form, not a malformed ".6N" string).
assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?\+00:00$", data["at"]), data["at"]
PY

# ---------------------------------------------------------------------------
# AC2: calling inside a linked git worktree still anchors the marker at the
# main checkout, NOT the worktree's own .polaris/.
# ---------------------------------------------------------------------------
worktree="$tmpdir/linked-worktree"
git -C "$repo" worktree add -q "$worktree" -b wt-branch >/dev/null 2>&1
# The V*.md fixture is not committed, so create it directly inside the worktree.
wt_task="$worktree/spec/tasks/V1/index.md"
make_v_task "$wt_task"
[[ -f "$wt_task" ]] || fail "AC2: worktree task fixture missing"

wt_head="$(git -C "$worktree" rev-parse HEAD)"
wt_work_item="DP-999-V2"
expected_marker="$repo/.polaris/evidence/ac-verification/${wt_work_item}-${wt_head}.json"
forbidden_marker="$worktree/.polaris/evidence/ac-verification/${wt_work_item}-${wt_head}.json"

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

[[ -f "$expected_marker" ]] || fail "AC2: marker did not land at main checkout ($expected_marker)"
[[ ! -f "$forbidden_marker" ]] || fail "AC2: marker leaked into worktree .polaris/ ($forbidden_marker)"

# ---------------------------------------------------------------------------
# AC3: auto-pass-runner verify-AC probe reads the PASS marker → status=PASS,
# next_action=report (terminal complete path).
# ---------------------------------------------------------------------------
probe_out="$(bash "$PROBE" --repo "$repo" --stage verify-AC \
  --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID" --head-sha "$HEAD_SHA")"
printf '%s' "$probe_out" >"$tmpdir/probe.json"
python3 - "$tmpdir/probe.json" <<'PY' || fail "AC3: probe did not report PASS/report"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["status"] == "PASS", data.get("status")
assert data["next_action"] == "report", data.get("next_action")
assert data["terminal_status"] == "complete", data.get("terminal_status")
PY

# ---------------------------------------------------------------------------
# AC4: IN_PROGRESS updates frontmatter but emits no verdict marker.
# ---------------------------------------------------------------------------
ip_task="$repo/spec/tasks/V3/index.md"
make_v_task "$ip_task"
ip_work_item="DP-999-V3"
ip_marker="$repo/.polaris/evidence/ac-verification/${ip_work_item}-${HEAD_SHA}.json"

bash "$SCRIPT" "$ip_task" \
  --status IN_PROGRESS \
  --last-run-at 2026-05-09T04:05:06Z \
  --ac-total 2 \
  --ac-pass 1 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 1 >/dev/null

grep -q "last_run_at: 2026-05-09T04:05:06Z" "$ip_task" || fail "AC4: IN_PROGRESS frontmatter not updated"
[[ ! -f "$ip_marker" ]] || fail "AC4: IN_PROGRESS must not emit a verdict marker ($ip_marker)"

# ---------------------------------------------------------------------------
# AC5: documented ≡ implemented. evidence-producers.json + verify-AC SKILL.md
# describe write-ac-verification.sh as the marker writer aligned to behaviour.
# ---------------------------------------------------------------------------
producers="$ROOT_DIR/scripts/lib/evidence-producers.json"
python3 - "$producers" <<'PY' || fail "AC5: evidence-producers.json ac-verification entry not aligned"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
entry = next(p for p in data["producers"]
             if p.get("owning_skill") == "verify-AC"
             and "ac_verification" in (p.get("marker_kinds") or []))
assert "scripts/write-ac-verification.sh" in entry.get("writer_scripts", []), entry
notes = entry.get("notes", "")
assert "write-ac-verification.sh" in notes, notes
assert "marker" in notes.lower(), notes
PY

skill_md="$ROOT_DIR/.claude/skills/verify-AC/SKILL.md"
grep -q 'write-ac-verification.sh' "$skill_md" || fail "AC5: SKILL.md missing write-ac-verification.sh reference"
grep -qE 'ac_verification.*marker|marker.*ac_verification|verdict marker' "$skill_md" \
  || fail "AC5: SKILL.md does not describe the ac_verification verdict marker"

# ---------------------------------------------------------------------------
# AC6: marker emit is pure script file I/O — succeeds with no POLARIS_* env.
# ---------------------------------------------------------------------------
noenv_task="$repo/spec/tasks/V4/index.md"
make_v_task "$noenv_task"
noenv_work_item="DP-999-V4"
noenv_marker="$repo/.polaris/evidence/ac-verification/${noenv_work_item}-${HEAD_SHA}.json"

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
  --work-item-id "$noenv_work_item" \
  --head-sha "$HEAD_SHA" >/dev/null

[[ -f "$noenv_marker" ]] || fail "AC6: marker not written under a no-POLARIS-env invocation"

# ---------------------------------------------------------------------------
# AC-NEG1: terminal status missing a required flag → fail-stop, no silent skip.
# ---------------------------------------------------------------------------
neg_task="$repo/spec/tasks/V5/index.md"
make_v_task "$neg_task"

assert_missing_flag_fails() {
  # assert_missing_flag_fails <token> <arg...>
  local token="$1"; shift
  if bash "$SCRIPT" "$neg_task" "$@" >/dev/null 2>"$tmpdir/neg1.err"; then
    fail "AC-NEG1: missing --$token should fail-stop, but exited 0"
  fi
  grep -qi "$token" "$tmpdir/neg1.err" || fail "AC-NEG1: error for missing --$token not explicit"
}

common=(--status PASS --last-run-at 2026-05-09T06:07:08Z
        --ac-total 1 --ac-pass 1 --ac-fail 0 --ac-manual-required 0 --ac-uncertain 0
        --human-disposition passed)

assert_missing_flag_fails "work-item-id" "${common[@]}" --source-id "$SOURCE_ID" --head-sha "$HEAD_SHA"
assert_missing_flag_fails "head-sha"     "${common[@]}" --source-id "$SOURCE_ID" --work-item-id "$WORK_ITEM_ID"
assert_missing_flag_fails "source-id"    "${common[@]}" --work-item-id "$WORK_ITEM_ID" --head-sha "$HEAD_SHA"

# ---------------------------------------------------------------------------
# AC-NEG2: marker emit failure → script exits 1 (not a false exit 0).
# Simulate an unwritable marker path by pre-creating it as a directory so the
# file write fails after frontmatter is already consistent.
# ---------------------------------------------------------------------------
neg2_task="$repo/spec/tasks/V6/index.md"
make_v_task "$neg2_task"
neg2_work_item="DP-999-V6"
neg2_marker="$repo/.polaris/evidence/ac-verification/${neg2_work_item}-${HEAD_SHA}.json"
mkdir -p "$neg2_marker"   # marker path is now a directory → file write must fail

set +e
bash "$SCRIPT" "$neg2_task" \
  --status PASS \
  --last-run-at 2026-05-09T07:08:09Z \
  --ac-total 1 \
  --ac-pass 1 \
  --ac-fail 0 \
  --ac-manual-required 0 \
  --ac-uncertain 0 \
  --human-disposition passed \
  --source-id "$SOURCE_ID" \
  --work-item-id "$neg2_work_item" \
  --head-sha "$HEAD_SHA" >/dev/null 2>"$tmpdir/neg2.err"
neg2_rc=$?
set -e
[[ "$neg2_rc" -eq 1 ]] || fail "AC-NEG2: marker emit failure must exit 1, got $neg2_rc"

echo "PASS: write-ac-verification selftest"
