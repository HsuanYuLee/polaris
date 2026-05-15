#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="${ROOT_DIR}/scripts/check-script-manifest.sh"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

TMP_DIR="$(script_test_temp_dir)"
trap 'rm -rf "${TMP_DIR}"' EXIT

write_script() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  printf '#!/usr/bin/env bash\nset -euo pipefail\nexit 0\n' >"${path}"
  chmod +x "${path}"
}

write_manifest() {
  local repo="$1"
  local body="$2"
  mkdir -p "${repo}/scripts"
  printf '%s\n' "${body}" >"${repo}/scripts/manifest.json"
}

expect_pass() {
  local name="$1"
  local repo="$2"
  script_test_expect_pass "${name}" bash "${CHECKER}" --root "${repo}" --quiet || exit 1
}

expect_fail() {
  local name="$1"
  local repo="$2"
  SCRIPT_TEST_LAST_OUTPUT=/tmp/check-script-manifest-selftest.out \
    script_test_expect_fail "${name}" bash "${CHECKER}" --root "${repo}" --quiet || exit 1
}

positive="${TMP_DIR}/positive"
write_script "${positive}/scripts/good.sh"
write_script "${positive}/scripts/good-selftest.sh"
write_manifest "${positive}" '{
  "version": 1,
  "coverage": {"entrypoint_patterns": ["scripts/gates/*"]},
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "scripts/good-selftest.sh",
      "lifecycle": "hot_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/good-selftest.sh",
      "kind": "selftest",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "selftest script",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}'
expect_pass "positive fixture" "${positive}"

missing_target="${TMP_DIR}/missing-target"
write_script "${missing_target}/scripts/good-selftest.sh"
write_manifest "${missing_target}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/missing.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "scripts/good-selftest.sh",
      "lifecycle": "hot_path",
      "relocation": "stay"
    },
    {
      "path": "scripts/good-selftest.sh",
      "kind": "selftest",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "selftest script",
      "lifecycle": "support_path",
      "relocation": "stay"
    }
  ]
}'
expect_fail "missing target" "${missing_target}"

missing_row="${TMP_DIR}/missing-row"
write_script "${missing_row}/scripts/good.sh"
write_script "${missing_row}/scripts/unregistered.sh"
write_manifest "${missing_row}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by positive fixture command",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ]
}'
expect_fail "missing root manifest row" "${missing_row}"

missing_selftest="${TMP_DIR}/missing-selftest"
write_script "${missing_selftest}/scripts/good.sh"
write_manifest "${missing_selftest}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "scripts/nope-selftest.sh",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ]
}'
expect_fail "missing selftest target" "${missing_selftest}"

invalid_enum="${TMP_DIR}/invalid-enum"
write_script "${invalid_enum}/scripts/good.sh"
write_manifest "${invalid_enum}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "invalid",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by enum fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ]
}'
expect_fail "invalid enum" "${invalid_enum}"

sunset_missing_evidence="${TMP_DIR}/sunset-missing-evidence"
write_script "${sunset_missing_evidence}/scripts/old.sh"
write_manifest "${sunset_missing_evidence}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/old.sh",
      "kind": "legacy",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by sunset fixture",
      "lifecycle": "sunset_ready",
      "relocation": "delete_after_gate"
    }
  ]
}'
expect_fail "sunset_ready missing evidence" "${sunset_missing_evidence}"

sunset_with_evidence="${TMP_DIR}/sunset-with-evidence"
write_script "${sunset_with_evidence}/scripts/old.sh"
write_manifest "${sunset_with_evidence}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/old.sh",
      "kind": "legacy",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by sunset fixture",
      "lifecycle": "sunset_ready",
      "relocation": "delete_after_gate",
      "no_active_consumer_evidence": "selftest fixture proves required evidence gate"
    }
  ]
}'
expect_pass "sunset_ready with evidence" "${sunset_with_evidence}"

governed_tests_positive="${TMP_DIR}/governed-tests-positive"
write_script "${governed_tests_positive}/scripts/good.sh"
write_manifest "${governed_tests_positive}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by governed test fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ],
  "test_governance": {
    "baseline_schema": ["owner", "reason", "remediation_task", "expiry", "scope"],
    "baseline": [
      {
        "owner": "polaris-framework",
        "reason": "fixture",
        "remediation_task": "DP-184-T2",
        "expiry": "2026-06-30",
        "scope": "fixture"
      }
    ]
  },
  "governed_tests": [
    {
      "id": "good",
      "command": "bash scripts/good.sh",
      "profiles": ["core", "release"],
      "changed_paths": ["scripts/good.sh"],
      "fixtures": [],
      "enrolled": true,
      "owner": "polaris-framework"
    }
  ]
}'
expect_pass "governed tests positive" "${governed_tests_positive}"

governed_tests_missing_baseline="${TMP_DIR}/governed-tests-missing-baseline"
write_script "${governed_tests_missing_baseline}/scripts/good.sh"
write_manifest "${governed_tests_missing_baseline}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by governed test fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ],
  "test_governance": {
    "baseline_schema": ["owner", "reason", "remediation_task", "expiry", "scope"],
    "baseline": [
      {
        "owner": "polaris-framework",
        "reason": "fixture",
        "expiry": "2026-06-30",
        "scope": "fixture"
      }
    ]
  }
}'
expect_fail "governed tests missing baseline field" "${governed_tests_missing_baseline}"

governed_tests_invalid_profile="${TMP_DIR}/governed-tests-invalid-profile"
write_script "${governed_tests_invalid_profile}/scripts/good.sh"
write_manifest "${governed_tests_invalid_profile}" '{
  "version": 1,
  "scripts": [
    {
      "path": "scripts/good.sh",
      "kind": "gate",
      "runner": "bash",
      "owner_surface": "selftest_fixture",
      "selftest": "N/A",
      "selftest_reason": "covered by governed test fixture",
      "lifecycle": "hot_path",
      "relocation": "stay"
    }
  ],
  "governed_tests": [
    {
      "id": "bad-profile",
      "command": "bash scripts/good.sh",
      "profiles": ["unknown"],
      "changed_paths": ["scripts/good.sh"],
      "fixtures": [],
      "enrolled": true,
      "owner": "polaris-framework"
    }
  ]
}'
expect_fail "governed tests invalid profile" "${governed_tests_invalid_profile}"

echo "check-script-manifest self-test PASS"
