#!/usr/bin/env bash
# no-direct-evidence-write-producer-token-selftest.sh — DP-226 T1 contract.
#
# Verifies the no-direct-evidence-write.sh hook recognises POLARIS_PRODUCER
# tokens against scripts/lib/evidence-producers.json with token-first lookup
# and path-glob enforcement.
#
# Cases:
#   AC1   valid token (auto-pass:source) + matching ledger path → exit 0
#         with stderr attribution log.
#   AC2   valid token (breakdown:initial-create) + overlapping path glob
#         (tasks/T*/index.md is also matched by dp-task-status-writer
#         tasks/**/index.md) → token-first lookup picks the initial-create
#         entry; exit 0 with attribution.
#   AC-NEG1  no POLARIS_PRODUCER + protected ledger path → exit 2 with
#            BLOCKED stderr (legacy behaviour preserved).
#   AC-NEG2  valid token but file_path outside that producer's path_globs[]
#            → exit 2 with DENIED token+path mismatch stderr; no bypass.
#   Token-not-in-table: random token → exit 2 with DENIED token-unknown.
#
# Exit 0 → PASS (echo `PASS`); any failure prints diagnostic + non-zero exit.

set -euo pipefail

# DP-226: prefer git-toplevel when invoked via run-verify-command.sh from a
# worktree (cwd = worktree, $0 path may still point at a stale absolute
# location). Fall back to BASH_SOURCE-derived path for direct invocation.
if ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$ROOT_DIR" ]]; then
  :
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
HOOK="$ROOT_DIR/.claude/hooks/no-direct-evidence-write.sh"
PRODUCERS_JSON="$ROOT_DIR/scripts/lib/evidence-producers.json"
WORKDIR="$(mktemp -d -t dp226-no-direct.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: hook is not executable: $HOOK" >&2
  exit 1
fi
if [[ ! -f "$PRODUCERS_JSON" ]]; then
  echo "FAIL: producers table missing: $PRODUCERS_JSON" >&2
  exit 1
fi

# Sanity check: producer table contains the DP-226 entries the contract relies on.
python3 - <<PY
import json, sys
data = json.load(open("$PRODUCERS_JSON"))
tokens = set()
for p in data.get("producers", []):
    for t in (p.get("producer_tokens") or []):
        if t in tokens:
            print(f"FAIL: duplicate token in producer_tokens[]: {t}", file=sys.stderr)
            sys.exit(2)
        tokens.add(t)
required = {"auto-pass:source", "auto-pass:breakdown", "auto-pass:engineering",
            "auto-pass:verify", "breakdown:initial-create"}
missing = required - tokens
if missing:
    print(f"FAIL: producer_tokens missing: {sorted(missing)}", file=sys.stderr)
    sys.exit(2)
PY

run_hook() {
  local payload="$1"
  local expected_exit="$2"
  local label="$3"
  local out_file="$WORKDIR/${label}.out"
  local env_var="${4:-}"
  set +e
  if [[ -n "$env_var" ]]; then
    env $env_var bash -c 'printf "%s" "$1" | "$2" >"$3" 2>&1' _ "$payload" "$HOOK" "$out_file"
  else
    printf '%s' "$payload" | "$HOOK" >"$out_file" 2>&1
  fi
  local rc=$?
  set -e
  if [[ "$rc" -ne "$expected_exit" ]]; then
    echo "FAIL ($label): expected exit $expected_exit, got $rc" >&2
    cat "$out_file" >&2
    exit 1
  fi
}

# AC1: auto-pass:source + matching ledger path → BYPASS.
ledger_path="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp226_fixture__/artifacts/auto-pass/20260522-fixture-ledger.json"
payload_ac1=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$ledger_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_ac1" 0 ac1-token-glob-bypass "POLARIS_PRODUCER=auto-pass:source"
grep -q 'producer=auto-pass:source' "$WORKDIR/ac1-token-glob-bypass.out"
grep -q 'DP-226 token+glob bypass' "$WORKDIR/ac1-token-glob-bypass.out"

# AC2: breakdown:initial-create + tasks/T*/index.md path — overlapping with
# dp-task-status-writer's tasks/**/index.md glob. Token-first lookup must pick
# the initial-create entry (which lists breakdown:initial-create in
# producer_tokens[]), not the older dp-task-status-writer (which has no
# producer_tokens[]).
task_index_path="$ROOT_DIR/docs-manager/src/content/docs/specs/design-plans/__dp226_fixture__/tasks/T1/index.md"
payload_ac2=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$task_index_path',
    'content': '---\ntitle: fixture\n---\n'
  }
}))
")
run_hook "$payload_ac2" 0 ac2-overlap-token-first "POLARIS_PRODUCER=breakdown:initial-create"
grep -q 'producer=breakdown:initial-create' "$WORKDIR/ac2-overlap-token-first.out"

# AC-NEG1: no POLARIS_PRODUCER + protected ledger path → BLOCKED.
payload_neg1=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$ledger_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_neg1" 2 neg1-no-token-blocked
grep -q 'BLOCKED' "$WORKDIR/neg1-no-token-blocked.out"

# AC-NEG2: valid token but file_path NOT in that producer's path_globs[].
# auto-pass:source belongs to entry with auto-pass ledger/resume globs only;
# writing to a task index path must be denied.
payload_neg2=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$task_index_path',
    'content': 'should be denied'
  }
}))
")
run_hook "$payload_neg2" 2 neg2-token-path-mismatch "POLARIS_PRODUCER=auto-pass:source"
grep -q 'DENIED token+path mismatch' "$WORKDIR/neg2-token-path-mismatch.out"
grep -q 'BLOCKED' "$WORKDIR/neg2-token-path-mismatch.out"

# Extra: unknown token → DENIED token unknown (still BLOCKED).
payload_unknown=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '$ledger_path',
    'content': '{}'
  }
}))
")
run_hook "$payload_unknown" 2 extra-token-unknown "POLARIS_PRODUCER=not-a-real-token"
grep -q 'DENIED token not in producer_tokens' "$WORKDIR/extra-token-unknown.out"

# Out-of-scope path: no bypass needed, hook is no-op (exit 0).
oos_payload=$(python3 -c "
import json
print(json.dumps({
  'tool_name': 'Write',
  'tool_input': {
    'file_path': '/tmp/some-random-file.txt',
    'content': 'irrelevant'
  }
}))
")
run_hook "$oos_payload" 0 oos-noop

echo "PASS"
