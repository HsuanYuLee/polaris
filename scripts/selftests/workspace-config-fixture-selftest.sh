#!/usr/bin/env bash
# Selftest for scripts/lib/workspace-config-fixture.sh — DP-230 D36 / AC36.
#
# Covers:
#   Case 1: stage_minimal_workspace_config writes the two-field minimal
#           shape (language: zh-TW + user.github_username).
#   Case 2: validate-spec-primary-doc-authoring-selftest.sh succeeds under
#           POLARIS_WORKSPACE_CONFIG_ROOT=$tmpdir (no language_unset fail).
#   Case 3: validate-dp-plan-authoring-selftest.sh succeeds under
#           POLARIS_WORKSPACE_CONFIG_ROOT=$tmpdir.
#   Case 4: live workspace-config.yaml byte-for-byte unchanged before /
#           after staging (attack: helper clobbers live config).
#   Case 5: misuse — missing arg, missing dir, non-tmp target — all fail
#           with exit code 2 and do not write any file.
#   Case 6: idempotent — calling twice on the same tmpdir produces the
#           same content (re-stage is safe).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT_DIR/scripts/lib/workspace-config-fixture.sh"

if [[ ! -f "$LIB" ]]; then
  echo "not ok lib missing: $LIB" >&2
  exit 1
fi

# Source the helper into this shell.
# shellcheck source=../lib/workspace-config-fixture.sh
. "$LIB"

tmpdir="$(mktemp -d -t workspace-config-fixture.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# --- Case 1: minimal shape ---
case_one_dir="$tmpdir/case-one"
mkdir -p "$case_one_dir"

if ! stage_minimal_workspace_config "$case_one_dir"; then
  echo "not ok stage_minimal_workspace_config failed on valid tmpdir" >&2
  exit 1
fi

written="$case_one_dir/workspace-config.yaml"
if [[ ! -f "$written" ]]; then
  echo "not ok expected file not written: $written" >&2
  exit 1
fi

if ! grep -q '^language: "zh-TW"$' "$written"; then
  echo "not ok language field missing or wrong: $written" >&2
  cat "$written" >&2
  exit 1
fi

if ! grep -qE '^  github_username: ' "$written"; then
  echo "not ok user.github_username field missing: $written" >&2
  cat "$written" >&2
  exit 1
fi

# --- Case 2: validate-spec-primary-doc-authoring-selftest under fixture ---
spec_selftest="$ROOT_DIR/scripts/selftests/validate-spec-primary-doc-authoring-selftest.sh"
if [[ ! -x "$spec_selftest" ]]; then
  echo "not ok dependency selftest missing or not executable: $spec_selftest" >&2
  exit 1
fi

# Re-use the same minimal staged config. The downstream selftests resolve
# workspace-config.yaml via lib/workspace-config-root.sh, which honors the
# POLARIS_WORKSPACE_CONFIG_ROOT env override. That is the deterministic
# escape hatch for fresh checkouts that lack a live workspace-config.yaml.
spec_log="$tmpdir/spec-selftest.out"
if ! POLARIS_WORKSPACE_CONFIG_ROOT="$case_one_dir" \
     bash "$spec_selftest" >"$spec_log" 2>&1; then
  echo "not ok spec primary doc authoring selftest failed under fixture" >&2
  echo "---- selftest output ----" >&2
  cat "$spec_log" >&2
  exit 1
fi

if grep -q 'language_unset' "$spec_log"; then
  echo "not ok spec selftest still emitted language_unset under fixture" >&2
  cat "$spec_log" >&2
  exit 1
fi

# --- Case 3: validate-dp-plan-authoring-selftest under fixture ---
dp_selftest="$ROOT_DIR/scripts/selftests/validate-dp-plan-authoring-selftest.sh"
if [[ ! -x "$dp_selftest" ]]; then
  echo "not ok dependency selftest missing or not executable: $dp_selftest" >&2
  exit 1
fi

dp_log="$tmpdir/dp-selftest.out"
if ! POLARIS_WORKSPACE_CONFIG_ROOT="$case_one_dir" \
     bash "$dp_selftest" >"$dp_log" 2>&1; then
  echo "not ok dp plan authoring selftest failed under fixture" >&2
  echo "---- selftest output ----" >&2
  cat "$dp_log" >&2
  exit 1
fi

if grep -q 'language_unset' "$dp_log"; then
  echo "not ok dp selftest still emitted language_unset under fixture" >&2
  cat "$dp_log" >&2
  exit 1
fi

# --- Case 4: live workspace-config.yaml must not be touched ---
live_config="$ROOT_DIR/workspace-config.yaml"
if [[ -f "$live_config" ]]; then
  pre_sum="$(shasum -a 256 "$live_config" | awk '{print $1}')"

  case_four_dir="$tmpdir/case-four"
  mkdir -p "$case_four_dir"
  stage_minimal_workspace_config "$case_four_dir" >/dev/null

  post_sum="$(shasum -a 256 "$live_config" | awk '{print $1}')"
  if [[ "$pre_sum" != "$post_sum" ]]; then
    echo "not ok live workspace-config.yaml mutated during fixture stage" >&2
    echo "  pre:  $pre_sum" >&2
    echo "  post: $post_sum" >&2
    exit 1
  fi
fi

# --- Case 5: misuse paths must fail closed ---
if stage_minimal_workspace_config 2>/dev/null; then
  echo "not ok missing-arg call unexpectedly succeeded" >&2
  exit 1
fi

if stage_minimal_workspace_config "$tmpdir/does-not-exist" 2>/dev/null; then
  echo "not ok missing-dir call unexpectedly succeeded" >&2
  exit 1
fi

# Refuse non-tmp target. Use the worktree's own scripts/ directory as the
# attack vector; the helper must reject it without writing anything.
non_tmp_target="$ROOT_DIR/scripts/lib"
non_tmp_marker="$non_tmp_target/workspace-config.yaml"
if [[ -e "$non_tmp_marker" ]]; then
  echo "not ok unexpected pre-existing marker: $non_tmp_marker" >&2
  exit 1
fi
if stage_minimal_workspace_config "$non_tmp_target" 2>/dev/null; then
  echo "not ok non-tmp target accepted: $non_tmp_target" >&2
  rm -f "$non_tmp_marker"
  exit 1
fi
if [[ -e "$non_tmp_marker" ]]; then
  echo "not ok non-tmp target wrote workspace-config.yaml: $non_tmp_marker" >&2
  rm -f "$non_tmp_marker"
  exit 1
fi

# --- Case 6: idempotent re-stage ---
case_six_dir="$tmpdir/case-six"
mkdir -p "$case_six_dir"
stage_minimal_workspace_config "$case_six_dir" >/dev/null
first_sum="$(shasum -a 256 "$case_six_dir/workspace-config.yaml" | awk '{print $1}')"
stage_minimal_workspace_config "$case_six_dir" >/dev/null
second_sum="$(shasum -a 256 "$case_six_dir/workspace-config.yaml" | awk '{print $1}')"
if [[ "$first_sum" != "$second_sum" ]]; then
  echo "not ok stage_minimal_workspace_config not idempotent" >&2
  exit 1
fi

echo "PASS: workspace-config-fixture selftest"
