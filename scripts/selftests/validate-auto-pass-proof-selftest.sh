#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-auto-pass-proof.sh"
PRODUCER_GATE="$ROOT/scripts/gates/gate-evidence-producer-whitelist.sh"
DIRECT_WRITE_HOOK="$ROOT/.claude/hooks/no-direct-evidence-write.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p \
  "$TMP/.polaris/evidence/task-snapshot" \
  "$TMP/.polaris/evidence/validation-fail" \
  "$TMP/.polaris/evidence/missing-v-task" \
  "$TMP/.polaris/evidence/completion-gate" \
  "$TMP/.polaris/evidence/blocked-conflict" \
  "$TMP/.polaris/evidence/unsupported-mutation" \
  "$TMP/.polaris/evidence/ci-local" \
  "$TMP/.polaris/evidence/verify" \
  "$TMP/.polaris/evidence/ac-verification" \
  "$TMP/.polaris/evidence/auto-pass/audit"

write_marker() {
  local path="$1"
  local kind="$2"
  local writer="$3"
  local owning="$4"
  local status="${5:-PASS}"
  python3 - "$path" "$kind" "$writer" "$owning" "$status" <<'PY'
import json
import sys
from pathlib import Path

path, kind, writer, owning, status = sys.argv[1:6]
payload = {
    "schema_version": 1,
    "marker_kind": kind,
    "writer": writer,
    "owning_skill": owning,
    "source_id": "DP-201",
    "work_item_id": "DP-201-T1",
    "status": status,
    "freshness": {
        "head_sha": "abc1234",
        "source_artifact": "docs-manager/src/content/docs/specs/design-plans/DP-201/tasks/T1/index.md"
    }
}
if kind == "audit_closure":
    payload["disposition_rows"] = [
        {"audit_marker": f"M{i}", "disposition": "implemented", "marker_kind": "validation_fail", "evidence_path": ".polaris/evidence/validation-fail/sample.json"}
        for i in range(1, 13)
    ]
if kind == "dp198_handoff":
    payload["dp_198_t3_unblocked"] = True
    payload["evidence_paths"] = [".polaris/evidence/auto-pass/audit/audit-closure-DP-201-abc1234.json"]
    payload["audit_closure_summary"] = {"implemented": 12, "blocked": 0}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

pushd "$TMP" >/dev/null
mkdir -p scripts/lib scripts/gates
cp "$ROOT/scripts/lib/evidence-producers.json" scripts/lib/evidence-producers.json
cp "$VALIDATOR" scripts/validate-auto-pass-proof.sh
cp "$PRODUCER_GATE" scripts/gates/gate-evidence-producer-whitelist.sh

write_marker ".polaris/evidence/task-snapshot/DP-201-T1.json" task_snapshot breakdown breakdown PASS
write_marker ".polaris/evidence/validation-fail/DP-201-T1.json" validation_fail breakdown breakdown FAIL
write_marker ".polaris/evidence/missing-v-task/DP-201-T1.json" missing_v_task breakdown breakdown BLOCKED
write_marker ".polaris/evidence/completion-gate/DP-201-T1-abc1234.json" completion_gate engineering engineering PASS
write_marker ".polaris/evidence/blocked-conflict/DP-201-T1-abc1234.json" blocked_conflict engineering engineering BLOCKED
write_marker ".polaris/evidence/unsupported-mutation/DP-201-T1-abc1234.json" unsupported_mutation engineering engineering BLOCKED
write_marker ".polaris/evidence/ci-local/DP-201-T1-abc1234.json" ci_local engineering engineering PASS
write_marker ".polaris/evidence/verify/polaris-verified-DP-201-T1-abc1234.json" verify run-verify-command.sh engineering PASS
write_marker ".polaris/evidence/ac-verification/DP-201-V1-abc1234.json" ac_verification verify-AC verify-AC PASS
write_marker ".polaris/evidence/ac-verification/spec-issue-DP-201-V1-abc1234.json" spec_issue verify-AC verify-AC ROUTE_BACK
write_marker ".polaris/evidence/ac-verification/drift-retry-DP-201-V1-abc1234.json" drift_retry verify-AC verify-AC IN_PROGRESS
write_marker ".polaris/evidence/ac-verification/drift-counter-DP-201-V1.json" drift_counter verify-AC verify-AC IN_PROGRESS
write_marker ".polaris/evidence/auto-pass/audit/audit-closure-DP-201-abc1234.json" audit_closure verify-AC verify-AC PASS
write_marker ".polaris/evidence/ac-verification/DP-201-V1-handoff-abc1234.json" dp198_handoff verify-AC verify-AC PASS

bash scripts/validate-auto-pass-proof.sh --producer-map
bash scripts/validate-auto-pass-proof.sh \
  .polaris/evidence/task-snapshot/DP-201-T1.json \
  .polaris/evidence/validation-fail/DP-201-T1.json \
  .polaris/evidence/missing-v-task/DP-201-T1.json \
  .polaris/evidence/completion-gate/DP-201-T1-abc1234.json \
  .polaris/evidence/blocked-conflict/DP-201-T1-abc1234.json \
  .polaris/evidence/unsupported-mutation/DP-201-T1-abc1234.json \
  .polaris/evidence/ci-local/DP-201-T1-abc1234.json \
  .polaris/evidence/verify/polaris-verified-DP-201-T1-abc1234.json \
  .polaris/evidence/ac-verification/DP-201-V1-abc1234.json \
  .polaris/evidence/ac-verification/spec-issue-DP-201-V1-abc1234.json \
  .polaris/evidence/ac-verification/drift-retry-DP-201-V1-abc1234.json \
  .polaris/evidence/ac-verification/drift-counter-DP-201-V1.json \
  .polaris/evidence/auto-pass/audit/audit-closure-DP-201-abc1234.json \
  .polaris/evidence/ac-verification/DP-201-V1-handoff-abc1234.json

bash scripts/gates/gate-evidence-producer-whitelist.sh --repo "$TMP" --files \
  .polaris/evidence/task-snapshot/DP-201-T1.json \
  .polaris/evidence/verify/polaris-verified-DP-201-T1-abc1234.json \
  .polaris/evidence/ac-verification/DP-201-V1-abc1234.json

python3 - <<'PY'
import json
from pathlib import Path
bad = {
    "schema_version": 1,
    "marker_kind": "ac_verification",
    "writer": "auto-pass",
    "owning_skill": "auto-pass",
    "source_id": "DP-201",
    "work_item_id": "DP-201-V1",
    "status": "PASS",
    "freshness": {"head_sha": "abc1234"}
}
Path(".polaris/evidence/ac-verification/bad-writer.json").write_text(json.dumps(bad) + "\n", encoding="utf-8")
prose = {"schema_version": 1, "marker_kind": "raw_prose", "writer": "verify-AC", "owning_skill": "verify-AC", "source_id": "DP-201", "work_item_id": "DP-201-V1", "status": "PASS", "freshness": {"head_sha": "abc1234"}}
Path(".polaris/evidence/ac-verification/raw-prose.json").write_text(json.dumps(prose) + "\n", encoding="utf-8")
jira_only = {"schema_version": 1, "marker_kind": "ac_verification", "writer": "verify-AC", "owning_skill": "verify-AC", "source_id": "DP-201", "work_item_id": "DP-201-V1", "status": "PASS", "jira_label": "done"}
Path(".polaris/evidence/ac-verification/jira-only.json").write_text(json.dumps(jira_only) + "\n", encoding="utf-8")
PY

if bash scripts/validate-auto-pass-proof.sh .polaris/evidence/ac-verification/bad-writer.json >/tmp/dp201-bad-writer.out 2>&1; then
  echo "FAIL: bad writer fixture unexpectedly passed" >&2
  exit 1
fi
if bash scripts/gates/gate-evidence-producer-whitelist.sh --repo "$TMP" --files .polaris/evidence/ac-verification/bad-writer.json >/tmp/dp201-gate-bad-writer.out 2>&1; then
  echo "FAIL: producer gate bad writer fixture unexpectedly passed" >&2
  exit 1
fi
if bash scripts/validate-auto-pass-proof.sh .polaris/evidence/ac-verification/raw-prose.json >/tmp/dp201-raw-prose.out 2>&1; then
  echo "FAIL: raw prose fixture unexpectedly passed" >&2
  exit 1
fi
if bash scripts/validate-auto-pass-proof.sh .polaris/evidence/ac-verification/jira-only.json >/tmp/dp201-jira-only.out 2>&1; then
  echo "FAIL: jira-only fixture unexpectedly passed" >&2
  exit 1
fi

tmp_pass="/tmp/dp201-tmp-only-pass.json"
write_marker "$tmp_pass" ac_verification verify-AC verify-AC PASS
if bash scripts/validate-auto-pass-proof.sh "$tmp_pass" >/tmp/dp201-tmp-only.out 2>&1; then
  echo "FAIL: tmp-only PASS fixture unexpectedly passed" >&2
  exit 1
fi

popd >/dev/null

printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":".polaris/evidence/ac-verification/DP-201-V1-abc1234.json"}}' >"$TMP/direct-write.json"
if "$DIRECT_WRITE_HOOK" <"$TMP/direct-write.json" >/tmp/dp201-direct-write.out 2>&1; then
  echo "FAIL: direct evidence Write fixture unexpectedly passed" >&2
  exit 1
fi
printf '%s\n' '{"tool_name":"Write","tool_input":{"file_path":"notes/not-evidence.json"}}' >"$TMP/non-evidence-write.json"
"$DIRECT_WRITE_HOOK" <"$TMP/non-evidence-write.json" >/tmp/dp201-non-evidence-write.out 2>&1

valid_verify="$TMP/valid-verify.json"
invalid_verify="$TMP/invalid-verify.json"
python3 - "$valid_verify" "$invalid_verify" <<'PY'
import json
import sys
from pathlib import Path

valid, invalid = map(Path, sys.argv[1:3])
base = {
    "ticket": "DP-201-T2",
    "head_sha": "abc1234",
    "exit_code": 0,
    "at": "2026-05-19T00:00:00+08:00",
}
valid.write_text(json.dumps(dict(base, writer="run-verify-command.sh")) + "\n", encoding="utf-8")
invalid.write_text(json.dumps(dict(base, writer="auto-pass")) + "\n", encoding="utf-8")
PY
# shellcheck source=scripts/lib/verification-evidence.sh
. "$ROOT/scripts/lib/verification-evidence.sh"
verification_evidence_validate_file "$valid_verify" DP-201-T2 abc1234 >/tmp/dp201-valid-verify-writer.out
if verification_evidence_validate_file "$invalid_verify" DP-201-T2 abc1234 >/tmp/dp201-invalid-verify-writer.out 2>&1; then
  echo "FAIL: invalid verify writer fixture unexpectedly passed" >&2
  exit 1
fi

bash "$ROOT/scripts/check-main-chain-compliance.sh" \
  --repo "$ROOT" \
  --source-container docs-manager/src/content/docs/specs/design-plans/DP-201-strict-pipeline-proof-of-work-artifact-contract \
  --allow-active-verification >/tmp/dp201-main-chain.out

echo "PASS: validate-auto-pass-proof selftest"
