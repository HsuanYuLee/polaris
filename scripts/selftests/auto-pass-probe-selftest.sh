#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$ROOT/scripts/auto-pass-probe.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/validation-fail" \
  "$TMP/.polaris/evidence/missing-v-task" \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/blocked-conflict" \
  "$TMP/.polaris/evidence/unsupported-mutation" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/archive" \
  "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement-inbox" \
  "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-557"

# ─── DP-900 active fixture (DP source path coverage; pre-existing) ─────────────
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "auto-pass probe source fixture"
status: LOCKED
---

## Fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "auto-pass probe source fixture"
---

## Scope

fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-900"},
  "modules": [{"path": "scripts/auto-pass-probe.sh", "action": "modify"}],
  "acceptance_criteria": []
}
JSON

# ─── EXAMPLE-556 active fixture (JIRA Epic source for AC12 / AC13) ─────────────────
cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/index.md" <<'MD'
---
title: "EXAMPLE-556 fixture"
description: "auto-pass probe JIRA Epic source fixture"
status: LOCKED
---

## Fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement.md" <<'MD'
---
title: "EXAMPLE-556 refinement"
description: "auto-pass probe JIRA Epic refinement"
---

## Scope

fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement.json" <<'JSON'
{
  "source": {"type": "jira", "id": "EXAMPLE-556"},
  "modules": [{"path": "scripts/auto-pass-probe.sh", "action": "modify"}],
  "acceptance_criteria": []
}
JSON

# ─── EXAMPLE-557 active fixture (DISCUSSION status — should BLOCK) ─────────────────
cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-557/index.md" <<'MD'
---
title: "EXAMPLE-557 fixture"
description: "auto-pass probe JIRA Epic DISCUSSION fixture"
status: DISCUSSION
---

## Fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-557/refinement.md" <<'MD'
---
title: "EXAMPLE-557 refinement"
description: "auto-pass probe JIRA Epic refinement"
---

## Scope

fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-557/refinement.json" <<'JSON'
{
  "source": {"type": "jira", "id": "EXAMPLE-557"},
  "modules": [],
  "acceptance_criteria": []
}
JSON

# ─── DP-901 archived fixture (AC-NEG7: archived must BLOCK) ───────────────────
mkdir -p "$TMP/docs-manager/src/content/docs/specs/design-plans/archive/DP-901-archived"
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/archive/DP-901-archived/index.md" <<'MD'
---
title: "DP-901 archived"
description: "archived source fixture"
status: LOCKED
---

## Fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/archive/DP-901-archived/refinement.md" <<'MD'
---
title: "DP-901 refinement"
description: "archived refinement"
---

## Scope

archived
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/archive/DP-901-archived/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-901"},
  "modules": [],
  "acceptance_criteria": []
}
JSON

write_marker() {
  local path="$1"
  local kind="$2"
  local status="$3"
  python3 - "$path" "$kind" "$status" <<'PY'
import json
import sys
from pathlib import Path

path, kind, status = sys.argv[1:4]
payload = {
    "schema_version": 1,
    "marker_kind": kind,
    "writer": "selftest",
    "owning_skill": "selftest",
    "source_id": "DP-900",
    "work_item_id": "DP-900-T1",
    "status": status,
    "freshness": {"head_sha": "abc1234"},
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

probe_field() {
  local field="$1"
  shift
  "$PROBE" --repo "$TMP" "$@" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field'))"
}

assert_field() {
  local label="$1"
  local expected="$2"
  shift 2
  local actual
  actual="$(probe_field "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label expected $expected got $actual" >&2
    exit 1
  fi
}

# ─── breakdown stage (DP path, pre-existing) ──────────────────────────────────
write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" task_snapshot PASS
assert_field "breakdown-pass" "engineering" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "source-shorthand-pass" "breakdown" next_action DP-900

rm -f "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json"
write_marker "$TMP/.polaris/evidence/validation-fail/DP-900-T1.json" validation_fail FAIL
assert_field "breakdown-validation-fail" "blocked_by_gate_failure" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm -f "$TMP/.polaris/evidence/validation-fail/DP-900-T1.json"

# DP-212 amendment loop: refinement-inbox presence under DP container → ROUTE_BACK_AMEND
# (terminal_status null; next_action refinement_amendment)
touch "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs-refinement.md"
assert_field "breakdown-refinement-inbox-terminal" "None" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-refinement-inbox-next" "refinement_amendment" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm -f "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs-refinement.md"

# AC13: amendment-inbox scan is source-neutral — JIRA Epic refinement-inbox/*.md
# also triggers ROUTE_BACK_AMEND, not UNKNOWN.
touch "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement-inbox/needs-refinement.md"
write_marker "$TMP/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" task_snapshot PASS
# Override source/work_item ids in the snapshot to match EXAMPLE-556-T1.
python3 - "$TMP/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["source_id"] = "EXAMPLE-556"
d["work_item_id"] = "EXAMPLE-556-T1"
p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
PY
assert_field "breakdown-amendment-jira" "refinement_amendment" next_action --stage breakdown --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-T1
rm -f "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement-inbox/needs-refinement.md"
rm -f "$TMP/.polaris/evidence/task-snapshot/EXAMPLE-556-T1.json"

assert_field "breakdown-unknown" "blocked_by_gate_failure" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

# ─── source stage (DP path, pre-existing) ─────────────────────────────────────
cp "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.locked.md"
python3 - "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace("status: LOCKED", "status: DISCUSSION"), encoding="utf-8")
PY
assert_field "source-discussion-blocked" "blocked_by_gate_failure" terminal_status DP-900
mv "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.locked.md" "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md"

# ─── source stage (AC12: JIRA Epic resolved via resolver — not UNKNOWN) ───────
# LOCKED Epic should PASS the source stage.
assert_field "source-jira-locked-status" "PASS" status --stage source --source-id EXAMPLE-556 --work-item-id EXAMPLE-556
assert_field "source-jira-locked-next" "breakdown" next_action --stage source --source-id EXAMPLE-556 --work-item-id EXAMPLE-556

# DISCUSSION Epic should BLOCK (not UNKNOWN).
assert_field "source-jira-discussion" "blocked_by_gate_failure" terminal_status --stage source --source-id EXAMPLE-557 --work-item-id EXAMPLE-557

# Missing JIRA key → resolver POLARIS_SOURCE_MISSING → BLOCKED (not UNKNOWN).
assert_field "source-jira-missing" "BLOCKED" status --stage source --source-id EXAMPLE-999 --work-item-id EXAMPLE-999

# ─── source stage (AC-NEG7: archived must BLOCK) ─────────────────────────────
assert_field "source-archived-blocked" "BLOCKED" status --stage source --source-id DP-901 --work-item-id DP-901

# ─── engineering stage (pre-existing) ─────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json" completion_gate PASS
assert_field "engineering-pass" "verify-AC" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json"

write_marker "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json" blocked_conflict BLOCKED
assert_field "engineering-blocked-conflict" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json"

# ─── verify-AC stage ─────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification PASS
assert_field "verify-pass" "complete" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

# DP-212 amendment loop: spec-issue marker → ROUTE_BACK_AMEND, terminal null.
write_marker "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json" spec_issue ROUTE_BACK
assert_field "verify-spec-issue-terminal" "None" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-spec-issue-next" "refinement_amendment" next_action --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json"

write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification MANUAL_REQUIRED
assert_field "verify-manual" "paused_for_user_external_write" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

assert_field "verify-unknown" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

LEDGER="$TMP/ledger.json"
python3 - "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "loop_counters": {"engineering_to_breakdown": 3, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {"DP-900-V1": 0},
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
assert_field "loop-cap" "loop_cap_reached" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 --ledger "$LEDGER"

python3 - "$LEDGER" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "loop_counters": {"engineering_to_breakdown": 0, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {"DP-900-V1": 3},
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY
assert_field "drift-cap" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234 --ledger "$LEDGER"

# ─── DP-237 T1: probe machine-field stability ─────────────────────────────────
# The auto-pass runner depends on probe emitting a stable shape: every probe
# invocation must produce JSON with these load-bearing fields, regardless of
# stage or outcome. AC-NEG3: when inputs are missing the probe must emit
# UNKNOWN (machine field) — it must not read prose to PASS.
mkdir -p \
  "$TMP/.polaris/evidence/dp237-stability-task-snapshot" \
  "$TMP/.polaris/evidence/dp237-stability-completion-gate"

stability_check() {
  local label="$1"; shift
  local out
  out="$("$PROBE" --repo "$TMP" "$@" 2>/dev/null)"
  python3 - "$label" "$out" <<'PY'
import json, sys
label, raw = sys.argv[1:3]
try:
    d = json.loads(raw)
except Exception as exc:
    print(f"FAIL: {label} probe output not JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)
required = ("schema_version", "stage", "source_id", "work_item_id", "status",
            "terminal_status", "next_action", "evidence_path", "reason")
missing = [k for k in required if k not in d]
if missing:
    print(f"FAIL: {label} probe output missing fields {missing}", file=sys.stderr)
    print(raw, file=sys.stderr)
    raise SystemExit(1)
if d.get("schema_version") != 1:
    print(f"FAIL: {label} probe schema_version != 1", file=sys.stderr)
    raise SystemExit(1)
PY
}

# (1) PASS shape: stable fields present.
write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" task_snapshot PASS
stability_check "stability-breakdown-pass" --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm -f "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json"

# (2) AC-NEG3: missing marker — probe must emit UNKNOWN, not PASS, even
# though the source fixture's index.md / refinement.md contain the literal
# word "PASS" in prose. We verify this with the existing DP-900 fixture
# (its prose does not contain PASS, so add a temporary file that does to
# prove probe does not crawl it).
echo "PASS PASS PASS — this prose should never influence probe outcome" \
  > "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/prose-decoy.md"
ac_neg3_out="$("$PROBE" --repo "$TMP" --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 2>/dev/null)"
echo "$ac_neg3_out" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('status')=='UNKNOWN' and d.get('terminal_status')=='blocked_by_gate_failure' else 1)" || {
  echo "FAIL: AC-NEG3 probe returned PASS despite missing marker (prose decoy attack)" >&2
  echo "$ac_neg3_out" >&2
  exit 1
}
rm -f "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/prose-decoy.md"

# (3) Engineering PASS marker stability.
write_marker "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json" completion_gate PASS
stability_check "stability-engineering-pass" --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json"

echo "PASS: auto-pass probe selftest"
