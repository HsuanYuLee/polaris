#!/usr/bin/env bash
# Purpose: DP-422 T8 source-closeout coverage：證明 T1-T7 transition／current
#          reproducers 與 DP-424～426 attribution 都由既有 canonical authority
#          覆蓋，且 callable owner／source-type authority 沒有 collision。
# Inputs: 正式 transition registry、script manifest 與 aggregate enrollment。
# Outputs: coverage 完整時 PASS；mutation fixture 必須以穩定 POLARIS marker fail closed。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRANSITION_VALIDATOR="$ROOT/scripts/validate-skill-flow-transition-registry.sh"
PARITY_VALIDATOR="$ROOT/scripts/validate-spec-check-contract-parity.sh"
REGISTRY="$ROOT/scripts/lib/skill-flow-transition-registry.json"
MECHANISM_REGISTRY="$ROOT/.claude/rules/mechanism-registry.md"
AGGREGATE="$ROOT/scripts/run-aggregate-selftests.sh"
TMP="$(mktemp -d -t dp422-transition-coverage.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Source-level closeout profile：exact DP-422 transition set、single owner、無
# DP/JIRA fast path；generic registry validation 仍由同一 validator 執行。
bash "$TRANSITION_VALIDATOR" --source-closeout "$REGISTRY" >/dev/null

# AC-NEG1：只 introspect 既有兩個 canonical authority，不新增第三把 parity
# 秤。authority id、registry 與 validator path 都必須唯一。
bash "$TRANSITION_VALIDATOR" --describe-authority >"$TMP/transition-authority.json"
bash "$PARITY_VALIDATOR" --describe-authority >"$TMP/parity-authority.json"
python3 - "$TMP/transition-authority.json" "$TMP/parity-authority.json" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(Path(path).read_text(encoding="utf-8")) for path in sys.argv[1:]]
for field in ("authority_id", "registry", "validator"):
    values = [row.get(field) for row in rows]
    if any(not isinstance(value, str) or not value for value in values):
        raise SystemExit(f"missing authority field: {field}")
    if len(values) != len(set(values)):
        raise SystemExit(f"owner collision: {field}={values}")
expected = {
    "observable_skill_flow_transition_registry",
    "producer_consumer_validator_parity",
}
actual = {row["authority_id"] for row in rows}
if actual != expected:
    raise SystemExit(f"unexpected canonical authorities: {sorted(actual)}")
PY

# W14 是 current reproducer executor；這裡 fail-closed 驗證 T1-T7 與三個
# predecessor 的 exact reproducers 都在其 canonical enrollment，避免 source
# closeout 只剩靜態 checklist。
bash "$AGGREGATE" --root "$ROOT" --list >"$TMP/enrolled.txt"
required_reproducers=(
  # T1 / AC1, AC12, AC-NEG4
  scripts/selftests/validate-skill-flow-transition-registry-selftest.sh
  scripts/selftests/validate-engineering-self-review-result-selftest.sh
  # T2 / AC4 / DP-424
  scripts/selftests/write-deliverable-selftest.sh
  scripts/selftests/check-delivery-completion-task-shape-selftest.sh
  # T3 / AC3, AC5 / DP-426
  scripts/selftests/validate-refinement-consumer-schema-binding-selftest.sh
  scripts/selftests/backfill-refinement-verification-strategy-selftest.sh
  scripts/selftests/validate-spec-check-contract-parity-selftest.sh
  # T4 / AC6 / DP-425
  scripts/selftests/engineering-source-scope-authority-selftest.sh
  scripts/selftests/gate-changed-files-scope-selftest.sh
  # T5 / AC3
  scripts/selftests/external-write-chain-wired-selftest.sh
  scripts/selftests/submit-pr-review-selftest.sh
  # T6 / AC8, AC10
  scripts/selftests/resolve-artifact-location-selftest.sh
  scripts/selftests/validate-artifact-location-selftest.sh
  scripts/selftests/run-verify-all-selftest.sh
  # T7 / AC9
  scripts/selftests/polaris-bootstrap-help-selftest.sh
  scripts/selftests/validate-safe-cli-introspection-selftest.sh
  scripts/selftests/verify-cross-llm-parity-selftest.sh
)
for reproducer in "${required_reproducers[@]}"; do
  grep -Fxq "$reproducer" "$TMP/enrolled.txt" || \
    fail "current reproducer 未 enrollment：$reproducer"
done

# Predecessor attribution 只能讀 tracked mechanism contract；該 contract 帶 LOCKED
# refinement 與 predecessor_audit hash provenance，不在 selftest 內另造 rows。
python3 - "$MECHANISM_REGISTRY" "$TMP/enrolled.txt" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
enrolled = set(Path(sys.argv[2]).read_text(encoding="utf-8").splitlines())
required_hashes = {
    "sha256:d3d2349152e883a92c3e211efb1e77de4ed636a0f2aa436fde5b8e3f663a2c89",
    "sha256:c1baae0365826314f1eace32a0c3e436fe46dceb38ec07ae4b630fb11d68bc56",
    "sha256:e9c9405a765a10a0897a28b1fedd3d3fab1fc321d23f9128cdf21cd888b92dac",
}
if not all(value in text for value in required_hashes):
    raise SystemExit("missing LOCKED refinement/predecessor-audit provenance hash")
start_match = re.search(r"(?m)^## DP-422 Source Closeout Attribution$", text)
if start_match is None:
    raise SystemExit("missing DP-422 source closeout attribution contract")
start = start_match.start()
end_match = re.search(r"(?m)^## ", text[start_match.end():])
end = len(text) if end_match is None else start_match.end() + end_match.start()
section = text[start:end]
rows = []
for line in section.splitlines():
    if not re.match(r"^\| DP-42[456] \|", line):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) != 6:
        raise SystemExit(f"invalid predecessor attribution row: {line}")
    predecessor, disposition, task, ac, checklist, reproducers = cells
    paths = re.findall(r"`([^`]+)`", reproducers)
    rows.append({
        "predecessor": predecessor,
        "disposition": disposition,
        "task": task,
        "ac": ac,
        "checklist_attribution": sorted(
            value.strip() for value in checklist.split("；") if value.strip()
        ),
        "current_reproducers": sorted(paths),
    })

rows.sort(key=lambda row: row["predecessor"])
expected = [
    {
        "predecessor": "DP-424",
        "disposition": "FULLY_SUPERSEDED",
        "task": "T2",
        "ac": "AC4",
        "checklist_attribution": sorted([
            "no-PR content delivery writer",
            "task_shape-first authoring／consumer parity",
            "end-to-end closeout regression",
        ]),
        "current_reproducers": sorted([
            "scripts/selftests/write-deliverable-selftest.sh",
            "scripts/selftests/check-delivery-completion-task-shape-selftest.sh",
        ]),
    },
    {
        "predecessor": "DP-425",
        "disposition": "FULLY_SUPERSEDED",
        "task": "T4",
        "ac": "AC6",
        "checklist_attribution": sorted([
            "退役 refinement.json.changed_files delivery gate",
            "task.md Allowed Files 唯一 authority regression",
        ]),
        "current_reproducers": sorted([
            "scripts/selftests/engineering-source-scope-authority-selftest.sh",
            "scripts/selftests/gate-changed-files-scope-selftest.sh",
        ]),
    },
    {
        "predecessor": "DP-426",
        "disposition": "FULLY_SUPERSEDED",
        "task": "T3",
        "ac": "AC5",
        "checklist_attribution": sorted([
            "backfill consumer registry entry",
            "tasks[].id／kind accessor-binding regression",
        ]),
        "current_reproducers": sorted([
            "scripts/selftests/validate-refinement-consumer-schema-binding-selftest.sh",
            "scripts/selftests/backfill-refinement-verification-strategy-selftest.sh",
            "scripts/selftests/validate-spec-check-contract-parity-selftest.sh",
        ]),
    },
]
if rows != expected:
    raise SystemExit(f"predecessor attribution mismatch: {rows}")
projection = json.dumps(
    rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")
).encode("utf-8")
projection_hash = "sha256:" + hashlib.sha256(projection).hexdigest()
if projection_hash != "sha256:e9c9405a765a10a0897a28b1fedd3d3fab1fc321d23f9128cdf21cd888b92dac":
    raise SystemExit(f"predecessor attribution projection hash mismatch: {projection_hash}")
tasks = [row["task"] for row in rows]
acs = [row["ac"] for row in rows]
if len(tasks) != len(set(tasks)) or len(acs) != len(set(acs)):
    raise SystemExit("predecessor task/AC owner collision")
for row in rows:
    missing = sorted(set(row["current_reproducers"]) - enrolled)
    if missing:
        raise SystemExit(f"predecessor current reproducer not enrolled: {missing}")
PY

# Source closeout 是 required-subset contract，不得凍結 registry 使未來 DP 無法
# 登記新 transition。新增一筆獨立 owner／callable 的 future row 仍須通過。
python3 - "$REGISTRY" "$TMP/future-transition.json" <<'PY'
import copy
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
row = copy.deepcopy(data["transitions"][0])
row.update({
    "id": "future.example",
    "owner_source": "DP-999",
    "summary": "future transition fixture",
    "producer": "scripts/check-framework-pr-gate.sh",
    "consumer": "scripts/check-framework-pr-gate-selftest.sh",
    "validator": "scripts/check-framework-pr-gate.sh",
    "blocking_invoke_point": "scripts/check-framework-pr-gate-selftest.sh",
})
row["callable_interface"].update({
    "path": "scripts/check-framework-pr-gate.sh",
    "selector": "--list-stages",
})
row["source_types"] = ["dp", "jira"]
data["transitions"].append(row)
Path(sys.argv[2]).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
bash "$TRANSITION_VALIDATOR" --source-closeout "$TMP/future-transition.json" >/dev/null

mutate_and_expect_failure() {
  local name="$1"
  local mutation="$2"
  local marker="$3"
  local fixture="$TMP/$name.json"
  python3 - "$REGISTRY" "$fixture" "$mutation" <<'PY'
import copy
import json
import sys
from pathlib import Path

source, target, mutation = sys.argv[1:]
data = json.loads(Path(source).read_text(encoding="utf-8"))
if mutation == "missing_transition":
    data["transitions"] = data["transitions"][:-1]
elif mutation == "wrong_owner":
    data["transitions"][0]["owner_source"] = "DP-424"
elif mutation == "callable_owner_collision":
    first = data["transitions"][0]
    second = data["transitions"][1]
    second["callable_interface"] = copy.deepcopy(first["callable_interface"])
    second["producer"] = first["producer"]
elif mutation == "source_type_fast_path":
    data["transitions"][0]["source_type"] = "dp"
elif mutation == "asymmetric_source_types":
    data["transitions"][0]["source_types"] = ["dp"]
elif mutation == "invalid_transition_id":
    data["transitions"][0]["id"] = ["not", "hashable"]
else:
    raise SystemExit(f"unknown mutation: {mutation}")
Path(target).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local exit_code=0
  if bash "$TRANSITION_VALIDATOR" --source-closeout "$fixture" >"$TMP/$name.out" 2>&1; then
    fail "$name unexpectedly passed"
  else
    exit_code=$?
  fi
  [[ "$exit_code" -eq 2 ]] || fail "$name exited $exit_code instead of 2"
  grep -Fq "$marker" "$TMP/$name.out" || fail "$name did not emit $marker"
}

mutate_and_expect_failure missing missing_transition POLARIS_SKILL_FLOW_TRANSITION_COVERAGE_GAP
mutate_and_expect_failure owner wrong_owner POLARIS_SKILL_FLOW_TRANSITION_OWNER_COLLISION
mutate_and_expect_failure callable callable_owner_collision POLARIS_SKILL_FLOW_TRANSITION_OWNER_COLLISION
mutate_and_expect_failure source_type source_type_fast_path POLARIS_SKILL_FLOW_TRANSITION_SOURCE_TYPE_FAST_PATH
mutate_and_expect_failure source_types asymmetric_source_types POLARIS_SKILL_FLOW_TRANSITION_SOURCE_TYPE_FAST_PATH
mutate_and_expect_failure invalid_id invalid_transition_id POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID

echo "PASS: DP-422 skill-flow transition source-closeout coverage"
