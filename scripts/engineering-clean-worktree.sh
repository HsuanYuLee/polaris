#!/usr/bin/env bash
# scripts/engineering-clean-worktree.sh
#
# Deterministic cleanup for engineering implementation worktrees after a task
# has been delivered. This script intentionally refuses to clean dirty or
# untracked worktrees: those need human classification before removal.
#
# Usage:
#   engineering-clean-worktree.sh --task-md <path> [--repo <path>] [--worktree <path>]
#
# Contract:
#   - target must be a registered git worktree
#   - target must live under a `.worktrees/` directory
#   - target must not be the main checkout
#   - target git status must be clean
#   - task.md deliverable.head_sha must match target HEAD
#   - or extension_deliverable.task_head_sha must match target HEAD or contain target HEAD as an ancestor
#
# Exit:
#   0 = removed or no matching implementation worktree found
#   2 = blocked / usage error

set -euo pipefail

PREFIX="[engineering-clean-worktree]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="${SCRIPT_DIR}/parse-task-md.sh"
SELFTEST_TMP=""

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") --task-md <path> [--repo <path>] [--worktree <path>]

Options:
  --task-md <path>   Authoritative engineering task.md
  --repo <path>      Any checkout/worktree of the target repo (default: cwd)
  --worktree <path>  Explicit worktree path to remove
  --self-test        Run self-test
EOF
}

json_field() {
  local json="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr} or '')" <<<"$json"
}

extract_frontmatter_nested_scalar() {
  local file="$1"
  local parent="$2"
  local child="$3"

  python3 - "$file" "$parent" "$child" <<'PY'
import sys

path, parent, child = sys.argv[1:4]
try:
    text = open(path, "r", encoding="utf-8").read()
except OSError:
    sys.exit(0)

if not (text.startswith("---\n") and "\n---\n" in text[4:]):
    sys.exit(0)

fm_end = text.find("\n---\n", 4)
frontmatter = text[4:fm_end].splitlines()
in_parent = False
for raw in frontmatter:
    if raw.startswith(parent + ":"):
        in_parent = True
        continue
    if not in_parent:
        continue
    if raw and raw[0] not in (" ", "\t"):
        break
    stripped = raw.strip()
    if stripped.startswith(child + ":"):
        _, _, value = stripped.partition(":")
        print(value.strip())
        sys.exit(0)
PY
}

task_delivered_head_sha() {
  local file="$1"
  local head_sha

  head_sha="$(extract_frontmatter_nested_scalar "$file" "deliverable" "head_sha")"
  if [[ -n "$head_sha" ]]; then
    printf '%s\n' "$head_sha"
    return 0
  fi

  extract_frontmatter_nested_scalar "$file" "extension_deliverable" "task_head_sha"
}

delivered_head_source() {
  local file="$1"

  if [[ -n "$(extract_frontmatter_nested_scalar "$file" "deliverable" "head_sha")" ]]; then
    printf '%s\n' "deliverable"
    return 0
  fi

  if [[ -n "$(extract_frontmatter_nested_scalar "$file" "extension_deliverable" "task_head_sha")" ]]; then
    printf '%s\n' "extension_deliverable"
  fi
}

canonical_path() {
  local path="$1"
  python3 - "$path" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
}

worktree_main_path() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain | awk '
    /^worktree / {
      if (first == "") {
        first = substr($0, 10)
      }
    }
    END { print first }
  '
}

registered_worktree_paths() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain | awk '/^worktree / { print substr($0, 10) }'
}

registered_worktree_for_branch() {
  local repo="$1"
  local branch="$2"
  git -C "$repo" worktree list --porcelain | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

ensure_main_excludes_worktrees() {
  local main_checkout="$1"
  local exclude_file="${main_checkout}/.git/info/exclude"

  [[ -f "$exclude_file" ]] || return 0
  if ! grep -qxF ".worktrees/" "$exclude_file"; then
    printf '\n.worktrees/\n' >>"$exclude_file"
    echo "$PREFIX added .worktrees/ to ${exclude_file}" >&2
  fi
}

self_test() {
  local tmp remote main task_md wt out rc head
  tmp="$(mktemp -d)"
  SELFTEST_TMP="$tmp"
  trap 'rm -rf "$SELFTEST_TMP"' EXIT
  remote="${tmp}/remote.git"
  main="${tmp}/repo"

  git init --bare "$remote" >/dev/null
  git clone "$remote" "$main" >/dev/null 2>&1
  git -C "$main" checkout -b main >/dev/null 2>&1
  echo init >"${main}/file.txt"
  git -C "$main" add file.txt
  git -C "$main" commit -m init >/dev/null
  git -C "$main" push -u origin main >/dev/null 2>&1
  git -C "$main" branch task/TEST-1-clean
  mkdir -p "${main}/.worktrees"
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-1" task/TEST-1-clean >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-1"
  head="$(git -C "$wt" rev-parse HEAD)"
  task_md="${tmp}/T1.md"
  cat >"$task_md" <<TASK
---
deliverable:
  pr_url: https://example.test/pr/1
  pr_state: OPEN
  head_sha: ${head}
status: IMPLEMENTED
---
# T1: Cleanup (1 pt)

> Epic: TEST-1 | JIRA: TEST-1 | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-1 |
| Parent Epic | TEST-1 |
| Base branch | main |
| Task branch | task/TEST-1-clean |
TASK

  out="$("$0" --task-md "$task_md" --repo "$main" 2>&1)"
  rc=$?
  [[ "$rc" == "0" ]] || { echo "self-test failed: clean remove rc=$rc output=$out" >&2; return 1; }
  [[ ! -d "$wt" ]] || { echo "self-test failed: worktree still exists" >&2; return 1; }
  grep -qxF ".worktrees/" "${main}/.git/info/exclude" || { echo "self-test failed: exclude not updated" >&2; return 1; }

  git -C "$main" branch task/TEST-EXT-clean main
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-EXT" task/TEST-EXT-clean >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-EXT"
  head="$(git -C "$wt" rev-parse HEAD)"
  task_md="${tmp}/T-ext.md"
  cat >"$task_md" <<TASK
---
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: ${head}
  workspace_commit: ${head}
  template_commit: ${head}
  version_tag: v1.2.3
  release_url: https://example.test/releases/v1.2.3
  evidence:
    ci_local: N/A
    verify: /tmp/example-verify.json
    vr: N/A
status: IMPLEMENTED
---
# T-ext: Local extension cleanup (1 pt)

> Epic: TEST-EXT | JIRA: TEST-EXT | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-EXT |
| Parent Epic | TEST-EXT |
| Base branch | main |
| Task branch | task/TEST-EXT-clean |
TASK

  out="$("$0" --task-md "$task_md" --repo "$main" 2>&1)"
  rc=$?
  [[ "$rc" == "0" ]] || { echo "self-test failed: local-extension remove rc=$rc output=$out" >&2; return 1; }
  [[ ! -d "$wt" ]] || { echo "self-test failed: local-extension worktree still exists" >&2; return 1; }

  git -C "$main" branch task/TEST-EXT-DESC main
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-EXT-DESC" task/TEST-EXT-DESC >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-EXT-DESC"
  head="$(git -C "$wt" rev-parse HEAD)"
  echo descendant >>"${main}/file.txt"
  git -C "$main" commit -am "workspace descendant" >/dev/null
  descendant_head="$(git -C "$main" rev-parse HEAD)"
  task_md="${tmp}/T-ext-desc.md"
  cat >"$task_md" <<TASK
---
extension_deliverable:
  endpoint: local_extension
  extension_id: framework-release
  task_head_sha: ${descendant_head}
  workspace_commit: ${descendant_head}
  template_commit: ${descendant_head}
  version_tag: v1.2.4
  release_url: https://example.test/releases/v1.2.4
  evidence:
    ci_local: N/A
    verify: /tmp/example-verify.json
    vr: N/A
status: IMPLEMENTED
---
# T-ext-desc: Local extension descendant cleanup (1 pt)

> Epic: TEST-EXT-DESC | JIRA: TEST-EXT-DESC | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-EXT-DESC |
| Parent Epic | TEST-EXT-DESC |
| Base branch | main |
| Task branch | task/TEST-EXT-DESC |
TASK

  out="$("$0" --task-md "$task_md" --repo "$main" 2>&1)"
  rc=$?
  [[ "$rc" == "0" ]] || { echo "self-test failed: local-extension descendant remove rc=$rc output=$out" >&2; return 1; }
  [[ ! -d "$wt" ]] || { echo "self-test failed: local-extension descendant worktree still exists" >&2; return 1; }

  git -C "$main" branch task/TEST-2-dirty main
  git -C "$main" worktree add "${main}/.worktrees/repo-engineering-TEST-2" task/TEST-2-dirty >/dev/null 2>&1
  wt="${main}/.worktrees/repo-engineering-TEST-2"
  head="$(git -C "$wt" rev-parse HEAD)"
  echo dirty >"${wt}/dirty.txt"
  task_md="${tmp}/T2.md"
  cat >"$task_md" <<TASK
---
deliverable:
  pr_url: https://example.test/pr/2
  pr_state: OPEN
  head_sha: ${head}
status: IMPLEMENTED
---
# T2: Dirty (1 pt)

> Epic: TEST-2 | JIRA: TEST-2 | Repo: repo

## Operational Context

| 欄位 | 值 |
|------|-----|
| Task JIRA key | TEST-2 |
| Parent Epic | TEST-2 |
| Base branch | main |
| Task branch | task/TEST-2-dirty |
TASK
  if "$0" --task-md "$task_md" --repo "$main" >/tmp/engineering-clean-worktree-selftest.out 2>&1; then
    echo "self-test failed: dirty worktree should block" >&2
    return 1
  fi
  [[ -d "$wt" ]] || { echo "self-test failed: dirty worktree was removed" >&2; return 1; }

  echo "engineering-clean-worktree.sh self-test PASS"
}

TASK_MD=""
REPO=""
WORKTREE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md)
      TASK_MD="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --worktree)
      WORKTREE="${2:-}"
      shift 2
      ;;
    --self-test)
      self_test
      exit $?
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$TASK_MD" || ! -f "$TASK_MD" ]]; then
  echo "$PREFIX missing or invalid --task-md: ${TASK_MD:-<empty>}" >&2
  exit 2
fi

if [[ -z "$REPO" ]]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO" || ! -d "$REPO" ]]; then
  echo "$PREFIX unable to resolve repo" >&2
  exit 2
fi

REPO="$(canonical_path "$REPO")"
TASK_JSON="$(bash "$PARSE_TASK_MD" "$TASK_MD")"
TASK_BRANCH="$(json_field "$TASK_JSON" "d.get('operational_context',{}).get('task_branch')")"
TASK_KEY="$(json_field "$TASK_JSON" "d.get('operational_context',{}).get('task_jira_key') or d.get('metadata',{}).get('jira')")"
DELIVERED_HEAD_SHA="$(task_delivered_head_sha "$TASK_MD")"
DELIVERED_HEAD_SOURCE="$(delivered_head_source "$TASK_MD")"

if [[ -z "$TASK_BRANCH" ]]; then
  echo "$PREFIX task branch missing in task.md" >&2
  exit 2
fi
if [[ -z "$DELIVERED_HEAD_SHA" ]]; then
  echo "$PREFIX deliverable.head_sha or extension_deliverable.task_head_sha missing in task.md" >&2
  exit 2
fi

MAIN_CHECKOUT="$(worktree_main_path "$REPO")"
MAIN_CHECKOUT="$(canonical_path "$MAIN_CHECKOUT")"
ensure_main_excludes_worktrees "$MAIN_CHECKOUT"

if [[ -z "$WORKTREE" ]]; then
  WORKTREE="$(registered_worktree_for_branch "$REPO" "$TASK_BRANCH" | while read -r candidate; do
    candidate="$(canonical_path "$candidate")"
    if [[ "$candidate" == *"/.worktrees/"* ]]; then
      printf '%s\n' "$candidate"
      break
    fi
  done)"
fi

if [[ -z "$WORKTREE" ]]; then
  echo "$PREFIX no implementation worktree found for ${TASK_BRANCH}; nothing to clean." >&2
  exit 0
fi

WORKTREE="$(canonical_path "$WORKTREE")"

if [[ "$WORKTREE" == "$MAIN_CHECKOUT" ]]; then
  echo "$PREFIX refusing to remove main checkout: $WORKTREE" >&2
  exit 2
fi

if [[ "$WORKTREE" != *"/.worktrees/"* ]]; then
  echo "$PREFIX refusing to remove path outside .worktrees/: $WORKTREE" >&2
  exit 2
fi

REGISTERED="false"
while read -r registered; do
  if [[ "$(canonical_path "$registered")" == "$WORKTREE" ]]; then
    REGISTERED="true"
    break
  fi
done < <(registered_worktree_paths "$REPO")

if [[ "$REGISTERED" != "true" ]]; then
  echo "$PREFIX refusing to remove unregistered worktree path: $WORKTREE" >&2
  exit 2
fi

STATUS="$(git -C "$WORKTREE" status --porcelain)"
if [[ -n "$STATUS" ]]; then
  echo "$PREFIX blocked: worktree is not clean: $WORKTREE" >&2
  echo "$STATUS" >&2
  exit 2
fi

CURRENT_HEAD_SHA="$(git -C "$WORKTREE" rev-parse HEAD)"
if [[ "$CURRENT_HEAD_SHA" != "$DELIVERED_HEAD_SHA" && "$CURRENT_HEAD_SHA" != "${DELIVERED_HEAD_SHA}"* ]]; then
  if [[ "$DELIVERED_HEAD_SOURCE" == "extension_deliverable" ]] &&
     git -C "$WORKTREE" merge-base --is-ancestor "$CURRENT_HEAD_SHA" "$DELIVERED_HEAD_SHA" >/dev/null 2>&1; then
    echo "$PREFIX extension deliverable head contains worktree HEAD (${CURRENT_HEAD_SHA} <= ${DELIVERED_HEAD_SHA})" >&2
  else
    echo "$PREFIX blocked: delivered head (${DELIVERED_HEAD_SHA}) != worktree HEAD (${CURRENT_HEAD_SHA})" >&2
    exit 2
  fi
fi

echo "$PREFIX removing ${WORKTREE} for ${TASK_KEY:-$TASK_BRANCH}" >&2
cd "$MAIN_CHECKOUT"
git -C "$MAIN_CHECKOUT" worktree remove "$WORKTREE"
echo "$PREFIX removed ${WORKTREE}" >&2
