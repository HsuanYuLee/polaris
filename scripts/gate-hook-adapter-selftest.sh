#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER="$SCRIPT_DIR/gate-hook-adapter.sh"
TMPROOT="$(mktemp -d -t gate-hook-adapter-XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

assert_file_missing() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "FAIL: expected file to be absent: $path" >&2
    exit 1
  fi
}

assert_file_present() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: expected file to exist: $path" >&2
    exit 1
  fi
}

fixture_repo="$TMPROOT/repo"
mkdir -p "$fixture_repo"
fixture_repo="$(cd "$fixture_repo" && pwd -P)"
git -C "$fixture_repo" init -q
printf 'fixture\n' >"$fixture_repo/README.md"
git -C "$fixture_repo" add README.md
git -C "$fixture_repo" -c user.name='Polaris Selftest' -c user.email='polaris-selftest@example.invalid' commit -q -m 'fixture'
git -C "$fixture_repo" checkout -q -b task/DP-999-T4-gate-ledger

allow_gate="$TMPROOT/allow-gate.sh"
soft_fail_gate="$TMPROOT/soft-fail-gate.sh"
block_gate="$TMPROOT/block-gate.sh"
cat >"$allow_gate" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
echo "allow"
exit 0
SH
cat >"$soft_fail_gate" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
echo "soft fail" >&2
exit 1
SH
cat >"$block_gate" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
echo "blocked by fixture gate" >&2
exit 2
SH
chmod +x "$allow_gate" "$soft_fail_gate" "$block_gate"

ledger="$fixture_repo/.polaris/evidence/gate-failures/DP-999-T4.jsonl"

GATE_PROJECT_DIR="$fixture_repo" bash "$ADAPTER" "$allow_gate" "echo allow" >/dev/null
assert_file_missing "$ledger"

if GATE_PROJECT_DIR="$fixture_repo" bash "$ADAPTER" "$soft_fail_gate" "echo soft" >/tmp/gate-hook-adapter-soft.out 2>&1; then
  echo "FAIL: expected soft fail fixture to exit non-zero" >&2
  exit 1
fi
assert_file_missing "$ledger"

if GATE_PROJECT_DIR="$fixture_repo" bash "$ADAPTER" "$block_gate" "echo block" >/tmp/gate-hook-adapter-block.out 2>&1; then
  echo "FAIL: expected blocking fixture to exit non-zero" >&2
  exit 1
fi
assert_file_present "$ledger"

python3 - "$ledger" "$fixture_repo" <<'PY'
import json
import sys
from pathlib import Path

ledger = Path(sys.argv[1])
repo = sys.argv[2]
lines = [json.loads(line) for line in ledger.read_text(encoding="utf-8").splitlines() if line.strip()]
assert len(lines) == 1, lines
entry = lines[0]
required = {
    "ts",
    "task_id",
    "gate_id",
    "repo",
    "head_sha",
    "exit_code",
    "stderr_excerpt",
    "classification",
}
missing = sorted(required - set(entry))
assert not missing, missing
assert entry["task_id"] == "DP-999-T4", entry
assert entry["gate_id"] == "block-gate", entry
assert entry["repo"] == repo, entry
assert entry["exit_code"] == 2, entry
assert entry["classification"] == "pending", entry
assert "blocked by fixture gate" in entry["stderr_excerpt"], entry

entry["disposition"] = "fixed"
entry["self_correct_disposition"] = [
    {
        "gate_id": entry["gate_id"],
        "disposition": "fixed",
        "note": "selftest reflection consumer round-trip",
    }
]
ledger.write_text(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")

round_trip = json.loads(ledger.read_text(encoding="utf-8"))
assert round_trip["disposition"] == "fixed", round_trip
assert round_trip["self_correct_disposition"][0]["gate_id"] == "block-gate", round_trip
PY

blocked_ledger_dir="$TMPROOT/not-a-dir"
printf 'blocked\n' >"$blocked_ledger_dir"
if GATE_PROJECT_DIR="$fixture_repo" POLARIS_GATE_FAILURE_LEDGER_DIR="$blocked_ledger_dir" bash "$ADAPTER" "$block_gate" "echo block" >/tmp/gate-hook-adapter-ledger-fail.out 2>&1; then
  echo "FAIL: expected ledger write failure to fail-stop" >&2
  exit 1
fi
grep -q "failed to write gate-failure ledger after 3 attempts" /tmp/gate-hook-adapter-ledger-fail.out

grep -q "gate-hook-adapter" "$ROOT_DIR/.claude/skills/references/deterministic-hooks-registry.md"
grep -q "gate-fail-self-correct-disposition" "$ROOT_DIR/.claude/rules/mechanism-registry.md"
grep -q "self_correct_disposition" "$ROOT_DIR/.claude/skills/references/post-task-reflection-checkpoint.md"
grep -q "ledger" "$ROOT_DIR/.claude/rules/feedback-and-memory.md"

echo "PASS: gate-hook-adapter ledger selftest"
