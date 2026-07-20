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

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_append_auto_pass_friction_1.py" "${PYTHON_ARGS[@]}"
