#!/usr/bin/env bash
# append-auto-pass-friction.sh — DP-214 helper
#
# Atomically append a single friction_log[] entry to an existing auto-pass ledger.
# Validates enum + required fields before write; emits warning when summary
# exceeds the soft limit but does NOT truncate (AC-NEG3).
#
# Usage:
#   scripts/append-auto-pass-friction.sh /abs/path/to/ledger.json \
#     --stage <source|breakdown|engineering|verify-AC|framework-release|post-task> \
#     --kind  <inner_skill_halt_bypass|manual_artifact_patch|deterministic_gap|env_bypass|validator_contract_conflict|missing_helper_script|language_drift_repair|other> \
#     --summary "<zh-TW summary, soft-limit 280 chars>" \
#     [--contract-evidence <repo/path:line>] \
#     [--ts <ISO8601, default=now>]
#
# --contract-evidence (DP-330) is REQUIRED for friction_kind deterministic_gap and
# validator_contract_conflict: a claimed framework gap must cite the pinned contract
# surface (repo/path:line) the author actually inspected. Repeatable; each value is one
# repo-resolvable path plus a positive line number. The other six kinds do not require it.
#
# Exit: 0 success, 1 invalid input, 2 ledger missing/unreadable, 3 write failure.

set -euo pipefail

LEDGER=""
STAGE=""
KIND=""
SUMMARY=""
TS=""
CONTRACT_EVIDENCE=()

usage() {
  sed -n '3,20p' "$0" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) STAGE="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-}"; shift 2 ;;
    --summary) SUMMARY="${2:-}"; shift 2 ;;
    --contract-evidence) CONTRACT_EVIDENCE+=("${2:-}"); shift 2 ;;
    --ts) TS="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage ;;
    *)
      if [[ -n "$LEDGER" ]]; then
        echo "ERROR: unexpected argument: $1" >&2
        usage
      fi
      LEDGER="$1"
      shift
      ;;
  esac
done

if [[ -z "$LEDGER" || -z "$STAGE" || -z "$KIND" || -z "$SUMMARY" ]]; then
  echo "ERROR: --stage, --kind, --summary, and ledger path are required" >&2
  usage
fi

# DP-220 NOOP boundary: when called from a deterministic trigger (gate adapter,
# pre-write hook, probe, counter helper) that opportunistically passes
# AUTO_PASS_LEDGER_PATH, the ledger may be absent for non-/auto-pass runs. In
# that case the friction is not orchestrator-tracked; exit 0 silently so the
# trigger script does not fail the user's main flow. Only emit warning to
# stderr (debugging aid) when POLARIS_FRICTION_DEBUG=1.
if [[ ! -f "$LEDGER" ]]; then
  if [[ "${POLARIS_FRICTION_DEBUG:-0}" == "1" ]]; then
    echo "append-auto-pass-friction: NOOP (ledger not found: $LEDGER)" >&2
  fi
  exit 0
fi

if [[ -z "$TS" ]]; then
  TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_ARGS=("$LEDGER" "$STAGE" "$KIND" "$SUMMARY" "$TS" "$ROOT")
if [[ "${#CONTRACT_EVIDENCE[@]}" -gt 0 ]]; then
  PYTHON_ARGS+=("${CONTRACT_EVIDENCE[@]}")
fi

python3 - "${PYTHON_ARGS[@]}" <<'PY'
import json
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
stage = sys.argv[2]
kind = sys.argv[3]
summary = sys.argv[4]
ts = sys.argv[5]
repo_root = Path(sys.argv[6]).resolve()
contract_evidence = [item.strip() for item in sys.argv[7:] if item.strip()]

sys.path.insert(0, str(repo_root / "scripts" / "lib"))
from contract_evidence import validate_contract_evidence_entries

KIND_ENUM = {
    "inner_skill_halt_bypass",
    "manual_artifact_patch",
    "deterministic_gap",
    "env_bypass",
    "validator_contract_conflict",
    "missing_helper_script",
    "language_drift_repair",
    "other",
}
STAGE_ENUM = {"source", "breakdown", "engineering", "verify-AC", "framework-release", "post-task"}
# DP-330: a claimed framework gap (these two kinds) must cite the pinned contract surface
# the author inspected, so the claim collapses on lookup if the contract already exists.
CONTRACT_EVIDENCE_REQUIRED_KINDS = {"deterministic_gap", "validator_contract_conflict"}
SOFT_LIMIT = 280

if stage not in STAGE_ENUM:
    sys.exit(f"ERROR: --stage must be one of {sorted(STAGE_ENUM)}")
if kind not in KIND_ENUM:
    sys.exit(f"ERROR: --kind must be one of {sorted(KIND_ENUM)}")
if not summary.strip():
    sys.exit("ERROR: --summary must not be empty")

if kind in CONTRACT_EVIDENCE_REQUIRED_KINDS and not contract_evidence:
    sys.exit(
        "ERROR: --contract-evidence is required for deterministic_gap and "
        "validator_contract_conflict"
    )

contract_evidence_errors = validate_contract_evidence_entries(
    contract_evidence,
    repo_root=repo_root,
    prefix="--contract-evidence",
    shape_error="ERROR: --contract-evidence must use repo/path:line shape (got: {raw})",
    outside_root_error="ERROR: --contract-evidence path must resolve under repo root (got: {raw})",
    not_found_error="ERROR: --contract-evidence path not found (got: {raw})",
    unreadable_error="ERROR: --contract-evidence path could not be read (got: {raw}; {exc})",
    out_of_range_error="ERROR: --contract-evidence line is outside file range (got: {raw})",
)
if contract_evidence_errors:
    sys.exit(contract_evidence_errors[0])

try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    sys.exit(f"ERROR: ledger invalid JSON: {exc}")

if not isinstance(ledger, dict):
    sys.exit("ERROR: ledger root must be an object")

friction_log = ledger.get("friction_log")
if friction_log is None:
    friction_log = []
    ledger["friction_log"] = friction_log
elif not isinstance(friction_log, list):
    sys.exit("ERROR: ledger.friction_log must be an array")

entry = {
    "ts": ts,
    "stage": stage,
    "friction_kind": kind,
    "summary": summary,
}
if contract_evidence:
    entry["contract_evidence"] = contract_evidence
friction_log.append(entry)

if len(summary) > SOFT_LIMIT:
    print(
        f"WARNING: summary length {len(summary)} exceeds soft limit {SOFT_LIMIT}; "
        "helper does not truncate by contract",
        file=sys.stderr,
    )

tmp = ledger_path.with_suffix(ledger_path.suffix + ".tmp")
tmp.write_text(json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
tmp.replace(ledger_path)
print(f"OK: appended friction_log entry to {ledger_path}")
PY
