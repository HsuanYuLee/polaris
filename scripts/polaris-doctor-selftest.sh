#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPERS="${ROOT_DIR}/scripts/selftests/lib/script-test-helpers.sh"
# shellcheck source=scripts/selftests/lib/script-test-helpers.sh
. "$HELPERS"

TMP_DIR="$(script_test_temp_dir)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_expect_fail_contains() {
  local name="$1"
  local pattern="$2"
  shift 2
  local output="${TMP_DIR}/${name}.out"
  if "$@" >"$output" 2>&1; then
    echo "FAIL: expected ${name} to fail" >&2
    cat "$output" >&2
    exit 1
  fi
  script_test_expect_output_contains "$name" "$pattern" "$output"
}

mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "exec" ]]; then
  shift
  [[ "${1:-}" == "--" ]] && shift
  joined="$*"
  case "$joined" in
    *"command -v rg"*) exit 1 ;;
    *"command -v jq"*) printf '%s\n' "/tmp/fake-jq"; exit 0 ;;
    *"command -v node"*) exit 1 ;;
    *"command -v pnpm"*) printf '%s\n' "/tmp/fake-pnpm"; exit 0 ;;
    *) exit 0 ;;
  esac
fi
if [[ "${1:-}" == "--version" ]]; then
  echo "mise 2099.1.1"
  exit 0
fi
exit 0
SH
chmod +x "$TMP_DIR/bin/mise"

run_expect_fail_contains \
  "core missing rg" \
  "BLOCKED_ENV blocker_class=mise-managed:rg" \
  env PATH="$TMP_DIR/bin:$(script_test_restricted_path)" bash "$ROOT_DIR/scripts/polaris-doctor.sh" --profile core --simulate-no-vscode-path

run_expect_fail_contains \
  "runtime missing node" \
  "BLOCKED_ENV blocker_class=mise-managed:node" \
  env PATH="$TMP_DIR/bin:$(script_test_restricted_path)" bash "$ROOT_DIR/scripts/polaris-doctor.sh" --profile runtime

run_expect_fail_contains \
  "delivery missing gh" \
  "BLOCKED_ENV blocker_class=gh-missing" \
  env PATH="$TMP_DIR/bin:$(script_test_restricted_path)" bash "$ROOT_DIR/scripts/polaris-doctor.sh" --profile delivery

cat >"$TMP_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 1
fi
exit 0
SH
chmod +x "$TMP_DIR/bin/gh"
run_expect_fail_contains \
  "delivery gh unauth" \
  "BLOCKED_ENV blocker_class=gh-unauth" \
  env PATH="$TMP_DIR/bin:$(script_test_restricted_path)" bash "$ROOT_DIR/scripts/polaris-doctor.sh" --profile delivery

echo "polaris-doctor-selftest PASS"
