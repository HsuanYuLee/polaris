#!/usr/bin/env bash
set -euo pipefail

# gate-revision-rebase.sh — Existing-PR push guard for engineering revision R0.
#
# Usage:
#   bash scripts/gates/gate-revision-rebase.sh [--repo <path>] [--ticket <KEY>]
#
# Exit: 0 = pass/skip, 2 = block

PREFIX="[polaris gate-revision-rebase]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_REST_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib/github-rest.sh"
REPO_ROOT=""
TICKET=""

MAIN_CHECKOUT_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib/main-checkout.sh"
if [[ -f "$MAIN_CHECKOUT_LIB" ]]; then
  # shellcheck source=../lib/main-checkout.sh
  . "$MAIN_CHECKOUT_LIB"
fi
if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=../lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --ticket) TICKET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-revision-rebase.sh [--repo <path>] [--ticket <KEY>]"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>    Work item key (default: extract from branch name)"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$branch" in
  task/*|fix/*) ;;
  *) exit 0 ;;
esac

if [[ "${POLARIS_SKIP_REVISION_REBASE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_REVISION_REBASE=1 — bypassing (emergency only)." >&2
  exit 0
fi

extract_task_key_from_branch() {
  local branch_name="$1"
  local key=""
  key="$(printf '%s' "$branch_name" | grep -oE 'DP-[0-9]{3}-T[0-9]+[a-z]*' | head -n 1 || true)"
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  printf '%s' "$branch_name" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true
}

if [[ -z "$TICKET" ]]; then
  TICKET="$(extract_task_key_from_branch "$branch")"
fi

if [[ -z "$TICKET" ]]; then
  echo "$PREFIX WARN: managed branch has no extractable ticket/work item id; allowing." >&2
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "$PREFIX WARN: gh not available; cannot determine whether branch has an existing PR — allowing." >&2
  exit 0
fi

if declare -F polaris_current_branch_pr_rest >/dev/null 2>&1; then
  pr_json="$(polaris_current_branch_pr_rest "$REPO_ROOT" 2>/dev/null || true)"
fi
if [[ -z "$pr_json" ]]; then
  pr_json="$(cd "$REPO_ROOT" && gh pr view --json number,baseRefName 2>/dev/null || true)"
fi
if [[ -z "$pr_json" ]]; then
  # First-cut branch before PR creation: no revision obligation yet.
  exit 0
fi

pr_number="$(printf '%s' "$pr_json" | python3 -c 'import json,sys
try:
    print(json.loads(sys.stdin.read() or "{}").get("number") or "")
except Exception:
    print("")
' 2>/dev/null || true)"

[[ -n "$pr_number" ]] || exit 0

head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$head_sha" ]] || exit 0

evidence_root="${POLARIS_EVIDENCE_ROOT:-}"
if [[ -z "$evidence_root" ]]; then
  main_checkout=""
  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$REPO_ROOT" 2>/dev/null || true)"
  fi
  if [[ -z "$main_checkout" ]]; then
    main_checkout="$REPO_ROOT"
  fi
  evidence_root="${main_checkout}/.polaris/evidence"
fi

evidence_tmp="/tmp/polaris-revision-rebase-${TICKET}-${head_sha}.json"
evidence_durable="${evidence_root}/revision-rebase/polaris-revision-rebase-${TICKET}-${head_sha}.json"
evidence_file=""

if [[ -f "$evidence_tmp" ]]; then
  evidence_file="$evidence_tmp"
elif [[ -f "$evidence_durable" ]]; then
  evidence_file="$evidence_durable"
else
  cat >&2 <<EOF
$PREFIX BLOCKED: existing PR #${pr_number} push has no revision-rebase evidence for ${TICKET} @ ${head_sha}.

Expected one of:
  ${evidence_tmp}
  ${evidence_durable}

Run R0 before revising/pushing this PR:
  bash scripts/revision-rebase.sh --repo "${REPO_ROOT}" --task-md <path/to/task.md> --pr ${pr_number}

Why: revision mode must rebase before fixing, including stacked branch-chain cascade.
EOF
  exit 2
fi

valid="$(python3 - "$evidence_file" "$REPO_ROOT" "$TICKET" "$head_sha" <<'PY'
import json
import pathlib
import sys

path, repo, ticket, head_sha = sys.argv[1:5]
try:
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    assert d.get("writer") == "revision-rebase.sh", "writer mismatch"
    assert d.get("head_sha") == head_sha, "head_sha mismatch"
    assert d.get("rebase_status") in {"clean", "not_needed"}, "rebase_status not successful"
    assert ticket in (d.get("evidence_ids") or []), "ticket/work item not in evidence_ids"
    evidence_repo = pathlib.Path(d.get("repo") or "").resolve()
    current_repo = pathlib.Path(repo).resolve()
    assert evidence_repo == current_repo, f"repo mismatch: {evidence_repo} != {current_repo}"
    assert d.get("task_md"), "missing task_md"
    print("valid")
except Exception as exc:
    print(f"invalid: {exc}")
PY
)"

if [[ "$valid" != "valid" ]]; then
  echo "$PREFIX BLOCKED: revision-rebase evidence is malformed or stale for ${TICKET}" >&2
  echo "  ${evidence_file}: ${valid}" >&2
  echo "" >&2
  echo "Re-run: bash scripts/revision-rebase.sh --repo \"${REPO_ROOT}\" --task-md <path/to/task.md> --pr ${pr_number}" >&2
  exit 2
fi

echo "$PREFIX ✅ revision-rebase evidence valid for PR #${pr_number}, ${TICKET} @ ${head_sha}." >&2
exit 0
