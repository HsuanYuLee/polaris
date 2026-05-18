#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

TMP_DIR="$(script_test_temp_dir)"
trap 'rm -rf "${TMP_DIR}"' EXIT

run_expect_fail_contains() {
  local name="$1"
  local pattern="$2"
  shift 2
  local output="${TMP_DIR}/${name}.out"
  if "$@" >"${output}" 2>&1; then
    echo "FAIL: expected ${name} to fail" >&2
    cat "${output}" >&2
    exit 1
  fi
  script_test_expect_output_contains "$name" "$pattern" "${output}"
}

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" ]]; then
  joined="$*"
  case "$joined" in
    *rg*) exit 1 ;;
    *node*) exit 1 ;;
    *jq*) exit 0 ;;
    *) exit 0 ;;
  esac
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "mise 2099.1.1"
  exit 0
fi
exit 0
SH
chmod +x "${TMP_DIR}/bin/mise"

output="${TMP_DIR}/doctor.out"
PATH="${TMP_DIR}/bin:$(script_test_restricted_path)" \
  bash "${ROOT_DIR}/scripts/polaris-doctor.sh" --profile core --simulate-no-vscode-path \
  >"${output}" 2>&1 && {
    echo "FAIL: expected missing rg doctor fixture to fail" >&2
    cat "${output}" >&2
    exit 1
  }

script_test_expect_output_contains "missing rg" "mise-managed ripgrep missing: rg" "${output}"
script_test_expect_output_contains "missing rg blocked env" "BLOCKED_ENV blocker_class=mise-managed:rg" "${output}"
if grep -q "command not found" "${output}"; then
  echo "FAIL: doctor emitted command-not-found instead of fail-loud status" >&2
  cat "${output}" >&2
  exit 1
fi

PATH="${TMP_DIR}/bin:$(script_test_restricted_path)" \
  bash "${ROOT_DIR}/scripts/doctor-mise-check.sh" --tool mise >"${TMP_DIR}/mise-present.json"
script_test_expect_output_contains "mise present json" '"status": "present"' "${TMP_DIR}/mise-present.json"

PATH="$(script_test_restricted_path)" \
  bash "${ROOT_DIR}/scripts/doctor-mise-check.sh" --tool node >"${TMP_DIR}/mise-missing.json" 2>/dev/null && {
    echo "FAIL: expected doctor-mise-check missing mise to fail" >&2
    exit 1
  }
script_test_expect_output_contains "mise missing json" '"blocker_class": "mise-missing"' "${TMP_DIR}/mise-missing.json"

cat >"${TMP_DIR}/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" ]]; then
  shift
  if [[ "${1:-}" == "--" ]]; then shift; fi
  joined="$*"
  case "$joined" in
    *"command -v node"*) exit 1 ;;
    *"command -v pnpm"*) printf '%s\n' "/tmp/fake-pnpm"; exit 0 ;;
    *"command -v rg"*) printf '%s\n' "/tmp/fake-rg"; exit 0 ;;
    *"command -v jq"*) printf '%s\n' "/tmp/fake-jq"; exit 0 ;;
    *"--version"*) exit 0 ;;
    *) exit 0 ;;
  esac
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "mise 2099.1.1"
  exit 0
fi
exit 0
SH
chmod +x "${TMP_DIR}/bin/mise"
run_expect_fail_contains \
  "managed node missing" \
  "BLOCKED_ENV blocker_class=mise-managed:node" \
  env PATH="${TMP_DIR}/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-doctor.sh" --profile runtime

mkdir -p "${TMP_DIR}/no-mise/bin"
cat >"${TMP_DIR}/no-mise/bin/node" <<'SH'
#!/usr/bin/env bash
echo v99.0.0
SH
chmod +x "${TMP_DIR}/no-mise/bin/node"
run_expect_fail_contains \
  "ide bundled node rejected" \
  "BLOCKED_ENV blocker_class=mise-missing" \
  env PATH="${TMP_DIR}/no-mise/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-doctor.sh" --profile runtime

run_expect_fail_contains \
  "gh missing" \
  "BLOCKED_ENV blocker_class=gh-missing" \
  env PATH="${TMP_DIR}/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-doctor.sh" --profile delivery

cat >"${TMP_DIR}/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "${TMP_DIR}/bin/gh"
run_expect_fail_contains \
  "gh unauth" \
  "BLOCKED_ENV blocker_class=gh-unauth" \
  env PATH="${TMP_DIR}/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-doctor.sh" --profile delivery

echo "polaris-doctor no-VSCode PATH self-test PASS"
