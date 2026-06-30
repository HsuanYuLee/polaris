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
#          --list          list enrolled selftest files (one per line) and exit 0
# Outputs: stdout per-selftest PASS/RED/TRACKED_DEBT lines + summary; exit 0 when no
#          head-only red, exit 1 when >=1 head-only red, exit 2 on contract/arg error
#          (fail-closed; AC-NF1, POLARIS_AGGREGATE_SELFTEST_*).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EMIT_JSON=false
LIST_ONLY=false
BASE_REF="${POLARIS_AGGREGATE_BASE_REF:-}"
BASE_WORKTREE=""

usage() {
  cat >&2 <<'USAGE'
usage: run-aggregate-selftests.sh [--root <repo>] [--base-ref <ref>] [--json] [--list]

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
    --list) LIST_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "POLARIS_AGGREGATE_SELFTEST_ARG: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -d "$ROOT_DIR/scripts" ]]; then
  echo "POLARIS_AGGREGATE_SELFTEST_NO_ROOT: scripts/ not found under $ROOT_DIR" >&2
  exit 2
fi

# enumerate_selftests — print the enrolled selftest corpus (repo-relative paths,
# sorted, deduplicated) to stdout. Source of truth is the filesystem glob, not a
# manifest, so a brand-new selftest file is enrolled the moment it lands (AC1/AC2).
# Side effects: none (read-only).
enumerate_selftests() {
  {
    find "$ROOT_DIR/scripts/selftests" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
    find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name '*-selftest.sh' 2>/dev/null || true
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
  bash "$root/$rel" >"$log_file" 2>&1
}

is_tracked_debt() {
  local rel="$1"
  local base_log="$2"
  ensure_base_worktree || return 1
  if [[ ! -f "$BASE_WORKTREE/$rel" ]]; then
    return 1
  fi
  if run_selftest_file "$BASE_WORKTREE" "$rel" "$base_log"; then
    return 1
  fi
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

total=${#ENROLLED[@]}
green=0
red=0
tracked_debt=0
RED_LIST=()
TRACKED_DEBT_LIST=()

for rel in "${ENROLLED[@]}"; do
  log_file="$(mktemp -t aggregate-selftest.XXXXXX)"
  if run_selftest_file "$ROOT_DIR" "$rel" "$log_file"; then
    green=$((green + 1))
    printf 'PASS       %s\n' "$rel"
  else
    rc=$?
    base_log="$(mktemp -t aggregate-base-selftest.XXXXXX)"
    if is_tracked_debt "$rel" "$base_log"; then
      tracked_debt=$((tracked_debt + 1))
      TRACKED_DEBT_LIST+=("$rel")
      printf 'TRACKED_DEBT %s — also red on comparison base\n' "$rel"
    else
      red=$((red + 1))
      RED_LIST+=("$rel")
      printf 'RED        %s (exit %s)\n' "$rel" "$rc"
      printf '  --- tail ---\n'
      tail -n 8 "$log_file" | sed 's/^/  /'
    fi
    rm -f "$base_log"
  fi
  rm -f "$log_file"
done

echo ""
echo "=== Aggregate selftest summary ==="
printf 'total=%s green=%s red=%s tracked_debt=%s\n' "$total" "$green" "$red" "$tracked_debt"

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

if [[ "$EMIT_JSON" == true ]]; then
  printf '{"total":%s,"green":%s,"red":%s,"tracked_debt":%s,"red_files":[' \
    "$total" "$green" "$red" "$tracked_debt"
  if [[ ${#RED_LIST[@]} -gt 0 ]]; then
    for i in "${!RED_LIST[@]}"; do
      [[ $i -gt 0 ]] && printf ','
      printf '"%s"' "${RED_LIST[$i]}"
    done
  fi
  printf '],"tracked_debt_files":['
  if [[ ${#TRACKED_DEBT_LIST[@]} -gt 0 ]]; then
    for i in "${!TRACKED_DEBT_LIST[@]}"; do
      [[ $i -gt 0 ]] && printf ','
      printf '"%s"' "${TRACKED_DEBT_LIST[$i]}"
    done
  fi
  printf ']}\n'
fi

if [[ "$red" -gt 0 ]]; then
  echo "POLARIS_AGGREGATE_SELFTEST_RED: $red selftest(s) failed" >&2
  exit 1
fi

exit 0
