#!/usr/bin/env bash
# Create a fresh one-shot worktree for engineering revision mode.

set -euo pipefail

PREFIX="[engineering-revision-worktree-setup]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
WORKTREE_CLEANUP="$SCRIPT_DIR/engineering-worktree-cleanup.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  engineering-revision-worktree-setup.sh --repo <repo> --task-md <task.md> [--pr <number>] [--branch <branch>] [--head <sha>] [--repo-base <dir>]

Creates a fresh detached worktree from the PR branch/head. Existing clean
worktrees for the same task identity are removed first; dirty/unsafe ones block.
EOF
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
value = data
for part in sys.argv[2].split("."):
    value = value.get(part, {}) if isinstance(value, dict) else {}
print(value if isinstance(value, str) else "")
PY
}

safe_slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

REPO=""
TASK_MD=""
PR_NUMBER=""
PR_BRANCH=""
PR_HEAD=""
REPO_BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --pr) PR_NUMBER="${2:-}"; shift 2 ;;
    --branch) PR_BRANCH="${2:-}"; shift 2 ;;
    --head) PR_HEAD="${2:-}"; shift 2 ;;
    --repo-base) REPO_BASE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -d "$REPO" ]] || { echo "$PREFIX --repo is required" >&2; exit 2; }
[[ -n "$TASK_MD" && -f "$TASK_MD" ]] || { echo "$PREFIX --task-md is required" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"
TASK_JSON="$(bash "$PARSE_TASK_MD" "$TASK_MD")"
TASK_ID="$(json_field "$TASK_JSON" "operational_context.task_id")"
if [[ -z "$TASK_ID" || "$TASK_ID" == "N/A" ]]; then
  TASK_ID="$(json_field "$TASK_JSON" "operational_context.task_jira_key")"
fi
REPO_NAME="$(json_field "$TASK_JSON" "metadata.repo")"
[[ -n "$TASK_ID" ]] || { echo "$PREFIX could not resolve task identity" >&2; exit 2; }

if [[ -z "$PR_BRANCH" ]]; then
  [[ -n "$PR_NUMBER" ]] || { echo "$PREFIX --pr or --branch is required" >&2; exit 2; }
  PR_BRANCH="$(gh pr view "$PR_NUMBER" --json headRefName --jq .headRefName)"
fi
if [[ -z "$PR_HEAD" && -n "$PR_NUMBER" ]]; then
  PR_HEAD="$(gh pr view "$PR_NUMBER" --json headRefOid --jq .headRefOid)"
fi
[[ -n "$PR_BRANCH" ]] || { echo "$PREFIX could not resolve PR branch" >&2; exit 2; }

if [[ -z "$REPO_BASE" ]]; then
  REPO_BASE="$(git -C "$REPO" rev-parse --show-toplevel)"
fi
WT_DIR="${REPO_BASE}/.worktrees"
WT_PATH="${WT_DIR}/${REPO_NAME:-repo}-revision-$(safe_slug "$TASK_ID")"

mkdir -p "$WT_DIR"
if [[ -e "$WT_PATH" ]]; then
  bash "$WORKTREE_CLEANUP" --repo "$REPO" --worktree "$WT_PATH" --identity "$TASK_ID" --apply >/dev/null || {
    echo "$PREFIX target path exists but is not safely cleanable: $WT_PATH" >&2
    exit 1
  }
fi

git -C "$REPO" fetch origin "$PR_BRANCH" >/dev/null
git -C "$REPO" worktree add --detach "$WT_PATH" "FETCH_HEAD" >/dev/null
ACTUAL_HEAD="$(git -C "$WT_PATH" rev-parse HEAD)"
if [[ -n "$PR_HEAD" && "$ACTUAL_HEAD" != "$PR_HEAD" ]]; then
  git -C "$REPO" worktree remove "$WT_PATH" >/dev/null 2>&1 || true
  echo "$PREFIX fetched head mismatch: expected $PR_HEAD got $ACTUAL_HEAD" >&2
  exit 1
fi

EVIDENCE="/tmp/polaris-revision-worktree-$(safe_slug "$TASK_ID")-${ACTUAL_HEAD}.json"
python3 - "$TASK_ID" "$PR_NUMBER" "$PR_BRANCH" "$ACTUAL_HEAD" "$WT_PATH" "$EVIDENCE" <<'PY'
import json, sys
task_id, pr, branch, head, path, evidence = sys.argv[1:7]
payload = {
    "task_id": task_id,
    "pr_number": pr or None,
    "branch": branch,
    "head_sha": head,
    "worktree_path": path,
    "fresh": True,
    "writer": "engineering-revision-worktree-setup.sh",
}
open(evidence, "w", encoding="utf-8").write(json.dumps(payload, separators=(",", ":")) + "\n")
print(json.dumps(payload, separators=(",", ":")))
PY
