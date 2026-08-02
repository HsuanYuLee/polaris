#!/usr/bin/env bash
# Measurement-change ledger: the paper trail behind a swapped oracle command.
#
# The assertion layer is frozen; the measurement layer is deliberately open so a
# loop can improve how it measures without waking a human. The hole that opens
# is that an implementation could quietly swap in a command that measures
# nothing. This ledger closes it by making every swap carry a triple:
#
#   old command hash -> new command hash -> evidence the new command went red
#                                           before the implementation existed
#
# A command that cannot go red measured nothing, so evidence whose failure is an
# environment error (interpreter missing, not executable, tool absent) is
# rejected the same way a green "red evidence" is.
#
# Hashing is delegated to frozen-assertion-fence.sh. There is exactly one hash
# implementation in this spine.
#
# Subcommands:
#   record --ledger <p> --assertion-id <id> --new-command <cmd> --baseline
#   record --ledger <p> --assertion-id <id> --new-command <cmd>
#          --old-command <cmd> --red-evidence <path>
#   verify --ledger <p> --assertion-id <id> --command <cmd>
#   show   --ledger <p> [--assertion-id <id>]
#
# Red evidence is a JSON file:
#   {"command": "<verbatim new command>", "exit_code": 3,
#    "captured_at": "2026-08-01T10:00:00Z", "head_sha": "<sha at capture>",
#    "stderr": "...", "stdout": "..."}
#
# What this gate proves mechanically: the evidence exists, binds to this exact
# command, records a genuine non-zero exit, and is not an environment error; and
# the ledger chain is continuous. Capture ordering is carried as recorded fact
# (captured_at must precede the record) rather than claimed in prose.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FENCE="$SCRIPT_DIR/frozen-assertion-fence.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  record-measurement-change.sh record --ledger <path> --assertion-id <id> \
      --new-command <cmd> --baseline
  record-measurement-change.sh record --ledger <path> --assertion-id <id> \
      --new-command <cmd> --old-command <cmd> --red-evidence <path>
  record-measurement-change.sh verify --ledger <path> --assertion-id <id> --command <cmd>
  record-measurement-change.sh show --ledger <path> [--assertion-id <id>]
EOF
}

die() {
  # Description: emit a POLARIS marker plus human message, then fail closed.
  # Args: $1 = marker, $2.. = message
  local marker="$1"
  shift
  echo "$marker" >&2
  echo "$*" >&2
  exit 2
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

command_hash() {
  # Description: hash a command string through the single spine hash helper.
  # Args: $1 = command string
  [[ -x "$FENCE" || -f "$FENCE" ]] \
    || die "POLARIS_MEASUREMENT_HASH_HELPER_MISSING" "frozen-assertion-fence.sh not found at $FENCE"
  printf '%s' "$1" | bash "$FENCE" hash --stdin
}

file_hash() {
  # Description: hash a file through the single spine hash helper.
  # Args: $1 = file path
  bash "$FENCE" hash --file "$1"
}

latest_new_hash() {
  # Description: print the currently sanctioned command hash for an assertion,
  #              bare (no `sha256:` prefix) so it compares against command_hash.
  # Args: $1 = ledger path, $2 = assertion id
  # Side effects: none; prints nothing when the assertion has no entry yet.
  require_python3
  python3 - "$1" "$2" <<'PY'
import json
import os
import sys

ledger, assertion = sys.argv[1:3]
if not os.path.exists(ledger):
    sys.exit(0)
try:
    data = json.load(open(ledger, encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    print("POLARIS_MEASUREMENT_LEDGER_UNREADABLE", file=sys.stderr)
    sys.exit(2)
for entry in reversed(data.get("entries", [])):
    if entry.get("assertion_id") == assertion:
        print(entry.get("new_command_hash", "").removeprefix("sha256:"))
        break
PY
}

validate_red_evidence() {
  # Description: fail closed unless the evidence proves a real red run of this command.
  # Args: $1 = evidence path, $2 = new command string
  # Side effects: exits 2 with a POLARIS_MEASUREMENT_* marker on any violation.
  local evidence="$1" new_command="$2"

  [[ -f "$evidence" ]] \
    || die "POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING" \
      "no red evidence at '$evidence'; a measurement command that was never seen failing measured nothing"

  require_python3
  python3 - "$evidence" "$new_command" <<'PY'
import json
import re
import sys

path, new_command = sys.argv[1:3]

# A failure that only proves the command could not start proves nothing about
# what the command measures.
ENVIRONMENT_EXIT_CODES = {126, 127}
ENVIRONMENT_PATTERNS = (
    r"command not found",
    r"No such file or directory",
    r"Permission denied",
    r"POLARIS_TOOL_MISSING",
    r"executable file not found",
)

def fail(marker, message):
    print(marker, file=sys.stderr)
    print(message, file=sys.stderr)
    sys.exit(2)

try:
    data = json.load(open(path, encoding="utf-8"))
except (json.JSONDecodeError, OSError) as exc:
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} is not readable JSON: {exc}")

if data.get("command") != new_command:
    fail("POLARIS_MEASUREMENT_EVIDENCE_COMMAND_MISMATCH",
         "red evidence records a different command than the one being registered\n"
         f"  evidence: {data.get('command')!r}\n"
         f"  new:      {new_command!r}")

# Field names come from the only producer of these records,
# run-hardened-oracle.sh. They were once read under different names here
# (exit_code / captured_at), which nothing ever caught because this script's
# fixtures wrote those names too — so the two halves of the one measurement-change
# path agreed with their own tests and with nothing else. The first real handoff
# between them failed closed.
exit_code = data.get("command_exit_code")
if not isinstance(exit_code, int):
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} has no integer command_exit_code")

if exit_code == 0:
    fail("POLARIS_MEASUREMENT_EVIDENCE_NOT_RED",
         f"red evidence at {path} exited 0; the command was never observed failing")

stream = f"{data.get('stderr', '')}\n{data.get('stdout', '')}"
if exit_code in ENVIRONMENT_EXIT_CODES or any(
    re.search(p, stream, re.IGNORECASE) for p in ENVIRONMENT_PATTERNS
):
    fail("POLARIS_MEASUREMENT_EVIDENCE_ENVIRONMENT_ERROR",
         f"red evidence at {path} failed because the command could not run "
         f"(exit {exit_code}); that is an environment error, not a measurement")

if not data.get("recorded_at"):
    fail("POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING",
         f"red evidence at {path} has no recorded_at timestamp")
PY
}

cmd_record() {
  local ledger="" assertion="" new_command="" old_command="" evidence="" baseline="no"
  local have_new="no" have_old="no"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      --new-command) new_command="${2:-}"; have_new="yes"; shift 2 ;;
      --old-command) old_command="${2:-}"; have_old="yes"; shift 2 ;;
      --red-evidence) evidence="${2:-}"; shift 2 ;;
      --baseline) baseline="yes"; shift ;;
      *) usage; exit 2 ;;
    esac
  done

  [[ -n "$ledger" ]] || { usage; exit 2; }
  [[ -n "$assertion" ]] || { usage; exit 2; }
  [[ "$have_new" == "yes" && -n "$new_command" ]] || { usage; exit 2; }

  local current
  current="$(latest_new_hash "$ledger" "$assertion")" || exit 2

  local new_hash old_hash="" evidence_hash="" kind
  new_hash="$(command_hash "$new_command")"

  if [[ "$baseline" == "yes" ]]; then
    if [[ -n "$current" ]]; then
      die "POLARIS_MEASUREMENT_BASELINE_ALREADY_SET" \
        "assertion '$assertion' already has a sanctioned command; a later swap needs --old-command and --red-evidence, not --baseline"
    fi
    kind="baseline"
  else
    if [[ -z "$current" ]]; then
      die "POLARIS_MEASUREMENT_BASELINE_MISSING" \
        "assertion '$assertion' has no baseline command; record the first command with --baseline"
    fi
    [[ "$have_old" == "yes" ]] \
      || die "POLARIS_MEASUREMENT_CHAIN_BROKEN" "a measurement change requires --old-command"
    old_hash="$(command_hash "$old_command")"
    if [[ "$old_hash" != "$current" ]]; then
      die "POLARIS_MEASUREMENT_CHAIN_BROKEN" \
        "--old-command does not match the sanctioned command for '$assertion' (sanctioned sha256:$current, given sha256:$old_hash)"
    fi
    [[ -n "$evidence" ]] \
      || die "POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING" \
        "a measurement change requires --red-evidence; an unaccompanied swap is exactly what this ledger rejects"
    validate_red_evidence "$evidence" "$new_command" || exit 2
    evidence_hash="$(file_hash "$evidence")"
    kind="change"
  fi

  require_python3
  python3 - "$ledger" "$assertion" "$kind" "$new_command" "$new_hash" "$old_hash" "$evidence" "$evidence_hash" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(ledger, assertion, kind, new_command, new_hash,
 old_hash, evidence_path, evidence_hash) = sys.argv[1:9]

data = {"schema_version": 1, "entries": []}
if os.path.exists(ledger):
    try:
        data = json.load(open(ledger, encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        print("POLARIS_MEASUREMENT_LEDGER_UNREADABLE", file=sys.stderr)
        print(f"{ledger}: {exc}", file=sys.stderr)
        sys.exit(2)

entry = {
    "assertion_id": assertion,
    "kind": kind,
    "old_command_hash": f"sha256:{old_hash}" if old_hash else None,
    "new_command_hash": f"sha256:{new_hash}",
    "new_command": new_command,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

if evidence_path:
    evidence = json.load(open(evidence_path, encoding="utf-8"))
    entry["red_evidence"] = {
        "path": evidence_path,
        "hash": f"sha256:{evidence_hash}",
        "command_exit_code": evidence.get("command_exit_code"),
        "recorded_at": evidence.get("recorded_at"),
        "head_sha": evidence.get("head_sha"),
    }
    if evidence.get("recorded_at", "") > entry["recorded_at"]:
        print("POLARIS_MEASUREMENT_EVIDENCE_NOT_RED", file=sys.stderr)
        print(f"red evidence recorded_at {evidence.get('recorded_at')} is after this record; "
              "the command must be seen failing before the change is registered", file=sys.stderr)
        sys.exit(2)

data.setdefault("entries", []).append(entry)
os.makedirs(os.path.dirname(os.path.abspath(ledger)) or ".", exist_ok=True)
with open(ledger, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"RECORDED: {assertion} {kind} sha256:{new_hash}")
PY
}

cmd_verify() {
  local ledger="" assertion="" command_str="" have_command="no"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      --command) command_str="${2:-}"; have_command="yes"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done

  [[ -n "$ledger" && -n "$assertion" && "$have_command" == "yes" ]] || { usage; exit 2; }

  local current
  current="$(latest_new_hash "$ledger" "$assertion")" || exit 2
  [[ -n "$current" ]] \
    || die "POLARIS_MEASUREMENT_COMMAND_UNREGISTERED" \
      "assertion '$assertion' has no sanctioned measurement command in $ledger"

  local given
  given="$(command_hash "$command_str")"
  if [[ "$given" != "$current" ]]; then
    die "POLARIS_MEASUREMENT_COMMAND_UNREGISTERED" \
      "the command offered for '$assertion' is not the sanctioned one (sanctioned sha256:$current, given sha256:$given); register the change with red evidence first"
  fi
  echo "PASS: measurement command for '$assertion' matches sanctioned sha256:$current"
}

cmd_show() {
  local ledger="" assertion=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ledger) ledger="${2:-}"; shift 2 ;;
      --assertion-id) assertion="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [[ -n "$ledger" && -f "$ledger" ]] \
    || die "POLARIS_MEASUREMENT_LEDGER_UNREADABLE" "ledger not readable: ${ledger:-<missing>}"

  require_python3
  python3 - "$ledger" "$assertion" <<'PY'
import json
import sys

ledger, assertion = sys.argv[1:3]
data = json.load(open(ledger, encoding="utf-8"))
for entry in data.get("entries", []):
    if assertion and entry.get("assertion_id") != assertion:
        continue
    evidence = entry.get("red_evidence") or {}
    print(f"{entry['assertion_id']} {entry['kind']} "
          f"old={entry.get('old_command_hash')} new={entry['new_command_hash']} "
          f"evidence={evidence.get('hash')}")
PY
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    record) cmd_record "$@" ;;
    verify) cmd_verify "$@" ;;
    show) cmd_show "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
