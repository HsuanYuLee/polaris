#!/usr/bin/env bash
# Purpose: DP-339 T1 — sanctioned deterministic writer that CONSUMES an auto-pass
#          session_handoff pause: clears pause (null) and stamps resumed_at, so the
#          runner stops short-circuiting to next_action=resume. Models on
#          scripts/auto-pass-finalize-ledger.sh (bash wrapper + embedded atomic
#          python rewrite). NOT a producer-token write: this is a plain file-I/O
#          writer (tempfile + os.replace) that deliberately does NOT go through
#          scripts/write-producer-owned-artifact.sh / the no-direct-evidence-write
#          hook and needs no new producer token — the auto-pass ledger is runner
#          state, not a specs-bound evidence artifact.
# Inputs:  --ledger <abs file>（必填，session_handoff ledger）
#          --resume-artifact <abs file>（write path 必填，交給 validate-auto-pass-resume.sh）
#          --source-id <KEY>（選填，透傳給 validate-auto-pass-resume.sh 交叉比對）
# Outputs: stdout CONSUMED / NOOP 訊息。exit 0 = consume 成功或 idempotent NOOP；
#          exit 2 = contract violation（stderr 帶 POLARIS_AUTO_PASS_CONSUME_RESUME_* marker）；
#          exit 1 = tool missing。
# NOOP 條件（exit 0、ledger 不動）：ledger 無 pause 或 pause 為 null（idempotent，AC-NEG2）。
# Fail-closed（exit 2、ledger 不動）：pause.kind != session_handoff（AC-NEG1）、缺
#          --resume-artifact、validate-auto-pass-resume.sh 非零（AC3）。
# 寫入內容（AC1 / AC4）：只 null pause、補 resumed_at（UTC ISO8601），其餘欄位
#          （loop_counters / task_snapshot / drift_retry 等）一律 byte-preserve。

set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/auto-pass-consume-resume.sh --ledger /abs/ledger.json \
    --resume-artifact /abs/session-handoff.json [--source-id DP-NNN]
USAGE
  exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  exit 1
fi

LEDGER=""
RESUME_ARTIFACT=""
SOURCE_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ledger)          LEDGER="${2:-}"; shift 2 ;;
    --resume-artifact) RESUME_ARTIFACT="${2:-}"; shift 2 ;;
    --source-id)       SOURCE_ID="${2:-}"; shift 2 ;;
    -h|--help)         usage ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      usage
      ;;
  esac
done

if [ -z "$LEDGER" ]; then
  echo "ERROR: --ledger is required" >&2
  usage
fi
if [ ! -f "$LEDGER" ]; then
  echo "POLARIS_AUTO_PASS_CONSUME_RESUME_LEDGER_MISSING:${LEDGER}" >&2
  exit 2
fi

# AC-NEG2 idempotent NOOP / AC-NEG1 wrong pause kind precede the resume-artifact
# requirement: a ledger with no active pause needs nothing and a wrong-kind pause
# is rejected before we ask for a resume artifact.
pause_kind="$(
  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_consume_resume_1.py" "$LEDGER"
)"

if [ "$pause_kind" = "__NO_PAUSE__" ]; then
  echo "NOOP: no active pause (${LEDGER})"
  exit 0
fi

if [ "$pause_kind" != "session_handoff" ]; then
  echo "POLARIS_AUTO_PASS_CONSUME_RESUME_NOT_SESSION_HANDOFF:${pause_kind}" >&2
  exit 2
fi

# AC3: write path requires a resume artifact, validated by the existing gate.
if [ -z "$RESUME_ARTIFACT" ]; then
  echo "POLARIS_AUTO_PASS_CONSUME_RESUME_RESUME_ARTIFACT_MISSING: --resume-artifact is required to consume a session_handoff pause" >&2
  exit 2
fi

validate_args=(--ledger "$LEDGER" --resume-artifact "$RESUME_ARTIFACT")
if [ -n "$SOURCE_ID" ]; then
  validate_args+=(--source-id "$SOURCE_ID")
fi
if ! bash "$SCRIPT_ROOT/scripts/validate-auto-pass-resume.sh" "${validate_args[@]}" >/dev/null 2>&1; then
  echo "POLARIS_AUTO_PASS_CONSUME_RESUME_VALIDATION_FAILED:${LEDGER}" >&2
  exit 2
fi

# AC1 / AC4: atomic in-place rewrite — null pause + stamp resumed_at, preserve the rest.
resumed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/auto_pass_auto_pass_consume_resume_2.py" "$LEDGER" "$resumed_at"

# Post-write fail-closed: the consumed ledger must still pass the ledger contract.
if ! bash "$SCRIPT_ROOT/scripts/validate-auto-pass-ledger.sh" "$LEDGER" >/dev/null 2>&1; then
  echo "POLARIS_AUTO_PASS_CONSUME_RESUME_POST_VALIDATE_FAILED:${LEDGER}" >&2
  exit 2
fi

echo "CONSUMED: pause cleared, resumed_at=${resumed_at} (${LEDGER})"
