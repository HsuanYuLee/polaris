#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_report() {
  local path="$1"
  local terminal="$2"
  local mode="$3"
  local source_id="${4:-DP-198}"
  python3 - "$path" "$terminal" "$mode" "$source_id" <<'PY'
import json
import sys
from pathlib import Path

path, terminal, mode, source_id = sys.argv[1:5]
payload = {
    "schema_version": 1,
    "source_id": source_id,
    "terminal_status": terminal,
    "created_at": "2026-05-19T10:30:00+08:00",
    "ledger_path": "/tmp/ledger.json",
    "required_prs": [{"task_id": f"{source_id}-T1", "pr_url": "https://github.com/org/repo/pull/1", "head_sha": "abc"}],
    "verification": {"status": "PASS", "work_item_id": f"{source_id}-V1"},
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
JIRA_COMPLETE="$TMP/jira-complete.json"
write_report "$JIRA_COMPLETE" complete complete EXAMPLE-999
"$VALIDATOR" "$JIRA_COMPLETE"

JIRA_BLOCKED="$TMP/jira-blocked.json"
write_report "$JIRA_BLOCKED" blocked_by_gate_failure blocked EXB2C-3461
"$VALIDATOR" "$JIRA_BLOCKED"

# DP-228 AC4 neg case: malformed source_id (lowercase) must fail.
BAD_PATTERN="$TMP/bad-pattern.json"
write_report "$BAD_PATTERN" complete complete gt-999
expect_fail "bad-pattern" "$VALIDATOR" "$BAD_PATTERN"
grep -n '{PREFIX}-NNN' "$TMP/bad-pattern.out" >/dev/null

echo "PASS: auto-pass report selftest"
