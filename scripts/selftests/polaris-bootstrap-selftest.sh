#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "${HELPERS}"

script_test_expect_pass \
  "polaris bootstrap dry-run" \
  bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile runtime --dry-run

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

run_expect_fail_contains \
  "mise missing" \
  "BLOCKED_ENV blocker_class=mise-missing" \
  env PATH="$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile core

mkdir -p "${TMP_DIR}/fake-mise/bin"
cat >"${TMP_DIR}/fake-mise/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  trust|install) exit 0 ;;
  exec)
    shift
    if [[ "${1:-}" == "--" ]]; then shift; fi
    joined="$*"
    case "$joined" in
      *"command -v node"*) exit 1 ;;
      *"command -v pnpm"*) printf '%s\n' "/tmp/fake-pnpm"; exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
SH
chmod +x "${TMP_DIR}/fake-mise/bin/mise"

run_expect_fail_contains \
  "mise managed node missing" \
  "BLOCKED_ENV blocker_class=mise-managed:node" \
  env PATH="${TMP_DIR}/fake-mise/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile runtime

mkdir -p "${TMP_DIR}/fake-gh/bin"
cp "${TMP_DIR}/fake-mise/bin/mise" "${TMP_DIR}/fake-gh/bin/mise"
run_expect_fail_contains \
  "gh missing" \
  "BLOCKED_ENV blocker_class=gh-missing" \
  env PATH="${TMP_DIR}/fake-gh/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile delivery

cat >"${TMP_DIR}/fake-gh/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "${TMP_DIR}/fake-gh/bin/gh"
run_expect_fail_contains \
  "gh unauth" \
  "BLOCKED_ENV blocker_class=gh-unauth" \
  env PATH="${TMP_DIR}/fake-gh/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile delivery

mkdir -p "${TMP_DIR}/ide-bundle/bin"
cat >"${TMP_DIR}/ide-bundle/bin/node" <<'SH'
#!/usr/bin/env bash
echo v99.0.0
SH
cat >"${TMP_DIR}/ide-bundle/bin/pnpm" <<'SH'
#!/usr/bin/env bash
echo 99.0.0
SH
chmod +x "${TMP_DIR}/ide-bundle/bin/node" "${TMP_DIR}/ide-bundle/bin/pnpm"
run_expect_fail_contains \
  "ide bundled fallback rejected" \
  "BLOCKED_ENV blocker_class=mise-missing" \
  env PATH="${TMP_DIR}/ide-bundle/bin:$(script_test_restricted_path)" bash "${ROOT_DIR}/scripts/polaris-bootstrap.sh" --profile runtime

echo "polaris-bootstrap self-test PASS"
