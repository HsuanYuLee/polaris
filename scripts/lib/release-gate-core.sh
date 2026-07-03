#!/usr/bin/env bash
# Purpose: shared owner matrix, parsers, GitHub helpers, and small utilities for framework-release-pr-lane.sh.

list_stage_owners() {
  cat <<'OWNERS'
stage	label	owner	route_back	release_tail_only_reason
R1	script manifest release gate	release_tail_only	engineering	Validates the final release checkout immediately before feat/DP merge because the manifest surface is release-lane scoped.
R2	script header release gate	upstream:script-authoring	engineering	N/A
R3	script categorization release gate	upstream:script-governance	engineering	N/A
R4	governed script test suite	upstream:engineering-completion	engineering	N/A
R5	selftest enrollment gate	upstream:selftest-governance	engineering	N/A
R6	aggregate selftest corpus	upstream:selftest-governance	engineering	N/A
R7	task PR lineage and base legality	release_tail_only	engineering	Requires live GitHub task PR state and the final feat/DP aggregation topology, which only exist at release tail.
R8	bundle PR lineage and base legality	release_tail_only	engineering	Bootstrap fallback legality requires the live bundle PR and member task mapping, which only exist at release tail.
R9	main contains final release head	release_tail_only	framework-release	This is a post-merge release-tail invariant over origin/main ancestry, not an implementation repair gate.
OWNERS
}

die() {
  echo "$PREFIX ERROR: $*" >&2
  exit 2
}

info() {
  echo "$PREFIX $*" >&2
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  else
    printf '%s\n' "$(cd -P "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  fi
}

table_field() {
  local field="$1"
  local file="$2"
  awk -F '|' -v key="$field" '
    /^[[:space:]]*\|[[:space:]]*-+/ { next }
    NF >= 3 {
      f = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
      if (f == key) {
        v = $3
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file"
}

task_frontmatter_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
field = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()

if not lines or lines[0] != "---":
    print("")
    raise SystemExit(0)

try:
    end = lines[1:].index("---") + 1
except ValueError:
    print("")
    raise SystemExit(0)

in_deliverable = False
in_verification = False
for raw in lines[1:end]:
    if raw == "deliverable:":
        in_deliverable = True
        in_verification = False
        continue
    if in_deliverable and raw and not raw.startswith((" ", "-")):
        in_deliverable = False
        in_verification = False
    if not in_deliverable:
        continue

    stripped = raw.strip()
    if stripped == "verification:":
        in_verification = True
        continue
    if in_verification and raw.startswith("  ") and not raw.startswith("    ") and stripped != "verification:":
        in_verification = False

    if field == "deliverable_verification_status" and in_verification and raw.startswith("    status:"):
        print(raw.split(":", 1)[1].strip())
        raise SystemExit(0)

    if in_verification:
        continue

    key_by_field = {
        "deliverable_pr_url": "pr_url",
        "deliverable_pr_state": "pr_state",
        "deliverable_head_sha": "head_sha",
    }
    key = key_by_field.get(field)
    if key and raw.startswith(f"  {key}:"):
        print(raw.split(":", 1)[1].strip())
        raise SystemExit(0)

print("")
PY
}

head_matches() {
  local recorded="$1"
  local actual="$2"
  [[ -n "$recorded" && -n "$actual" ]] || return 1
  [[ "$recorded" == "$actual" || "$actual" == "$recorded"* ]]
}

route_back_upstream_evidence() {
  local task_id="$1"
  local evidence_status="$2"
  local detail="$3"

  die "release preflight route-back: stage=R2-R6 owner=upstream:engineering-completion route_back=engineering evidence_status=${evidence_status} task=${task_id} ${detail}"
}

check_task_upstream_evidence_freshness() {
  local task_md="$1"
  local task_id="$2"
  local pr_head="$3"
  local recorded_head verification_status

  recorded_head="$(task_frontmatter_field "$task_md" deliverable_head_sha)"
  verification_status="$(task_frontmatter_field "$task_md" deliverable_verification_status)"

  if [[ -z "$recorded_head" || -z "$verification_status" ]]; then
    route_back_upstream_evidence "$task_id" "missing" "expected=deliverable.head_sha+deliverable.verification.status"
  fi
  if [[ "$verification_status" != "PASS" ]]; then
    route_back_upstream_evidence "$task_id" "non_pass" "verification_status=${verification_status}"
  fi
  if ! head_matches "$recorded_head" "$pr_head"; then
    route_back_upstream_evidence "$task_id" "stale" "recorded_head=${recorded_head} pr_head=${pr_head}"
  fi

  info "upstream evidence fresh: stage=R2-R6 owner=upstream:engineering-completion route_back=engineering evidence_status=fresh task=${task_id} head=${recorded_head}"
}

json_field() {
  local json="$1"
  local expr="$2"
  python3 -c "import json,sys; d=json.load(sys.stdin); print(${expr} or '')" <<<"$json"
}

# DP-270: extract `bundle_branch_alias` from a task.md leading YAML frontmatter
# block. Same parse shape as resolve-task-md-by-branch.sh / gate-work-source.sh.
# Empty stdout when the task.md is not a bundle member.
task_md_bundle_alias() {
  local file="$1"
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^bundle_branch_alias:/ {
      sub(/^bundle_branch_alias:[[:space:]]*/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file" 2>/dev/null || true
}

line_in_list() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

is_feat_aggregation_branch() {
  local branch="$1"
  [[ "$branch" == feat/DP-* ]]
}

fetch_remote_branch_ref() {
  local branch="$1"
  git -C "$REPO_PATH" fetch -q origin "+refs/heads/${branch}:refs/remotes/origin/${branch}"
}

remote_branch_contains_head() {
  local branch="$1"
  local head="$2"
  fetch_remote_branch_ref "$branch" >/dev/null 2>&1 || return 1
  git -C "$REPO_PATH" cat-file -e "${head}^{commit}" >/dev/null 2>&1 || return 1
  git -C "$REPO_PATH" merge-base --is-ancestor "$head" "refs/remotes/origin/${branch}" >/dev/null 2>&1
}

assert_feat_branch_linear_release_head() {
  local branch="$1"
  local merge_commits=""

  [[ -n "$branch" ]] || die "release preflight blocked: empty feat aggregation branch"
  is_feat_aggregation_branch "$branch" || return 0
  fetch_remote_branch_ref "$branch" \
    || die "release preflight blocked: cannot fetch aggregation branch '$branch'"
  git -C "$REPO_PATH" fetch -q origin main >/dev/null 2>&1 || true

  if git -C "$REPO_PATH" rev-parse --verify "refs/remotes/origin/main" >/dev/null 2>&1; then
    merge_commits="$(git -C "$REPO_PATH" log --format='%H %s' --merges "refs/remotes/origin/main..refs/remotes/origin/${branch}" || true)"
  else
    merge_commits="$(git -C "$REPO_PATH" log --format='%H %s' --merges "refs/remotes/origin/${branch}" || true)"
  fi

  if [[ -n "$merge_commits" ]]; then
    die "release preflight blocked: $branch contains merge commits in its release range; framework-release requires a linear feat head before version compression. Offending commits: $(printf '%s' "$merge_commits" | tr '\n' '; ')"
  fi
}

assert_feat_branch_contains_current_main() {
  local branch="$1"
  local main_sha=""
  local branch_sha=""
  local merge_base=""

  [[ -n "$branch" ]] || die "release preflight blocked: empty feat aggregation branch"
  is_feat_aggregation_branch "$branch" || return 0
  fetch_remote_branch_ref "$branch" \
    || die "release preflight blocked: cannot fetch aggregation branch '$branch'"
  git -C "$REPO_PATH" fetch -q origin main \
    || die "release preflight blocked: cannot fetch origin/main"

  main_sha="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/main")"
  branch_sha="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/${branch}")"
  if ! git -C "$REPO_PATH" merge-base --is-ancestor "refs/remotes/origin/main" "refs/remotes/origin/${branch}" >/dev/null 2>&1; then
    merge_base="$(git -C "$REPO_PATH" merge-base "refs/remotes/origin/main" "refs/remotes/origin/${branch}" 2>/dev/null || true)"
    die "release preflight blocked: $branch does not contain current origin/main before version compression; re-drive or rebase the DP stack on current main. origin/main=${main_sha} ${branch}=${branch_sha} merge_base=${merge_base:-unknown}"
  fi
}

fast_forward_feat_task_pr() {
  local task_id="$1"
  local number="$2"
  local base="$3"
  local head_branch="$4"
  local head="$5"
  local new_head

  [[ -n "$head_branch" ]] || die "PR #$number for $task_id has empty headRefName"
  fetch_remote_branch_ref "$base" \
    || die "release preflight blocked: cannot fetch aggregation branch '$base'"
  git -C "$REPO_PATH" fetch -q origin "+refs/heads/${head_branch}:refs/remotes/origin/${head_branch}" \
    || die "release preflight blocked: cannot fetch task branch '$head_branch'"
  git -C "$REPO_PATH" cat-file -e "${head}^{commit}" >/dev/null 2>&1 \
    || die "release preflight blocked: task head $head is not available locally after fetch"
  git -C "$REPO_PATH" merge-base --is-ancestor "refs/remotes/origin/${base}" "$head" \
    || die "release preflight blocked: $base cannot fast-forward to $task_id head $head; rebase the task branch onto the current aggregation branch first"

  info "fast-forwarding $base to PR #$number ($task_id) head $head"
  git -C "$REPO_PATH" push origin "$head:refs/heads/${base}" \
    || die "release preflight blocked: push fast-forward to $base failed"
  fetch_remote_branch_ref "$base" \
    || die "release preflight blocked: cannot refetch aggregation branch '$base' after fast-forward"
  new_head="$(git -C "$REPO_PATH" rev-parse "refs/remotes/origin/${base}")"
  [[ "$new_head" == "$head" ]] \
    || die "release preflight blocked: $base fast-forward verification failed; expected $head got $new_head"
}

gh_repo_args=()
refresh_gh_repo_args() {
  gh_repo_args=()
  if [[ -n "$WORKSPACE_REPO" ]]; then
    gh_repo_args=(--repo "$WORKSPACE_REPO")
  fi
}

resolve_workspace_repo_slug() {
  [[ -n "$WORKSPACE_REPO" ]] && return 0
  if declare -F polaris_github_repo_slug >/dev/null 2>&1; then
    WORKSPACE_REPO="$(polaris_github_repo_slug "$REPO_PATH" 2>/dev/null || true)"
  fi
  if [[ -z "$WORKSPACE_REPO" ]]; then
    WORKSPACE_REPO="$(git -C "$REPO_PATH" remote get-url origin 2>/dev/null | python3 -c '
import re
import sys
url = sys.stdin.read().strip()
patterns = [
    r"github\\.com[:/]([^/]+)/([^/.]+)(?:\\.git)?$",
    r"https://github\\.com/([^/]+)/([^/.]+)(?:\\.git)?$",
]
for pattern in patterns:
    m = re.search(pattern, url)
    if m:
        print(f"{m.group(1)}/{m.group(2)}")
        break
' || true)"
  fi
}

resolve_gh_bin() {
  if [[ -n "${GH_BIN:-}" && "$GH_BIN" != "gh" ]]; then
    [[ -x "$GH_BIN" ]] || die "POLARIS_TOOL_MISSING tool=gh owner=delivery install_authority=system hint=GH_BIN is not executable: $GH_BIN"
    "$GH_BIN" auth status >/dev/null 2>&1 || die "POLARIS_TOOL_AUTH_FAILED tool=gh owner=delivery install_authority=system hint=GitHub CLI is installed but not authenticated"
    return 0
  fi
  GH_BIN="$(polaris_require_delivery_tool gh)" || die "GitHub CLI delivery preflight failed"
}

pr_view_json() {
  local branch="$1"
  local gh_repo="$WORKSPACE_REPO"
  local owner=""
  local rest_json=""

  if [[ -z "$gh_repo" ]] && declare -F polaris_github_repo_slug >/dev/null 2>&1; then
    gh_repo="$(polaris_github_repo_slug "$REPO_PATH" 2>/dev/null || true)"
  fi

  if [[ -n "$gh_repo" ]] && declare -F polaris_gh_api >/dev/null 2>&1; then
    owner="${gh_repo%%/*}"
    rest_json="$(polaris_gh_api "repos/${gh_repo}/pulls" \
      --method GET \
      -f "head=${owner}:${branch}" \
      -f "state=all" \
      -f "per_page=1" \
      --jq '.[0] | {
        number: .number,
        state: (if .merged_at then "MERGED" else (.state | ascii_upcase) end),
        baseRefName: .base.ref,
        headRefName: .head.ref,
        headRefOid: .head.sha,
        mergeStateStatus: (.mergeable_state // "unknown"),
        url: .html_url
      }' 2>/dev/null || true)"
    if [[ -n "$rest_json" && "$rest_json" != "null" ]]; then
      printf '%s\n' "$rest_json"
      return
    fi
  fi

  "$GH_BIN" pr view "$branch" ${gh_repo_args[@]+"${gh_repo_args[@]}"} \
    --json number,state,baseRefName,headRefName,headRefOid,mergeStateStatus,url
}
