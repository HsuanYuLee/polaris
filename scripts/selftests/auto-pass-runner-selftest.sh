#!/usr/bin/env bash
# DP-237 T1: auto-pass-runner selftest
#
# Shadow fixture alignment: build synthetic fixtures for each stage and assert
# the runner's stable JSON contract. Covers:
# - AC2: stable JSON next_action across stages
# - AC4: runner-probe semantic parity (also covered by the parity selftest)
# - AC-NEG3: missing marker WITH "PASS" prose still emits blocked_by_gate_failure
# - AC-NEG4: JIRA consent fixtures cover marker missing/denied/granted/fallback-TTL
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/auto-pass-runner.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox" \
  "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556"

# ─── DP-900 active fixture (locked + valid refinement) ────────────────────────
cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/index.md" <<'MD'
---
title: "DP-900 fixture"
description: "runner selftest source fixture — pretend this prose says PASS everywhere; runner must ignore"
status: LOCKED
---

## Fixture body — contains the word PASS to verify the runner ignores prose.
PASS PASS PASS — only machine fields count.
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.md" <<'MD'
---
title: "DP-900 refinement"
description: "runner selftest refinement"
---

## Scope

fixture — also contains the word PASS to bait prose readers.
MD

cat >"$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement.json" <<'JSON'
{
  "source": {"type": "dp", "id": "DP-900"},
  "modules": [{"path": "scripts/auto-pass-runner.sh", "action": "modify"}],
  "acceptance_criteria": []
}
JSON

# ─── EXAMPLE-556 JIRA Epic fixture ────────────────────────────────────────────
cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/index.md" <<'MD'
---
title: "EXAMPLE-556 fixture"
description: "JIRA Epic fixture"
status: LOCKED
---

## Fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement.md" <<'MD'
---
title: "EXAMPLE-556 refinement"
description: "JIRA Epic refinement"
---

## Scope

fixture
MD

cat >"$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556/refinement.json" <<'JSON'
{
  "source": {"type": "jira", "id": "EXAMPLE-556"},
  "modules": [],
  "acceptance_criteria": []
}
JSON

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────
write_marker() {
  local path="$1" kind="$2" status="$3" source_id="${4:-DP-900}" work_item_id="${5:-DP-900-T1}"
  python3 - "$path" "$kind" "$status" "$source_id" "$work_item_id" <<'PY'
import json, sys
from pathlib import Path
path, kind, status, source_id, work_item_id = sys.argv[1:6]
payload = {
    "schema_version": 1,
    "marker_kind": kind,
    "writer": "selftest",
    "owning_skill": "selftest",
    "source_id": source_id,
    "work_item_id": work_item_id,
    "status": status,
    "freshness": {"head_sha": "abc1234"},
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

run_runner() {
  bash "$RUNNER" --repo "$TMP" "$@"
}

field() {
  local field="$1"; shift
  run_runner "$@" | python3 -c "import json,sys; v=json.load(sys.stdin).get('$field'); print('null' if v is None else v)"
}

assert_field() {
  local label="$1" expected="$2"; shift 2
  local actual
  actual="$(field "$@")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $label expected '$expected' got '$actual'" >&2
    echo "  args: $*" >&2
    run_runner "$@" >&2 || true
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# source stage fixtures
# ──────────────────────────────────────────────────────────────────────────────
# (1) locked refinement → PASS, dispatch breakdown
assert_field "source-pass-status"     "PASS"      status      --stage source --source-id DP-900
assert_field "source-pass-next"       "dispatch"  next_action --stage source --source-id DP-900
assert_field "source-pass-skill"      "breakdown" next_skill  --stage source --source-id DP-900
assert_field "source-pass-terminal"   "null"      terminal_status --stage source --source-id DP-900

# Shorthand positional form must equal explicit stage=source.
assert_field "source-shorthand"       "dispatch"  next_action DP-900

# (2) JIRA Epic locked → PASS
assert_field "jira-source-pass-status" "PASS"      status      --stage source --source-id EXAMPLE-556
assert_field "jira-source-pass-next"   "dispatch"  next_action --stage source --source-id EXAMPLE-556

# (3) Missing source → blocked
assert_field "missing-source-status"  "BLOCKED"   status         --stage source --source-id EXAMPLE-999
assert_field "missing-source-terminal" "blocked_by_gate_failure" terminal_status --stage source --source-id EXAMPLE-999
assert_field "missing-source-action"  "blocked"   next_action    --stage source --source-id EXAMPLE-999

# ──────────────────────────────────────────────────────────────────────────────
# breakdown stage fixtures
# ──────────────────────────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json" task_snapshot PASS
assert_field "breakdown-pass-status" "PASS"        status      --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-pass-action" "dispatch"    next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-pass-skill"  "engineering" next_skill  --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-pass-wi"     "DP-900-T1"   next_work_item_id --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm "$TMP/.polaris/evidence/task-snapshot/DP-900-T1.json"

# AC-NEG3: missing breakdown marker WITH "PASS" prose in spec must remain blocked.
# (DP-900 index.md / refinement.md already contain the literal word PASS above.)
assert_field "breakdown-missing-terminal" "blocked_by_gate_failure" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-missing-action"   "blocked" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-missing-skill"    "null"    next_skill  --stage breakdown --source-id DP-900 --work-item-id DP-900-T1

# refinement-inbox presence → non-terminal refinement_amendment loop.
touch "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs.md"
assert_field "breakdown-amend-status"   "ROUTE_BACK_AMEND" status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-amend-action"   "refinement_amendment" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-amend-skill"    "refinement" next_skill --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
assert_field "breakdown-amend-terminal" "null" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1
rm "$TMP/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/refinement-inbox/needs.md"

# ──────────────────────────────────────────────────────────────────────────────
# engineering stage fixtures
# ──────────────────────────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json" completion_gate PASS
assert_field "engineering-pass-status" "PASS" status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
assert_field "engineering-pass-action" "dispatch" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
assert_field "engineering-pass-skill"  "verify-AC" next_skill --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
rm "$TMP/.polaris/evidence/completion-gate/DP-900-T1-abc1234.json"

# Missing completion marker → blocked.
assert_field "engineering-missing-terminal" "blocked_by_gate_failure" terminal_status --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234
assert_field "engineering-missing-action"   "blocked" next_action --stage engineering --source-id DP-900 --work-item-id DP-900-T1 --head-sha abc1234

# ──────────────────────────────────────────────────────────────────────────────
# verify-AC stage fixtures
# ──────────────────────────────────────────────────────────────────────────────
write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification PASS DP-900 DP-900-V1
assert_field "verify-pass-status"   "PASS" status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-pass-action"   "terminal" next_action --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-pass-terminal" "complete" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-pass-skill"    "null" next_skill --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

# MANUAL_REQUIRED → paused for user external write
write_marker "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json" ac_verification MANUAL_REQUIRED DP-900 DP-900-V1
assert_field "verify-manual-terminal" "paused_for_user_external_write" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-manual-action"   "terminal" next_action --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm "$TMP/.polaris/evidence/ac-verification/DP-900-V1-abc1234.json"

# UNKNOWN / missing → blocked
assert_field "verify-unknown-terminal" "blocked_by_gate_failure" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234

# spec-issue → non-terminal refinement_amendment loop
write_marker "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json" spec_issue ROUTE_BACK DP-900 DP-900-V1
assert_field "verify-spec-issue-action"   "refinement_amendment" next_action --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
assert_field "verify-spec-issue-terminal" "null" terminal_status --stage verify-AC --source-id DP-900 --work-item-id DP-900-V1 --head-sha abc1234
rm "$TMP/.polaris/evidence/ac-verification/spec-issue-DP-900-V1-abc1234.json"

# ──────────────────────────────────────────────────────────────────────────────
# Loop cap fixture (via ledger)
# ──────────────────────────────────────────────────────────────────────────────
LEDGER="$TMP/loop-cap-ledger.json"
python3 - "$LEDGER" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    "loop_counters": {"engineering_to_breakdown": 4, "breakdown_to_refinement_inbox": 0},
    "drift_retry": {},
}) + "\n", encoding="utf-8")
PY
assert_field "loop-cap-terminal" "loop_cap_reached" terminal_status --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 --ledger "$LEDGER"
assert_field "loop-cap-action"   "terminal" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T1 --ledger "$LEDGER"

# ──────────────────────────────────────────────────────────────────────────────
# session_handoff resume fixture
# ──────────────────────────────────────────────────────────────────────────────
RESUME_LEDGER="$TMP/resume-ledger.json"
RESUME_ARTIFACT="$TMP/resume.json"
echo '{"resume":"ok"}' > "$RESUME_ARTIFACT"
python3 - "$RESUME_LEDGER" "$RESUME_ARTIFACT" <<'PY'
import json, sys
from pathlib import Path
ledger, artifact = sys.argv[1:3]
Path(ledger).write_text(json.dumps({
    "schema_version": "1",
    "source": {"type": "dp", "id": "DP-900"},
    "pause": {
        "kind": "session_handoff",
        "reason": "session pressure",
        "created_at": "2026-05-01T00:00:00+08:00",
        "resume_artifact": artifact,
        "next_work_item_id": "DP-900-T2",
    },
    "loop_counters": {"engineering_to_breakdown": 0, "breakdown_to_refinement_inbox": 0},
}) + "\n", encoding="utf-8")
PY
# With session_handoff pause, the runner must emit next_action=resume even when
# the underlying probe would have returned a stage status. This guards
# auto-pass-orchestrator-premature-stop: when sidecar is ready to continue,
# do not pause.
assert_field "resume-action" "resume" next_action --stage breakdown --source-id DP-900 --work-item-id DP-900-T2 --ledger "$RESUME_LEDGER"
assert_field "resume-evidence" "$RESUME_ARTIFACT" evidence_path --stage breakdown --source-id DP-900 --work-item-id DP-900-T2 --ledger "$RESUME_LEDGER"
assert_field "resume-wi" "DP-900-T2" next_work_item_id --stage breakdown --source-id DP-900 --work-item-id DP-900-T2 --ledger "$RESUME_LEDGER"

# ──────────────────────────────────────────────────────────────────────────────
# AC-NEG4: JIRA consent fixtures — marker missing / denied / granted /
# fallback-TTL. The runner does NOT expand consent (validation is delegated
# to validate-auto-pass-ledger.sh). The runner's job is to not synthesize
# consent and to never grant on absence.
#
# Strategy: build four ledger variants and use ledger validator directly to
# verify the surface (ledger validator owns this contract). The runner-side
# check is that on a JIRA source where the ledger is malformed (e.g. missing
# jira_status_consent_record), the runner does not silently PASS — it relies
# on the probe / external validator to gate. We assert the runner output
# remains the probe-derived stage state and never marks consent as granted
# in its own JSON.
# ──────────────────────────────────────────────────────────────────────────────
LEDGER_VALIDATOR="$ROOT/scripts/validate-auto-pass-ledger.sh"

make_jira_ledger() {
  local out="$1" mode="$2"
  python3 - "$out" "$mode" "$TMP" <<'PY'
import json, sys
from pathlib import Path
out, mode, tmp = sys.argv[1:4]
container = f"{tmp}/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556"
# Compute hash matching refinement_hash() in validate-auto-pass-ledger
import hashlib
digest = hashlib.sha256()
for name in ("refinement.md", "refinement.json"):
    digest.update(name.encode("utf-8")); digest.update(b"\0")
    digest.update(Path(f"{container}/{name}").read_bytes()); digest.update(b"\0")
ref_hash = "sha256:" + digest.hexdigest()

base = {
    "schema_version": "1",
    "source": {"type": "jira", "id": "EXAMPLE-556", "container": container, "refinement_hash": ref_hash},
    "started_at": "2026-05-01T00:00:00+08:00",
    "consent_policy": {
        "auto_reestimate": True,
        "auto_resplit": True,
        "auto_task_repair": True,
        "jira_status_transition": True,
    },
    "consent_excludes": [
        "base_branch_force_push",
        "force_push_without_lease",
        "history_rewrite",
        "merge",
        "release",
        "deploy",
        "production_write",
        "jira_child_write",
        "jira_comment_write",
        "jira_worklog_write",
        "task_scope_outside_mutation",
    ],
    "loop_counters": {"engineering_to_breakdown": 0, "breakdown_to_refinement_inbox": 0},
    "jira_status_consent_record": {
        "session_id": "selftest",
        "source_id": "EXAMPLE-556",
        "granted_at": "2026-05-01T00:00:00+08:00",
        "ttl_seconds": 3600,
    },
}

if mode == "granted":
    pass
elif mode == "missing":
    # JIRA source must declare jira_status_consent_record; drop it.
    del base["jira_status_consent_record"]
elif mode == "denied":
    # Flag jira_status_transition false to model an explicit denial.
    base["consent_policy"]["jira_status_transition"] = False
elif mode == "fallback_ttl":
    # ttl_seconds = 1 second; record is present but the TTL window is short.
    # Validator must still accept the structural shape; the orchestrator (not
    # the runner) is the layer that re-confirms within the window.
    base["jira_status_consent_record"]["ttl_seconds"] = 1
else:
    raise SystemExit(f"unknown mode {mode}")

Path(out).write_text(json.dumps(base) + "\n", encoding="utf-8")
PY
}

# Each consent variant: assert that ledger validator behaves as expected
# (granted / fallback_ttl PASS; missing / denied FAIL) AND that the runner
# does not synthesize a grant in its own JSON.
for variant in granted missing denied fallback_ttl; do
  LDG="$TMP/jira-consent-${variant}.json"
  make_jira_ledger "$LDG" "$variant"

  set +e
  "$LEDGER_VALIDATOR" "$LDG" --source-container "$TMP/docs-manager/src/content/docs/specs/companies/exampleco/EXAMPLE-556" --source-id EXAMPLE-556 >"$TMP/ldg.out" 2>&1
  LDG_RC=$?
  set -e

  case "$variant" in
    granted|fallback_ttl)
      if [[ $LDG_RC -ne 0 ]]; then
        echo "FAIL: jira-consent-$variant ledger validator unexpectedly failed (rc=$LDG_RC)" >&2
        cat "$TMP/ldg.out" >&2
        exit 1
      fi
      ;;
    missing|denied)
      if [[ $LDG_RC -eq 0 ]]; then
        echo "FAIL: jira-consent-$variant ledger validator unexpectedly passed" >&2
        exit 1
      fi
      ;;
  esac

  # Runner-side: for the JIRA Epic at source stage, the runner reads the probe
  # output (which does not invent consent). We assert the runner's JSON does
  # not contain a key claiming consent was granted by the runner itself.
  RUNNER_OUT="$(run_runner --stage source --source-id EXAMPLE-556 --ledger "$LDG" 2>/dev/null || true)"
  if echo "$RUNNER_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'consent_granted_by_runner' not in d else 1)"; then
    :
  else
    echo "FAIL: jira-consent-$variant runner output unexpectedly invented consent_granted_by_runner field" >&2
    echo "$RUNNER_OUT" >&2
    exit 1
  fi
done

# ──────────────────────────────────────────────────────────────────────────────
# DP-237 T3 — Runner-first execution flow switch
#
# AC2: runner-first stable JSON contract — orchestrator must be able to read
#      next_action / next_skill / terminal_status as the *primary* state source,
#      without re-running auto-pass-probe or re-deriving from ledger.
# AC4: runner-probe parity — covered in detail by
#      auto-pass-runner-probe-parity-selftest.sh; here we sanity-check that
#      runner output preserves every field the orchestrator consumes (no probe
#      re-read needed).
# AC-NF2: runner authority is portable, not Claude-only — the runner script
#         must not depend on Claude Code hooks, Claude-only env vars, or any
#         claude.ai MCP server. Codex / other LLMs invoke the same script.
# AC-NF3: runner selftest finishes in seconds — guarded by a wall-clock
#         assertion below.
# AC-NEG2: runner does not write task.md / refinement.md, mutate code, judge
#          AC PASS/FAIL, or execute merge / release / deploy / production
#          writes. Enforced by static scan of the runner script.
# AC-NEG3: missing / UNKNOWN markers stay blocked even when surrounding spec
#          prose contains the word "PASS". Already covered in earlier section;
#          we add a runner-first companion that checks the runner does NOT
#          read inner-skill final answer text to escalate status.
# ──────────────────────────────────────────────────────────────────────────────

# ─── AC2 / AC4: runner-first dispatch payload completeness ───────────────────
# When breakdown PASS, orchestrator must receive every dispatch field from the
# runner alone — source_id, stage, status, next_action, next_skill,
# next_work_item_id, schema_version. No probe re-read needed.
write_marker "$TMP/.polaris/evidence/task-snapshot/DP-900-T2.json" task_snapshot PASS DP-900 DP-900-T2
RUNNER_DISPATCH_JSON="$(run_runner --stage breakdown --source-id DP-900 --work-item-id DP-900-T2 2>/dev/null)"
python3 - "$RUNNER_DISPATCH_JSON" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
required = {
    "schema_version",
    "source_id",
    "stage",
    "status",
    "terminal_status",
    "next_action",
    "next_skill",
    "next_work_item_id",
    "evidence_path",
    "reason",
}
missing = required - set(data.keys())
if missing:
    print(f"FAIL: runner-first dispatch JSON missing fields: {sorted(missing)}", file=sys.stderr)
    raise SystemExit(1)
if data["schema_version"] != 1:
    print(f"FAIL: schema_version must be 1, got {data['schema_version']}", file=sys.stderr)
    raise SystemExit(1)
if data["next_action"] != "dispatch":
    print(f"FAIL: expected next_action=dispatch, got {data['next_action']}", file=sys.stderr)
    raise SystemExit(1)
if data["next_skill"] != "engineering":
    print(f"FAIL: expected next_skill=engineering, got {data['next_skill']}", file=sys.stderr)
    raise SystemExit(1)
PY
rm "$TMP/.polaris/evidence/task-snapshot/DP-900-T2.json"

# ─── AC-NF2: runner authority is portable ────────────────────────────────────
# The runner script must not reference Claude-only surfaces. Codex / other LLMs
# invoke the same script through the same JSON contract.
python3 - "$RUNNER" <<'PY'
import re, sys
from pathlib import Path
src = Path(sys.argv[1]).read_text(encoding="utf-8")
forbidden = [
    "CLAUDE_CODE",                  # Claude-only env signal
    "claude.ai/mcp",                # MCP server URL
    ".claude/hooks/",               # Claude-only hook callsite
    "anthropic-",                   # Anthropic-specific identifiers
]
for token in forbidden:
    if token in src:
        print(f"FAIL: AC-NF2 runner references Claude-only surface '{token}'", file=sys.stderr)
        raise SystemExit(1)
PY

# ─── AC-NEG2: runner does not mutate code / task / release ───────────────────
# Static scan: runner must not call merge / push / deploy / release / writer
# helpers that mutate authoritative artifacts. The runner is a pure JSON
# aggregator over probe + ledger validator.
python3 - "$RUNNER" <<'PY'
import re, sys
from pathlib import Path
src = Path(sys.argv[1]).read_text(encoding="utf-8")
# Tokens that would indicate the runner is doing mutation work.
forbidden_patterns = [
    r"\bgh pr merge\b",
    r"\bgit push\b",
    r"\bnpm publish\b",
    r"\bpnpm publish\b",
    r"\bdocker push\b",
    r"\bkubectl apply\b",
    r"sync-to-polaris\.sh",
    r"write-producer-owned-artifact\.sh",  # runner does not write evidence
    # mark-spec-implemented.sh moved to the DP-311 declared-exception check
    # below; it is no longer a blanket-forbidden token.
    r"polaris-pr-create\.sh",              # PR creation is engineering's job
]
for pattern in forbidden_patterns:
    if re.search(pattern, src):
        print(f"FAIL: AC-NEG2 runner contains forbidden mutation '{pattern}'", file=sys.stderr)
        raise SystemExit(1)
# DP-311 declared exception (Terminal Complete Sequence, escalation T1-1):
# before declaring terminal_status=complete the runner advances required V
# work items through the existing canonical task-level writer
# scripts/mark-spec-implemented.sh. The DP-237 blanket ban on that token is
# superseded for this single declared writer path only — the guard intent
# stays: the token may appear in comments plus exactly ONE writer-path
# assignment (mark_spec = scripts_dir / "mark-spec-implemented.sh") inside
# terminal_complete_v_gate; any other code reference is still a violation.
dp311_allowed_assignment = re.compile(
    r'^\s*mark_spec\s*=\s*scripts_dir\s*/\s*"mark-spec-implemented\.sh"\s*$'
)
mark_spec_code_lines = [
    line for line in src.splitlines()
    if "mark-spec-implemented.sh" in line and not line.lstrip().startswith("#")
]
if len(mark_spec_code_lines) != 1 or not dp311_allowed_assignment.match(mark_spec_code_lines[0]):
    print(
        "FAIL: AC-NEG2 mark-spec-implemented.sh may only appear as the single "
        "DP-311 Terminal Complete Sequence writer-path assignment; found: "
        f"{mark_spec_code_lines!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
# Also forbid direct writes to task.md / refinement.md / refinement.json.
forbidden_writes = [
    r"task\.md.*>\s*['\"]?",
    r"refinement\.md.*>\s*['\"]?",
    r"refinement\.json.*>\s*['\"]?",
]
for pattern in forbidden_writes:
    if re.search(pattern, src, flags=re.MULTILINE):
        print(f"FAIL: AC-NEG2 runner appears to write authoritative artifact: {pattern}", file=sys.stderr)
        raise SystemExit(1)
PY

# ─── AC-NEG3 (runner-first companion): inner-skill prose ignored ─────────────
# DP-900 fixture index.md and refinement.md both contain "PASS PASS PASS" as
# free-text bait. With no completion-gate marker and no probe match, the runner
# must still return blocked_by_gate_failure for engineering and verify-AC.
assert_field "neg3-prose-engineering-terminal" "blocked_by_gate_failure" terminal_status \
  --stage engineering --source-id DP-900 --work-item-id DP-900-T3 --head-sha deadbeef
assert_field "neg3-prose-engineering-action" "blocked" next_action \
  --stage engineering --source-id DP-900 --work-item-id DP-900-T3 --head-sha deadbeef
assert_field "neg3-prose-verify-terminal" "blocked_by_gate_failure" terminal_status \
  --stage verify-AC --source-id DP-900 --work-item-id DP-900-V2 --head-sha deadbeef
assert_field "neg3-prose-verify-action" "blocked" next_action \
  --stage verify-AC --source-id DP-900 --work-item-id DP-900-V2 --head-sha deadbeef

# ─── AC-NF3: runner selftest finishes in seconds ─────────────────────────────
# The runner-first design is that the orchestrator can read runner output
# cheaply between every stage. If a single probe call ballooned to several
# seconds, the source gate would become a long-running step. We assert each
# stage probe completes in < 5 seconds (synthetic fixture, no real work).
START_NS=$(python3 -c "import time; print(int(time.time() * 1000000000))")
run_runner --stage source --source-id DP-900 >/dev/null
END_NS=$(python3 -c "import time; print(int(time.time() * 1000000000))")
ELAPSED_MS=$(( (END_NS - START_NS) / 1000000 ))
if [[ $ELAPSED_MS -gt 5000 ]]; then
  echo "FAIL: AC-NF3 runner source stage took ${ELAPSED_MS}ms (>5000ms)" >&2
  exit 1
fi

# ─── AC2 / dispatch-envelope alignment: runner-first execution loop ──────────
# auto-pass-execution-flow.md § Dispatch Envelope Worktree Resolution must
# exist (referenced by .claude/skills/auto-pass/SKILL.md § Dispatch Boundary).
# We assert the canonical reference content is present in the worktree —
# this guards the contract that SKILL.md pointers resolve to real sections.
EXECUTION_FLOW="$ROOT/.claude/skills/references/auto-pass-execution-flow.md"
if ! grep -q "Dispatch Envelope Worktree Resolution" "$EXECUTION_FLOW"; then
  echo "FAIL: AC2 auto-pass-execution-flow.md missing 'Dispatch Envelope Worktree Resolution' section" >&2
  exit 1
fi
# Runner-first narrative: the execution loop must declare runner JSON as the
# primary state source, not probe matrix as authority.
if ! grep -q "runner JSON" "$EXECUTION_FLOW"; then
  echo "FAIL: AC2 auto-pass-execution-flow.md missing runner-first narrative ('runner JSON')" >&2
  exit 1
fi

# ─── SKILL.md execution loop must point to runner JSON, not 'runner / probe' ──
SKILL_MD="$ROOT/.claude/skills/auto-pass/SKILL.md"
if grep -q "runner / probe PASS" "$SKILL_MD"; then
  echo "FAIL: AC2 SKILL.md still treats runner/probe as co-authorities; runner JSON must be primary" >&2
  exit 1
fi
if ! grep -q "runner JSON" "$SKILL_MD"; then
  echo "FAIL: AC2 SKILL.md execution loop pointer must mention runner JSON" >&2
  exit 1
fi

echo "PASS: auto-pass-runner selftest"
