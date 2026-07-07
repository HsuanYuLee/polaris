#!/usr/bin/env bash
# Purpose: Selftest for scripts/auto-pass-probe.sh — drives the auto-pass stage
#          probe across task-snapshot / validation-fail / missing-v-task evidence
#          fixtures and asserts the emitted stage decisions.
# Inputs:  none (builds hermetic fixtures under a mktemp dir)
# Outputs: stdout PASS/FAIL lines; exit 0 on PASS, non-zero on failure
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

# DP-360 T7: engineering/verify-AC stages now read the canonical task.md
# `deliverable` block (deliverable.head_sha + deliverable.verification.status)
# resolved by work_item_id — no head-sha-keyed completion-gate / ac-verification
# markers. write_task_deliverable scaffolds a real tasks/<Tn>/index.md so
# resolve-task-md.sh can locate it.
#   $1 = work_item_id (e.g. DP-900-T1, DP-900-V1)
#   $2 = delivered head_sha (empty string to omit the deliverable block entirely)
#   $3 = verification status (empty string to omit the verification sub-block)
write_task_deliverable() {
  local wid="$1"
  local head="$2"
  local vstatus="$3"
  local task_id="${wid##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$wid fixture\""
    echo "description: \"auto-pass probe task.md deliverable fixture\""
    echo "status: IN_PROGRESS"
    if [[ -n "$head" ]]; then
      echo "deliverable:"
      echo "  head_sha: $head"
      if [[ -n "$vstatus" ]]; then
        echo "  verification:"
        echo "    status: $vstatus"
      fi
    fi
    echo "---"
    echo ""
    echo "## Fixture"
  } >"$task_dir/index.md"
}

write_jira_task_deliverable() {
  local wid="$1"
  local head="$2"
  local vstatus="$3"
  local source_id="${wid%-*}"
  local task_id="${wid##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/companies/exampleco/$source_id/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$wid fixture\""
    echo "description: \"auto-pass probe JIRA Epic task.md deliverable fixture\""
    echo "status: IN_PROGRESS"
    echo "task_kind: T"
    echo "work_item_id: $wid"
    if [[ -n "$head" ]]; then
      echo "deliverable:"
      echo "  head_sha: $head"
      if [[ -n "$vstatus" ]]; then
        echo "  verification:"
        echo "    status: $vstatus"
      fi
    fi
    echo "---"
    echo ""
    echo "# $wid"
    echo ""
    echo "> Source: $source_id | Task: $wid | JIRA: $wid | Repo: polaris-framework"
  } >"$task_dir/index.md"
}

remove_task_deliverable() {
  local wid="$1"
  local task_id="${wid##*-}"
  local source_id="${wid%-*}"
  if [[ "$source_id" == DP-* ]]; then
    rm -rf "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  else
    rm -rf "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/$source_id/tasks/$task_id"
    rm -rf "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/$source_id/tasks/pr-release/$task_id"
  fi
}

# DP-360 T7: the verify-AC stage reads the V-task `ac_verification` frontmatter
# block (the canonical V-task lifecycle record), NOT a head-keyed marker and NOT
# a deliverable block. write_v_task_ac scaffolds tasks/<Vn>/index.md with it.
#   $1 = work_item_id (e.g. DP-900-V1)
#   $2 = ac_verification status (empty string omits the block entirely)
write_v_task_ac() {
  local wid="$1"
  local vstatus="$2"
  local task_id="${wid##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$wid fixture\""
    echo "description: \"auto-pass probe V-task ac_verification fixture\""
    echo "status: IN_PROGRESS"
    echo "task_kind: V"
    if [[ -n "$vstatus" ]]; then
      echo "ac_verification:"
      echo "  status: $vstatus"
    fi
    echo "---"
    echo ""
    echo "## Fixture"
  } >"$task_dir/index.md"
}

write_jira_v_task_ac() {
  local wid="$1"
  local vstatus="$2"
  local source_id="${wid%-*}"
  local task_id="${wid##*-}"
  local task_dir="$TMP/docs-manager/src/content/docs/specs/companies/exampleco/$source_id/tasks/pr-release/$task_id"
  mkdir -p "$task_dir"
  {
    echo "---"
    echo "title: \"$wid fixture\""
    echo "description: \"auto-pass probe JIRA Epic V-task ac_verification fixture\""
    echo "status: IN_PROGRESS"
    echo "task_kind: V"
    echo "work_item_id: $wid"
    if [[ -n "$vstatus" ]]; then
      echo "ac_verification:"
      echo "  status: $vstatus"
    fi
    echo "---"
    echo ""
    echo "# $wid"
    echo ""
    echo "> Source: $source_id | Task: $wid | JIRA: $wid | Repo: polaris-framework"
  } >"$task_dir/index.md"
}

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

write_pr_ownership_state() {
  local path="$1"
  local draft="$2"
  local publisher="$3"
  local freshness="$4"
  python3 - "$path" "$draft" "$publisher" "$freshness" <<'PY'
import json
import sys
from pathlib import Path

path, draft, publisher, freshness = sys.argv[1:5]
payload = {
    "pr_state": "OPEN",
    "readiness_state": "mergeable_ready",
    "pr_url": "https://github.com/org/repo/pull/900",
    "isDraft": draft == "true",
    "publisher": publisher,
    "engineering_completion_marker": True,
    "base_freshness": freshness,
}
Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
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

# ─── engineering stage (DP-360 T7: task.md deliverable block) ─────────────────
# AC3: no marker; task.md deliverable.head_sha bound to probe head + PASS → verify-AC.
write_task_deliverable DP-900-T1 abc1234 PASS
assert_field "engineering-pass" "verify-AC" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234

# AC12/AC13 extension: JIRA Epic composite work item ids must resolve through
# the same task.md delivery reader as DP composite ids.
write_jira_task_deliverable EXAMPLE-556-T1 abc1234 PASS
assert_field "engineering-jira-composite-pass" "verify-AC" next_action --stage engineering --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-T1 --head-sha abc1234
remove_task_deliverable EXAMPLE-556-T1

# DP-231 T7: when the explicit PR state carries auto-pass ownership payload,
# engineering PASS must first consume the shared ownership/non-draft gate before
# continuing to verify-AC.
write_pr_ownership_state "$TMP/pr-ownership-pass.json" false polaris-pr-create.sh fresh
assert_field "engineering-pr-ownership-pass" "verify-AC" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/pr-ownership-pass.json"

write_pr_ownership_state "$TMP/pr-ownership-draft.json" true polaris-pr-create.sh fresh
assert_field "engineering-pr-ownership-draft-blocks" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/pr-ownership-draft.json"

write_pr_ownership_state "$TMP/pr-ownership-generic.json" false generic-github-publisher fresh
assert_field "engineering-pr-ownership-generic-blocks" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234 --pr-state-file "$TMP/pr-ownership-generic.json"

# AC-NEG1: a polluting branch ref must NOT rescue — head mismatch in task.md
# blocks even though the work item would be deliverable at a different head.
git -C "$TMP" init -q 2>/dev/null || true
git -C "$TMP" update-ref "refs/heads/task/DP-900-T1-abc1234" HEAD 2>/dev/null || true
assert_field "engineering-head-mismatch-blocks" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha deadbee
git -C "$TMP" update-ref -d "refs/heads/task/DP-900-T1-abc1234" 2>/dev/null || true

# AC-NEG2: a stray completion-gate marker at the probe head must be IGNORED —
# the deliverable block (here non-PASS) is the sole authority.
write_task_deliverable DP-900-T1 abc1234 IN_PROGRESS
write_marker "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json" completion_gate PASS
assert_field "engineering-stray-marker-ignored" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json"
remove_task_deliverable DP-900-T1

# Latent reader guard (DP-325): blocked-conflict marker still blocks.
write_task_deliverable DP-900-T1 abc1234 PASS
write_marker "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json" blocked_conflict BLOCKED
assert_field "engineering-blocked-conflict" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/blocked-conflict/DP-900-T1-abc1234.json"
remove_task_deliverable DP-900-T1

# AC3: missing deliverable block entirely → blocked (task.md exists, no head).
write_task_deliverable DP-900-T1 "" ""
assert_field "engineering-no-deliverable-blocks" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
remove_task_deliverable DP-900-T1

# ─── verify-AC stage (DP-360 T7: V-task ac_verification frontmatter block) ─────
# AC3: no marker; V-task ac_verification.status=PASS → complete.
write_v_task_ac DP-900-V1 PASS
assert_field "verify-pass" "complete" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

write_jira_v_task_ac EXAMPLE-556-V1 PASS
assert_field "verify-jira-composite-pass" "complete" terminal_status --stage verify-AC --source-id EXAMPLE-556 --work-item-id EXAMPLE-556-V1 --head-sha abc1234
remove_task_deliverable EXAMPLE-556-V1

# AC-NEG2: a stray PASS ac-verification marker must be IGNORED — the V-task
# ac_verification block (here FAIL) is the sole authority and still blocks.
write_v_task_ac DP-900-V1 FAIL
write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification PASS
assert_field "verify-stray-marker-ignored" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

# DP-212 amendment loop: spec-issue marker (distinct, NOT torn down) →
# ROUTE_BACK_AMEND, terminal null. Read BEFORE the ac_verification block.
write_v_task_ac DP-900-V1 PASS
write_marker "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json" spec_issue ROUTE_BACK
assert_field "verify-spec-issue-terminal" "None" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-spec-issue-next" "refinement_amendment" next_action --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm -f "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json"

# Verification disposition MANUAL_REQUIRED → paused_for_user_external_write.
write_v_task_ac DP-900-V1 MANUAL_REQUIRED
assert_field "verify-manual" "paused_for_user_external_write" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

# Missing ac_verification block → blocked (V-task present, no status).
write_v_task_ac DP-900-V1 ""
assert_field "verify-no-status-blocks" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
remove_task_deliverable DP-900-V1

# Missing task.md entirely → blocked (no V-task authority).
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

# (3) Engineering PASS stability (DP-360 T7: task.md deliverable block).
write_task_deliverable DP-900-T1 abc1234 PASS
stability_check "stability-engineering-pass" --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
remove_task_deliverable DP-900-T1

echo "PASS: auto-pass probe selftest"
