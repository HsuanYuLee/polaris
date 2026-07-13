#!/usr/bin/env bash
# Purpose: DP-417 T6 — assert the auto-pass complete gate
#          (scripts/validate-auto-pass-report.sh) closes PR-visible evidence
#          publication ownership after a review-driven revision / head rebind.
#          A required_prs[] row that declares a REVISED head (the head the PR
#          rebound to) may only reach terminal `complete` when its PR-visible
#          evidence publication marker is CURRENT at that revised head (AC6). A
#          stale (old-head) or missing evidence-publication head fails closed —
#          a revision that changed the head but did NOT re-publish evidence must
#          never silently PASS (AC-NEG2). Route-back (terminal != complete) is
#          the AC6 escape hatch and is NOT gated. A first-cut delivery row that
#          declares no revised head is not subject to the gate (no false
#          positive). Executable coverage itself satisfies AC-N1.
# Inputs:  none (hermetic; fixtures under a mktemp workspace, scan root pinned
#          via POLARIS_WORKSPACE_ROOT / POLARIS_SPECS_ROOT). Drives the EXISTING
#          scripts/validate-auto-pass-report.sh gate — no re-implemented logic.
# Outputs: stdout PASS line on success; exit 1 on any assertion failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
STALE_TOKEN="POLARIS_AUTO_PASS_PR_EVIDENCE_PUBLICATION_STALE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Hermetic scan root: the validator resolves the V work item's task.md
# deliverable block via resolve-task-md.sh --scan-root "$TMP".
export POLARIS_WORKSPACE_ROOT="$TMP"
export POLARIS_SPECS_ROOT="$TMP/docs-manager/src/content/docs/specs"
SPECS_ROOT="$TMP/docs-manager/src/content/docs/specs"
mkdir -p "$SPECS_ROOT/design-plans"

NEW_HEAD="1111111111111111111111111111111111111111"
OLD_HEAD="2222222222222222222222222222222222222222"
VERIFY_HEAD="3333333333333333333333333333333333333333"

# Description: record the V work item's delivery in its task.md `deliverable`
#              block so verification.status=PASS resolves (mirrors the DP-360 T7
#              delivery-evidence contract). Verification head-binding is a
#              separate T3 surface; this fixture just makes the complete report
#              otherwise valid so the evidence-publication check is isolated.
# Args:        $1 = work_item_id; $2 = head sha; $3 = status
write_marker() {
  local work_item="$1" head="$2" status="$3"
  python3 - "$SPECS_ROOT" "$work_item" "$head" "$status" <<'PY'
import re
import sys
from pathlib import Path

specs_root, work_item, head, status = sys.argv[1:5]
m = re.match(r"^([A-Z][A-Z0-9]+-\d+)-([A-Za-z]+\d+)$", work_item)
assert m, f"unexpected work_item shape: {work_item}"
source_id, stem = m.group(1), m.group(2)
task_dir = Path(specs_root) / "design-plans" / f"{source_id}-selftest" / "tasks" / stem
task_dir.mkdir(parents=True, exist_ok=True)
(task_dir / "index.md").write_text(
    "---\n"
    f'title: "{stem}"\n'
    "status: IN_PROGRESS\n"
    "task_kind: V\n"
    f"work_item_id: {work_item}\n"
    "deliverable:\n"
    f"  head_sha: {head}\n"
    "  pr_url: https://github.com/example-org/example/pull/1\n"
    "  pr_state: MERGED\n"
    "  verification:\n"
    f"    status: {status}\n"
    "---\n\n"
    f"# {stem}\n\n"
    f"> Source: {source_id} | Task: {work_item} | JIRA: {work_item} | Repo: polaris-framework\n",
    encoding="utf-8",
)
PY
}

# Description: write a minimal complete-eligible auto-pass ledger fixture.
write_ledger() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": "1",
    "terminal_status": "complete",
    "pause": None,
    "friction_log": [],
}) + "\n", encoding="utf-8")
PY
}

# Description: write an auto-pass terminal report with a caller-supplied
#              required_prs[] rows array.
# Args:        $1 = report path; $2 = terminal_status; $3 = rows JSON array;
#              $4 = mode (complete|blocked); $5 = complete ledger path
write_report() {
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
from pathlib import Path
path, terminal, rows_json, mode, ledger_path = sys.argv[1:6]
payload = {
    "schema_version": 1,
    "source_id": "DP-417",
    "terminal_status": terminal,
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": ledger_path if mode == "complete" else "/tmp/x",
    "required_prs": json.loads(rows_json),
    "verification": {"status": "PASS", "work_item_id": "DP-417-V1"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}
if mode == "blocked":
    # Route-back / still-revising report: not a complete claim. Verification is
    # not PASS (no delivery evidence asserted yet) and the issue threshold forces
    # a follow_up_dp_seed, matching the schema for non-complete terminals.
    payload["verification"] = {"status": "UNCERTAIN"}
    payload["issues"].append({"kind": "revision_in_flight", "reason": "still revising"})
    payload["follow_up_dp_seed"] = {
        "path": "docs-manager/src/content/docs/specs/design-plans/DP-999/index.md",
        "reason": terminal,
        "source_report": str(Path(path)),
        "framework_gap": False,
    }
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

assert_pass() {
  local label="$1" report="$2"
  if ! "$VALIDATOR" "$report" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label expected PASS (exit 0) but validator failed" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
  if grep -q "$STALE_TOKEN" "$TMP/$label.out"; then
    echo "FAIL: $label passed but emitted $STALE_TOKEN (false positive)" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

# Description: assert the validator fails closed with exit 2 AND the
#              evidence-publication staleness marker on stderr.
assert_stale() {
  local label="$1" report="$2" rc=0
  "$VALIDATOR" "$report" >"$TMP/$label.out" 2>&1 || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: $label expected exit 2 (fail-closed), got $rc" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
  if ! grep -q "$STALE_TOKEN" "$TMP/$label.out"; then
    echo "FAIL: $label exited 2 but missing $STALE_TOKEN marker" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

write_marker "DP-417-V1" "$VERIFY_HEAD" "PASS"
COMPLETE_LEDGER="$TMP/ledger-complete.json"
write_ledger "$COMPLETE_LEDGER"

# ── (a) AC6: revision → head rebind → evidence re-published at the NEW head ───
# The row declares the revised head and a PR-visible evidence publication head
# that is current at it → the flow may reach complete.
FRESH="$TMP/fresh.json"
write_report "$FRESH" complete \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"revised_head_sha\":\"$NEW_HEAD\",\"evidence_publication_head_sha\":\"$NEW_HEAD\"}]" \
  complete "$COMPLETE_LEDGER"
assert_pass "ac6-fresh-current-head" "$FRESH"

# ── (a') AC6 nested shape: evidence_publication.head_sha current at revised ───
FRESH_NESTED="$TMP/fresh-nested.json"
write_report "$FRESH_NESTED" complete \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"revised_head_sha\":\"$NEW_HEAD\",\"evidence_publication\":{\"head_sha\":\"$NEW_HEAD\"}}]" \
  complete "$COMPLETE_LEDGER"
assert_pass "ac6-fresh-nested-shape" "$FRESH_NESTED"

# ── (b) AC-NEG2: head rebound to NEW but evidence still published at OLD ──────
# Stale evidence publication → must fail closed (never a silent PASS).
STALE="$TMP/stale.json"
write_report "$STALE" complete \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"revised_head_sha\":\"$NEW_HEAD\",\"evidence_publication_head_sha\":\"$OLD_HEAD\"}]" \
  complete "$COMPLETE_LEDGER"
assert_stale "acneg2-stale-old-head" "$STALE"

# ── (c) AC-NEG2: head rebound to NEW but no evidence re-published at all ──────
MISSING="$TMP/missing.json"
write_report "$MISSING" complete \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"revised_head_sha\":\"$NEW_HEAD\"}]" \
  complete "$COMPLETE_LEDGER"
assert_stale "acneg2-missing-publication" "$MISSING"

# ── (d) AC6 route-back: same stale row but terminal != complete ──────────────
# The flow routed back to the owner (still revising) — the evidence-publication
# ownership gate does NOT fire; the report is otherwise valid → PASS.
ROUTEBACK="$TMP/routeback.json"
write_report "$ROUTEBACK" blocked_by_gate_failure \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"revised_head_sha\":\"$NEW_HEAD\",\"evidence_publication_head_sha\":\"$OLD_HEAD\"}]" \
  blocked "$COMPLETE_LEDGER"
assert_pass "ac6-routeback-not-gated" "$ROUTEBACK"

# ── (e) no-false-positive: first-cut delivery row declares no revised head ────
# A normal delivery PR (no head rebind) is not subject to the revision gate.
FIRSTCUT="$TMP/firstcut.json"
write_report "$FIRSTCUT" complete \
  "[{\"task_id\":\"DP-417-T1\",\"pr_url\":\"https://github.com/o/r/pull/1\",\"head_sha\":\"abc\"}]" \
  complete "$COMPLETE_LEDGER"
assert_pass "no-false-positive-first-cut" "$FIRSTCUT"

echo "PASS: revision-head-rebind-evidence-publication-ownership selftest"
