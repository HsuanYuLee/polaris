#!/usr/bin/env bash
set -euo pipefail

# Purpose: DP-325 T5 / AC9 + AC-NF1 — selftest for the full-surface marker
#          source_artifact resolvability detector
#          (scripts/validate-marker-artifact-resolvable.sh). Asserts:
#            - a marker whose frozen path still resolves PASSes;
#            - a marker whose frozen path is gone but carries
#              task_artifact_sha256 + work_item_id re-resolves (task.md moved to
#              pr-release/) and PASSes;
#            - a path-only-and-stale marker (no sha) fails closed with a
#              structured POLARIS_MARKER_ARTIFACT_UNRESOLVABLE marker;
#            - a marker whose re-resolved sha mismatches fails closed.
# Inputs:  none (builds tmp fixture workspace + evidence markers).
# Outputs: TAP-ish lines; exit 0 when all cases pass, 1 otherwise.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$SCRIPT_DIR/validate-marker-artifact-resolvable.sh"
TMPROOT="$(mktemp -d -t marker-resolvable-selftest-XXXXXX)"
PASS=0
TOTAL=0

cleanup() { rm -rf "$TMPROOT"; }
trap cleanup EXIT

assert_rc() {
  local label="$1" got="$2" want="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: got rc=%s want rc=%s\n' "$label" "$got" "$want" >&2
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1)); printf 'ok %s\n' "$label"
  else
    printf 'not ok %s: missing %q\n' "$label" "$needle" >&2
    printf '  output: %s\n' "$haystack" >&2
  fi
}

# Build a hermetic fixture workspace: a DP task.md that lives in pr-release/
# (i.e. it has already moved post-delivery) so the resolver can re-locate it.
build_fixture() {
  local root="$1"
  printf 'language: en\n' > "$root/workspace-config.yaml"
  local tasks="$root/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks"
  mkdir -p "$tasks/pr-release/T1"
  printf 'moved task body\n' > "$tasks/pr-release/T1/index.md"
  mkdir -p "$root/.polaris/evidence/completion-gate" \
           "$root/.polaris/evidence/ac-verification" \
           "$root/.polaris/evidence/task-snapshot"
}

write_marker() {
  # write_marker <out.json> <marker_kind> <work_item_id> <source_artifact> [task_artifact_sha256]
  python3 - "$@" <<'PY'
import json, sys
out, kind, wid, artifact = sys.argv[1:5]
sha = sys.argv[5] if len(sys.argv) > 5 else None
freshness = {"head_sha": "deadbeef", "source_artifact": artifact}
if sha:
    freshness["task_artifact_sha256"] = sha
data = {
    "schema_version": 1,
    "marker_kind": kind,
    "work_item_id": wid,
    "status": "PASS",
    "freshness": freshness,
}
json.dump(data, open(out, "w"))
PY
}

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

ROOT="$TMPROOT/ws"
mkdir -p "$ROOT"
build_fixture "$ROOT"
MOVED="$ROOT/docs-manager/src/content/docs/specs/design-plans/DP-900-fixture/tasks/pr-release/T1/index.md"
MOVED_SHA="$(sha256_of "$MOVED")"
EV="$ROOT/.polaris/evidence"

# Case 1: frozen path still resolves (points at the live moved file) → PASS.
write_marker "$EV/completion-gate/DP-900-T1-deadbeef.json" completion_gate DP-900-T1 "$MOVED" "$MOVED_SHA"

rc=0; out="$(bash "$DETECTOR" --repo "$ROOT" 2>&1)" || rc=$?
assert_rc "case1: frozen path resolves -> PASS" "$rc" "0"

# Case 2: frozen path gone but sha+work_item_id re-resolves (task moved) → PASS.
rm -f "$EV/completion-gate/DP-900-T1-deadbeef.json"
write_marker "$EV/ac-verification/DP-900-T1-deadbeef.json" ac_verification DP-900-T1 \
  "/gone/old/tasks/T1/index.md" "$MOVED_SHA"
rc=0; out="$(bash "$DETECTOR" --repo "$ROOT" 2>&1)" || rc=$?
assert_rc "case2: re-resolvable moved task.md -> PASS" "$rc" "0"

# Case 3: path-only-and-stale (no sha) → fail closed + POLARIS marker.
write_marker "$EV/task-snapshot/DP-900-T2.json" task_snapshot DP-900-T2 \
  "/gone/old/tasks/T2/index.md"
rc=0; out="$(bash "$DETECTOR" --repo "$ROOT" 2>&1)" || rc=$?
assert_rc "case3: path-only-stale -> exit 2" "$rc" "2"
assert_contains "case3: structured POLARIS marker" "$out" "POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:"

# Case 4: re-resolved artifact sha mismatch → fail closed.
rm -f "$EV/task-snapshot/DP-900-T2.json"
rm -f "$EV/ac-verification/DP-900-T1-deadbeef.json"
write_marker "$EV/completion-gate/DP-900-T1-deadbeef.json" completion_gate DP-900-T1 \
  "/gone/old/tasks/T1/index.md" "0000000000000000000000000000000000000000000000000000000000000000"
rc=0; out="$(bash "$DETECTOR" --repo "$ROOT" 2>&1)" || rc=$?
assert_rc "case4: relocated sha mismatch -> exit 2" "$rc" "2"
assert_contains "case4: sha mismatch reason" "$out" "POLARIS_MARKER_ARTIFACT_UNRESOLVABLE:"

# Case 5: clean workspace with only resolvable markers → PASS (regression guard).
rm -f "$EV/completion-gate/DP-900-T1-deadbeef.json"
write_marker "$EV/task-snapshot/DP-900-T1.json" task_snapshot DP-900-T1 "$MOVED" "$MOVED_SHA"
rc=0; out="$(bash "$DETECTOR" --repo "$ROOT" 2>&1)" || rc=$?
assert_rc "case5: all resolvable -> PASS" "$rc" "0"
assert_contains "case5: PASS summary" "$out" "PASS:"

printf '\n%s/%s checks passed\n' "$PASS" "$TOTAL"
[[ "$PASS" == "$TOTAL" ]]
