#!/usr/bin/env bash
# Purpose: DP-294 T2 / AC2 — amendment-time ledger refinement_hash re-anchor.
# Inputs:  none (hermetic tmpdir fixture).
# Outputs: PASS/FAIL lines + exit 0 (all pass) / 1 (any fail).
#
# Asserts that write-producer-owned-artifact.sh, when it mutates a source's
# refinement design doc (refinement.json) AND is given the in-flight auto-pass
# --ledger-path, re-anchors that ledger's source.refinement_hash to the new
# canonical hash in the SAME action (single writer path). The runner /
# source-gate stays a strict reader: a stale (un-re-anchored) ledger FAILS the
# validator — there is no stale-but-ok fast path.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRITER="$ROOT/scripts/write-producer-owned-artifact.sh"
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"

for f in "$WRITER" "$LEDGER_VALIDATOR"; do
  [[ -x "$f" ]] || { echo "FAIL: missing/not executable: $f" >&2; exit 1; }
done

TMP="$(mktemp -d -t auto-pass-rehash-XXXX)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1" >&2; }

# --- Build a hermetic LOCKED DP source container -----------------------------
C="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-999-rehash-fixture"
mkdir -p "$C"

cat >"$C/index.md" <<'MD'
---
title: "DP-999: rehash fixture"
description: "amendment rehash selftest fixture"
status: LOCKED
locked_at: 2026-06-07
---

# DP-999 fixture
MD

cat >"$C/refinement.md" <<'MD'
---
title: "DP-999 Refinement"
description: "amendment rehash fixture refinement"
---

## Scope

amendment rehash selftest fixture.
MD

write_refinement_json() {
  # $1 = output path, $2 = container, $3 = a marker string to vary content
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
from pathlib import Path
out, container, marker = sys.argv[1:4]
payload = {
    "schema_version": "1.0", "version": "1",
    "created_at": "2026-06-07T10:00:00+08:00" if marker == "v1" else "2026-06-07T10:01:00+08:00",
    "source": {"type": "dp", "id": "DP-999", "container": container,
               "plan_path": str(Path(container) / "index.md"), "jira_key": None},
    "modules": [{"path": "scripts/x.sh", "action": "modify"}],
    "acceptance_criteria": [{"id": "AC1", "text": "fixture",
                             "category": "functional", "quantifiable": True,
                             "negative": False,
                             "verification": {"method": "unit_test", "detail": "f"}}],
    "dependencies": [], "edge_cases": [], "predecessor_audit": [],
    "tasks": [{"id": "T1", "kind": "implementation", "title": "fixture",
               "scope": "f",
               "modules": ["scripts/x.sh"], "ac_ids": ["AC1"],
               "dependencies": [],
               "verification": {"method": "unit_test", "detail": "f"}}],
    "adversarial_pass": [{"ac_id": "AC1", "attack": "x", "enforce": "y"}],
}
Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

canonical_hash() {
  # $1 = container — recompute the canonical refinement_hash independently.
  python3 - "$1" <<'PY'
import hashlib, sys
from pathlib import Path
c = Path(sys.argv[1])
d = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    d.update(name.encode("utf-8")); d.update(b"\0")
    d.update((c / name).read_bytes()); d.update(b"\0")
print("sha256:" + d.hexdigest())
PY
}

ledger_hash() {
  python3 - "$1" <<'PY'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text())["source"]["refinement_hash"])
PY
}

write_ledger() {
  # $1 = path, $2 = refinement_hash to anchor
  python3 - "$1" "$C" "$2" <<'PY'
import json, sys
from pathlib import Path
path, container, ref_hash = sys.argv[1:4]
payload = {
    "schema_version": "1",
    "source": {"type": "dp", "id": "DP-999", "container": container, "refinement_hash": ref_hash},
    "started_at": "2026-06-07T10:00:00+08:00", "resumed_at": None, "terminal_status": None,
    "consent_policy": {"auto_reestimate": True, "auto_resplit": True, "auto_task_repair": True},
    "consent_excludes": ["base_branch_force_push", "force_push_without_lease", "history_rewrite",
                         "merge", "release", "deploy", "production_write", "jira_child_write",
                         "jira_comment_write", "jira_worklog_write", "task_scope_outside_mutation"],
    "task_snapshot": [], "stage_events": [],
    "loop_counters": {"engineering_to_breakdown": {"count": 0, "evidence_ids": []},
                      "breakdown_to_refinement_inbox": {"count": 0, "evidence_ids": []}},
    "drift_retry": {}, "pause": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

# Initial refinement.json + hash + ledger anchored to it.
write_refinement_json "$C/refinement.json" "$C" "v1"
bash "$ROOT/scripts/render-refinement-md.sh" "$C/refinement.json"
INIT_HASH="$(canonical_hash "$C")"
LEDGER="$TMP/ledger.json"
write_ledger "$LEDGER" "$INIT_HASH"

# --- Test 1: source gate PASS at initial anchor ---
if "$LEDGER_VALIDATOR" "$LEDGER" --source-container "$C" --source-id DP-999 >"$TMP/t1.out" 2>&1; then
  pass
else
  fail "initial-anchor source gate should PASS"; cat "$TMP/t1.out" >&2
fi

# --- Build the amended refinement.json body (different content → different hash) ---
BODY="$TMP/amended-refinement.json"
write_refinement_json "$BODY" "$C" "v2-amended"

# --- Test 2 (adversarial, no stale-but-ok): simulate the amendment WITHOUT the
#     writer re-anchor by mutating refinement.json directly; the ledger still
#     points at the OLD hash. The validator MUST FAIL (strict reader). ---
cp "$BODY" "$C/refinement.json"
if "$LEDGER_VALIDATOR" "$LEDGER" --source-container "$C" --source-id DP-999 >"$TMP/t2.out" 2>&1; then
  fail "stale ledger (old hash, mutated refinement) should FAIL — no stale-but-ok fast path"
else
  pass
fi
# restore the initial refinement.json + ledger for the writer-driven path
write_refinement_json "$C/refinement.json" "$C" "v1"
write_ledger "$LEDGER" "$INIT_HASH"

# --- Test 3: writer mutates refinement.json with --ledger-path → re-anchor ---
if "$WRITER" \
    --producer-token refinement:design-doc \
    --path "$C/refinement.json" \
    --body-file "$BODY" \
    --source-container "$C" \
    --source-id DP-999 \
    --ledger-path "$LEDGER" >"$TMP/t3.out" 2>&1; then
  pass
else
  fail "writer (amendment refinement.json + --ledger-path) should exit 0"; cat "$TMP/t3.out" >&2
fi

# --- Test 4: ledger refinement_hash re-anchored to NEW canonical hash ---
NEW_HASH="$(canonical_hash "$C")"
LEDGER_NOW="$(ledger_hash "$LEDGER")"
if [[ "$LEDGER_NOW" == "$NEW_HASH" && "$NEW_HASH" != "$INIT_HASH" ]]; then
  pass
else
  fail "ledger hash should re-anchor to new ($NEW_HASH), got '$LEDGER_NOW' (init=$INIT_HASH)"
fi

# --- Test 5: source gate PASS after re-anchor (no stale) ---
if "$LEDGER_VALIDATOR" "$LEDGER" --source-container "$C" --source-id DP-999 >"$TMP/t5.out" 2>&1; then
  pass
else
  fail "re-anchored ledger source gate should PASS"; cat "$TMP/t5.out" >&2
fi

# --- Test 6: writer is the single writer path — runner has no hash-writing /
#     stale-but-ok branch. Assert the runner does NOT write refinement_hash. ---
if grep -q 'refinement_hash' "$RUNNER" 2>/dev/null && \
   grep -Eq '(stale.but.ok|stale_but_ok)' "$RUNNER" 2>/dev/null; then
  fail "runner must not contain a stale-but-ok refinement_hash fast path"
else
  pass
fi

echo "[auto-pass-amendment-rehash-selftest] $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
