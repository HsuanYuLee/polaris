#!/usr/bin/env bash
# Selftest for DP-035 handbook config reader / validator contract.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/scripts/fixtures/handbook-config"
READER="$ROOT_DIR/scripts/handbook-config-reader.sh"
VALIDATOR="$ROOT_DIR/scripts/handbook-config-validator.sh"

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_fails() {
  local name="$1"
  shift
  if "$@" >/tmp/handbook-config-selftest.out 2>/tmp/handbook-config-selftest.err; then
    echo "FAIL: $name unexpectedly passed" >&2
    cat /tmp/handbook-config-selftest.out >&2 || true
    cat /tmp/handbook-config-selftest.err >&2 || true
    exit 1
  fi
}

valid_config="$FIXTURE_DIR/valid-company/polaris-config/web/handbook/config.yaml"
valid_workspace="$FIXTURE_DIR/valid-company/workspace.fixture.yaml"
conflict_config="$FIXTURE_DIR/conflict-company/polaris-config/web/handbook/config.yaml"
conflict_workspace="$FIXTURE_DIR/conflict-company/workspace.fixture.yaml"
b2c_config="$FIXTURE_DIR/kkday-b2c-web/polaris-config/kkday-b2c-web/handbook/config.yaml"
b2c_workspace="$FIXTURE_DIR/kkday-b2c-web/workspace.fixture.yaml"
start_env_workspace="$FIXTURE_DIR/start-test-env-company/workspace.fixture.yaml"
missing_runtime="$FIXTURE_DIR/missing-runtime.yaml"
bad_version="$FIXTURE_DIR/unsupported-version.yaml"
malformed="$FIXTURE_DIR/malformed.yaml"

health_check="$("$READER" --config "$valid_config" --field runtime.health_check | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
assert_eq "reader emits selected field" "$health_check" "https://dev.example.test/health"

"$VALIDATOR" --config "$valid_config" --project web --workspace-config "$valid_workspace" --require-section runtime --require-section test --check-conflicts >/tmp/handbook-config-selftest.valid.out
if ! rg -q "PASS: handbook config valid" /tmp/handbook-config-selftest.valid.out; then
  echo "FAIL: valid fixture did not print PASS" >&2
  cat /tmp/handbook-config-selftest.valid.out >&2
  exit 1
fi

assert_fails "missing runtime section" "$VALIDATOR" --config "$missing_runtime" --require-section runtime
assert_fails "unsupported schema version" "$VALIDATOR" --config "$bad_version"
assert_fails "malformed yaml" "$VALIDATOR" --config "$malformed"
assert_fails "workspace-config conflict" "$VALIDATOR" --config "$conflict_config" --project web --workspace-config "$conflict_workspace" --check-conflicts
assert_fails "kkday-b2c-web health-check drift" "$VALIDATOR" --config "$b2c_config" --project kkday-b2c-web --workspace-config "$b2c_workspace" --check-conflicts

if ! "$VALIDATOR" --config "$conflict_config" --project web --workspace-config "$conflict_workspace" --check-conflicts >/tmp/handbook-config-selftest.conflict.out 2>&1; then
  if ! rg -q "workspace-config conflict" /tmp/handbook-config-selftest.conflict.out; then
    echo "FAIL: conflict output missing expected marker" >&2
    cat /tmp/handbook-config-selftest.conflict.out >&2
    exit 1
  fi
fi

b2c_health_check="$("$READER" --config "$b2c_config" --field runtime.health_check | python3 -c 'import json,sys; print(json.load(sys.stdin))')"
assert_eq "b2c reviewed config health check" "$b2c_health_check" "https://dev.kkday.com/zh-tw"

"$VALIDATOR" --config "$b2c_config" --project kkday-b2c-web --require-section runtime --require-section test >/tmp/handbook-config-selftest.b2c.out
if ! rg -q "PASS: handbook config valid" /tmp/handbook-config-selftest.b2c.out; then
  echo "FAIL: b2c fixture did not print PASS" >&2
  cat /tmp/handbook-config-selftest.b2c.out >&2
  exit 1
fi

if ! "$VALIDATOR" --config "$b2c_config" --project kkday-b2c-web --workspace-config "$b2c_workspace" --check-conflicts >/tmp/handbook-config-selftest.b2c-conflict.out 2>&1; then
  if ! rg -q "runtime.health_check" /tmp/handbook-config-selftest.b2c-conflict.out; then
    echo "FAIL: b2c conflict output missing health_check marker" >&2
    cat /tmp/handbook-config-selftest.b2c-conflict.out >&2
    exit 1
  fi
fi

handbook_source="$(bash "$ROOT_DIR/scripts/start-test-env.sh" --project handbook-web --workspace-config "$start_env_workspace" --resolve-config-only | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
assert_eq "start-test-env handbook source" "$handbook_source" "handbook_config"

handbook_start="$(bash "$ROOT_DIR/scripts/start-test-env.sh" --project handbook-web --workspace-config "$start_env_workspace" --resolve-config-only | python3 -c 'import json,sys; print(json.load(sys.stdin)["dev_environment"]["start_command"])')"
assert_eq "start-test-env handbook start command" "$handbook_start" "echo handbook-start"

fallback_source="$(bash "$ROOT_DIR/scripts/start-test-env.sh" --project legacy-only --workspace-config "$start_env_workspace" --resolve-config-only | python3 -c 'import json,sys; print(json.load(sys.stdin)["source"])')"
assert_eq "start-test-env fallback source" "$fallback_source" "workspace_config_fallback"

assert_fails "start-test-env conflict fails loud" bash "$ROOT_DIR/scripts/start-test-env.sh" --project conflict-web --workspace-config "$start_env_workspace" --resolve-config-only

echo "PASS: handbook config selftest"
