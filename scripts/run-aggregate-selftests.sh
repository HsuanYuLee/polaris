#!/usr/bin/env bash
# Purpose: aggregate selftest runner — enumerate the framework workspace selftest
#          corpus from the filesystem (scripts/selftests/*-selftest.sh +
#          scripts/*-selftest.sh) and execute every one. A head-only red selftest
#          makes the runner exit non-zero. A selftest that is already red on the
#          comparison base is reported as tracked debt and does not block.
# Inputs:  --root <repo>   workspace root (default: repo containing this script)
#          --base-ref <ref> comparison base for red selftests (default:
#                          POLARIS_AGGREGATE_BASE_REF, upstream merge-base, or
#                          origin/main merge-base)
#          --json          emit machine-readable summary JSON to stdout tail
#          --metrics-output <path> write the same reproducible quality metrics JSON
#          --per-test-max-ms <n> fail when one corpus member exceeds the latency budget
#          --list          list enrolled selftest files (one per line) and exit 0
#          POLARIS_SELFTEST_STATE_FILE overrides the durable successful-full-run
#                          state path for hermetic tests; normal runs resolve the
#                          registered main checkout's .polaris runtime directory.
# Outputs: stdout per-selftest PASS/RED/TRACKED_DEBT lines + summary; exit 0 when no
#          head-only red, exit 1 when >=1 head-only red, exit 2 on contract/arg error
#          (fail-closed; AC-NF1, POLARIS_AGGREGATE_SELFTEST_*).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]]; then
  # shellcheck source=lib/main-checkout.sh
  . "$SCRIPT_DIR/lib/main-checkout.sh"
fi
EMIT_JSON=false
LIST_ONLY=false
BASE_REF="${POLARIS_AGGREGATE_BASE_REF:-}"
BASE_WORKTREE=""
METRICS_OUTPUT=""
PER_TEST_MAX_MS="${POLARIS_SELFTEST_MAX_MS:-600000}"
RECORDS_FILE=""
LAST_BASE_EXIT_CODE=""

usage() {
  cat >&2 <<'USAGE'
usage: run-aggregate-selftests.sh [--root <repo>] [--base-ref <ref>] [--json]
                                  [--metrics-output <path>] [--per-test-max-ms <n>] [--list]

Enumerates scripts/selftests/*-selftest.sh + scripts/*-selftest.sh from the
filesystem and runs each. Head-only red selftests => exit 1. Red selftests that
also fail on the comparison base are reported as tracked debt and do not block.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    # Resolve --root without aborting under set -e so a bad path produces the
    # structured NO_ROOT marker below (fail-closed exit 2), not a bare exit 1.
    --root) ROOT_DIR="$(cd "$2" 2>/dev/null && pwd || printf '%s' "$2")"; shift 2 ;;
    --base-ref) BASE_REF="${2:-}"; shift 2 ;;
    --json) EMIT_JSON=true; shift ;;
    --metrics-output) [[ $# -ge 2 ]] || { echo "POLARIS_AGGREGATE_SELFTEST_ARG: --metrics-output requires a value" >&2; exit 2; }; METRICS_OUTPUT="$2"; shift 2 ;;
    --per-test-max-ms) [[ $# -ge 2 ]] || { echo "POLARIS_AGGREGATE_SELFTEST_ARG: --per-test-max-ms requires a value" >&2; exit 2; }; PER_TEST_MAX_MS="$2"; shift 2 ;;
    --list) LIST_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_AGGREGATE_SELFTEST_ARG: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -d "$ROOT_DIR/scripts" ]]; then
  echo "POLARIS_AGGREGATE_SELFTEST_NO_ROOT: scripts/ not found under $ROOT_DIR" >&2
  exit 2
fi
case "$PER_TEST_MAX_MS" in
  ''|*[!0-9]*) echo "POLARIS_AGGREGATE_SELFTEST_BUDGET_ARG: --per-test-max-ms must be a non-negative integer" >&2; exit 2 ;;
esac

# enumerate_selftests — print the enrolled selftest corpus (repo-relative paths,
# sorted, deduplicated) to stdout. Source of truth is the filesystem glob, not a
# manifest, so a brand-new selftest file is enrolled the moment it lands (AC1/AC2).
# Side effects: none (read-only).
enumerate_selftests() {
  {
    find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
    find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
    find "$ROOT_DIR/tests" -maxdepth 1 -type f -name 'test_*.py' 2>/dev/null || true
  } | sed "s#^$ROOT_DIR/##" | LC_ALL=C sort -u
}

resolve_base_ref() {
  if [[ -n "$BASE_REF" ]]; then
    printf '%s\n' "$BASE_REF"
    return 0
  fi

  local upstream=""
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    git -C "$ROOT_DIR" merge-base HEAD "$upstream" 2>/dev/null && return 0
  fi
  git -C "$ROOT_DIR" merge-base HEAD origin/main 2>/dev/null && return 0
  return 1
}

cleanup_base_worktree() {
  if [[ -n "${BASE_WORKTREE:-}" && -d "$BASE_WORKTREE" ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$BASE_WORKTREE" >/dev/null 2>&1 || rm -rf "$BASE_WORKTREE"
  fi
  [[ -z "${RECORDS_FILE:-}" ]] || rm -f "$RECORDS_FILE"
}
trap cleanup_base_worktree EXIT

ensure_base_worktree() {
  if [[ -n "${BASE_WORKTREE:-}" && -d "$BASE_WORKTREE" ]]; then
    return 0
  fi
  local base
  base="$(resolve_base_ref || true)"
  if [[ -z "$base" ]]; then
    return 1
  fi
  BASE_WORKTREE="$(mktemp -d -t aggregate-base.XXXXXX)"
  rm -rf "$BASE_WORKTREE"
  git -C "$ROOT_DIR" worktree add -q --detach "$BASE_WORKTREE" "$base" >/dev/null 2>&1
}

run_selftest_file() {
  local root="$1" rel="$2" log_file="$3"
  case "$rel" in
    tests/test_*.py) (cd "$root" && mise exec -- pytest "$rel" -q) >"$log_file" 2>&1 ;;
    *) bash "$root/$rel" >"$log_file" 2>&1 ;;
  esac
}

resolve_full_run_state_file() {
  if [[ -n "${POLARIS_SELFTEST_STATE_FILE:-}" ]]; then
    printf '%s\n' "$POLARIS_SELFTEST_STATE_FILE"
    return 0
  fi
  local main_checkout=""
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$ROOT_DIR" 2>/dev/null || true)"
  fi
  [[ -n "$main_checkout" ]] || main_checkout="$ROOT_DIR"
  printf '%s/.polaris/runtime/selftest-staleness/last-full-corpus-run.json\n' "$main_checkout"
}

write_full_run_state() {
  local state_file="" head_sha="" at_ts=""
  state_file="$(resolve_full_run_state_file)"
  head_sha="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$head_sha" ]] || {
    echo 'POLARIS_AGGREGATE_SELFTEST_STATE: cannot bind successful full run to HEAD' >&2
    return 2
  }
  at_ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  python3 - "$state_file" "$head_sha" "$at_ts" "$run_duration_ms" "$total" "$green" "$tracked_debt" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

state_file, head_sha, at, duration_ms, total, green, tracked_debt = sys.argv[1:]
target = Path(state_file)
target.parent.mkdir(parents=True, exist_ok=True)
doc = {
    "schema_version": 1,
    "last_full_corpus_run_ts": at,
    "head_sha": head_sha,
    "duration_ms": int(duration_ms),
    "total": int(total),
    "green": int(green),
    "tracked_debt": int(tracked_debt),
}
fd, tmp_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(doc, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_name, target)
except Exception:
    try:
        os.unlink(tmp_name)
    except FileNotFoundError:
        pass
    raise
PY
}

is_tracked_debt() {
  local rel="$1"
  local base_log="$2"
  ensure_base_worktree || return 1
  if [[ ! -f "$BASE_WORKTREE/$rel" ]]; then
    return 1
  fi
  set +e
  run_selftest_file "$BASE_WORKTREE" "$rel" "$base_log"
  local base_rc=$?
  set -e
  if [[ "$base_rc" -eq 0 ]]; then
    return 1
  fi
  LAST_BASE_EXIT_CODE="$base_rc"
  return 0
}

ENROLLED=()
while IFS= read -r _line; do
  [[ -n "$_line" ]] && ENROLLED+=("$_line")
done < <(enumerate_selftests)

if [[ ${#ENROLLED[@]} -eq 0 ]]; then
  echo "POLARIS_AGGREGATE_SELFTEST_EMPTY: no selftests enumerated under $ROOT_DIR" >&2
  exit 2
fi
if [[ "$LIST_ONLY" == true ]]; then
  printf '%s\n' "${ENROLLED[@]}"
  exit 0
fi
command -v python3 >/dev/null 2>&1 || {
  echo 'POLARIS_TOOL_MISSING:python3 — run `mise install` to restore the Polaris runtime toolchain' >&2
  exit 2
}
has_python_tests=false
for rel in "${ENROLLED[@]}"; do
  case "$rel" in
    tests/test_*.py)
      has_python_tests=true
      break
      ;;
  esac
done
if [[ "$has_python_tests" == true ]]; then
  command -v mise >/dev/null 2>&1 || {
    echo 'POLARIS_TOOL_MISSING:mise — run `mise install` to restore the Polaris runtime toolchain' >&2
    exit 2
  }
fi

total=${#ENROLLED[@]}
green=0
red=0
tracked_debt=0
RED_LIST=()
TRACKED_DEBT_LIST=()
RECORDS_FILE="$(mktemp -t aggregate-selftest-metrics.XXXXXX)"
run_started_ms="$(python3 -c 'import time; print(int(time.monotonic() * 1000))')"

for rel in "${ENROLLED[@]}"; do
  log_file="$(mktemp -t aggregate-selftest.XXXXXX)"
  test_started_ms="$(python3 -c 'import time; print(int(time.monotonic() * 1000))')"
  set +e
  run_selftest_file "$ROOT_DIR" "$rel" "$log_file"
  rc=$?
  set -e
  test_finished_ms="$(python3 -c 'import time; print(int(time.monotonic() * 1000))')"
  duration_ms=$((test_finished_ms - test_started_ms))
  if [[ "$rc" -eq 0 && "$duration_ms" -le "$PER_TEST_MAX_MS" ]]; then
    green=$((green + 1))
    printf 'PASS       %s\n' "$rel"
    printf '%s\t%s\t0\t\tgreen\n' "$rel" "$duration_ms" >>"$RECORDS_FILE"
  elif [[ "$rc" -eq 0 ]]; then
    red=$((red + 1))
    RED_LIST+=("$rel")
    printf 'RED        %s (latency %sms > %sms budget)\n' "$rel" "$duration_ms" "$PER_TEST_MAX_MS"
    printf '%s\t%s\t0\t\tlatency_budget_red\n' "$rel" "$duration_ms" >>"$RECORDS_FILE"
  else
    base_log="$(mktemp -t aggregate-base-selftest.XXXXXX)"
    if is_tracked_debt "$rel" "$base_log"; then
      tracked_debt=$((tracked_debt + 1))
      TRACKED_DEBT_LIST+=("$rel")
      printf 'TRACKED_DEBT %s — also red on comparison base\n' "$rel"
      printf '%s\t%s\t%s\t%s\ttracked_debt\n' "$rel" "$duration_ms" "$rc" "$LAST_BASE_EXIT_CODE" >>"$RECORDS_FILE"
    else
      red=$((red + 1))
      RED_LIST+=("$rel")
      printf 'RED        %s (exit %s)\n' "$rel" "$rc"
      printf '  --- tail ---\n'
      tail -n 8 "$log_file" | sed 's/^/  /'
      printf '%s\t%s\t%s\t\thead_red\n' "$rel" "$duration_ms" "$rc" >>"$RECORDS_FILE"
    fi
    rm -f "$base_log"
  fi
  rm -f "$log_file"
done
run_finished_ms="$(python3 -c 'import time; print(int(time.monotonic() * 1000))')"
run_duration_ms=$((run_finished_ms - run_started_ms))

echo ""
echo "=== Aggregate selftest summary ==="
printf 'total=%s green=%s red=%s tracked_debt=%s\n' "$total" "$green" "$red" "$tracked_debt"
printf 'duration_ms=%s per_test_max_ms=%s\n' "$run_duration_ms" "$PER_TEST_MAX_MS"

if [[ ${#TRACKED_DEBT_LIST[@]} -gt 0 ]]; then
  echo "--- tracked debt (red on comparison base; reported, not blocking) ---"
  for d in "${TRACKED_DEBT_LIST[@]}"; do
    printf '  %s\n' "$d"
  done
fi

if [[ ${#RED_LIST[@]} -gt 0 ]]; then
  echo "--- red selftests ---"
  for r in "${RED_LIST[@]}"; do
    printf '  %s\n' "$r"
  done
fi

if [[ "$EMIT_JSON" == true || -n "$METRICS_OUTPUT" ]]; then
  metrics_tmp="$(mktemp -t aggregate-selftest-summary.XXXXXX)"
  python3 - "$ROOT_DIR" "$RECORDS_FILE" "$run_duration_ms" "$PER_TEST_MAX_MS" "$metrics_tmp" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

root, records_path, duration_ms, max_ms, output = sys.argv[1:]
head = subprocess.run(
    ["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True, check=False
).stdout.strip()
per_test = []
tracked_debt = []
red_files = []
route_backs = []
for line in Path(records_path).read_text(encoding="utf-8").splitlines():
    path, elapsed, head_rc, base_rc, disposition = (line.split("\t") + [""] * 5)[:5]
    item = {
        "path": path,
        "duration_ms": int(elapsed),
        "exit_code": int(head_rc),
        "disposition": disposition,
    }
    per_test.append(item)
    if disposition == "tracked_debt":
        debt = {
            "path": path,
            "reproducer": (f"mise exec -- pytest {path} -q" if path.startswith("tests/") else f"bash {path}"),
            "head_exit_code": int(head_rc),
            "base_exit_code": int(base_rc),
        }
        tracked_debt.append(debt)
        route_backs.append(
            {
                "path": path,
                "owner": "current-head-gap-disposition",
                "reason": "red on comparison base; requires explicit current-head disposition",
                "reproducer": debt["reproducer"],
            }
        )
    elif disposition != "green":
        red_files.append(path)
doc = {
    "schema_version": 1,
    "head_sha": head,
    "duration_ms": int(duration_ms),
    "per_test_max_ms": int(max_ms),
    "total": len(per_test),
    "green": sum(item["disposition"] == "green" for item in per_test),
    "red": len(red_files),
    "red_files": red_files,
    "tracked_debt_count": len(tracked_debt),
    "tracked_debt": tracked_debt,
    "false_positive_reproducers": [],
    "route_backs": route_backs,
    "per_test": per_test,
}
Path(output).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if [[ -n "$METRICS_OUTPUT" ]]; then
    mkdir -p "$(dirname "$METRICS_OUTPUT")"
    cp "$metrics_tmp" "$METRICS_OUTPUT"
  fi
  if [[ "$EMIT_JSON" == true ]]; then
    cat "$metrics_tmp"
  fi
  rm -f "$metrics_tmp"
fi

if [[ "$red" -gt 0 ]]; then
  echo "POLARIS_AGGREGATE_SELFTEST_RED: $red selftest(s) failed" >&2
  exit 1
fi

if ! write_full_run_state; then
  echo 'POLARIS_AGGREGATE_SELFTEST_STATE: successful full run could not refresh durable state' >&2
  exit 2
fi

exit 0
