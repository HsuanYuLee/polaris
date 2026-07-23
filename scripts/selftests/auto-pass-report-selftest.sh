#!/usr/bin/env bash
# Purpose: selftest for scripts/validate-auto-pass-report.sh — DP-198 report
#          schema happy paths / threshold negatives, DP-228 AC4 source-neutral
#          source_id cases. Fixtures satisfy the DP-311 T3 fail-closed
#          cross-checks (real complete ledger + V-task ac_verification PASS +
#          implementation-head binding under a hermetic POLARIS_WORKSPACE_ROOT).
# Inputs:  none (hermetic; fixtures in mktemp dir)
# Outputs: "PASS: ..." on success; non-zero exit with diagnostics on failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
# DP-330 T2: workspace-root-bound source file for framework_gap contract_evidence
# (validator resolves it under WORKSPACE_ROOT=$ROOT, independent of the hermetic
# POLARIS_WORKSPACE_ROOT marker override). Exported so the write_report heredoc
# can read it via os.environ.
export CONTRACT_EVIDENCE="scripts/validate-auto-pass-report.sh:1"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# DP-311 T3 cross-check fixtures: hermetic evidence root + complete ledger.
export POLARIS_WORKSPACE_ROOT="$TMP"
FIXTURE_HEAD="cccccccccccccccccccccccccccccccccccccccc"
FIXTURE_LEDGER="$TMP/fixture-ledger.json"
python3 - "$FIXTURE_LEDGER" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": "1",
    "terminal_status": "complete",
    "pause": None,
    "friction_log": [],
}) + "\n", encoding="utf-8")
PY
# The report resolves the V task through the canonical resolver and trusts only
# `ac_verification.status` for the V lifecycle verdict. The report's pinned head
# is implementation evidence and must match a required T task's canonical
# deliverable.head_sha.
SPECS_DP="$TMP/docs-manager/src/content/docs/specs/design-plans"
write_v_ac_task() {
  local dp_dir="$1"
  local task_no="$2"
  local ac_status="${3:-PASS}"
  local fake_deliverable="${4:-false}"
  mkdir -p "${dp_dir}/tasks/${task_no}"
  python3 - "${dp_dir}/tasks/${task_no}/index.md" "$task_no" "$ac_status" "$FIXTURE_HEAD" "$fake_deliverable" <<'PY'
import sys
from pathlib import Path
path, task_no, ac_status, head, fake_deliverable = sys.argv[1:6]
source_id = Path(path).parents[2].name.split("-report-fixture", 1)[0]
work_item = f"{source_id}-{task_no}"
frontmatter = (
    "---\n"
    "task_kind: V\n"
    "ac_verification:\n"
    f"  status: {ac_status}\n"
)
if fake_deliverable == "true":
    frontmatter += (
        "deliverable:\n"
        f"  head_sha: {head}\n"
        "  verification:\n"
        "    status: PASS\n"
    )
Path(path).write_text(
    frontmatter
    + "---\n\n"
    + f"# {task_no}\n\n"
    + f"> Source: {source_id} | Task: {work_item} | JIRA: N/A | Repo: polaris-framework\n",
    encoding="utf-8",
)
PY
}
write_t_delivery_task() {
  local dp_dir="$1"
  local source_id="$2"
  local task_no="${3:-T1}"
  mkdir -p "${dp_dir}/tasks/${task_no}"
  cat >"${dp_dir}/tasks/${task_no}/index.md" <<MD
---
task_kind: T
deliverable:
  head_sha: ${FIXTURE_HEAD}
---

# ${task_no}

> Source: ${source_id} | Task: ${source_id}-${task_no} | JIRA: N/A | Repo: polaris-framework
MD
}
# DP-198-V1 (default source_id=DP-198): COMPLETE + SUNSET reports fire PASS.
write_v_ac_task "${SPECS_DP}/DP-198-report-fixture" V1
write_t_delivery_task "${SPECS_DP}/DP-198-report-fixture" DP-198

write_report() {
  local path="$1"
  local terminal="$2"
  local mode="$3"
  local source_id="${4:-DP-198}"
  # DP-360 T7: the verification cross-check resolves the V work item's task.md via
  # the canonical resolver. A DP source's V id (`DP-NNN-V1`) is directly
  # resolvable, but a JIRA-Epic source's V work item carries its own JIRA ticket
  # key (resolvable as a plain `^[A-Z][A-Z0-9]+-[0-9]+$` key) — never `{epic}-V1`,
  # which the resolver rejects. Callers may pass an explicit resolvable V
  # work_item_id (arg 5) for the JIRA happy path; default keeps the DP shape.
  local v_work_item="${5:-${source_id}-V1}"
  local impl_work_item="${6:-${source_id}-T1}"
  REPORT_LEDGER_FIXTURE="$FIXTURE_LEDGER" python3 - "$path" "$terminal" "$mode" "$source_id" "$v_work_item" "$impl_work_item" <<'PY'
import json
import os
import sys
from pathlib import Path

path, terminal, mode, source_id, v_work_item, impl_work_item = sys.argv[1:7]
payload = {
    "schema_version": 1,
    "source_id": source_id,
    "terminal_status": terminal,
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": os.environ.get("REPORT_LEDGER_FIXTURE", "/tmp/ledger.json"),
    "required_prs": [{"task_id": impl_work_item, "pr_url": "https://github.com/org/repo/pull/1", "head_sha": "cccccccccccccccccccccccccccccccccccccccc"}],
    "verification": {"status": "PASS", "work_item_id": v_work_item, "head_sha": "cccccccccccccccccccccccccccccccccccccccc"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [{"candidate": "converge", "disposition": "keep", "reason": "active-work convergence"}],
    "follow_up_dp_seed": None,
    "framework_release_tail": {"trigger": f"framework-release {source_id}", "allowed": True, "reason": "workspace PR ready"},
}
if mode == "blocked":
    payload["blockers"].append({"kind": "probe_unknown", "reason": "missing marker"})
    payload["verification"]["status"] = "UNCERTAIN"
if mode == "sunset":
    payload["overlap_disposition"].append({"candidate": "legacy-skill", "disposition": "follow-up-sunset", "reason": "behavioral removal requires new DP"})
if mode in {"blocked", "sunset"}:
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999-follow-up/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": False,
    }
if mode == "framework_gap":
    payload["blockers"].append({"kind": "framework_gap", "reason": "validator contract gap"})
    payload["verification"]["status"] = "UNCERTAIN"
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999-follow-up/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": True,
        "contract_evidence": [os.environ["CONTRACT_EVIDENCE"]],
    }
if mode == "framework_gap_missing_evidence":
    payload["blockers"].append({"kind": "framework_gap", "reason": "validator contract gap"})
    payload["verification"]["status"] = "UNCERTAIN"
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999-follow-up/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": True,
    }
if mode == "missing_seed":
    payload["blockers"].append({"kind": "manual", "reason": "needs seed"})
if mode == "bad_overlap":
    payload["overlap_disposition"][0]["disposition"] = "delete"
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label unexpectedly passed" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

COMPLETE="$TMP/complete.json"
write_report "$COMPLETE" complete complete
"$VALIDATOR" "$COMPLETE"

BLOCKED="$TMP/blocked.json"
write_report "$BLOCKED" blocked_by_gate_failure blocked
"$VALIDATOR" "$BLOCKED"

SUNSET="$TMP/sunset.json"
write_report "$SUNSET" complete sunset
"$VALIDATOR" "$SUNSET"

MISSING_SEED="$TMP/missing-seed.json"
write_report "$MISSING_SEED" complete missing_seed
expect_fail "missing-seed" "$VALIDATOR" "$MISSING_SEED"

BAD_TERMINAL="$TMP/bad-terminal.json"
write_report "$BAD_TERMINAL" done complete
expect_fail "bad-terminal" "$VALIDATOR" "$BAD_TERMINAL"

BAD_OVERLAP="$TMP/bad-overlap.json"
write_report "$BAD_OVERLAP" complete bad_overlap
expect_fail "bad-overlap" "$VALIDATOR" "$BAD_OVERLAP"

# DP-228 AC4: JIRA source report fixture — happy path with non-DP source_id.
# DP-360 T7: a JIRA-Epic source's V work item carries its own JIRA ticket key
# (resolvable as a plain JIRA key); pass it explicitly and provide the resolvable
# V task.md (T-path with a matching jira_key field + PASS ac_verification) so
# the verification cross-check is independently satisfiable.
JIRA_V_WORK_ITEM="EXAMPLE-1000"
JIRA_T_WORK_ITEM="EXAMPLE-1001"
JIRA_V_TASK_DIR="$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-999/tasks/T1"
mkdir -p "$JIRA_V_TASK_DIR"
python3 - "$JIRA_V_TASK_DIR/index.md" "$JIRA_V_WORK_ITEM" "$FIXTURE_HEAD" <<'PY'
import sys
from pathlib import Path
path, jira_key, head = sys.argv[1:4]
Path(path).write_text(
    "---\n"
    "task_kind: V\n"
    f"jira_key: {jira_key}\n"
    "ac_verification:\n"
    "  status: PASS\n"
    "---\n\n"
    "# V1\n\n"
    f"> Source: EXAMPLE-999 | Task: {jira_key} | JIRA: {jira_key} | Repo: selftest\n",
    encoding="utf-8",
)
PY
JIRA_T_TASK_DIR="$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-999/tasks/T2"
mkdir -p "$JIRA_T_TASK_DIR"
cat >"$JIRA_T_TASK_DIR/index.md" <<MD
---
task_kind: T
jira_key: ${JIRA_T_WORK_ITEM}
deliverable:
  head_sha: ${FIXTURE_HEAD}
---

# T2

> Source: EXAMPLE-999 | Task: ${JIRA_T_WORK_ITEM} | JIRA: ${JIRA_T_WORK_ITEM} | Repo: selftest
MD
JIRA_COMPLETE="$TMP/jira-complete.json"
write_report "$JIRA_COMPLETE" complete complete EXAMPLE-999 "$JIRA_V_WORK_ITEM" "$JIRA_T_WORK_ITEM"
"$VALIDATOR" "$JIRA_COMPLETE"

JIRA_BLOCKED="$TMP/jira-blocked.json"
write_report "$JIRA_BLOCKED" blocked_by_gate_failure blocked EXB2C-3461
"$VALIDATOR" "$JIRA_BLOCKED"

# DP-330 T2 AC3: framework_gap=true with valid contract_evidence → PASS.
FRAMEWORK_GAP="$TMP/framework-gap.json"
write_report "$FRAMEWORK_GAP" blocked_by_gate_failure framework_gap
"$VALIDATOR" "$FRAMEWORK_GAP"

# DP-330 T2 AC3: framework_gap=true but contract_evidence absent → FAIL.
FRAMEWORK_GAP_MISSING_EVIDENCE="$TMP/framework-gap-missing-evidence.json"
write_report "$FRAMEWORK_GAP_MISSING_EVIDENCE" blocked_by_gate_failure framework_gap_missing_evidence
expect_fail "framework-gap-missing-evidence" "$VALIDATOR" "$FRAMEWORK_GAP_MISSING_EVIDENCE"
grep -q 'contract_evidence is required' "$TMP/framework-gap-missing-evidence.out"

# DP-228 AC4 neg case: malformed source_id (lowercase) must fail.
BAD_PATTERN="$TMP/bad-pattern.json"
write_report "$BAD_PATTERN" complete complete gt-999
expect_fail "bad-pattern" "$VALIDATOR" "$BAD_PATTERN"
grep -n '{PREFIX}-NNN' "$TMP/bad-pattern.out" >/dev/null

# DP-438 AC-NEG2: a fake V deliverable cannot replace the canonical
# ac_verification lifecycle verdict.
write_v_ac_task "${SPECS_DP}/DP-199-report-fixture" V1 FAIL true
FAKE_V_DELIVERABLE="$TMP/fake-v-deliverable.json"
write_report "$FAKE_V_DELIVERABLE" complete complete DP-199
expect_fail "fake-v-deliverable" "$VALIDATOR" "$FAKE_V_DELIVERABLE"
grep -q 'POLARIS_AUTO_PASS_REPORT_VERIFICATION_MARKER_MISMATCH' "$TMP/fake-v-deliverable.out"

echo "PASS: auto-pass report selftest"
