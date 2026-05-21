#!/usr/bin/env bash
# memory-hygiene-capacity-ceiling-selftest.sh — DP-213 capacity ceiling contract.
#
# Verifies:
#   - apply_hot_capacity_ceiling demotes overflow Hot candidates to Warm.
#   - pinned entries always stay Hot (AC-NEG1).
#   - graduated_to entries stay Cold (AC-NEG2; never reach ceiling).
#   - apply Hot section ≤ MEMORY_HOT_CAPACITY (AC2).
#   - migration log lists overflowed-hot-capacity entries (AC5).

set -euo pipefail

REPO="${REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
TIERING="$REPO/scripts/memory-hygiene-tiering.py"
VALIDATOR="$REPO/scripts/validate-memory-hygiene-plan.sh"

if [[ ! -f "$TIERING" ]]; then
  echo "FAIL: $TIERING not found" >&2
  exit 1
fi

WORK="$(mktemp -d -t mh-ceiling-XXXX)"
trap 'rm -rf "$WORK"' EXIT

MEMORY_DIR="$WORK/memory"
mkdir -p "$MEMORY_DIR"

# 20 active feedback entries (last_triggered within 30d → Hot candidates)
for i in $(seq 1 20); do
  name="active_$(printf '%02d' "$i").md"
  cat >"$MEMORY_DIR/$name" <<EOF
---
name: active-$i
description: active feedback $i
type: feedback
last_triggered: 2026-05-20
trigger_count: $i
created: 2026-05-01
---
body
EOF
done

# 5 pinned entries (must always stay Hot regardless of capacity)
for i in $(seq 1 5); do
  name="pinned_$(printf '%02d' "$i").md"
  cat >"$MEMORY_DIR/$name" <<EOF
---
name: pinned-$i
description: pinned $i
type: feedback
pinned: true
pinned_reason: required for selftest
created: 2026-05-01
---
body
EOF
done

# 3 graduated entries (Cold; never compete for Hot)
for i in $(seq 1 3); do
  name="graduated_$(printf '%02d' "$i").md"
  cat >"$MEMORY_DIR/$name" <<EOF
---
name: graduated-$i
description: graduated $i
type: feedback
graduated_to: .claude/rules/example.md
created: 2026-05-01
---
body
EOF
done

# Empty MEMORY.md placeholder
printf '# Memory Index\n\n' >"$MEMORY_DIR/MEMORY.md"

# Run dry-run --json to get plan
plan_json="$WORK/plan.json"
MEMORY_HOT_CAPACITY=15 python3 "$TIERING" dry-run --json --memory-dir "$MEMORY_DIR" >"$plan_json"

# Verify plan classifications
hot_count="$(python3 -c "import json,sys; d=json.load(open('$plan_json')); print(sum(1 for c in d['classifications'] if c['tier']=='hot'))")"
pinned_hot="$(python3 -c "import json,sys; d=json.load(open('$plan_json')); print(sum(1 for c in d['classifications'] if c['tier']=='hot' and c['pinned']))")"
cold_count="$(python3 -c "import json,sys; d=json.load(open('$plan_json')); print(sum(1 for c in d['classifications'] if c['tier']=='cold'))")"
overflow_count="$(python3 -c "import json,sys; d=json.load(open('$plan_json')); print(sum(1 for c in d['classifications'] if 'overflowed-hot-capacity' in (c.get('reason') or '')))")"

if [[ "$hot_count" -gt 15 ]]; then
  echo "FAIL: Hot count in plan = $hot_count (expected ≤ 15)" >&2
  exit 1
fi

if [[ "$pinned_hot" -ne 5 ]]; then
  echo "FAIL: pinned-in-Hot = $pinned_hot (expected 5; AC-NEG1)" >&2
  exit 1
fi

if [[ "$cold_count" -lt 3 ]]; then
  echo "FAIL: Cold count = $cold_count (expected ≥ 3 for graduated entries; AC-NEG2)" >&2
  exit 1
fi

if [[ "$overflow_count" -lt 1 ]]; then
  echo "FAIL: no overflow demotion observed (expected ≥ 1; AC1)" >&2
  exit 1
fi

# Validator should accept the plan (no env bypass)
if ! "$VALIDATOR" --input "$plan_json" >/dev/null 2>"$WORK/validator.err"; then
  echo "FAIL: validator rejected plan unexpectedly" >&2
  cat "$WORK/validator.err" >&2
  exit 1
fi

# Apply the plan
python3 "$TIERING" apply --memory-dir "$MEMORY_DIR" <"$plan_json" >"$WORK/apply.out" 2>&1 || {
  echo "FAIL: apply exited non-zero" >&2
  cat "$WORK/apply.out" >&2
  exit 1
}

# Verify MEMORY.md Hot section count ≤ 15 (AC2)
hot_lines="$(awk '/^## Hot/{flag=1;next} /^## /{flag=0} flag && /^- /{count++} END{print count+0}' "$MEMORY_DIR/MEMORY.md")"
if [[ "$hot_lines" -gt 15 ]]; then
  echo "FAIL: MEMORY.md Hot section = $hot_lines entries (expected ≤ 15; AC2)" >&2
  exit 1
fi

# Verify migration log contains overflowed-hot-capacity (AC5)
log="$MEMORY_DIR/.migration-log.md"
if ! grep -q "overflowed-hot-capacity" "$log"; then
  echo "FAIL: migration log missing overflowed-hot-capacity entries (AC5)" >&2
  cat "$log" >&2
  exit 1
fi

echo "PASS: DP-213 capacity ceiling selftest (Hot=$hot_lines, pinned-kept=$pinned_hot, cold=$cold_count, overflowed=$overflow_count)"
