#!/usr/bin/env bash
set -euo pipefail

# gate-pr-title.sh — Developer PR title gate.
# Enforces engineer-delivery-flow Developer title format. The expected format is
# read from company workspace-config.yaml projects[].delivery.pr_title.developer
# when configured, then falls back to:
#   [{TICKET}] {summary}
#
# Aggregate-release lane (FD6, DP-301-T3): when the resolved task.md carries a
# `bundle_branch_alias` frontmatter field matching the current branch — the SAME
# aggregate-release detection source DP-287 gate-work-source.sh uses — the gate
# switches to the bundle title contract:
#   chore(release): bundle DP-NNN -> vX.Y.Z
# In that lane a valid bundle title passes WITHOUT POLARIS_SKIP_PR_TITLE_GATE,
# and an invalid one still fails closed. The non-aggregate developer-title
# contract is unchanged (the relaxation is scoped to aggregate-release only).
#
# DP-334 Migration Boundaries: the bundle_branch_alias title lane is RETAINED as a
# bootstrap fallback only. Framework DP delivery now keys off feat/DP-NNN
# aggregation; a feat-lifecycle DP task PR (no bundle_branch_alias) falls through
# to the unchanged developer title contract below. Removal criteria: removed in
# DP-334 once it self-releases under the feat model (AC7 PASS); see
# docs-manager/.../DP-334-framework-release-feature-branch-aggregation-release-model/index.md
# § Migration Boundaries.
#
# Usage:
#   bash scripts/gates/gate-pr-title.sh [--repo <path>] [--task-md <path>] [--title <title>]
#
# If --title is omitted, the gate reads the current branch's PR title via gh.
#
# Exit: 0 = pass/skip, 2 = block (with POLARIS_PR_TITLE_GATE_BLOCKED on stderr)
# Bypass: POLARIS_SKIP_PR_TITLE_GATE=1

PREFIX="[polaris gate-pr-title]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
RESOLVE_BY_BRANCH="${WORKSPACE_SCRIPTS}/resolve-task-md-by-branch.sh"
PARSE_TASK="${WORKSPACE_SCRIPTS}/parse-task-md.sh"
ENV_LIB="${WORKSPACE_SCRIPTS}/env/_lib.sh"
RESOLVE_COMPANY_CONTEXT="${WORKSPACE_SCRIPTS}/resolve-company-context.sh"
GATE_PR_LANGUAGE="${SCRIPT_DIR}/gate-pr-language.sh"
GITHUB_REST_LIB="${WORKSPACE_SCRIPTS}/lib/github-rest.sh"

REPO_ROOT=""
TASK_MD=""
ACTUAL_TITLE=""
TITLE_TEMPLATE_RESOLUTION_ERROR=""
RESOLVED_TITLE_TEMPLATE=""

if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=../lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --title) ACTUAL_TITLE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-pr-title.sh [--repo <path>] [--task-md <path>] [--title <title>]"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_PR_TITLE_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_PR_TITLE_GATE=1 — bypassing." >&2
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

if [[ -z "$TASK_MD" ]]; then
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    exit 0
  fi
  TASK_MD="$(bash "$RESOLVE_BY_BRANCH" --scan-root "$WORKSPACE_SCRIPTS/.." "$branch" 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$TASK_MD" ]]; then
  # Non-managed branch/admin workflow.
  exit 0
fi

if [[ ! -f "$TASK_MD" ]]; then
  echo "$PREFIX BLOCKED: resolved task.md does not exist: $TASK_MD" >&2
  exit 2
fi

# read_bundle_branch_alias: echo the first-frontmatter `bundle_branch_alias`
# value of a task.md, or empty when absent. This mirrors DP-287
# gate-work-source.sh: aggregate-release is identified by the bundle_branch_alias
# frontmatter (written by engineering-branch-setup.sh --aggregate-release)
# matching the current branch. Shared detection source — no second detector.
read_bundle_branch_alias() {
  local task_md="$1"
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^bundle_branch_alias:/ {
      sub(/^bundle_branch_alias:[[:space:]]*/, "")
      print
      exit
    }
  ' "$task_md" 2>/dev/null || true
}

# acquire_actual_title: resolve the PR title to validate. Prefers the explicit
# --title; otherwise reads the current branch's PR title via gh (D7
# readiness-probe carve-out: fail-open when gh is unavailable). Echoes the title
# (possibly empty).
acquire_actual_title() {
  local repo_root="$1"
  local explicit="$2"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  local title=""
  if declare -F polaris_current_branch_pr_rest >/dev/null 2>&1; then
    title="$(polaris_current_branch_pr_rest "$repo_root" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("title") or "")' 2>/dev/null || true)"
  fi
  if [[ -z "$title" ]]; then
    title="$(cd "$repo_root" && gh pr view --json title --jq .title 2>/dev/null || true)"
  fi
  printf '%s\n' "$title"
}

# Aggregate-release lane (FD6): when the task.md bundle_branch_alias matches the
# current branch, validate the bundle title format instead of the developer
# format, with no POLARIS_SKIP_PR_TITLE_GATE requirement. Bundle title contract:
#   chore(release): bundle DP-NNN -> vX.Y.Z
BUNDLE_BRANCH_ALIAS="$(read_bundle_branch_alias "$TASK_MD")"
if [[ -n "$BUNDLE_BRANCH_ALIAS" && -n "$branch" && "$branch" == "$BUNDLE_BRANCH_ALIAS" ]]; then
  bundle_title_regex='^chore\(release\): bundle DP-[0-9]+ -> v[0-9]+\.[0-9]+\.[0-9]+$'
  agg_actual_title="$(acquire_actual_title "$REPO_ROOT" "$ACTUAL_TITLE")"
  if [[ -z "$agg_actual_title" ]]; then
    # No PR yet and no --title supplied; nothing to validate.
    exit 0
  fi
  if [[ "$agg_actual_title" =~ $bundle_title_regex ]]; then
    echo "$PREFIX ✅ aggregate-release PR title matches bundle format." >&2
    exit 0
  fi
  cat >&2 <<EOF
$PREFIX BLOCKED: POLARIS_PR_TITLE_GATE_BLOCKED aggregate-release PR title does not match bundle format.
  Task.md:  $TASK_MD
  Branch:   $branch (aggregate-release bundle)
  Expected: chore(release): bundle DP-NNN -> vX.Y.Z
  Actual:   $agg_actual_title

Fix:
  gh pr edit --title "chore(release): bundle DP-NNN -> vX.Y.Z"
EOF
  exit 2
fi

# delivery_ticket_key is the canonical product-PR-identity atom (DP-238): Bug
# source = real JIRA key (e.g. PROJ-4190); DP source = work_item_id (e.g.
# DP-238-T4). The legacy task_jira_key alias holds the internal work_item_id for
# Bug sources and must not be used here, or the internal task marker would leak
# into the reviewer-visible PR title (AC-NEG5).
ticket="$(bash "$PARSE_TASK" "$TASK_MD" --field delivery_ticket_key 2>/dev/null || true)"
summary="$(bash "$PARSE_TASK" "$TASK_MD" --field summary 2>/dev/null || true)"

if [[ -z "$ticket" || -z "$summary" ]]; then
  echo "$PREFIX BLOCKED: could not derive ticket/summary from $TASK_MD" >&2
  exit 2
fi

resolve_title_template() {
  local repo_root="$1"
  local ticket="$2"
  local fallback="[{TICKET}] {summary}"

  TITLE_TEMPLATE_RESOLUTION_ERROR=""
  RESOLVED_TITLE_TEMPLATE="$fallback"

  [[ -f "$ENV_LIB" ]] || return 0
  # shellcheck source=/dev/null
  source "$ENV_LIB"

  local cfg=""
  if [[ -n "$ticket" && "$ticket" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ && -x "$RESOLVE_COMPANY_CONTEXT" ]]; then
    local resolver_status resolver_error
    resolver_status="$("$RESOLVE_COMPANY_CONTEXT" --ticket "$ticket" --format field --field status 2>/dev/null || true)"
    if [[ "$resolver_status" == "error" ]]; then
      resolver_error="$("$RESOLVE_COMPANY_CONTEXT" --ticket "$ticket" --format field --field error_code 2>/dev/null || true)"
      TITLE_TEMPLATE_RESOLUTION_ERROR="${resolver_error:-resolver_failed}"
      return 0
    fi
    cfg="$("$RESOLVE_COMPANY_CONTEXT" --ticket "$ticket" --format field --field config_path 2>/dev/null || true)"
  fi

  if [[ -z "$cfg" ]]; then
    cfg="$(env_lib_find_workspace_config "$repo_root" 2>/dev/null || true)"
  fi
  [[ -n "$cfg" && -f "$cfg" ]] || return 0

  local remote repo_basename
  remote="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || true)"
  repo_basename="$(basename "$repo_root")"

  RESOLVED_TITLE_TEMPLATE="$(python3 - "$cfg" "$repo_basename" "$remote" "$fallback" <<'PY' 2>/dev/null || echo "$fallback"
import os, re, sys

try:
    import yaml
except Exception:
    print(sys.argv[4])
    raise SystemExit(0)

cfg_path, repo_basename, remote, fallback = sys.argv[1:5]

def normalize_repo(value):
    value = (value or "").strip()
    if not value:
        return ""
    value = re.sub(r"^git@github\.com:", "", value)
    value = re.sub(r"^https://github\.com/", "", value)
    value = value[:-4] if value.endswith(".git") else value
    return value.strip("/")

remote_norm = normalize_repo(remote)
basename_norm = os.path.basename(remote_norm) if remote_norm else repo_basename

with open(cfg_path) as f:
    data = yaml.safe_load(f) or {}

for project in data.get("projects") or []:
    repo = normalize_repo(project.get("repo"))
    name = (project.get("name") or "").strip()
    if repo and repo == remote_norm or name and name == repo_basename or repo and os.path.basename(repo) == basename_norm:
        delivery = project.get("delivery") or {}
        pr_title = delivery.get("pr_title") or {}
        template = pr_title.get("developer") or pr_title.get("template") or ""
        print(template or fallback)
        raise SystemExit(0)

print(fallback)
PY
)"
}

render_title_template() {
  local template="$1"
  local ticket="$2"
  local summary="$3"
  local rendered="$template"
  rendered="${rendered//\{TICKET\}/$ticket}"
  rendered="${rendered//\{ticket\}/$ticket}"
  rendered="${rendered//\{summary\}/$summary}"
  printf '%s\n' "$rendered"
}

resolve_title_template "$REPO_ROOT" "$ticket"
if [[ -n "$TITLE_TEMPLATE_RESOLUTION_ERROR" ]]; then
  cat >&2 <<EOF
$PREFIX BLOCKED: cannot resolve company-specific PR title template for $ticket.
  Reason: $TITLE_TEMPLATE_RESOLUTION_ERROR
  Task.md: $TASK_MD

Fix:
  Resolve company routing first (for example via /use-company), or fix workspace-config company routing so the shared resolver can map $ticket.
EOF
  exit 2
fi
title_template="$RESOLVED_TITLE_TEMPLATE"
expected_title="$(render_title_template "$title_template" "$ticket" "$summary")"

if [[ -x "$GATE_PR_LANGUAGE" ]]; then
  if ! "$GATE_PR_LANGUAGE" --repo "$REPO_ROOT" --title "$expected_title" >/dev/null 2>&1; then
    cat >&2 <<EOF
$PREFIX BLOCKED: task summary / PR title template is incompatible with workspace language policy.
  Task.md:  $TASK_MD
  Template: $title_template
  Expected: $expected_title

Fix:
  Update the task summary/title so the rendered PR title satisfies the workspace language policy.
EOF
    exit 2
  fi
fi

if [[ -z "$ACTUAL_TITLE" ]]; then
  # D7 readiness-probe carve-out: fail-open because title can be supplied explicitly.
  command -v gh >/dev/null 2>&1 || exit 0
  if declare -F polaris_current_branch_pr_rest >/dev/null 2>&1; then
    ACTUAL_TITLE="$(polaris_current_branch_pr_rest "$REPO_ROOT" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("title") or "")' 2>/dev/null || true)"
  fi
  if [[ -z "$ACTUAL_TITLE" ]]; then
    ACTUAL_TITLE="$(cd "$REPO_ROOT" && gh pr view --json title --jq .title 2>/dev/null || true)"
  fi
fi

if [[ -z "$ACTUAL_TITLE" ]]; then
  # No PR yet and no --title supplied; nothing to validate.
  exit 0
fi

if [[ "$ACTUAL_TITLE" == "$expected_title" ]]; then
  echo "$PREFIX ✅ PR title matches Developer format." >&2
  exit 0
fi

cat >&2 <<EOF
$PREFIX BLOCKED: POLARIS_PR_TITLE_GATE_BLOCKED PR title does not match Developer format.
  Task.md:  $TASK_MD
  Template: $title_template
  Expected: $expected_title
  Actual:   $ACTUAL_TITLE

Fix:
  gh pr edit --title "$expected_title"
EOF
exit 2
