#!/usr/bin/env bash
# Purpose: selftest for scripts/validate-auto-pass-report.sh DP-303 T5 + DP-438 —
#          fresh follow_up_dp_seed collision and existing-owner authority checks.
#          Before a seeded follow-up DP
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

# Hermetic evidence root for canonical task resolution.
export POLARIS_WORKSPACE_ROOT="$TMP"
HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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
  if [[ "$ns" == "active" ]]; then
    printf '%s\n' '---' 'status: LOCKED' '---' '' '# placeholder plan' >"$base/$dir/index.md"
  else
    printf '%s\n' '---' 'status: IMPLEMENTED' '---' '' '# placeholder plan' >"$base/$dir/index.md"
  fi
}

# Description: add canonical refinement predecessor linkage proving that an
#              active owner has deliberately consumed the report source.
# Args:        $1 = active DP dir name; $2 = report source id
link_owner_to_source() {
  local dir="$1" source_id="$2"
  python3 - "$DESIGN_PLANS/$dir/refinement.json" "$source_id" <<'PY'
import json, sys
from pathlib import Path
path, source_id = sys.argv[1:3]
Path(path).write_text(json.dumps({
    "predecessor_audit": [{
        "spec_id": source_id,
        "disposition": "KEEP",
        "rationale": "selftest owner consumes this source as telemetry input",
        "writeback": {
            "required": False,
            "summary": "selftest canonical owner linkage",
            "expected_status": "UNCHANGED",
            "checklist_attribution": [],
        },
    }],
}) + "\n", encoding="utf-8")
PY
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

# Description: write a report whose issue threshold is owned by an existing DP,
#              not by a fresh seed.
# Args:        $1 = output path; $2 = existing source id; $3 = owner path
write_report_with_existing_owner() {
  local path="$1" owner_id="$2" owner_path="$3"
  python3 - "$path" "$owner_id" "$owner_path" <<'PY'
import json, sys
from pathlib import Path
report_path, owner_id, owner_path = sys.argv[1:4]
Path(report_path).write_text(json.dumps({
    "schema_version": 1,
    "source_id": "DP-303",
    "terminal_status": "blocked_by_gate_failure",
    "created_at": "2026-06-16T10:30:00+08:00",
    "ledger_path": "/tmp/x",
    "required_prs": [],
    "verification": {"status": "UNCERTAIN"},
    "issues": [{"kind": "existing_owner"}],
    "blockers": [],
    "manual_items": [],
    "follow_ups": [],
    "overlap_disposition": [],
    "follow_up_dp_seed": None,
    "follow_up_existing_owner": {
        "source_id": owner_id,
        "path": owner_path,
        "reason": "既有 DP 已擁有此摩擦。",
        "source_report": str(Path(report_path)),
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

# ─── 4. POS: issue threshold can reuse an existing owner without seed collision ─
occupy_dp active "DP-904-existing"
link_owner_to_source "DP-904-existing" "DP-303"
EXISTING_OWNER="$TMP/existing-owner.json"
write_report_with_existing_owner "$EXISTING_OWNER" "DP-904" \
  "docs-manager/src/content/docs/specs/design-plans/DP-904-existing/index.md"
assert_pass "existing-owner" "$VALIDATOR" "$EXISTING_OWNER"

# Canonical parent archive moves the report from active/ to archive/ without
# rewriting its JSON body. source_report remains valid across that one namespace
# relocation, but not across arbitrary path changes.
ARCHIVED_REPORT_DIR="$ARCHIVE/DP-303-move-fixture/artifacts/auto-pass"
mkdir -p "$ARCHIVED_REPORT_DIR"
ARCHIVED_REPORT="$ARCHIVED_REPORT_DIR/report.json"
write_report_with_existing_owner "$ARCHIVED_REPORT" "DP-904" \
  "docs-manager/src/content/docs/specs/design-plans/DP-904-existing/index.md"
python3 - "$ARCHIVED_REPORT" "$DESIGN_PLANS/DP-303-move-fixture/artifacts/auto-pass/report.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["follow_up_existing_owner"]["source_report"] = sys.argv[2]
path.write_text(json.dumps(data) + "\n", encoding="utf-8")
PY
assert_pass "existing-owner-after-source-archive" "$VALIDATOR" "$ARCHIVED_REPORT"

FOREIGN_ROOT_REPORT="$TMP/foreign-root-report.json"
write_report_with_existing_owner "$FOREIGN_ROOT_REPORT" "DP-904" \
  "docs-manager/src/content/docs/specs/design-plans/DP-904-existing/index.md"
python3 - "$FOREIGN_ROOT_REPORT" "$TMP/foreign/design-plans/DP-303-move-fixture/artifacts/auto-pass/report.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["follow_up_existing_owner"]["source_report"] = sys.argv[2]
path.write_text(json.dumps(data) + "\n", encoding="utf-8")
PY
assert_fail2 "existing-owner-foreign-report-root" "$VALIDATOR" "$FOREIGN_ROOT_REPORT"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-foreign-report-root.out"

# ─── 5. NEG: existing owner must exist and match the declared identity ───────
MISSING_OWNER="$TMP/missing-owner.json"
write_report_with_existing_owner "$MISSING_OWNER" "DP-905" \
  "docs-manager/src/content/docs/specs/design-plans/DP-905-missing/index.md"
assert_fail2 "existing-owner-missing" "$VALIDATOR" "$MISSING_OWNER"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-missing.out"

MISMATCH_OWNER="$TMP/mismatch-owner.json"
write_report_with_existing_owner "$MISMATCH_OWNER" "DP-999" \
  "docs-manager/src/content/docs/specs/design-plans/DP-904-existing/index.md"
assert_fail2 "existing-owner-mismatch" "$VALIDATOR" "$MISMATCH_OWNER"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-mismatch.out"

# ─── 6. NEG: unrelated, self, or archived sources cannot act as owners ───────
occupy_dp active "DP-907-unrelated"
link_owner_to_source "DP-907-unrelated" "DP-999"
UNRELATED_OWNER="$TMP/unrelated-owner.json"
write_report_with_existing_owner "$UNRELATED_OWNER" "DP-907" \
  "docs-manager/src/content/docs/specs/design-plans/DP-907-unrelated/index.md"
assert_fail2 "existing-owner-unrelated" "$VALIDATOR" "$UNRELATED_OWNER"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-unrelated.out"

occupy_dp active "DP-303-report-fixture"
link_owner_to_source "DP-303-report-fixture" "DP-303"
SELF_OWNER="$TMP/self-owner.json"
write_report_with_existing_owner "$SELF_OWNER" "DP-303" \
  "docs-manager/src/content/docs/specs/design-plans/DP-303-report-fixture/index.md"
assert_fail2 "existing-owner-self" "$VALIDATOR" "$SELF_OWNER"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-self.out"

occupy_dp archive "DP-908-archived"
python3 - "$ARCHIVE/DP-908-archived/refinement.json" <<'PY'
from pathlib import Path
Path(__import__("sys").argv[1]).write_text(
    '{"predecessor_audit":[{"spec_id":"DP-303","disposition":"KEEP"}]}\n',
    encoding="utf-8",
)
PY
ARCHIVED_OWNER="$TMP/archived-owner.json"
write_report_with_existing_owner "$ARCHIVED_OWNER" "DP-908" \
  "docs-manager/src/content/docs/specs/design-plans/archive/DP-908-archived/index.md"
assert_fail2 "existing-owner-archived" "$VALIDATOR" "$ARCHIVED_OWNER"
grep -q 'POLARIS_AUTO_PASS_REPORT_EXISTING_OWNER_INVALID' "$TMP/existing-owner-archived.out"

# ─── 7. NEG: fresh seed and existing owner are mutually exclusive ───────────
BOTH="$TMP/both-authorities.json"
write_report_with_existing_owner "$BOTH" "DP-904" \
  "docs-manager/src/content/docs/specs/design-plans/DP-904-existing/index.md"
python3 - "$BOTH" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["follow_up_dp_seed"] = {
    "path": "docs-manager/src/content/docs/specs/design-plans/DP-906-follow-up/index.md",
    "reason": "blocked_by_gate_failure",
    "source_report": str(p),
    "framework_gap": False,
}
p.write_text(json.dumps(d) + "\n", encoding="utf-8")
PY
assert_fail2 "both-authorities" "$VALIDATOR" "$BOTH"
grep -q 'POLARIS_AUTO_PASS_REPORT_FOLLOW_UP_AUTHORITY_CONFLICT' "$TMP/both-authorities.out"

# ─── 8. POS: complete report with no follow-up authority → no-op ─────────────
# verification.status=PASS needs a resolvable V task.md whose
# ac_verification.status is PASS. The pinned head is implementation evidence and
# must match the required T task's canonical deliverable.
python3 - "${DESIGN_PLANS}/DP-303-report-fixture/index.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(
    path.read_text(encoding="utf-8").replace("status: LOCKED", "status: IMPLEMENTED"),
    encoding="utf-8",
)
PY
mkdir -p "${DESIGN_PLANS}/DP-303-report-fixture/tasks/V1"
python3 - "${DESIGN_PLANS}/DP-303-report-fixture/tasks/V1/index.md" "$HEAD_SHA" <<'PY'
import sys
from pathlib import Path
path, head = sys.argv[1:3]
Path(path).write_text(
    "---\n"
    "task_kind: V\n"
    "work_item_id: DP-303-V1\n"
    "ac_verification:\n"
    "  status: PASS\n"
    "---\n\n"
    "# V1\n\n"
    "> Source: DP-303 | Task: DP-303-V1 | JIRA: N/A | Repo: polaris-framework\n",
    encoding="utf-8",
)
PY
mkdir -p "${DESIGN_PLANS}/DP-303-report-fixture/tasks/T1"
python3 - "${DESIGN_PLANS}/DP-303-report-fixture/tasks/T1/index.md" "$HEAD_SHA" <<'PY'
import sys
from pathlib import Path
path, head = sys.argv[1:3]
Path(path).write_text(
    "---\n"
    "task_kind: T\n"
    "work_item_id: DP-303-T1\n"
    "deliverable:\n"
    f"  head_sha: {head}\n"
    "---\n\n"
    "# T1\n\n"
    "> Source: DP-303 | Task: DP-303-T1 | JIRA: N/A | Repo: polaris-framework\n",
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
    "required_prs": [{"task_id": "DP-303-T1", "head_sha": "$HEAD_SHA"}],
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
