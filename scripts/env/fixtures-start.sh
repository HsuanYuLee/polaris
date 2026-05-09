#!/usr/bin/env bash
# scripts/env/fixtures-start.sh — D11 L2 primitive.
#
# Starts a fixture server (Mockoon today; the abstraction lets us swap the
# tooling without touching callers). Receives a directory path; the L3
# orchestrator is responsible for resolving the path from task.md or
# workspace-config.yaml.
#
# Usage:
#   fixtures-start.sh FIXTURE_DIR [--epic EPIC] [--proxy] [--type mockoon]
#
# Exit codes:
#   0  Fixture server started (per the underlying tool)
#   1  Tool reported failure / FIXTURE_DIR contains no fixture files
#   2  Usage error or missing FIXTURE_DIR
#
# Stdout: "PASS fixtures up via {tool} at {dir}" on success.
# Stderr: tool stderr passes through.
#
# Composable: mockoon-runner.sh internally tracks PIDs; the corresponding stop
# is `mockoon-runner.sh stop` (a future fixtures-stop.sh primitive will wrap
# it). For now callers stop via mockoon-runner.sh directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

DEFAULT_MOCKOON_RUNNER="${POLARIS_MOCKOON_RUNNER_OVERRIDE:-$(cd "$SCRIPT_DIR/../mockoon" 2>/dev/null && pwd)/mockoon-runner.sh}"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") FIXTURE_DIR [--epic EPIC] [--proxy] [--type mockoon]

Wraps the fixture tool (today: mockoon-runner.sh) for D11 composability.

Exit:  0 = started, 1 = tool failure / empty dir, 2 = usage / missing dir.
EOF
}

# ── Args ────────────────────────────────────────────────────────────────────
FIXTURE_DIR=""
EPIC=""
PROXY=""
TYPE="mockoon"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --epic) EPIC="${2:-}"; shift 2 ;;
    --proxy) PROXY="--proxy"; shift ;;
    --type) TYPE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) env_lib_log_fail "unknown flag: $1"; usage; exit 2 ;;
    *)
      if [[ -z "$FIXTURE_DIR" ]]; then FIXTURE_DIR="$1"; else
        env_lib_log_fail "unexpected positional arg: $1"; usage; exit 2
      fi
      shift ;;
  esac
done

if [[ -z "$FIXTURE_DIR" ]]; then
  env_lib_log_fail "FIXTURE_DIR is required"; usage; exit 2
fi

FIXTURE_DIR="$(env_lib_expand_path "$FIXTURE_DIR")"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  env_lib_log_fail "FIXTURE_DIR does not exist: $FIXTURE_DIR"
  exit 2
fi

resolve_mockoon_runner() {
  local runner=""
  local cfg_path=""
  local hint=""

  cfg_path="$(env_lib_find_workspace_config "$PWD" 2>/dev/null || true)"
  if [[ -n "$cfg_path" ]]; then
    cfg_json="$(env_lib_parse_yaml "$cfg_path" 2>/dev/null || echo '{}')"
    runner="$(printf '%s' "$cfg_json" | env_lib_get_field 'visual_regression.domains[0].fixtures.runner' 2>/dev/null || true)"
  else
    hint="$(env_lib_workspace_config_resolution_hint "$PWD" 2>/dev/null || true)"
    if [[ -n "$hint" ]]; then
      env_lib_log_info "mockoon runner override skipped: $hint"
      env_lib_log_info "falling back to framework default mockoon runner"
    fi
  fi

  if [[ -z "$runner" ]]; then
    runner="$DEFAULT_MOCKOON_RUNNER"
  fi

  env_lib_expand_path "$runner"
}

# ── Tool dispatch ───────────────────────────────────────────────────────────
case "$TYPE" in
  mockoon)
    # Resolve mockoon-runner from workspace-config (preferred) so a re-skinned
    # workspace can override the path. If company routing cannot be resolved,
    # this consumer stays soft: it logs the skipped override and falls back to
    # the framework default runner instead of blocking tracked workflow.
    runner="$(resolve_mockoon_runner)"
    if [[ ! -x "$runner" ]]; then
      env_lib_log_fail "mockoon runner not found or not executable: $runner"
      exit 1
    fi

    # Sanity: dir must contain at least one *.json (or {epic}/*.json)
    probe_dir="$FIXTURE_DIR"
    [[ -n "$EPIC" ]] && probe_dir="$FIXTURE_DIR/$EPIC"
    if ! compgen -G "$probe_dir/*.json" > /dev/null; then
      env_lib_log_fail "no Mockoon environment files (*.json) under $probe_dir"
      exit 1
    fi

    args=("start" "$FIXTURE_DIR")
    [[ -n "$EPIC" ]] && args+=("--epic" "$EPIC")
    [[ -n "$PROXY" ]] && args+=("$PROXY")
    if "$runner" "${args[@]}"; then
      env_lib_log_pass "fixtures up via mockoon at $probe_dir"
      echo "PASS fixtures up via mockoon at $probe_dir"
      exit 0
    else
      rc=$?
      env_lib_log_fail "mockoon-runner exited $rc at $probe_dir"
      exit 1
    fi
    ;;
  *)
    env_lib_log_fail "unsupported fixture type: $TYPE (supported: mockoon)"
    exit 2
    ;;
esac
