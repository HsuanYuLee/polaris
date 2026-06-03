#!/usr/bin/env bash
# Purpose: DP-277 T2 — validator transparent-pipe gate + documented apply chain.
# Inputs:  none (hermetic; builds tmpdir memory_dir fixtures)
# Outputs: PASS line on stdout, exit 0; FAIL line on stderr + exit 1 on failure.
#
# Verifies:
#   AC5: documented chain `set -o pipefail; dry-run --json | validate | apply`
#        runs end-to-end (exit 0) and a demotable file is actually moved.
#   AC6: on PASS, validator stdout is byte-equal to the input plan JSON AND is
#        valid JSON; the verdict appears on stderr (not stdout).
#   AC-NEG4: an INVALID plan through the chain (under set -o pipefail) exits
#        nonzero, validator stdout is empty, and memory_dir is unchanged.

set -euo pipefail

REPO="${REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
TIERING="$REPO/scripts/memory-hygiene-tiering.py"
VALIDATOR="$REPO/scripts/validate-memory-hygiene-plan.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$TIERING" ]] || fail "$TIERING not found"
[[ -f "$VALIDATOR" ]] || fail "$VALIDATOR not found"

WORK="$(mktemp -d -t mh-chain-XXXX)"
trap 'rm -rf "$WORK"' EXIT

build_memory_dir() {
  local md="$1"
  mkdir -p "$md"
  # A clearly-demotable warm file (old snapshot, terminal-ish, no recent trigger)
  cat >"$md/demote_me.md" <<'EOF'
---
name: Demote Me
description: a stale snapshot that should move to warm
type: project
topic: cwv-epics
created: 2026-01-01
snapshot_of: DP-191
snapshot_taken: 2026-01-02
---
body
EOF
  # A hot file to keep MEMORY.md realistic
  cat >"$md/keep_hot.md" <<'EOF'
---
name: Keep Hot
description: active feedback
type: feedback
last_triggered: 2026-05-20
trigger_count: 4
created: 2026-05-01
---
body
EOF
  printf '# Memory Index\n\n' >"$md/MEMORY.md"
}

# === AC5: documented chain runs end-to-end + file actually moves ===
MD1="$WORK/ac5/memory"
build_memory_dir "$MD1"

set -o pipefail
python3 "$TIERING" dry-run --memory-dir "$MD1" --json \
  | bash "$VALIDATOR" \
  | python3 "$TIERING" apply --memory-dir "$MD1" >"$WORK/ac5/chain.out" 2>"$WORK/ac5/chain.err" \
  || { cat "$WORK/ac5/chain.err" >&2; fail "AC5 documented chain exited nonzero"; }

# A demotion must have happened: demote_me.md moved into cwv-epics/
[[ ! -f "$MD1/demote_me.md" ]] \
  || fail "AC5 demote_me.md still at flat root (no migration happened)"
[[ -f "$MD1/cwv-epics/demote_me.md" ]] \
  || { ls -R "$MD1" >&2; fail "AC5 demote_me.md not moved into cwv-epics/"; }

# === AC6: PASS pass-through stdout == input plan; verdict on stderr ===
MD2="$WORK/ac6/memory"
build_memory_dir "$MD2"
plan="$WORK/ac6/plan.json"
python3 "$TIERING" dry-run --memory-dir "$MD2" --json >"$plan"

out="$WORK/ac6/val.out"
err="$WORK/ac6/val.err"
bash "$VALIDATOR" --input "$plan" >"$out" 2>"$err" \
  || { cat "$err" >&2; fail "AC6 validator rejected a valid plan"; }

cmp "$plan" "$out" || { diff "$plan" "$out" >&2 || true; fail "AC6 stdout not byte-equal to input plan"; }
python3 -m json.tool <"$out" >/dev/null || fail "AC6 stdout is not valid JSON"
grep -q 'PASS' "$err" || { cat "$err" >&2; fail "AC6 verdict (PASS) not found on stderr"; }
[[ -s "$err" ]] || fail "AC6 stderr empty (verdict must be on stderr)"

# stdin path must also pass plan through verbatim on PASS
out2="$WORK/ac6/val2.out"
err2="$WORK/ac6/val2.err"
bash "$VALIDATOR" <"$plan" >"$out2" 2>"$err2" \
  || { cat "$err2" >&2; fail "AC6 stdin-mode validator rejected a valid plan"; }
cmp "$plan" "$out2" || fail "AC6 stdin-mode stdout not byte-equal to input plan"

# === AC-NEG4: invalid plan → chain nonzero, empty stdout, memory_dir unchanged ===
MD3="$WORK/neg4/memory"
build_memory_dir "$MD3"
# Snapshot memory_dir state before
before="$WORK/neg4/before.txt"
( find "$MD3" -type f | sort ) >"$before"

bad_plan="$WORK/neg4/bad.json"
# Missing classifications → triggers missing_classifications issue
printf '{"date":"2026-05-20"}\n' >"$bad_plan"

chain_exit=0
set -o pipefail
cat "$bad_plan" \
  | bash "$VALIDATOR" \
  | python3 "$TIERING" apply --memory-dir "$MD3" >"$WORK/neg4/chain.out" 2>"$WORK/neg4/chain.err" \
  || chain_exit=$?
[[ "$chain_exit" -ne 0 ]] || fail "AC-NEG4 chain exited 0 on invalid plan (expected nonzero)"

# Validator stdout must be empty on FAIL
neg_out="$WORK/neg4/val.out"
neg_err="$WORK/neg4/val.err"
neg_exit=0
bash "$VALIDATOR" --input "$bad_plan" >"$neg_out" 2>"$neg_err" || neg_exit=$?
[[ "$neg_exit" -ne 0 ]] || fail "AC-NEG4 validator exited 0 on invalid plan"
[[ ! -s "$neg_out" ]] || { cat "$neg_out" >&2; fail "AC-NEG4 validator wrote to stdout on FAIL (must be empty)"; }
grep -q 'FAIL' "$neg_err" || { cat "$neg_err" >&2; fail "AC-NEG4 FAIL verdict not on stderr"; }

# memory_dir unchanged (apply must not have moved anything)
after="$WORK/neg4/after.txt"
( find "$MD3" -type f | sort ) >"$after"
cmp "$before" "$after" || { diff "$before" "$after" >&2 || true; fail "AC-NEG4 memory_dir changed despite invalid plan"; }

echo "PASS: memory-hygiene-apply-chain selftest (AC5/AC6/AC-NEG4)"
