#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

TMP_DIR="$(script_test_temp_dir)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" ]]; then
  joined="$*"
  case "$joined" in
    *rg*) exit 1 ;;
    *jq*) exit 0 ;;
    *) exit 0 ;;
  esac
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
if grep -q "command not found" "${output}"; then
  echo "FAIL: doctor emitted command-not-found instead of fail-loud status" >&2
  cat "${output}" >&2
  exit 1
fi

echo "polaris-doctor no-VSCode PATH self-test PASS"
