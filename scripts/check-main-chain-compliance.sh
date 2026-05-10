#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SOURCE_CONTAINER=""
TASK_MD=""
CHECK_CALLSITES=0
ALLOW_ACTIVE_VERIFICATION=0
REQUIRE_RELEASE_METADATA=0

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-main-chain-compliance.sh [--repo <path>] [--source-container <path>] [--task-md <path>] [--check-callsites] [--allow-active-verification] [--require-release-metadata]

Checks the strict refinement -> breakdown -> engineering -> verify-AC main chain
mechanics for active DP/Epic source containers.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --check-callsites) CHECK_CALLSITES=1; shift ;;
    --allow-active-verification) ALLOW_ACTIVE_VERIFICATION=1; shift ;;
    --require-release-metadata) REQUIRE_RELEASE_METADATA=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-main-chain-compliance: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$REPO_ROOT" ]] || { echo "check-main-chain-compliance: repo not found: $REPO_ROOT" >&2; exit 2; }
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

status_of() {
  awk '
    NR == 1 && $0 == "---" { fm=1; next }
    fm && $0 == "---" { exit }
    fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
  ' "$1"
}

ac_status_of() {
  awk '
    /^ac_verification:/ { in_block=1; next }
    in_block && /^[^[:space:]-][^:]*:/ { exit }
    in_block && /^[[:space:]]+status:/ {
      sub(/^[[:space:]]+status:[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

check_callsites() {
  rg -q "check-main-chain-compliance.sh" "$REPO_ROOT/.claude/skills/references/breakdown-dp-intake-flow.md" || fail "breakdown DP intake missing main-chain compliance callsite"
  rg -q "check-main-chain-compliance.sh" "$REPO_ROOT/.claude/skills/references/engineer-delivery-flow.md" || fail "engineering delivery missing main-chain compliance callsite"
  rg -q "check-main-chain-compliance.sh" "$REPO_ROOT/.claude/skills/references/verify-ac-reporting-flow.md" || fail "verify-AC reporting missing main-chain compliance callsite"
  rg -q "check-main-chain-compliance.sh" "$REPO_ROOT/scripts/framework-release-closeout.sh" || fail "framework release closeout missing main-chain compliance callsite"
}

check_task_md() {
  local task="$1"
  [[ -f "$task" ]] || { fail "task.md not found: $task"; return; }
  bash "$SCRIPT_DIR/validate-task-md.sh" "$task" >/dev/null || fail "task schema failed: $task"
  if [[ "$(basename "$task")" == "index.md" && "$(basename "$(dirname "$task")")" == T* ]] || [[ "$(basename "$task")" == T*.md ]]; then
    bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$task" >/dev/null || fail "breakdown ready failed: $task"
  fi
}

check_source_container() {
  local source="$1"
  [[ -d "$source" ]] || { fail "source container not found: $source"; return; }
  local parent=""
  if [[ -f "$source/index.md" ]]; then parent="$source/index.md"; elif [[ -f "$source/refinement.md" ]]; then parent="$source/refinement.md"; elif [[ -f "$source/plan.md" ]]; then parent="$source/plan.md"; fi
  [[ -n "$parent" ]] || fail "source container missing parent markdown: $source"
  if [[ -f "$source/refinement.md" ]]; then
    bash "$SCRIPT_DIR/refinement-handoff-gate.sh" "$source/refinement.md" >/dev/null || fail "refinement handoff failed: $source/refinement.md"
  fi
  [[ -d "$source/tasks" ]] || { fail "source container missing tasks directory: $source"; return; }

  local t_count=0 v_count=0 active_v=0 bad_v=0
  while IFS= read -r task; do
    [[ -n "$task" ]] || continue
    t_count=$((t_count + 1))
    check_task_md "$task"
  done < <(find "$source/tasks" -path "$source/tasks/pr-release" -prune -o \( -name 'T*.md' -o -path '*/T*/index.md' \) -type f -print | sort)

  while IFS= read -r task; do
    [[ -n "$task" ]] || continue
    v_count=$((v_count + 1))
    check_task_md "$task"
    if [[ "$task" != */tasks/pr-release/* ]]; then
      active_v=$((active_v + 1))
      [[ "$ALLOW_ACTIVE_VERIFICATION" -eq 1 ]] || fail "active V*.md remains before parent closeout: $task"
    fi
    if [[ "$(status_of "$task")" != "IMPLEMENTED" || "$(ac_status_of "$task")" != "PASS" ]]; then
      bad_v=$((bad_v + 1))
    fi
  done < <(find "$source/tasks" \( -name 'V*.md' -o -path '*/V*/index.md' \) -type f -print | sort)

  [[ "$t_count" -gt 0 ]] || fail "source container has no T*.md implementation tasks"
  [[ "$v_count" -gt 0 ]] || fail "source container has no V*.md dogfood/AC verification task"

  if [[ "$REQUIRE_RELEASE_METADATA" -eq 1 ]]; then
    while IFS= read -r task; do
      [[ -n "$task" ]] || continue
      if [[ "$task" != */tasks/pr-release/* ]]; then
        fail "implementation task not moved to pr-release: $task"
      fi
      rg -q "extension_deliverable:" "$task" || fail "implementation task missing extension_deliverable: $task"
    done < <(find "$source/tasks" \( -name 'T*.md' -o -path '*/T*/index.md' \) -type f -print | sort)
  fi
}

if [[ "$CHECK_CALLSITES" -eq 1 ]]; then
  check_callsites
fi
if [[ -n "$TASK_MD" ]]; then
  check_task_md "$TASK_MD"
fi
if [[ -n "$SOURCE_CONTAINER" ]]; then
  [[ "$SOURCE_CONTAINER" = /* ]] || SOURCE_CONTAINER="$REPO_ROOT/$SOURCE_CONTAINER"
  check_source_container "$SOURCE_CONTAINER"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "BLOCKED: main-chain compliance failed ($failures issue(s))" >&2
  exit 1
fi

echo "PASS: main-chain compliance"
