#!/usr/bin/env bash
# Purpose: prove check-delivery-completion runs the aggregate selftest corpus
# before declaring completion, and fails closed on a red corpus.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/check-delivery-completion.sh"
TMP="$(mktemp -d -t completion-corpus.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "[completion-gate-integration-corpus-selftest] FAIL: $*" >&2
  exit 1
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo/scripts/selftests"
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Polaris Selftest"
  git -C "$repo" config user.email "polaris-selftest@example.com"
  cat >"$repo/scripts/run-aggregate-selftests.sh" <<'SH'
#!/usr/bin/env bash
echo "fixture aggregate runner should be overridden"
exit 99
SH
  cat >"$repo/scripts/selftests/sample-selftest.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$repo/scripts/run-aggregate-selftests.sh" "$repo/scripts/selftests/sample-selftest.sh"
  git -C "$repo" add scripts
  git -C "$repo" commit -q -m "fixture"
}

write_stub_runner() {
  local path="$1"
  local rc="$2"
  cat >"$path" <<SH
#!/usr/bin/env bash
set -euo pipefail
echo "STUB_AGGREGATE_RUNNER rc=$rc root=\${2:-}"
exit $rc
SH
  chmod +x "$path"
}

repo_pass="$TMP/repo-pass"
make_repo "$repo_pass"
pass_runner="$TMP/pass-runner.sh"
write_stub_runner "$pass_runner" 0
pass_out="$(POLARIS_COMPLETION_AGGREGATE_SELFTESTS_BIN="$pass_runner" bash "$CHECK" --repo "$repo_pass" --admin 2>&1)" \
  || fail "admin completion should pass when aggregate corpus passes: $pass_out"
[[ "$pass_out" == *"running aggregate selftest corpus before completion finalize"* ]] \
  || fail "completion gate did not announce aggregate corpus execution"
[[ "$pass_out" == *"STUB_AGGREGATE_RUNNER rc=0"* ]] \
  || fail "completion gate did not invoke aggregate runner override"
[[ "$pass_out" == *"completion gates satisfied"* ]] \
  || fail "completion did not reach satisfied state after green corpus"

repo_fail="$TMP/repo-fail"
make_repo "$repo_fail"
fail_runner="$TMP/fail-runner.sh"
write_stub_runner "$fail_runner" 1
set +e
fail_out="$(POLARIS_COMPLETION_AGGREGATE_SELFTESTS_BIN="$fail_runner" bash "$CHECK" --repo "$repo_fail" --admin 2>&1)"
fail_rc=$?
set -e
[[ "$fail_rc" -eq 2 ]] || fail "red aggregate corpus should exit 2, got $fail_rc: $fail_out"
[[ "$fail_out" == *"STUB_AGGREGATE_RUNNER rc=1"* ]] \
  || fail "red case did not invoke aggregate runner"
[[ "$fail_out" == *"BLOCKED: aggregate selftest corpus failed before completion finalize"* ]] \
  || fail "red case missing fail-closed marker"
[[ "$fail_out" != *"completion gates satisfied"* ]] \
  || fail "completion must not be declared after red aggregate corpus"

repo_skip="$TMP/repo-skip"
mkdir -p "$repo_skip"
git init -q -b main "$repo_skip"
git -C "$repo_skip" config user.name "Polaris Selftest"
git -C "$repo_skip" config user.email "polaris-selftest@example.com"
git -C "$repo_skip" commit --allow-empty -q -m "empty"
skip_out="$(bash "$CHECK" --repo "$repo_skip" --admin 2>&1)" \
  || fail "non-framework repo without runner/corpus should skip: $skip_out"
[[ "$skip_out" == *"aggregate corpus gate skipped"* ]] \
  || fail "missing skip log for repo without framework corpus"

echo "[completion-gate-integration-corpus-selftest] PASS"
