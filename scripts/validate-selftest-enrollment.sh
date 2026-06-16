#!/usr/bin/env bash
# Purpose: enrollment gate — fail-closed if any selftest file on the filesystem is
#          NOT covered by the aggregate runner (run-aggregate-selftests.sh --list).
#          Source of truth for "is a selftest" is the filesystem (*-selftest.sh),
#          not scripts/manifest.json, so a selftest that exists on disk but is not
#          enrolled in the aggregate runner is caught here (AC2).
# Inputs:  --root <repo>   workspace root (default: repo containing this script)
# Outputs: stdout PASS line; exit 0 when every filesystem selftest is enrolled,
#          exit 2 + POLARIS_SELFTEST_ENROLLMENT_GAP when a selftest is not enrolled
#          (fail-closed; AC-NF1). exit 2 on missing inputs (fail-closed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat >&2 <<'USAGE'
usage: validate-selftest-enrollment.sh [--root <repo>]

Cross-checks every *-selftest.sh on the filesystem against the aggregate runner's
enrolled corpus. Any selftest not enrolled => exit 2 (fail-closed).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_SELFTEST_ENROLLMENT_ARG: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

AGGREGATE_RUNNER="$ROOT_DIR/scripts/run-aggregate-selftests.sh"
if [[ ! -x "$AGGREGATE_RUNNER" && ! -f "$AGGREGATE_RUNNER" ]]; then
  echo "POLARIS_SELFTEST_ENROLLMENT_NO_RUNNER: aggregate runner missing: $AGGREGATE_RUNNER" >&2
  exit 2
fi

# filesystem_selftests — print every selftest file on disk (repo-relative, sorted).
# This is the authoritative "what must be covered" set. Side effects: none.
filesystem_selftests() {
  {
    find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
    find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
  } | sed "s#^$ROOT_DIR/##" | LC_ALL=C sort -u
}

# enrolled_selftests — print the runner's enrolled corpus (repo-relative, sorted).
# Side effects: invokes the aggregate runner in --list mode (read-only).
enrolled_selftests() {
  bash "$AGGREGATE_RUNNER" --root "$ROOT_DIR" --list | LC_ALL=C sort -u
}

fs_file="$(mktemp -t selftest-enroll-fs.XXXXXX)"
enrolled_file="$(mktemp -t selftest-enroll-enrolled.XXXXXX)"
trap 'rm -f "$fs_file" "$enrolled_file"' EXIT

filesystem_selftests >"$fs_file"
enrolled_selftests >"$enrolled_file"

if [[ ! -s "$fs_file" ]]; then
  echo "POLARIS_SELFTEST_ENROLLMENT_EMPTY: no selftests found on filesystem under $ROOT_DIR" >&2
  exit 2
fi

# comm -23: lines only in filesystem (not enrolled) => enrollment gaps.
GAPS=()
while IFS= read -r _gap; do
  [[ -n "$_gap" ]] && GAPS+=("$_gap")
done < <(LC_ALL=C comm -23 "$fs_file" "$enrolled_file")

if [[ ${#GAPS[@]} -gt 0 ]]; then
  echo "POLARIS_SELFTEST_ENROLLMENT_GAP: ${#GAPS[@]} selftest(s) on filesystem not enrolled in aggregate runner:" >&2
  for g in "${GAPS[@]}"; do
    printf '  %s\n' "$g" >&2
  done
  exit 2
fi

fs_count="$(wc -l <"$fs_file" | tr -d '[:space:]')"
echo "PASS: selftest enrollment — all $fs_count filesystem selftests enrolled in aggregate runner"
exit 0
