#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TASK_MD=""
HEAD_SHA=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/check-flow-gap-audit.sh [--repo <path>] [--task-md <path>] [--head-sha <sha>]

Fail-stop audit for post-implementation bypass, fallback, false-pass, ignored
artifact, and verification evidence gaps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-flow-gap-audit: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -d "$REPO_ROOT" ]] || { echo "check-flow-gap-audit: repo not found: $REPO_ROOT" >&2; exit 2; }
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
[[ -n "$HEAD_SHA" ]] || HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"

failures=0
fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

while IFS='=' read -r name _; do
  case "$name" in
    POLARIS_SKIP_*) fail "bypass env var is set: $name" ;;
  esac
done < <(env)

tracked_specs="$(git -C "$REPO_ROOT" ls-files -- docs-manager/src/content/docs/specs 2>/dev/null || true)"
if [[ -n "$tracked_specs" ]]; then
  fail "tracked docs-manager specs are not allowed in release diff"
  printf '%s\n' "$tracked_specs" >&2
fi

if [[ -x "$SCRIPT_DIR/validate-polaris-config-migration.sh" ]]; then
  bash "$SCRIPT_DIR/validate-polaris-config-migration.sh" >/dev/null || fail "polaris config migration gate failed"
fi

if [[ -n "$TASK_MD" ]]; then
  [[ -f "$TASK_MD" ]] || { echo "check-flow-gap-audit: task.md not found: $TASK_MD" >&2; exit 2; }
  # shellcheck source=lib/verification-evidence.sh
  . "$SCRIPT_DIR/lib/verification-evidence.sh"
  task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field work_item_id 2>/dev/null || true)"
  [[ -n "$task_id" && "$task_id" != "N/A" ]] || task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field task_jira_key 2>/dev/null || true)"
  [[ -n "$task_id" && "$task_id" != "N/A" ]] || task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field jira_key 2>/dev/null || true)"
  [[ -n "$task_id" && "$task_id" != "N/A" ]] || fail "cannot resolve task identity for evidence check"
  if [[ -n "$task_id" && "$task_id" != "N/A" ]]; then
    evidence="$(verification_evidence_resolve_existing_path "$REPO_ROOT" "$task_id" "$HEAD_SHA" 2>/dev/null || true)"
    if [[ -z "$evidence" ]]; then
      fail "missing head-bound run-verify-command evidence for ${task_id}@${HEAD_SHA}"
    else
      verification_evidence_validate_file "$evidence" "$task_id" "$HEAD_SHA" >/dev/null || fail "invalid verification evidence: $evidence"
      verification_evidence_is_pass "$evidence" >/dev/null || fail "verification evidence is not PASS: $evidence"
    fi
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  echo "BLOCKED: flow gap audit failed ($failures issue(s))" >&2
  exit 1
fi

echo "PASS: flow gap audit"
