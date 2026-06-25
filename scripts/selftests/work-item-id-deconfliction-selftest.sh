#!/usr/bin/env bash
# Purpose: DP-338 T1 (D1) — assert task.md de-conflates the work_item_id atom
#          from the branch-identity atom into two distinct Operational Context
#          cells, and that the producer (derive-task-md-from-refinement-json.sh)
#          and consumer (parse-task-md.sh) honour the split:
#            * derive emits a NEW "Work item ID" cell = canonical {source}-T{n}
#              (source-type-agnostic), and keeps the "Task ID" cell carrying the
#              branch-identity (= tasks[].jira_key for JIRA-Epic sources, else the
#              canonical task_id) so DP-328 branch identity is unchanged.
#            * parse reads work_item_id from the new "Work item ID" cell first,
#              falling back to the legacy "Task ID" cell only for old task.md that
#              predates the new cell (EC1 read-side tolerance, not a dual writer).
# Covers:  AC1 (JIRA work_item_id={Epic}-T{n} via new cell + branch=jira_key both
#            hold; DP source both atoms equal), AC8 (branch-identity behaviour
#            unchanged: delivery_ticket_key still tracks the branch atom and the
#            branch validates), AC-NEG1 (a composite {source}-T{n} placed in the
#            branch-identity cell still fails resolve-task-branch validate_branch
#            AC-NEG5 — the leak guard is not weakened), plus the EC1 legacy
#            fallback and an AC-NEG4 single-writer (read-side-fallback-only) check.
# Inputs:  none (constructs refinement.json + task.md fixtures in a tmpdir using
#          GENERIC placeholder identities — EXCO / exampleco-web — never live slugs)
# Outputs: stdout PASS line; exit 0 PASS, non-zero FAIL
# Side effects: writes/removes a tmpdir

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVE="$ROOT_DIR/scripts/derive-task-md-from-refinement-json.sh"
PARSE="$ROOT_DIR/scripts/parse-task-md.sh"
RESOLVE_BRANCH="$ROOT_DIR/scripts/resolve-task-branch.sh"

[[ -x "$DERIVE" || -f "$DERIVE" ]] || { echo "FAIL: derive script missing: $DERIVE" >&2; exit 1; }
[[ -f "$PARSE" ]] || { echo "FAIL: parse script missing: $PARSE" >&2; exit 1; }
[[ -f "$RESOLVE_BRANCH" ]] || { echo "FAIL: resolve-task-branch missing: $RESOLVE_BRANCH" >&2; exit 1; }

tmpdir="$(mktemp -d -t work-item-id-deconfliction.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail=0

parse_field() {
  # parse_field <task.md> <field>
  bash "$PARSE" "$1" --no-resolve --field "$2" 2>/dev/null
}

expect_eq() {
  # expect_eq <label> <got> <want>
  local label="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "[selftest] FAIL ($label): got '$got' want '$want'" >&2
    fail=1
  fi
}

# ---------------------------------------------------------------------------
# Fixture A — JIRA-Epic-backed source. The Epic is EXCO-700; the per-task
# delivery ticket is EXCO-712. The canonical work_item_id is EXCO-700-T1
# ({source}-T{n}); the branch identity is EXCO-712 (the real delivery ticket).
# ---------------------------------------------------------------------------
jira_json="$tmpdir/refinement-jira.json"
cat >"$jira_json" <<'JSON'
{
  "source": {
    "type": "jira",
    "id": "EXCO-700",
    "repo": "exampleco-web",
    "base_branch": "develop",
    "container": "/tmp/companies/exampleco/EXCO-700",
    "plan_path": "/tmp/companies/exampleco/EXCO-700/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "title": "Deconfliction jira fixture",
      "scope": "JIRA-Epic 來源的 work_item_id 與 branch-identity 拆分驗證。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "jira_key": "EXCO-712",
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS"
      }
    }
  ]
}
JSON

jira_task="$tmpdir/jira-task.md"
bash "$DERIVE" --refinement-json "$jira_json" --task-id "EXCO-700-T1" >"$jira_task" 2>"$tmpdir/jira.stderr" || {
  echo "[selftest] FAIL (AC1.jira): derive failed for EXCO-700-T1" >&2
  cat "$tmpdir/jira.stderr" >&2
  exit 1
}

# AC1 (JIRA): work_item_id must be the canonical {source}-T{n} read from the NEW
# cell, NOT polluted by the branch-identity (jira_key).
expect_eq "AC1.jira.work_item_id"        "$(parse_field "$jira_task" work_item_id)"        "EXCO-700-T1"
# branch identity atom must remain the real delivery ticket (DP-328 unchanged).
expect_eq "AC1.jira.delivery_ticket_key" "$(parse_field "$jira_task" delivery_ticket_key)" "EXCO-712"
expect_eq "AC1.jira.jira_key"            "$(parse_field "$jira_task" jira_key)"            "EXCO-712"
expect_eq "AC1.jira.task_branch_prefix"  "$(parse_field "$jira_task" task_branch | sed -E 's#^(task/EXCO-712-).*#\1#')" "task/EXCO-712-"

# The derived body must literally carry BOTH cells (de-conflation, not rename).
if ! grep -q "Work item ID | EXCO-700-T1" "$jira_task"; then
  echo "[selftest] FAIL (AC1.jira.cell): derived task.md missing 'Work item ID | EXCO-700-T1' cell" >&2
  fail=1
fi
if ! grep -q "Task ID | EXCO-712" "$jira_task"; then
  echo "[selftest] FAIL (AC1.jira.branchcell): derived task.md missing 'Task ID | EXCO-712' branch-identity cell" >&2
  fail=1
fi

# AC8 — the branch the producer emits must validate (no identity leak).
if ! bash "$RESOLVE_BRANCH" "$jira_task" >/dev/null 2>"$tmpdir/jira-branch.err"; then
  echo "[selftest] FAIL (AC8.jira): resolve-task-branch rejected the derived JIRA branch" >&2
  cat "$tmpdir/jira-branch.err" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# Fixture B — DP-backed source. Both atoms collapse to DP-338-T1.
# ---------------------------------------------------------------------------
dp_json="$tmpdir/refinement-dp.json"
cat >"$dp_json" <<'JSON'
{
  "source": {
    "type": "dp",
    "id": "DP-338",
    "container": "/tmp/dp-338",
    "plan_path": "/tmp/dp-338/index.md",
    "jira_key": null
  },
  "schema_version": 1,
  "tasks": [
    {
      "id": "T1",
      "kind": "implementation",
      "task_shape": "implementation",
      "title": "Deconfliction dp fixture",
      "scope": "DP 來源的 work_item_id 與 branch-identity 應相等。",
      "allowed_files": ["scripts/sample.sh"],
      "modules": ["scripts/sample.sh"],
      "ac_ids": ["AC1"],
      "dependencies": [],
      "estimate_points": 1,
      "verification": {
        "method": "unit_test",
        "detail": "echo PASS"
      }
    }
  ]
}
JSON

dp_task="$tmpdir/dp-task.md"
bash "$DERIVE" --refinement-json "$dp_json" --task-id "DP-338-T1" >"$dp_task" 2>"$tmpdir/dp.stderr" || {
  echo "[selftest] FAIL (AC1.dp): derive failed for DP-338-T1" >&2
  cat "$tmpdir/dp.stderr" >&2
  exit 1
}

expect_eq "AC1.dp.work_item_id"        "$(parse_field "$dp_task" work_item_id)"        "DP-338-T1"
expect_eq "AC1.dp.delivery_ticket_key" "$(parse_field "$dp_task" delivery_ticket_key)" "DP-338-T1"
if ! grep -q "Work item ID | DP-338-T1" "$dp_task"; then
  echo "[selftest] FAIL (AC1.dp.cell): derived DP task.md missing 'Work item ID | DP-338-T1' cell" >&2
  fail=1
fi
# DP branch must validate.
if ! bash "$RESOLVE_BRANCH" "$dp_task" >/dev/null 2>"$tmpdir/dp-branch.err"; then
  echo "[selftest] FAIL (AC8.dp): resolve-task-branch rejected the derived DP branch" >&2
  cat "$tmpdir/dp-branch.err" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# EC1 — legacy task.md with NO "Work item ID" cell. parse must fall back to the
# old "Task ID" cell so existing active task.md keep resolving work_item_id.
# (This is read-side tolerance only; the derive writer never emits the legacy
# shape going forward — AC-NEG4.)
# ---------------------------------------------------------------------------
legacy_task="$tmpdir/legacy-task.md"
cat >"$legacy_task" <<'MD'
---
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "legacy fixture"
depends_on: []
---

# T1: legacy work order without a Work item ID cell (1 pt)

> Source: DP-100 | Task: DP-100-T1 | JIRA: N/A | Repo: polaris-framework

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-100 |
| Task ID | DP-100-T1 |
| JIRA key | N/A |
| Base branch | main |
| Branch chain | main -> task/DP-100-T1-legacy |
| Task branch | task/DP-100-T1-legacy |
| Depends on | N/A |
| References to load | - refinement.json |

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
MD

expect_eq "EC1.legacy.work_item_id"        "$(parse_field "$legacy_task" work_item_id)"        "DP-100-T1"
expect_eq "EC1.legacy.delivery_ticket_key" "$(parse_field "$legacy_task" delivery_ticket_key)" "DP-100-T1"

# ---------------------------------------------------------------------------
# AC-NEG1 — a composite {source}-T{n} placed in the branch-identity (Task ID)
# cell of a JIRA-Epic task, combined with a Task branch that prefixes the
# composite, must STILL be rejected by resolve-task-branch validate_branch
# (AC-NEG5 leak guard not weakened by the de-conflation).
# ---------------------------------------------------------------------------
leak_task="$tmpdir/leak-task.md"
cat >"$leak_task" <<'MD'
---
status: IN_PROGRESS
task_kind: T
task_shape: implementation
verification:
  behavior_contract:
    applies: false
    reason: "leak fixture"
depends_on: []
---

# T1: composite-leak negative (1 pt)

> Source: EXCO-700 | Task: EXCO-712 | JIRA: EXCO-712 | Repo: exampleco-web

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | jira |
| Source ID | EXCO-700 |
| Work item ID | EXCO-700-T1 |
| Task ID | EXCO-712 |
| JIRA key | EXCO-712 |
| Base branch | develop |
| Branch chain | develop -> task/EXCO-700-T1-leak |
| Task branch | task/EXCO-700-T1-leak |
| Depends on | N/A |
| References to load | - refinement.json |

## Test Environment

- **Level**: static
- **Dev env config**: N/A
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A
MD

# Sanity: parse this fixture so work_item_id reads the new composite cell and the
# delivery ticket the branch atom — the exact (work_item_id != task_key) shape the
# AC-NEG5 leak guard keys off.
expect_eq "AC-NEG1.work_item_id"        "$(parse_field "$leak_task" work_item_id)"        "EXCO-700-T1"
expect_eq "AC-NEG1.delivery_ticket_key" "$(parse_field "$leak_task" delivery_ticket_key)" "EXCO-712"

if bash "$RESOLVE_BRANCH" "$leak_task" >/dev/null 2>"$tmpdir/leak.err"; then
  echo "[selftest] FAIL (AC-NEG1): resolve-task-branch accepted a composite-leak branch (should fail AC-NEG5)" >&2
  fail=1
elif ! grep -q "AC-NEG5" "$tmpdir/leak.err"; then
  echo "[selftest] FAIL (AC-NEG1): rejection did not cite the AC-NEG5 leak guard" >&2
  cat "$tmpdir/leak.err" >&2
  fail=1
fi

# ---------------------------------------------------------------------------
# AC-NEG4 — single writer: derive must NOT emit a dual legacy/new pair where the
# old cell carries the canonical work_item_id. For JIRA sources the legacy Task
# ID cell carries the branch atom (jira_key), proving the new cell is the sole
# work_item_id writer path (read-side fallback only, no dual-writer steady state).
# ---------------------------------------------------------------------------
if grep -q "Task ID | EXCO-700-T1" "$jira_task"; then
  echo "[selftest] FAIL (AC-NEG4): JIRA derive duplicated work_item_id into the legacy Task ID cell (dual writer)" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "work-item-id-deconfliction selftest FAIL" >&2
  exit 1
fi

echo "work-item-id-deconfliction selftest PASS"
