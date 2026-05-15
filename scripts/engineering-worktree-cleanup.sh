#!/usr/bin/env bash
# scripts/engineering-worktree-cleanup.sh
#
# Inventory and cleanup helper for one-shot Polaris worktrees. The helper is
# deliberately conservative: apply mode only removes registered, clean,
# source-identifiable worktrees inside managed locations.

set -euo pipefail

PREFIX="[engineering-worktree-cleanup]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELFTEST_TMP=""
LIVE_PIDS=()

usage() {
  cat >&2 <<'EOF'
Usage:
  engineering-worktree-cleanup.sh [--repo <path>] [--identity <id>] [--worktree <path>] [--dry-run|--apply] [--include-temp]
  engineering-worktree-cleanup.sh --self-test

Options:
  --repo <path>       Any checkout/worktree of the target repo (default: cwd)
  --identity <id>     Task/source identity used to select source-owned worktrees
  --worktree <path>   Explicit path to inspect/clean
  --dry-run           Classify candidates without removal (default)
  --apply             Remove safe candidates; unsafe candidates block with exit 2
  --include-temp      Allow registered /private/tmp/polaris-* worktrees when safe
  --self-test         Run local fixture self-test
EOF
}

canonical_path() {
  local path="$1"
  python3 - "$path" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

shell_quote() {
  python3 - "$1" <<'PY'
import shlex
import sys
print(shlex.quote(sys.argv[1]))
PY
}

repo_root() {
  local repo="$1"
  git -C "$repo" rev-parse --show-toplevel 2>/dev/null
}

main_checkout_path() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain | awk '
    /^worktree / {
      print substr($0, 10)
      exit
    }
  '
}

worktree_branch_for_path() {
  local repo="$1"
  local target="$2"
  git -C "$repo" worktree list --porcelain | awk -v target="$target" '
    /^worktree / { wt = substr($0, 10); branch = ""; detached = 0; next }
    /^branch / { branch = substr($0, 8); next }
    /^detached$/ { detached = 1; next }
    /^$/ {
      if (wt == target) {
        if (branch != "") print branch
        else if (detached) print "detached"
        printed = 1
        exit
      }
    }
    END {
      if (!printed && wt == target) {
        if (branch != "") print branch
        else if (detached) print "detached"
      }
    }
  '
}

is_registered_worktree() {
  local repo="$1"
  local target="$2"
  git -C "$repo" worktree list --porcelain | awk -v target="$target" '
    /^worktree / {
      if (substr($0, 10) == target) {
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

identity_matches() {
  local identity="$1"
  local path="$2"
  local branch="$3"
  [[ -n "$identity" ]] || return 1
  [[ "$path" == *"$identity"* || "$branch" == *"$identity"* ]]
}

managed_temp_path() {
  local path="$1"
  [[ "$path" == /private/tmp/polaris-* || "$path" == /tmp/polaris-* ]]
}

managed_worktree_path() {
  local path="$1"
  [[ "$path" == *"/.worktrees/"* ]]
}

live_process_pids() {
  local path="$1"
  local pid ancestors
  command -v lsof >/dev/null 2>&1 || return 0
  ancestors=" $$ "
  pid="$$"
  while pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"; do
    [[ -n "$pid" && "$pid" != "0" ]] || break
    ancestors="${ancestors}${pid} "
  done
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case "$ancestors" in
      *" ${pid} "*) continue ;;
    esac
    printf '%s\n' "$pid"
  done < <(lsof -t +D "$path" 2>/dev/null | sort -u || true)
}

emit_line() {
  local state="$1"
  local action="$2"
  local reason="$3"
  local path="$4"
  local branch="$5"
  printf '%s action=%s reason=%s path=%s branch=%s\n' \
    "$state" "$action" "$reason" "$(shell_quote "$path")" "$(shell_quote "${branch:-unknown}")"
}

classify_one() {
  local repo="$1"
  local main_checkout="$2"
  local path="$3"
  local identity="$4"
  local explicit="$5"
  local include_temp="$6"
  local canonical branch pids

  canonical="$(canonical_path "$path")"
  branch="$(worktree_branch_for_path "$repo" "$canonical" || true)"

  if [[ -n "$identity" && "$explicit" != "true" ]]; then
    if ! identity_matches "$identity" "$canonical" "$branch"; then
      return 20
    fi
  fi

  if [[ "$canonical" == "$main_checkout" ]]; then
    emit_line "BLOCKED" "keep" "main_checkout" "$canonical" "$branch"
    return 10
  fi

  if ! is_registered_worktree "$repo" "$canonical"; then
    emit_line "BLOCKED" "keep" "unregistered_path" "$canonical" "$branch"
    return 10
  fi

  if [[ ! -d "$canonical" ]]; then
    emit_line "BLOCKED" "keep" "missing_path" "$canonical" "$branch"
    return 10
  fi

  if ! managed_worktree_path "$canonical"; then
    if managed_temp_path "$canonical"; then
      if [[ "$include_temp" != "true" ]]; then
        emit_line "BLOCKED" "keep" "temp_requires_include_temp" "$canonical" "$branch"
        return 10
      fi
    else
      emit_line "BLOCKED" "keep" "outside_managed_path" "$canonical" "$branch"
      return 10
    fi
  fi

  if [[ -n "$identity" ]]; then
    if ! identity_matches "$identity" "$canonical" "$branch"; then
      emit_line "BLOCKED" "keep" "identity_mismatch" "$canonical" "$branch"
      return 10
    fi
  fi

  if [[ -n "$(git -C "$canonical" status --porcelain)" ]]; then
    emit_line "BLOCKED" "keep" "dirty" "$canonical" "$branch"
    return 10
  fi

  pids="$(live_process_pids "$canonical")"
  if [[ -n "$pids" ]]; then
    emit_line "BLOCKED" "keep" "live_process" "$canonical" "$branch"
    return 10
  fi

  if [[ -z "$identity" ]]; then
    emit_line "BLOCKED" "keep" "source_unknown" "$canonical" "$branch"
    return 10
  fi

  emit_line "SAFE" "remove" "clean_registered" "$canonical" "$branch"
  return 0
}

candidate_paths() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }'
}

self_test() {
  local tmp remote main helper out rc wt pid
  local pass=0 total=0
  helper="${SCRIPT_DIR}/engineering-worktree-cleanup.sh"
  tmp="$(mktemp -d)"
  SELFTEST_TMP="$tmp"
  trap 'for p in "${LIVE_PIDS[@]:-}"; do kill "$p" >/dev/null 2>&1 || true; done; rm -rf "$SELFTEST_TMP"' EXIT

  assert_eq() {
    total=$((total + 1))
    if [[ "$1" == "$2" ]]; then
      pass=$((pass + 1))
    else
      echo "FAIL: $3 expected=$2 got=$1" >&2
      return 1
    fi
  }

  remote="${tmp}/remote.git"
  main="${tmp}/repo"
  git init --bare "$remote" >/dev/null
  git clone "$remote" "$main" >/dev/null 2>&1
  git -C "$main" checkout -b main >/dev/null 2>&1
  echo init >"${main}/file.txt"
  git -C "$main" add file.txt
  git -C "$main" commit -m init >/dev/null
  git -C "$main" push -u origin main >/dev/null 2>&1

  mkdir -p "${main}/.worktrees"
  git -C "$main" branch task/TEST-1-clean main
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-1" task/TEST-1-clean >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-1"
  out="$(bash "$helper" --repo "$main" --identity TEST-1 --dry-run)"
  grep -q "SAFE action=remove reason=clean_registered" <<<"$out"
  assert_eq "$?" "0" "clean registered dry-run"
  bash "$helper" --repo "$main" --identity TEST-1 --apply >/dev/null
  [[ ! -d "$wt" ]]
  assert_eq "$?" "0" "clean registered apply removes path"

  git -C "$main" branch task/TEST-2-dirty main
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-2" task/TEST-2-dirty >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-2"
  echo dirty >"${wt}/dirty.txt"
  if bash "$helper" --repo "$main" --identity TEST-2 --apply >/tmp/polaris-cleanup-selftest.out 2>&1; then
    echo "FAIL: dirty worktree should block" >&2
    return 1
  fi
  grep -q "reason=dirty" /tmp/polaris-cleanup-selftest.out
  assert_eq "$?" "0" "dirty worktree blocks"
  [[ -d "$wt" ]]
  assert_eq "$?" "0" "dirty worktree remains"

  if bash "$helper" --repo "$main" --identity TEST-MAIN --worktree "$main" --apply >/tmp/polaris-cleanup-selftest.out 2>&1; then
    echo "FAIL: main checkout should block" >&2
    return 1
  fi
  grep -q "reason=main_checkout" /tmp/polaris-cleanup-selftest.out
  assert_eq "$?" "0" "main checkout blocks"

  wt="${main}/.worktrees/unregistered-TEST-3"
  mkdir -p "$wt"
  if bash "$helper" --repo "$main" --identity TEST-3 --worktree "$wt" --apply >/tmp/polaris-cleanup-selftest.out 2>&1; then
    echo "FAIL: unregistered path should block" >&2
    return 1
  fi
  grep -q "reason=unregistered_path" /tmp/polaris-cleanup-selftest.out
  assert_eq "$?" "0" "unregistered path blocks"
  [[ -d "$wt" ]]
  assert_eq "$?" "0" "unregistered path remains"

  git -C "$main" branch task/TEST-TEMP-clean main
  wt="/private/tmp/polaris-cleanup-selftest-${$}-TEST-TEMP"
  git -C "$main" worktree add "$wt" task/TEST-TEMP-clean >/dev/null 2>&1
  out="$(bash "$helper" --repo "$main" --identity TEST-TEMP --include-temp --dry-run)"
  grep -q "SAFE action=remove reason=clean_registered" <<<"$out"
  assert_eq "$?" "0" "registered temp dry-run"
  bash "$helper" --repo "$main" --identity TEST-TEMP --include-temp --apply >/dev/null
  [[ ! -d "$wt" ]]
  assert_eq "$?" "0" "registered temp apply removes path"

  wt="/private/tmp/polaris-cleanup-selftest-${$}-TEST-DETACHED"
  git -C "$main" worktree add --detach "$wt" main >/dev/null 2>&1
  out="$(bash "$helper" --repo "$main" --identity TEST-DETACHED --include-temp --dry-run)"
  grep -q "branch=detached" <<<"$out"
  assert_eq "$?" "0" "detached temp dry-run"
  bash "$helper" --repo "$main" --identity TEST-DETACHED --include-temp --apply >/dev/null
  [[ ! -d "$wt" ]]
  assert_eq "$?" "0" "detached temp apply removes path"

  if command -v lsof >/dev/null 2>&1; then
    git -C "$main" branch task/TEST-LIVE-clean main
    git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-LIVE" task/TEST-LIVE-clean >/dev/null 2>&1
    wt="${main}/.worktrees/repo-engineering-TEST-LIVE"
    (cd "$wt" && sleep 60) &
    pid=$!
    LIVE_PIDS+=("$pid")
    sleep 1
    if bash "$helper" --repo "$main" --identity TEST-LIVE --apply >/tmp/polaris-cleanup-selftest.out 2>&1; then
      echo "FAIL: live-process worktree should block" >&2
      return 1
    fi
    grep -q "reason=live_process" /tmp/polaris-cleanup-selftest.out
    assert_eq "$?" "0" "live process blocks"
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    LIVE_PIDS=()
  else
    echo "$PREFIX self-test note: lsof unavailable; live-process fixture skipped" >&2
  fi

  echo "engineering-worktree-cleanup.sh self-test PASS (${pass}/${total})"
}

REPO=""
IDENTITY=""
WORKTREE=""
MODE="dry-run"
INCLUDE_TEMP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --worktree) WORKTREE="${2:-}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --include-temp) INCLUDE_TEMP="true"; shift ;;
    --self-test) self_test; exit $? ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO" ]] || { echo "$PREFIX unable to resolve repo" >&2; exit 2; }
REPO="$(repo_root "$REPO")" || { echo "$PREFIX not a git repo: $REPO" >&2; exit 2; }
REPO="$(canonical_path "$REPO")"
MAIN_CHECKOUT="$(main_checkout_path "$REPO")"
[[ -n "$MAIN_CHECKOUT" ]] || { echo "$PREFIX unable to resolve main checkout" >&2; exit 2; }
MAIN_CHECKOUT="$(canonical_path "$MAIN_CHECKOUT")"

SAFE_PATHS=()
BLOCKED=0
MATCHED=0

if [[ -n "$WORKTREE" ]]; then
  paths=("$WORKTREE")
else
  paths=()
  while IFS= read -r candidate; do
    paths+=("$candidate")
  done < <(candidate_paths "$REPO")
fi

for path in "${paths[@]}"; do
  set +e
  line="$(classify_one "$REPO" "$MAIN_CHECKOUT" "$path" "$IDENTITY" "$([[ -n "$WORKTREE" ]] && echo true || echo false)" "$INCLUDE_TEMP")"
  rc=$?
  set -e
  [[ -n "$line" ]] && printf '%s\n' "$line"
  case "$rc" in
    0)
      MATCHED=$((MATCHED + 1))
      SAFE_PATHS+=("$(canonical_path "$path")")
      ;;
    10)
      MATCHED=$((MATCHED + 1))
      BLOCKED=1
      ;;
    20)
      ;;
    *)
      BLOCKED=1
      ;;
  esac
done

if [[ "$MATCHED" -eq 0 ]]; then
  echo "NOOP action=keep reason=no_matching_worktree path='' branch=''"
fi

if [[ "$MODE" == "apply" ]]; then
  if [[ "$BLOCKED" -ne 0 ]]; then
    exit 2
  fi
  cd "$MAIN_CHECKOUT"
  for safe_path in "${SAFE_PATHS[@]}"; do
    echo "$PREFIX removing $safe_path" >&2
    git -C "$MAIN_CHECKOUT" worktree remove "$safe_path"
  done
fi

exit 0
