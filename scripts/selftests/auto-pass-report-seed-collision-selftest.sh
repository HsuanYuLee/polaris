#!/usr/bin/env bash
# Purpose: selftest for scripts/validate-auto-pass-report.sh DP-303 T5 (AC8) —
#          follow_up_dp_seed collision check. Before a seeded follow-up DP
#          number is written, the validator must verify the number is not
#          already occupied across BOTH the active (design-plans/DP-*) and the
#          archive (design-plans/archive/DP-*) namespaces; an occupied number
#          fails closed (exit 2 + structured POLARIS_AUTO_PASS_REPORT_SEED_*
#          marker). A free number passes.
# Inputs:  none (hermetic; fixtures in mktemp dir, specs root pinned via
#          POLARIS_SPECS_ROOT, evidence root via POLARIS_WORKSPACE_ROOT).
# Outputs: "PASS: ..." on success; non-zero exit with diagnostics on failure.
#
# Adversarial coverage (refinement.json adversarial_pass AC8): a seed writer
# that only checks the active namespace and skips archive must fail — the
# archive-occupied fixture asserts fail-closed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Hermetic specs tree: the validator resolves the design-plans namespaces under
# POLARIS_SPECS_ROOT (overrides the default workspace docs-manager specs root).
SPECS_ROOT="$TMP/specs"
DESIGN_PLANS="$SPECS_ROOT/design-plans"
ARCHIVE="$DESIGN_PLANS/archive"
mkdir -p "$DESIGN_PLANS" "$ARCHIVE"
export POLARIS_SPECS_ROOT="$SPECS_ROOT"

# Hermetic evidence root for the DP-311 verification-marker cross-check, so the
# report's verification.status=PASS claim is independently satisfiable and the
# seed-collision check is what we actually exercise.
export POLARIS_WORKSPACE_ROOT="$TMP"
MARKER_DIR="$TMP/.polaris/evidence/ac-verification"
mkdir -p "$MARKER_DIR"
HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Description: write an ac_verification PASS marker fixture.
# Args:        $1 = work_item_id
# Side effects: creates $MARKER_DIR/{work_item}-{HEAD_SHA}.json
write_pass_marker() {
  local work_item="$1"
  python3 - "$MARKER_DIR/${work_item}-${HEAD_SHA}.json" "$work_item" "$HEAD_SHA" <<'PY'
import json, sys
from pathlib import Path
path, work_item, head = sys.argv[1:4]
Path(path).write_text(json.dumps({
    "schema_version": 1,
    "marker_kind": "ac_verification",
    "writer": "verify-AC",
    "work_item_id": work_item,
    "head_sha": head,
    "status": "PASS",
}) + "\n", encoding="utf-8")
PY
}

# Description: occupy a DP number in the active or archive namespace by creating
#              a parent plan directory with an index.md (matches allocator
#              occupancy semantics).
# Args:        $1 = "active"|"archive"; $2 = DP dir name (e.g. DP-777-foo)
# Side effects: creates {namespace}/{dir}/index.md
occupy_dp() {
  local ns="$1" dir="$2" base
  case "$ns" in
    active) base="$DESIGN_PLANS" ;;
    archive) base="$ARCHIVE" ;;
    *) echo "occupy_dp: bad namespace $ns" >&2; exit 1 ;;
  esac
  mkdir -p "$base/$dir"
  printf '%s\n' "# placeholder plan" >"$base/$dir/index.md"
}

# Description: write a blocked auto-pass report whose follow_up_dp_seed.path
#              encodes a follow-up DP number under design-plans.
# Args:        $1 = output path; $2 = seed DP dir slug (e.g. DP-999-follow-up)
# Side effects: creates the report file
write_report_with_seed() {
  local path="$1" seed_dir="$2"
  python3 - "$path" "$seed_dir" <<'PY'
import json, sys
from pathlib import Path
report_path, seed_dir = sys.argv[1:3]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-303",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-06-16T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "x"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": {
        "path": f"docs-manager/src/content/docs/specs/design-plans/{seed_dir}/index.md",
        "reason": "blocked_by_gate_failure",
        "source_report": str(Path(report_path)),
        "framework_gap": False,
    },
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

assert_pass() {
  local label="$1"; shift
  if ! "$@" >"$TMP/$label.out" 2>&1; then
    echo "FAIL: $label expected PASS" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}
# Description: assert exit code 2 (fail-closed seed-collision cross-check).
assert_fail2() {
  local label="$1"; shift
  local rc=0
  "$@" >"$TMP/$label.out" 2>&1 || rc=$?
  if [[ "$rc" -ne 2 ]]; then
    echo "FAIL: $label expected exit 2 (fail-closed), got $rc" >&2
    cat "$TMP/$label.out" >&2
    exit 1
  fi
}

# ─── 1. POS: seed number free in both namespaces → PASS ──────────────────────
FREE="$TMP/free.json"
write_report_with_seed "$FREE" "DP-901-follow-up"
assert_pass "seed-free" "$VALIDATOR" "$FREE"

# ─── 2. NEG: seed number already occupied in ACTIVE namespace → fail-closed ──
occupy_dp active "DP-902-existing"
ACTIVE_HIT="$TMP/active-hit.json"
write_report_with_seed "$ACTIVE_HIT" "DP-902-follow-up"
assert_fail2 "seed-active-collision" "$VALIDATOR" "$ACTIVE_HIT"
grep -q 'POLARIS_AUTO_PASS_REPORT_SEED_COLLISION' "$TMP/seed-active-collision.out" \
  || { echo "FAIL: active collision should emit POLARIS_AUTO_PASS_REPORT_SEED_COLLISION" >&2; cat "$TMP/seed-active-collision.out" >&2; exit 1; }

# ─── 3. NEG (adversarial AC8): seed number occupied ONLY in ARCHIVE → fail ───
# A writer that checks active but skips archive would wrongly pass this.
occupy_dp archive "DP-903-archived"
ARCHIVE_HIT="$TMP/archive-hit.json"
write_report_with_seed "$ARCHIVE_HIT" "DP-903-follow-up"
assert_fail2 "seed-archive-collision" "$VALIDATOR" "$ARCHIVE_HIT"
grep -q 'POLARIS_AUTO_PASS_REPORT_SEED_COLLISION' "$TMP/seed-archive-collision.out" \
  || { echo "FAIL: archive collision should emit POLARIS_AUTO_PASS_REPORT_SEED_COLLISION" >&2; cat "$TMP/seed-archive-collision.out" >&2; exit 1; }

# ─── 4. POS: complete report with no seed (null) → seed check is a no-op ─────
# verification.status=PASS needs a resolvable V task.md whose deliverable block
# records a head-bound delivered head + PASS status (DP-311 cross-check (b),
# amended DP-360 T7 — the ac_verification marker is retired as the head-resolution
# authority; the task.md `deliverable` block is the sole delivery-evidence source).
# DP-303-V1 resolves under POLARIS_SPECS_ROOT=$SPECS_ROOT; the deliverable.head_sha
# is head-bound to the report's verification.head_sha=$HEAD_SHA.
write_pass_marker "DP-303-V1"
mkdir -p "${DESIGN_PLANS}/DP-303-report-fixture/tasks/V1"
python3 - "${DESIGN_PLANS}/DP-303-report-fixture/tasks/V1/index.md" "$HEAD_SHA" <<'PY'
import sys
from pathlib import Path
path, head = sys.argv[1:3]
Path(path).write_text(
    "---\n"
    "task_kind: V\n"
    "deliverable:\n"
    "  pr_url: https://github.com/example/polaris/pull/1\n"
    "  pr_state: MERGED\n"
    f"  head_sha: {head}\n"
    "  verification:\n"
    "    status: PASS\n"
    "---\n\n"
    "# V1\n",
    encoding="utf-8",
)
PY
NO_SEED="$TMP/no-seed.json"
python3 - "$NO_SEED" <<PY
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-303",
    "terminal_status": "complete",
    "created_at": "2026-06-16T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "PASS", "work_item_id": "DP-303-V1", "head_sha": "$HEAD_SHA"},
    "issues": [],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
}) + "\n", encoding="utf-8")
PY
# Provide a complete-eligible ledger so cross-check (a) passes.
LEDGER="$TMP/ledger.json"
printf '{"schema_version":"1","terminal_status":null,"pause":null,"friction_log":[]}\n' >"$LEDGER"
python3 - "$NO_SEED" "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["ledger_path"] = sys.argv[2]
p.write_text(json.dumps(d) + "\n", encoding="utf-8")
PY
assert_pass "no-seed-null" "$VALIDATOR" "$NO_SEED"

echo "PASS: auto-pass-report-seed-collision selftest"
