#!/usr/bin/env bash
# Purpose: Verify the measurement-change ledger rejects unaccompanied swaps.
# Inputs: Hermetic ledger and red-evidence fixtures under mktemp.
# Outputs: PASS when a swap without evidence is refused, an environment-error
#          "red" is refused, a genuine red run is accepted with a complete
#          triple, and unregistered commands are refused at verify time.

set -euo pipefail

for tool in python3 shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:$tool" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
done

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDER="$ROOT_DIR/scripts/record-measurement-change.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LEDGER="$WORK/measurement-ledger.json"
BASE_CMD='bash fixture/example-selftest.sh'
NEW_CMD='bash fixture/example-selftest.sh --strict'

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_marker() {
  # Description: run a command expected to fail with a specific POLARIS marker.
  # Args: $1 = case name, $2 = expected marker, $3.. = command
  local name="$1" marker="$2"
  shift 2
  local out status
  out="$("$@" 2>&1)" && status=0 || status=$?
  [[ "$status" -ne 0 ]] || fail "$name unexpectedly passed"
  grep -Fq "$marker" <<<"$out" || fail "$name did not emit $marker; got: $out"
}

write_evidence() {
  # Description: write a red-evidence JSON fixture, in the shape the only real
  #   producer (run-hardened-oracle.sh) writes. Field names matter: these
  #   fixtures once used names the producer never emitted, so both halves of the
  #   measurement-change path passed their own tests and failed the first time
  #   they met. Case 11 covers the real handoff; these stay hand-rolled only
  #   because they exercise validator branches a passing oracle cannot produce.
  # Args: $1 = path, $2 = command, $3 = command_exit_code, $4 = stderr text
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json
import sys
path, command, exit_code, stderr = sys.argv[1:5]
json.dump({
    "schema_version": 1,
    "producer": "run-hardened-oracle.sh",
    "command": command,
    "command_exit_code": int(exit_code),
    "recorded_at": "2026-08-01T00:00:00Z",
    "head_sha": "0000000000000000000000000000000000000000",
    "stderr": stderr,
    "stdout": "",
}, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

# --- Case 1: baseline registration, then verify accepts it -------------------
bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
  --new-command "$BASE_CMD" --baseline >/dev/null \
  || fail "baseline registration failed"
bash "$RECORDER" verify --ledger "$LEDGER" --assertion-id AC-P1 --command "$BASE_CMD" >/dev/null \
  || fail "verify rejected the baseline command"

# --- Case 2: an unregistered command is refused ------------------------------
assert_marker "unregistered command" POLARIS_MEASUREMENT_COMMAND_UNREGISTERED \
  bash "$RECORDER" verify --ledger "$LEDGER" --assertion-id AC-P1 --command "$NEW_CMD"

# --- Case 3: a swap with no red evidence is refused --------------------------
assert_marker "swap without evidence" POLARIS_MEASUREMENT_RED_EVIDENCE_MISSING \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command "$BASE_CMD"

# --- Case 4: evidence that exited 0 is not red -------------------------------
write_evidence "$WORK/green.json" "$NEW_CMD" 0 ""
assert_marker "green evidence" POLARIS_MEASUREMENT_EVIDENCE_NOT_RED \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command "$BASE_CMD" --red-evidence "$WORK/green.json"

# --- Case 5: an environment error is not a measurement -----------------------
write_evidence "$WORK/env-code.json" "$NEW_CMD" 127 "example-selftest.sh: command not found"
assert_marker "environment error by exit code" POLARIS_MEASUREMENT_EVIDENCE_ENVIRONMENT_ERROR \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command "$BASE_CMD" --red-evidence "$WORK/env-code.json"

write_evidence "$WORK/env-text.json" "$NEW_CMD" 2 "bash: fixture/x.sh: No such file or directory"
assert_marker "environment error by message" POLARIS_MEASUREMENT_EVIDENCE_ENVIRONMENT_ERROR \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command "$BASE_CMD" --red-evidence "$WORK/env-text.json"

# --- Case 6: evidence for a different command is refused ---------------------
write_evidence "$WORK/other.json" 'bash fixture/other-selftest.sh' 1 "assertion failed"
assert_marker "evidence command mismatch" POLARIS_MEASUREMENT_EVIDENCE_COMMAND_MISMATCH \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command "$BASE_CMD" --red-evidence "$WORK/other.json"

# --- Case 7: a broken chain is refused ---------------------------------------
write_evidence "$WORK/red.json" "$NEW_CMD" 1 "FAIL: expected non-empty evidence, got none"
assert_marker "broken chain" POLARIS_MEASUREMENT_CHAIN_BROKEN \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command "$NEW_CMD" --old-command 'bash fixture/never-registered.sh' \
    --red-evidence "$WORK/red.json"

# --- Case 8: a genuine red run is accepted with a complete triple ------------
bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
  --new-command "$NEW_CMD" --old-command "$BASE_CMD" --red-evidence "$WORK/red.json" >/dev/null \
  || fail "a genuine red run was refused"

python3 - "$LEDGER" "$NEW_CMD" <<'PY'
import json
import sys
ledger, new_command = sys.argv[1:3]
entries = json.load(open(ledger, encoding="utf-8"))["entries"]
change = [e for e in entries if e["kind"] == "change"]
assert len(change) == 1, f"expected exactly one change entry, got {len(change)}"
entry = change[0]
assert entry["assertion_id"] == "AC-P1"
assert entry["new_command"] == new_command
for field in ("old_command_hash", "new_command_hash"):
    assert str(entry[field]).startswith("sha256:"), f"{field} is not a sha256 triple member"
evidence = entry["red_evidence"]
for field in ("path", "hash", "command_exit_code", "recorded_at"):
    assert evidence.get(field) not in (None, ""), f"red_evidence.{field} missing"
assert evidence["command_exit_code"] != 0
PY

# --- Case 9: verify follows the chain to the new command ---------------------
bash "$RECORDER" verify --ledger "$LEDGER" --assertion-id AC-P1 --command "$NEW_CMD" >/dev/null \
  || fail "verify rejected the newly sanctioned command"
assert_marker "superseded command" POLARIS_MEASUREMENT_COMMAND_UNREGISTERED \
  bash "$RECORDER" verify --ledger "$LEDGER" --assertion-id AC-P1 --command "$BASE_CMD"

# --- Case 10: a second baseline for the same assertion is refused ------------
assert_marker "duplicate baseline" POLARIS_MEASUREMENT_BASELINE_ALREADY_SET \
  bash "$RECORDER" record --ledger "$LEDGER" --assertion-id AC-P1 \
    --new-command 'bash fixture/sneaky.sh' --baseline

# --- Case 11: the hash comes from the single spine implementation ------------
expected="$(printf '%s' "$NEW_CMD" | bash "$ROOT_DIR/scripts/frozen-assertion-fence.sh" hash --stdin)"
recorded="$(python3 -c '
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))["entries"]
print([e for e in entries if e["kind"] == "change"][0]["new_command_hash"])
' "$LEDGER")"
[[ "$recorded" == "sha256:$expected" ]] \
  || fail "ledger hash ($recorded) does not match the fence helper (sha256:$expected)"

# --- Case 12: a record the oracle actually produced is accepted ---------------
# The two halves of this path are only ever exercised together here. Everything
# above builds its own evidence, which is why a producer/consumer field-name
# drift survived: each half agreed with its own fixtures.
FAILING_CMD='bash -c "echo 量到了; exit 1"'
bash "$ROOT_DIR/scripts/run-hardened-oracle.sh" --command "$FAILING_CMD" \
  --expect-evidence '量到了' --evidence-out "$WORK/from-oracle.json" >/dev/null 2>&1 || true
[[ -f "$WORK/from-oracle.json" ]] || fail "the oracle wrote no evidence record"

bash "$RECORDER" record --ledger "$WORK/oracle-ledger.json" --assertion-id AC-P2 \
  --new-command "$BASE_CMD" --baseline >/dev/null \
  || fail "baseline registration failed for the oracle handoff case"
bash "$RECORDER" record --ledger "$WORK/oracle-ledger.json" --assertion-id AC-P2 \
  --new-command "$FAILING_CMD" --old-command "$BASE_CMD" \
  --red-evidence "$WORK/from-oracle.json" >/dev/null \
  || fail "the recorder refused a red record produced by run-hardened-oracle.sh"

echo "PASS: record-measurement-change-selftest.sh"
