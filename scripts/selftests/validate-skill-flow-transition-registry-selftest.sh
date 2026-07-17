#!/usr/bin/env bash
# Purpose: 驗證 observable transition registry validator 與 resolver 會 fail closed。
# Inputs: 正式 registry 與隔離的 mutation fixtures。
# Outputs: 正向與對抗案例皆符合契約時輸出 PASS。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/validate-skill-flow-transition-registry.sh"
RESOLVER="$ROOT_DIR/scripts/resolve-skill-flow-transition.sh"
REGISTRY="$ROOT_DIR/scripts/lib/skill-flow-transition-registry.json"
TMP="$(mktemp -d -t dp422-transition-registry.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

bash "$VALIDATOR" "$REGISTRY" >/dev/null
bash "$VALIDATOR" --help >/dev/null
bash "$RESOLVER" --help >/dev/null
[[ "$(bash "$RESOLVER" --id skill_flow_transition_registry.resolve --field callable_interface.path)" == \
  "scripts/resolve-skill-flow-transition.sh" ]] || fail "resolver did not return the canonical callable"

mutate_and_expect_failure() {
  local name="$1"
  local mutation="$2"
  local expected="$3"
  local fixture="$TMP/$name.json"
  python3 - "$REGISTRY" "$fixture" "$mutation" <<'PY'
import json
import sys
from pathlib import Path

source, target, mutation = sys.argv[1:4]
data = json.loads(Path(source).read_text(encoding="utf-8"))
row = data["transitions"][0]
if mutation == "duplicate_id":
    data["transitions"].append(dict(row))
elif mutation == "non_observable":
    row["inputs"][0]["observable"] = False
elif mutation == "non_decidable":
    row["inputs"][0]["mechanically_decidable"] = False
elif mutation == "llm_prose_source":
    row["outputs"][0]["source_kind"] = "llm_prose"
elif mutation == "missing_callable":
    row["callable_interface"]["path"] = "scripts/does-not-exist.sh"
elif mutation == "producer_mismatch":
    row["producer"] = "scripts/validate-skill-flow-transition-registry.sh"
elif mutation == "validator_not_invoked":
    row["validator"] = "scripts/manifest.json"
elif mutation == "consumer_not_invoking":
    row["consumer"] = "VERSION"
elif mutation == "consumer_prose_only":
    row["consumer"] = ".claude/rules/mechanism-registry.md"
elif mutation == "blocking_not_invoking":
    row["blocking_invoke_point"] = "VERSION"
elif mutation == "blocking_prose_only":
    row["blocking_invoke_point"] = ".claude/rules/mechanism-registry.md"
elif mutation == "path_escape":
    row["validator"] = "../outside-workspace.sh"
elif mutation == "exclusions_object":
    data["llm_owned_exclusions"] = {"research": True}
elif mutation == "exclusions_entry_object":
    data["llm_owned_exclusions"][0] = {"name": "research"}
else:
    raise SystemExit(f"unknown mutation: {mutation}")
Path(target).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local exit_code=0
  if bash "$VALIDATOR" "$fixture" >"$TMP/$name.out" 2>&1; then
    fail "$name unexpectedly passed"
  else
    exit_code=$?
  fi
  [[ "$exit_code" -eq 2 ]] || fail "$name exited $exit_code instead of 2"
  grep -q "$expected" "$TMP/$name.out" || fail "$name did not emit $expected"
}

mutate_and_expect_failure duplicate duplicate_id 'transition id 重複'
mutate_and_expect_failure observable non_observable 'observable 必須是 true'
mutate_and_expect_failure decidable non_decidable 'mechanically_decidable 必須是 true'
mutate_and_expect_failure prose llm_prose_source '無法機械觀測'
mutate_and_expect_failure callable missing_callable 'path 不存在'
mutate_and_expect_failure producer producer_mismatch 'producer 必須等於 callable_interface.path'
mutate_and_expect_failure validator validator_not_invoked 'validator 在 script manifest 必須恰有一筆'
mutate_and_expect_failure consumer consumer_not_invoking 'manifest selftest 必須等於 consumer'
mutate_and_expect_failure consumer_prose consumer_prose_only 'manifest selftest 必須等於 consumer'
mutate_and_expect_failure blocking blocking_not_invoking 'blocking_invoke_point 必須等於已 enrollment'
mutate_and_expect_failure blocking_prose blocking_prose_only 'blocking_invoke_point 必須等於已 enrollment'
mutate_and_expect_failure escape path_escape '超出 workspace root'
mutate_and_expect_failure exclusions_object exclusions_object 'llm_owned_exclusions 必須完全符合'
mutate_and_expect_failure exclusions_entry exclusions_entry_object 'llm_owned_exclusions 必須完全符合'

python3 - "$TMP/root-array.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps([]) + "\n", encoding="utf-8")
PY
if bash "$VALIDATOR" "$TMP/root-array.json" >"$TMP/root-array.out" 2>&1; then
  fail "root array unexpectedly passed"
else
  exit_code=$?
fi
[[ "$exit_code" -eq 2 ]] || fail "root array exited $exit_code instead of 2"
grep -q 'registry root 必須是 object' "$TMP/root-array.out" || \
  fail "root array did not emit the structural error"

if bash "$RESOLVER" --registry "$TMP/root-array.json" --id skill_flow_transition_registry.resolve \
  >"$TMP/invalid-registry.out" 2>&1; then
  fail "resolver accepted an invalid registry"
else
  exit_code=$?
fi
[[ "$exit_code" -eq 2 ]] || fail "invalid registry exited $exit_code instead of 2"
grep -q 'POLARIS_SKILL_FLOW_TRANSITION_REGISTRY_INVALID' "$TMP/invalid-registry.out" || \
  fail "resolver did not consume the registry validator"

for option in --id --registry --field; do
  if bash "$RESOLVER" "$option" >"$TMP/option-value.out" 2>&1; then
    fail "$option without a value unexpectedly passed"
  else
    exit_code=$?
  fi
  [[ "$exit_code" -eq 2 ]] || fail "$option without a value exited $exit_code instead of 2"
  grep -q "POLARIS_SKILL_FLOW_TRANSITION_OPTION_VALUE_REQUIRED:$option" "$TMP/option-value.out" || \
    fail "$option without a value did not emit the stable marker"
done

if bash "$RESOLVER" --registry "$REGISTRY" --id missing.transition >"$TMP/missing.out" 2>&1; then
  fail "missing transition unexpectedly resolved"
else
  exit_code=$?
fi
[[ "$exit_code" -eq 2 ]] || fail "missing transition exited $exit_code instead of 2"
grep -q 'POLARIS_SKILL_FLOW_TRANSITION_NOT_UNIQUE' "$TMP/missing.out" || \
  fail "missing transition did not fail closed"

echo "PASS: validate-skill-flow-transition-registry selftest"
