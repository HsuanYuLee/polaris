#!/usr/bin/env bash
# auto-pass-counter-race-recovery.sh — DP-246 T3 canonical surgical recovery path.
#
# When an auto-pass run terminates with loop_cap_reached and there is evidence
# that the counter was over-incremented due to a race condition (duplicate
# orchestration sessions writing the same transition without idempotency
# guards), this helper creates a corrected ledger that resets loop_counters to
# the actual back-edge count observed in stage_events, carries forward the old
# evidence_ids[] as already-accounted, and writes a COUNTER_RACE_RECOVERY audit
# entry to stage_events.
#
# This script is TERMINAL-ONLY.  It must never be called during an active
# orchestration loop; doing so would defeat the cap enforcement that protects
# against runaway retries.
#
# Three preconditions are checked (all must pass; any failure → exit 1):
#
#   (a) Prior ledger terminal_status == "loop_cap_reached"
#   (b) Prior ledger friction_log[] contains at least one stage_retry entry
#       (kind == inner_skill_halt_bypass or kind == stage_retry)
#   (c) Actual back-edge count computed from stage_events < cap (3)
#
# 24h rate-limit: a recovery is not allowed more than once per source per
# rolling 24-hour window.  The helper writes a stamp file at
#   {source_container}/.polaris/counter-race-recovery-last.json
# and checks mtime / "ts" field on each invocation.
#
# Usage:
#   scripts/auto-pass-counter-race-recovery.sh \
#     --source-id DP-NNN \
#     --prior-ledger /absolute/path/to/ledger.json \
#     [--repo /absolute/path/to/repo-root]
#
# Output:
#   Writes new ledger to same directory as prior-ledger with timestamp suffix:
#   {dir}/YYYYMMDD-HHMMSS-ledger.json
#   Prints path of new ledger to stdout on success.
#
# Exit:
#   0 success — new ledger written; path printed to stdout
#   1 precondition failure — stderr contains POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED
#   2 usage/environment error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${SCRIPT_DIR%/scripts}"

SOURCE_ID=""
PRIOR_LEDGER=""

usage() {
  sed -n '3,38p' "$0" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-id) SOURCE_ID="${2:-}"; shift 2 ;;
    --prior-ledger) PRIOR_LEDGER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage ;;
    *) echo "ERROR: unexpected argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$SOURCE_ID" || -z "$PRIOR_LEDGER" ]]; then
  echo "ERROR: --source-id and --prior-ledger are required" >&2
  usage
fi

if [[ ! -f "$PRIOR_LEDGER" ]]; then
  echo "POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED: prior ledger not found: $PRIOR_LEDGER" >&2
  exit 1
fi

# Delegate all logic to Python so bash arithmetic edge-cases don't matter.
NEW_LEDGER_PATH="$(python3 - "$SOURCE_ID" "$PRIOR_LEDGER" "$REPO" "$SCRIPT_DIR" <<'PY'
import datetime as dt
import json
import os
import sys
from pathlib import Path

source_id    = sys.argv[1]
prior_path   = Path(sys.argv[2]).resolve()
repo_root    = Path(sys.argv[3])
script_dir   = Path(sys.argv[4])

COUNTER_CAP = 3

def fail_precondition(msg):
    print(f"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED: {msg}", file=sys.stderr)
    sys.exit(1)

# ------------------------------------------------------------------ load ledger
try:
    ledger = json.loads(prior_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail_precondition(f"prior ledger is not valid JSON: {exc}")

# ------------------------------------------------------------------ resolve source container
# Use spec-source-resolver if available; otherwise fall back to path scan.
import subprocess
resolver = script_dir / "spec-source-resolver.sh"
source_container = None
if resolver.is_file():
    result = subprocess.run(
        ["bash", str(resolver), "--source-id", source_id, "--format", "json"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        try:
            info = json.loads(result.stdout)
            source_container = Path(info.get("container", ""))
        except Exception:
            pass

if source_container is None:
    # Fall back: extract from ledger source.container
    src = ledger.get("source") or {}
    raw_container = src.get("container", "")
    if raw_container:
        source_container = Path(raw_container)

if not source_container or not source_container.is_dir():
    fail_precondition(
        f"cannot resolve source container for {source_id}; "
        "pass --repo with a valid repo root or ensure spec-source-resolver.sh is present"
    )

# ------------------------------------------------------------------ 24h rate limit
stamp_path = source_container / ".polaris" / "counter-race-recovery-last.json"
now = dt.datetime.now(tz=dt.timezone.utc)
if stamp_path.is_file():
    try:
        stamp = json.loads(stamp_path.read_text(encoding="utf-8"))
        last_ts_str = stamp.get("ts", "")
        if last_ts_str:
            if last_ts_str.endswith("Z"):
                last_ts_str = last_ts_str[:-1] + "+00:00"
            last_ts = dt.datetime.fromisoformat(last_ts_str)
            elapsed = (now - last_ts).total_seconds()
            if elapsed < 86400:
                remaining_h = (86400 - elapsed) / 3600
                fail_precondition(
                    f"24h rate-limit: race-recovery already ran {elapsed/3600:.1f}h ago "
                    f"(cooldown {remaining_h:.1f}h remaining) for source {source_id}"
                )
    except json.JSONDecodeError:
        pass  # Corrupt stamp — treat as no prior recovery

# ------------------------------------------------------------------ precondition (a): terminal_status == loop_cap_reached
terminal_status = ledger.get("terminal_status")
if terminal_status != "loop_cap_reached":
    fail_precondition(
        f"precondition (a) FAIL: terminal_status must be 'loop_cap_reached', "
        f"got '{terminal_status}'"
    )

# ------------------------------------------------------------------ precondition (b): friction_log contains stage_retry evidence
friction_log = ledger.get("friction_log", [])
STAGE_RETRY_KINDS = {"inner_skill_halt_bypass", "stage_retry"}
race_friction = [
    e for e in friction_log
    if isinstance(e, dict) and e.get("friction_kind") in STAGE_RETRY_KINDS
]
if not race_friction:
    fail_precondition(
        "precondition (b) FAIL: friction_log contains no stage_retry "
        "(inner_skill_halt_bypass) entries; cannot confirm counter race condition"
    )

# ------------------------------------------------------------------ precondition (c): actual back-edge < cap
# Count the actual number of HALT/DISPATCHING back-edge events from stage_events.
# A back-edge is defined as a stage_events entry with status in
# {HALT, DISPATCHING} that records an engineering→breakdown or
# breakdown→refinement_inbox transition.
stage_events = ledger.get("stage_events", [])

BACK_EDGE_STATUSES = {"HALT", "DISPATCHING", "backward_transition"}

def _count_back_edges(transition_key):
    """Count distinct back-edge events for a given transition in stage_events."""
    count = 0
    for evt in stage_events:
        if not isinstance(evt, dict):
            continue
        # Match by work_item_id pattern or explicit transition field
        evt_transition = evt.get("transition", evt.get("kind", ""))
        evt_status = evt.get("status", "")
        if (
            transition_key in str(evt_transition)
            or evt_status in BACK_EDGE_STATUSES
            and transition_key.replace("_to_", "->") in str(evt)
        ):
            count += 1
    return count

engineering_to_breakdown_actual = _count_back_edges("engineering_to_breakdown")
breakdown_to_inbox_actual = _count_back_edges("breakdown_to_refinement_inbox")
actual_max = max(engineering_to_breakdown_actual, breakdown_to_inbox_actual)

# Also check the loop_counters that already exist to see the claimed count
loop_counters = ledger.get("loop_counters") or {}

def _counter_count(value):
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, dict):
        return int(value.get("count", 0))
    return 0

claimed_e2b = _counter_count(loop_counters.get("engineering_to_breakdown", 0))
claimed_b2i = _counter_count(loop_counters.get("breakdown_to_refinement_inbox", 0))

# Precondition (c): actual back-edge count must be < cap. If actual >= cap,
# the counter reflects reality and race-recovery should not be used to bypass it.
if actual_max >= COUNTER_CAP:
    fail_precondition(
        f"precondition (c) FAIL: actual back-edge count ({actual_max}) >= cap ({COUNTER_CAP}); "
        "counter reflects real retries — race-recovery cannot bypass genuine loop cap"
    )

# ------------------------------------------------------------------ build new ledger
import copy
import hashlib

new_ledger = copy.deepcopy(ledger)

# Carry forward old evidence_ids[] as already-accounted;
# reset count to actual back-edge count so orchestrator can resume cleanly.
def _merge_counter(old_value, actual_count):
    old_eids = []
    if isinstance(old_value, dict):
        old_eids = list(old_value.get("evidence_ids", []))
    return {"count": actual_count, "evidence_ids": old_eids}

new_loop_counters = {}
for key in ("engineering_to_breakdown", "breakdown_to_refinement_inbox"):
    old_val = loop_counters.get(key, {"count": 0, "evidence_ids": []})
    actual = (
        engineering_to_breakdown_actual if key == "engineering_to_breakdown"
        else breakdown_to_inbox_actual
    )
    new_loop_counters[key] = _merge_counter(old_val, actual)

new_ledger["loop_counters"] = new_loop_counters

# Clear terminal_status so orchestrator can resume
new_ledger["terminal_status"] = None

# Write lineage: record prior ledger path so we can detect repeated recovery
now_iso = now.strftime("%Y-%m-%dT%H:%M:%S+00:00")
recovery_audit = {
    "ts": now_iso,
    "stage": "post-task",
    "status": "COUNTER_RACE_RECOVERY",
    "kind": "COUNTER_RACE_RECOVERY",
    "prior_ledger": str(prior_path),
    "actual_engineering_to_breakdown": engineering_to_breakdown_actual,
    "actual_breakdown_to_refinement_inbox": breakdown_to_inbox_actual,
    "claimed_engineering_to_breakdown": claimed_e2b,
    "claimed_breakdown_to_refinement_inbox": claimed_b2i,
    "summary": (
        f"counter race-recovery: actual back-edge counts "
        f"(e2b={engineering_to_breakdown_actual}, b2i={breakdown_to_inbox_actual}) "
        f"< cap={COUNTER_CAP}; counters reset; old evidence_ids carried forward"
    )
}
if not isinstance(new_ledger.get("stage_events"), list):
    new_ledger["stage_events"] = []
new_ledger["stage_events"].append(recovery_audit)

# Update resumed_at
new_ledger["resumed_at"] = now_iso

# ------------------------------------------------------------------ write new ledger atomically
ts_str = now.strftime("%Y%m%d-%H%M%S")
new_ledger_path = prior_path.parent / f"{ts_str}-ledger.json"

# Validate with validate-auto-pass-ledger.sh before finalising
new_body = json.dumps(new_ledger, indent=2, ensure_ascii=False) + "\n"
tmp_path = new_ledger_path.with_suffix(".json.tmp")
tmp_path.write_text(new_body, encoding="utf-8")

validate_script = script_dir / "validate-auto-pass-ledger.sh"
if validate_script.is_file():
    result = subprocess.run(
        ["bash", str(validate_script), str(tmp_path)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        tmp_path.unlink(missing_ok=True)
        print(f"POLARIS_COUNTER_RECOVERY_PRECONDITION_FAILED: new ledger failed validation:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

tmp_path.rename(new_ledger_path)

# ------------------------------------------------------------------ write 24h rate-limit stamp
stamp_dir = stamp_path.parent
stamp_dir.mkdir(parents=True, exist_ok=True)
stamp_payload = {
    "source_id": source_id,
    "ts": now_iso,
    "prior_ledger": str(prior_path),
    "new_ledger": str(new_ledger_path),
}
tmp_stamp = stamp_path.with_suffix(".json.tmp")
tmp_stamp.write_text(json.dumps(stamp_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
tmp_stamp.rename(stamp_path)

print(str(new_ledger_path))
PY
)"

echo "$NEW_LEDGER_PATH"
