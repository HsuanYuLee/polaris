#!/usr/bin/env bash
# Purpose: DP-419 T4 selftest — exercise the framework-release-pr-lane.sh promotion-後 tail
#          self-referential-window guard (release_lane_selfref_tail_guard) through its hidden
#          --selfref-tail-guard test seam. Asserts:
#            AC4      self-ref Allowed Files + green corpus stub  -> exit 0  (proceed)
#            AC-NF1   self-ref Allowed Files + red corpus stub    -> exit 1  (hard-block)
#            non-self-ref Allowed Files (+ red corpus stub)       -> exit 10 (carve-out N/A,
#                     corpus NOT consulted, so a red stub must not block)
#            undeterminable (zero Allowed Files)                  -> exit 10 (carve-out N/A)
# Inputs:  none (locates the lane + real classifier from repo root; stubs the corpus via
#          POLARIS_AGGREGATE_SELFTESTS_BIN).
# Outputs: PASS line on success; non-zero FAIL on regression.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="$ROOT/scripts/framework-release-pr-lane.sh"
DETECT="$ROOT/scripts/detect-self-referential-delivery.sh"

[[ -f "$LANE" ]] || { echo "FAIL: lane not found: $LANE" >&2; exit 1; }
[[ -f "$DETECT" ]] || { echo "FAIL: classifier not found: $DETECT" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GREEN_STUB="$WORK/corpus-green.sh"
RED_STUB="$WORK/corpus-red.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$GREEN_STUB"
printf '#!/usr/bin/env bash\nexit 1\n' >"$RED_STUB"
chmod +x "$GREEN_STUB" "$RED_STUB"

# A path that genuinely lives in the delivery-gate script set (the lane itself) -> self-referential.
SELFREF_FILE="scripts/framework-release-pr-lane.sh"
# A path that is not a delivery-gate script -> not self-referential.
NON_SELFREF_FILE="README.md"

# run_guard <corpus_stub> <allowed-file...> ; prints nothing, returns the seam exit code.
run_guard() {
  local corpus="$1"; shift
  local -a args=(--selfref-tail-guard --repo-root "$ROOT")
  local af
  for af in "$@"; do
    args+=(--allowed-file "$af")
  done
  set +e
  POLARIS_DETECT_SELFREF_BIN="$DETECT" \
    POLARIS_AGGREGATE_SELFTESTS_BIN="$corpus" \
    bash "$LANE" "${args[@]}" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

fail=0

# AC4: self-referential + green corpus -> proceed (exit 0).
rc="$(run_guard "$GREEN_STUB" "$SELFREF_FILE")"
if [[ "$rc" != "0" ]]; then
  echo "FAIL AC4: self-ref + green corpus expected exit 0, got $rc" >&2; fail=1
fi

# AC-NF1: self-referential + red corpus -> hard-block (exit 1).
rc="$(run_guard "$RED_STUB" "$SELFREF_FILE")"
if [[ "$rc" != "1" ]]; then
  echo "FAIL AC-NF1: self-ref + red corpus expected exit 1 (fail-closed), got $rc" >&2; fail=1
fi

# non-self-ref carve-out: not self-referential -> exit 10, and the (red) corpus must NOT be
# consulted (proving the guard does not hard-block a non-self-referential release).
rc="$(run_guard "$RED_STUB" "$NON_SELFREF_FILE")"
if [[ "$rc" != "10" ]]; then
  echo "FAIL non-self-ref: expected exit 10 (carve-out N/A, corpus not consulted), got $rc" >&2; fail=1
fi

# undeterminable carve-out: zero Allowed Files -> exit 10.
rc="$(run_guard "$RED_STUB")"
if [[ "$rc" != "10" ]]; then
  echo "FAIL undeterminable: zero Allowed Files expected exit 10, got $rc" >&2; fail=1
fi

[[ "$fail" -eq 0 ]] || exit 1
echo "[selftest] framework-release-tail-self-verify PASS"
