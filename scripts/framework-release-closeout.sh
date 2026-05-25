#!/usr/bin/env bash
set -euo pipefail

# framework-release-closeout.sh
#
# Deterministic post-release closeout for DP-backed framework tasks after the
# workspace PR has been merged and sync-to-polaris completed.
#
# Usage:
#   scripts/framework-release-closeout.sh \
#     --task-md <path> [--task-head-sha <sha>] \
#     --verify-evidence <path> [--ci-local-evidence <path|N/A>] [--vr-evidence <path|N/A>] \
#     [--preflight-evidence <path|N/A>] \
#     [--task-md <path> ...] \
#     --workspace-commit <sha> \
#     --template-commit <sha> \
#     --version-tag <tag|N/A> \
#     --release-url <url|N/A> \
#     [--repo <workspace-repo>] \
#     [--template-repo <template-repo>] \
#     [--extension-id framework-release] \
#     [--delete-branches]
#
# Repeated per-task inputs are positional. Each --task-md must have one
# --verify-evidence. --task-head-sha is optional; when omitted it is resolved
# from the task branch in task.md.
# After the parent DP reaches IMPLEMENTED, the canonical DP container is archived
# automatically. docs-manager reads canonical specs directly, so no viewer sync is
# needed after this move.
#
# Deterministic Consumption (DP-230 D30):
#   parent-closeout 直接讀 refinement.json (acceptance_criteria / verification.method)；
#   絕不讀 task.md acceptance_criteria 文字段。task lifecycle 由 frontmatter status
#   經 mark-spec-implemented.sh / update_frontmatter_status 推進，不消費 task.md
#   acceptance text。drift 時以 refinement.json 為準，task.md drift 僅 advisory。
#   POLARIS_FRAMEWORK_RELEASE_CLOSEOUT_DETERMINISTIC_CONSUMPTION_MARKER: parent-closeout
#   consumes refinement.json, not task.md acceptance text.

PREFIX="[framework-release-closeout]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK_RELEASE_ELIGIBLE="${SCRIPT_DIR}/check-release-eligible.sh"
CHECK_RELEASE_COMPLETED="${SCRIPT_DIR}/check-release-completed.sh"
CHECK_MAIN_CHAIN_COMPLIANCE="${SCRIPT_DIR}/check-main-chain-compliance.sh"
# shellcheck source=lib/specs-root.sh
. "$SCRIPT_DIR/lib/specs-root.sh"
# shellcheck source=lib/worktree-classifier.sh
. "$SCRIPT_DIR/lib/worktree-classifier.sh"
TEMPLATE_REPO=""
EXTENSION_ID="framework-release"
WORKSPACE_COMMIT=""
TEMPLATE_COMMIT=""
VERSION_TAG=""
RELEASE_URL=""
DELETE_BRANCHES=0

TASK_MDS=()
TASK_HEAD_SHAS=()
VERIFY_EVIDENCES=()
CI_LOCAL_EVIDENCES=()
VR_EVIDENCES=()
PREFLIGHT_EVIDENCES=()
# DP-230 D16: per-task head SHA map (task_id => sha) populated when
# --task-head-sha receives the map syntax "DP-NNN-T1=<sha1>,DP-NNN-T2=<sha2>".
# Legacy positional --task-head-sha <sha> (one per --task-md) continues to fill
# TASK_HEAD_SHAS in declaration order. macOS ships bash 3.2 which lacks
# associative arrays, so we keep two parallel arrays and a linear lookup.
TASK_HEAD_SHA_MAP_KEYS=()
TASK_HEAD_SHA_MAP_VALUES=()
TASK_HEAD_SHA_MAP_USED=0

task_head_sha_map_set() {
  local key="$1"
  local value="$2"
  local i
  for (( i = 0; i < ${#TASK_HEAD_SHA_MAP_KEYS[@]}; i++ )); do
    if [[ "${TASK_HEAD_SHA_MAP_KEYS[$i]}" == "$key" ]]; then
      TASK_HEAD_SHA_MAP_VALUES[$i]="$value"
      return 0
    fi
  done
  TASK_HEAD_SHA_MAP_KEYS+=("$key")
  TASK_HEAD_SHA_MAP_VALUES+=("$value")
}

task_head_sha_map_get() {
  local key="$1"
  local i
  for (( i = 0; i < ${#TASK_HEAD_SHA_MAP_KEYS[@]}; i++ )); do
    if [[ "${TASK_HEAD_SHA_MAP_KEYS[$i]}" == "$key" ]]; then
      printf '%s\n' "${TASK_HEAD_SHA_MAP_VALUES[$i]}"
      return 0
    fi
  done
  return 1
}

usage() {
  sed -n '3,34p' "$0" >&2
}

die() {
  echo "$PREFIX ERROR: $1" >&2
  exit 2
}

info() {
  echo "$PREFIX $1" >&2
}

repo_diagnostic_summary() {
  local repo="$1"
  local status branch main_status=""

  status="$(git -C "$repo" status --short --branch --untracked-files=no 2>/dev/null || true)"
  branch="$(git -C "$repo" branch --show-current 2>/dev/null || true)"
  if git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main; then
    main_status="$(git -C "$repo" rev-list --left-right --count HEAD...origin/main 2>/dev/null || true)"
  fi

  echo "selected repo: ${repo}" >&2
  echo "current branch: ${branch:-DETACHED}" >&2
  [[ -n "$main_status" ]] && echo "head vs origin/main: ${main_status} (left=ahead right=behind)" >&2
  if [[ -n "$status" ]]; then
    echo "tracked status:" >&2
    printf '%s\n' "$status" | sed 's/^/  /' >&2
  else
    echo "tracked status: clean" >&2
  fi
  echo "hint: rerun closeout against the merged clean release repo/worktree, not a stale main checkout." >&2
}

is_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

sha_matches() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" || "$expected" == "$actual"* || "$actual" == "$expected"* ]]
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$path")")
  fi
}

resolve_current_task_md_path() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi

  python3 - "$path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
parts = list(path.parts)
try:
    idx = parts.index("design-plans")
except ValueError:
    print(path)
    raise SystemExit(0)

if idx + 1 < len(parts) and parts[idx + 1] != "archive":
    archived = Path(*parts[:idx + 1], "archive", *parts[idx + 1:])
    print(archived)
else:
    print(path)
PY
}

resolve_source_container_for_task() {
  local task_md="$1"
  python3 - "$task_md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
parts = path.parts
if "tasks" not in parts:
    print("")
    raise SystemExit(0)
idx = len(parts) - 1 - list(reversed(parts)).index("tasks")
print(Path(*parts[:idx]).as_posix())
PY
}

parent_file_for_task() {
  local task_md="$1"
  python3 - "$task_md" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
parts = path.parts
if "tasks" not in parts:
    print("")
    raise SystemExit(0)
idx = len(parts) - 1 - list(reversed(parts)).index("tasks")
parent = Path(*parts[:idx])
for name in ("index.md", "refinement.md", "plan.md"):
    candidate = parent / name
    if candidate.exists():
        print(candidate)
        raise SystemExit(0)
print("")
PY
}

json_field() {
  local json="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr} or '')" <<<"$json"
}

frontmatter_status() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk -F ':' '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && /^status:/ {
      sub(/^[[:space:]]+/, "", $2)
      print $2
      exit
    }
  ' "$file"
}

update_frontmatter_status() {
  local file="$1"
  local new_status="$2"
  python3 - "$file" "$new_status" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
new_status = sys.argv[2]

content = path.read_text(encoding="utf-8")
lines = content.split("\n")

if lines and lines[0] == "---":
    try:
        close_idx = lines.index("---", 1)
    except ValueError:
        print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
        sys.exit(1)

    fm = lines[1:close_idx]
    found = False
    for idx, line in enumerate(fm):
        if re.match(r"^status:\s*", line):
            fm[idx] = f"status: {new_status}"
            found = True
            break
    if not found:
        fm.append(f"status: {new_status}")

    new_content = "---\n" + "\n".join(fm) + "\n---\n" + "\n".join(lines[close_idx + 1:])
else:
    new_content = f"---\nstatus: {new_status}\n---\n\n" + content

path.write_text(new_content, encoding="utf-8")
PY
}

mark_task_implemented() {
  local task_md="$1"
  local task_id="$2"
  local status="IMPLEMENTED"
  local dir task_file tasks_dir pr_release_dir pr_release_path existing_status

  if [[ "$task_md" == */design-plans/archive/*/tasks/* ]]; then
    dir="$(dirname "$task_md")"
    task_file="$(basename "$task_md")"
    if [[ "$(basename "$dir")" == "pr-release" ]]; then
      pr_release_path="$task_md"
    else
      tasks_dir="$dir"
      pr_release_dir="${tasks_dir}/pr-release"
      pr_release_path="${pr_release_dir}/${task_file}"
      mkdir -p "$pr_release_dir"
      if [[ -f "$pr_release_path" ]]; then
        if ! cmp -s "$task_md" "$pr_release_path"; then
          die "same-key invariant violation for archived ${task_file}; active and pr-release copies differ"
        fi
        rm "$task_md"
      else
        mv "$task_md" "$pr_release_path"
      fi
    fi

    existing_status="$(frontmatter_status "$pr_release_path")"
    if [[ "$existing_status" != "$status" ]]; then
      update_frontmatter_status "$pr_release_path" "$status"
      info "marked archived task ${task_id} as ${status}: ${pr_release_path}"
    else
      info "archived task ${task_id} already has status: ${status}"
    fi
    printf '%s\n' "$pr_release_path"
    return 0
  fi

  bash "${SCRIPT_DIR}/mark-spec-implemented.sh" "$task_id" --workspace "$REPO_ROOT" >&2
  if [[ -f "$task_md" ]]; then
    printf '%s\n' "$task_md"
  elif [[ "$(basename "$task_md")" == "index.md" ]]; then
    local task_dir tasks_dir task_name
    task_dir="$(dirname "$task_md")"
    tasks_dir="$(dirname "$task_dir")"
    task_name="$(basename "$task_dir")"
    if [[ "$(basename "$tasks_dir")" == "pr-release" ]]; then
      printf '%s\n' "$task_md"
    else
      printf '%s/pr-release/%s/index.md\n' "$tasks_dir" "$task_name"
    fi
  else
    printf '%s/pr-release/%s\n' "$(dirname "$task_md")" "$(basename "$task_md")"
  fi
}

registered_worktree_for_branch() {
  local branch="$1"
  git -C "$REPO_ROOT" worktree list --porcelain | awk -v branch="refs/heads/${branch}" '
    /^worktree / { wt = substr($0, 10); next }
    /^branch / {
      if (substr($0, 8) == branch) {
        print wt
      }
    }
  '
}

resolve_branch_sha() {
  local branch="$1"
  local sha=""
  sha="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "${branch}^{commit}" 2>/dev/null || true)"
  if [[ -z "$sha" ]]; then
    sha="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "origin/${branch}^{commit}" 2>/dev/null || true)"
  fi
  [[ -n "$sha" ]] || die "cannot resolve task branch commit: ${branch}"
  printf '%s\n' "$sha"
}

# classify_worktree_for_branch <task_branch>
#   Echo one of:
#     none        — no registered worktree for the branch (cleanup NOOP)
#     engineering — engineering implementation worktree (must be clean)
#     sub-agent   — sub-agent scratch worktree (closeout must skip)
#   Side effects: dies if an engineering worktree is dirty, or if the worktree
#   path is neither engineering nor sub-agent.
classify_worktree_for_branch() {
  local task_branch="$1"
  local worktree
  worktree="$(registered_worktree_for_branch "$task_branch")"
  if [[ -z "$worktree" ]]; then
    info "no registered worktree for ${task_branch}; cleanup will be NOOP"
    echo "none"
    return 0
  fi
  local kind
  kind="$(classify_worktree "$worktree")"
  case "$kind" in
    sub-agent)
      # Sub-agent worktrees are owned by the dispatcher, not by closeout.
      # Per DP-230-T9 (D23), closeout must skip per-task cleanup on them so
      # the closeout log does not surface sub-agent worktree paths.
      info "skip per-task closeout for sub-agent worktree: ${task_branch}"
      echo "sub-agent"
      return 0
      ;;
    engineering)
      if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
        die "dirty implementation worktree blocks closeout: ${worktree}"
      fi
      echo "engineering"
      return 0
      ;;
    *)
      die "refusing non-implementation worktree: ${worktree}"
      ;;
  esac
}

delete_branch_if_safe() {
  local task_branch="$1"
  local task_head_sha="$2"

  [[ "$DELETE_BRANCHES" -eq 1 ]] || return 0

  if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$task_head_sha" "$WORKSPACE_COMMIT"; then
    die "refusing branch delete; workspace_commit does not contain task head for ${task_branch}"
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/${task_branch}"; then
    git -C "$REPO_ROOT" branch -d "$task_branch"
    info "deleted local branch ${task_branch}"
  else
    info "local branch already absent: ${task_branch}"
  fi

  if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$task_branch" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" push origin --delete "$task_branch"
    info "deleted remote branch origin/${task_branch}"
  else
    info "remote branch already absent: origin/${task_branch}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --template-repo) TEMPLATE_REPO="${2:-}"; shift 2 ;;
    --extension-id) EXTENSION_ID="${2:-}"; shift 2 ;;
    --task-md) TASK_MDS+=("${2:-}"); shift 2 ;;
    --task-head-sha)
      _ths_value="${2:-}"
      # DP-230 D16: detect map syntax "task_id=<sha>[,task_id=<sha>...]".
      # Any token containing '=' switches this flag into map mode; once map
      # mode is engaged, the value must parse cleanly or we fail-stop.
      if [[ "$_ths_value" == *"="* ]]; then
        if [[ "${#TASK_HEAD_SHAS[@]}" -gt 0 ]]; then
          die "--task-head-sha map syntax cannot mix with positional --task-head-sha entries"
        fi
        TASK_HEAD_SHA_MAP_USED=1
        IFS=',' read -r -a _ths_entries <<< "$_ths_value"
        for _ths_entry in "${_ths_entries[@]}"; do
          _ths_entry="${_ths_entry#"${_ths_entry%%[![:space:]]*}"}"
          _ths_entry="${_ths_entry%"${_ths_entry##*[![:space:]]}"}"
          [[ -n "$_ths_entry" ]] || continue
          if [[ "$_ths_entry" != *"="* ]]; then
            die "--task-head-sha map entry missing '=': '$_ths_entry' (expected task_id=<sha>)"
          fi
          _ths_key="${_ths_entry%%=*}"
          _ths_sha="${_ths_entry#*=}"
          [[ -n "$_ths_key" ]] || die "--task-head-sha map entry has empty task id: '$_ths_entry'"
          [[ -n "$_ths_sha" ]] || die "--task-head-sha map entry has empty SHA for ${_ths_key}"
          task_head_sha_map_set "$_ths_key" "$_ths_sha"
        done
      else
        if [[ "$TASK_HEAD_SHA_MAP_USED" -eq 1 ]]; then
          die "--task-head-sha map syntax cannot mix with positional --task-head-sha entries"
        fi
        TASK_HEAD_SHAS+=("$_ths_value")
      fi
      shift 2
      ;;
    --verify-evidence) VERIFY_EVIDENCES+=("${2:-}"); shift 2 ;;
    --ci-local-evidence) CI_LOCAL_EVIDENCES+=("${2:-}"); shift 2 ;;
    --vr-evidence) VR_EVIDENCES+=("${2:-}"); shift 2 ;;
    --preflight-evidence) PREFLIGHT_EVIDENCES+=("${2:-}"); shift 2 ;;
    --workspace-commit) WORKSPACE_COMMIT="${2:-}"; shift 2 ;;
    --template-commit) TEMPLATE_COMMIT="${2:-}"; shift 2 ;;
    --version-tag) VERSION_TAG="${2:-}"; shift 2 ;;
    --release-url) RELEASE_URL="${2:-}"; shift 2 ;;
    --delete-branches) DELETE_BRANCHES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "${#TASK_MDS[@]}" -gt 0 ]] || die "at least one --task-md is required"
[[ "${#VERIFY_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "provide exactly one --verify-evidence for each --task-md"
[[ "${#TASK_HEAD_SHAS[@]}" -eq 0 || "${#TASK_HEAD_SHAS[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--task-head-sha count must be zero or match --task-md count"
# DP-230 D16: map mode covers per-task SHA lookup by task_id during the
# iteration loop below; count parity is enforced at lookup time, not here.
[[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 0 || "${#CI_LOCAL_EVIDENCES[@]}" -eq 1 || "${#CI_LOCAL_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--ci-local-evidence count must be zero, one, or match --task-md count"
[[ "${#VR_EVIDENCES[@]}" -eq 0 || "${#VR_EVIDENCES[@]}" -eq 1 || "${#VR_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--vr-evidence count must be zero, one, or match --task-md count"
[[ "${#PREFLIGHT_EVIDENCES[@]}" -eq 0 || "${#PREFLIGHT_EVIDENCES[@]}" -eq 1 || "${#PREFLIGHT_EVIDENCES[@]}" -eq "${#TASK_MDS[@]}" ]] || die "--preflight-evidence count must be zero, one, or match --task-md count"
[[ -n "$WORKSPACE_COMMIT" ]] || die "--workspace-commit is required"
[[ -n "$TEMPLATE_COMMIT" ]] || die "--template-commit is required"
[[ -n "$VERSION_TAG" ]] || die "--version-tag is required"
[[ -n "$RELEASE_URL" ]] || die "--release-url is required"
is_sha "$WORKSPACE_COMMIT" || die "--workspace-commit must be a 7-40 char hex SHA"
is_sha "$TEMPLATE_COMMIT" || die "--template-commit must be a 7-40 char hex SHA"

REPO_ROOT="$(abs_path "$REPO_ROOT")"
[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || die "repo is not a git checkout: ${REPO_ROOT}"
git -C "$REPO_ROOT" cat-file -e "${WORKSPACE_COMMIT}^{commit}" 2>/dev/null || die "workspace commit not found: ${WORKSPACE_COMMIT}"
current_workspace_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
if ! sha_matches "$WORKSPACE_COMMIT" "$current_workspace_head"; then
  echo "$PREFIX ERROR: workspace commit is stale; current HEAD is ${current_workspace_head}" >&2
  repo_diagnostic_summary "$REPO_ROOT"
  exit 2
fi

if [[ -n "$TEMPLATE_REPO" ]]; then
  TEMPLATE_REPO="$(abs_path "$TEMPLATE_REPO")"
  [[ -d "$TEMPLATE_REPO/.git" || -f "$TEMPLATE_REPO/.git" ]] || die "template repo is not a git checkout: ${TEMPLATE_REPO}"
  git -C "$TEMPLATE_REPO" cat-file -e "${TEMPLATE_COMMIT}^{commit}" 2>/dev/null || die "template commit not found: ${TEMPLATE_COMMIT}"
  current_template_head="$(git -C "$TEMPLATE_REPO" rev-parse HEAD)"
  sha_matches "$TEMPLATE_COMMIT" "$current_template_head" || die "template commit is stale; template HEAD is ${current_template_head}"
  if [[ "$VERSION_TAG" != "N/A" ]]; then
    git -C "$TEMPLATE_REPO" rev-parse -q --verify "refs/tags/${VERSION_TAG}" >/dev/null || die "template tag missing: ${VERSION_TAG}"
  fi
fi

declare -a ABS_TASK_MDS TASK_IDS TASK_BRANCHES RESOLVED_TASK_HEADS TASK_WORKTREE_KINDS

for i in "${!TASK_MDS[@]}"; do
  task_md="$(abs_path "${TASK_MDS[$i]}")"
  [[ -f "$task_md" ]] || die "task.md not found: ${task_md}"

  parser_json="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$task_md" --no-resolve)" || die "unable to parse task.md: ${task_md}"
  task_id="$(json_field "$parser_json" "d.get('identity', {}).get('work_item_id') or d.get('header', {}).get('task_id')")"
  task_branch="$(json_field "$parser_json" "d.get('operational_context', {}).get('task_branch')")"
  [[ -n "$task_id" ]] || die "task identity missing in ${task_md}"
  [[ -n "$task_branch" ]] || die "Task branch missing in ${task_md}"

  task_head_sha=""
  if [[ "$TASK_HEAD_SHA_MAP_USED" -eq 1 ]]; then
    if task_head_sha="$(task_head_sha_map_get "$task_id")"; then
      :
    else
      die "--task-head-sha map missing entry for ${task_id}; bundle PR identity requires per-task SHA"
    fi
  elif [[ "${#TASK_HEAD_SHAS[@]}" -gt 0 ]]; then
    task_head_sha="${TASK_HEAD_SHAS[$i]}"
  fi
  if [[ -z "$task_head_sha" ]]; then
    task_head_sha="$(resolve_branch_sha "$task_branch")"
  fi
  is_sha "$task_head_sha" || die "--task-head-sha value malformed for ${task_id}: ${task_head_sha} (expected 7-40 char hex SHA; map syntax is task_id=<sha>)"
  git -C "$REPO_ROOT" cat-file -e "${task_head_sha}^{commit}" 2>/dev/null || die "task head does not exist for ${task_id}: ${task_head_sha}"
  git -C "$REPO_ROOT" merge-base --is-ancestor "$task_head_sha" "$WORKSPACE_COMMIT" || die "workspace commit does not contain task head for ${task_id}"

  worktree_kind="$(classify_worktree_for_branch "$task_branch")"

  ABS_TASK_MDS+=("$task_md")
  TASK_IDS+=("$task_id")
  TASK_BRANCHES+=("$task_branch")
  RESOLVED_TASK_HEADS+=("$task_head_sha")
  TASK_WORKTREE_KINDS+=("$worktree_kind")
done

for i in "${!ABS_TASK_MDS[@]}"; do
  task_md="${ABS_TASK_MDS[$i]}"
  task_id="${TASK_IDS[$i]}"
  task_branch="${TASK_BRANCHES[$i]}"
  task_head_sha="${RESOLVED_TASK_HEADS[$i]}"
  worktree_kind="${TASK_WORKTREE_KINDS[$i]}"
  verify_evidence="${VERIFY_EVIDENCES[$i]}"

  if [[ "$worktree_kind" == "sub-agent" ]]; then
    # Per DP-230-T9 (D23): sub-agent worktrees are dispatcher-owned scratch
    # space. framework-release closeout must skip per-task closeout entirely so
    # the closeout log carries no sub-agent worktree path.
    info "skip per-task closeout for ${task_id}: sub-agent worktree"
    continue
  fi

  if [[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 0 ]]; then
    ci_local_evidence="N/A"
  elif [[ "${#CI_LOCAL_EVIDENCES[@]}" -eq 1 ]]; then
    ci_local_evidence="${CI_LOCAL_EVIDENCES[0]}"
  else
    ci_local_evidence="${CI_LOCAL_EVIDENCES[$i]}"
  fi

  if [[ "${#VR_EVIDENCES[@]}" -eq 0 ]]; then
    vr_evidence="N/A"
  elif [[ "${#VR_EVIDENCES[@]}" -eq 1 ]]; then
    vr_evidence="${VR_EVIDENCES[0]}"
  else
    vr_evidence="${VR_EVIDENCES[$i]}"
  fi

  if [[ "${#PREFLIGHT_EVIDENCES[@]}" -eq 0 ]]; then
    preflight_evidence="N/A"
  elif [[ "${#PREFLIGHT_EVIDENCES[@]}" -eq 1 ]]; then
    preflight_evidence="${PREFLIGHT_EVIDENCES[0]}"
  else
    preflight_evidence="${PREFLIGHT_EVIDENCES[$i]}"
  fi
  if [[ -n "$preflight_evidence" && "$preflight_evidence" != "N/A" ]]; then
    [[ -f "$preflight_evidence" ]] || die "preflight evidence file not found: $preflight_evidence"
  fi

  info "writing extension deliverable for ${task_id}"
  bash "${SCRIPT_DIR}/write-extension-deliverable.sh" "$task_md" \
    --extension-id "$EXTENSION_ID" \
    --task-head-sha "$task_head_sha" \
    --workspace-commit "$WORKSPACE_COMMIT" \
    --template-commit "$TEMPLATE_COMMIT" \
    --version-tag "$VERSION_TAG" \
    --release-url "$RELEASE_URL" \
    --ci-local-evidence "$ci_local_evidence" \
    --verify-evidence "$verify_evidence" \
    --vr-evidence "$vr_evidence"

  if [[ -n "$preflight_evidence" && "$preflight_evidence" != "N/A" ]]; then
    python3 - "$task_md" "$preflight_evidence" <<'PY'
import re
import sys
from pathlib import Path

task_path, preflight_evidence = sys.argv[1:3]
path = Path(task_path)
content = path.read_text(encoding="utf-8")
block = "release_preflight:\n" f"  evidence: {preflight_evidence}\n"
match = re.match(r"^---\n(.*?)^---\n", content, flags=re.DOTALL | re.MULTILINE)
if not match:
    path.write_text("---\n" + block + "---\n" + content, encoding="utf-8")
else:
    fm = re.sub(r"^release_preflight:(?:\n(?:[ \t]+[^\n]*))*\n?", "", match.group(1), flags=re.MULTILINE)
    if fm and not fm.endswith("\n"):
        fm += "\n"
    path.write_text("---\n" + fm + block + "---\n" + content[match.end():], encoding="utf-8")
PY
  fi

  bash "${CHECK_RELEASE_ELIGIBLE}" \
    --repo "$REPO_ROOT" \
    --task-md "$task_md" \
    ${TEMPLATE_REPO:+--template-repo "$TEMPLATE_REPO"}

  bash "${SCRIPT_DIR}/check-local-extension-completion.sh" \
    --repo "$REPO_ROOT" \
    --task-md "$task_md" \
    --task-id "$task_id" \
    --extension-id "$EXTENSION_ID" \
    ${TEMPLATE_REPO:+--template-repo "$TEMPLATE_REPO"}

  # Terminal closeout chain: task closeout can close the parent, and the final
  # task in this closeout invokes close-parent-spec-if-complete.sh with
  # --archive-terminal-parent so archive-spec.sh is deterministic.
  #
  # DP-230 D30 deterministic consumption: this block delegates lifecycle to
  # frontmatter status (mark_task_implemented -> mark-spec-implemented.sh) and
  # never reads task.md acceptance_criteria text. parent-closeout consumes
  # refinement.json via close-parent-spec-if-complete.sh /
  # update_frontmatter_status. See SKILL.md verify-AC § Deterministic Consumption.
  moved_task_md="$(mark_task_implemented "$task_md" "$task_id")"
  [[ -f "$moved_task_md" ]] || die "implemented task file not found after mark-spec-implemented: ${task_id}"

  bash "${SCRIPT_DIR}/engineering-clean-worktree.sh" --task-md "$moved_task_md" --repo "$REPO_ROOT"
  delete_branch_if_safe "$task_branch" "$task_head_sha"
  source_container="$(resolve_source_container_for_task "$moved_task_md")"
  if [[ -n "$source_container" && -x "$CHECK_MAIN_CHAIN_COMPLIANCE" ]] \
    && find "$source_container/tasks" \( -name 'V*.md' -o -path '*/V*/index.md' \) -type f -print -quit 2>/dev/null | grep -q .; then
    bash "$CHECK_MAIN_CHAIN_COMPLIANCE" \
      --repo "$REPO_ROOT" \
      --source-container "$source_container" \
      --allow-active-verification
  fi
  case "$moved_task_md" in
    */specs/design-plans/archive/*|*/specs/companies/*/archive/*)
      archived_parent_file="$(parent_file_for_task "$moved_task_md")"
      [[ -n "$archived_parent_file" && -f "$archived_parent_file" ]] || die "archived parent file not found for ${moved_task_md}"
      update_frontmatter_status "$archived_parent_file" IMPLEMENTED
      info "marked archived parent implemented: ${archived_parent_file}"
      ;;
    *)
      close_parent_args=(
        --task-md "$moved_task_md"
        --workspace "$REPO_ROOT"
      )
      if [[ "$i" -eq $((${#ABS_TASK_MDS[@]} - 1)) ]]; then
        close_parent_args+=(--archive-terminal-parent)
      fi
      bash "${SCRIPT_DIR}/close-parent-spec-if-complete.sh" "${close_parent_args[@]}"
      ;;
  esac

  current_task_md="$(resolve_current_task_md_path "$moved_task_md")"
  bash "${CHECK_RELEASE_COMPLETED}" \
    --repo "$REPO_ROOT" \
    --task-md "$current_task_md" \
    ${TEMPLATE_REPO:+--template-repo "$TEMPLATE_REPO"}

  info "closed out ${task_id}"
done

info "PASS: framework release closeout completed for ${#ABS_TASK_MDS[@]} task(s)"
