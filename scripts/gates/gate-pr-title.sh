#!/usr/bin/env bash
set -euo pipefail

# gate-pr-title.sh — Developer PR title gate.
# Enforces engineer-delivery-flow Developer title format. The expected format is
# read from company workspace-config.yaml projects[].delivery.pr_title.developer
# when configured, then falls back to:
#   [{TICKET}] {summary}
#
# Usage:
#   bash scripts/gates/gate-pr-title.sh [--repo <path>] [--task-md <path>] [--title <title>]
#
# If --title is omitted, the gate reads the current branch's PR title via gh.
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_PR_TITLE_GATE=1

PREFIX="[polaris gate-pr-title]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
RESOLVE_BY_BRANCH="${WORKSPACE_SCRIPTS}/resolve-task-md-by-branch.sh"
PARSE_TASK="${WORKSPACE_SCRIPTS}/parse-task-md.sh"
ENV_LIB="${WORKSPACE_SCRIPTS}/env/_lib.sh"

REPO_ROOT=""
TASK_MD=""
ACTUAL_TITLE=""

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

ticket="$(bash "$PARSE_TASK" "$TASK_MD" --field task_jira_key 2>/dev/null || true)"
summary="$(bash "$PARSE_TASK" "$TASK_MD" --field summary 2>/dev/null || true)"

if [[ -z "$ticket" || -z "$summary" ]]; then
  echo "$PREFIX BLOCKED: could not derive ticket/summary from $TASK_MD" >&2
  exit 2
fi

resolve_title_template() {
  local repo_root="$1"
  local fallback="[{TICKET}] {summary}"

  [[ -f "$ENV_LIB" ]] || { echo "$fallback"; return 0; }
  # shellcheck source=/dev/null
  source "$ENV_LIB"

  local cfg
  cfg="$(env_lib_find_workspace_config "$repo_root" 2>/dev/null || true)"
  [[ -n "$cfg" && -f "$cfg" ]] || { echo "$fallback"; return 0; }

  local remote repo_basename
  remote="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || true)"
  repo_basename="$(basename "$repo_root")"

  python3 - "$cfg" "$repo_basename" "$remote" "$fallback" <<'PY' 2>/dev/null || echo "$fallback"
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

title_template="$(resolve_title_template "$REPO_ROOT")"
expected_title="$(render_title_template "$title_template" "$ticket" "$summary")"

if [[ -z "$ACTUAL_TITLE" ]]; then
  command -v gh >/dev/null 2>&1 || exit 0
  ACTUAL_TITLE="$(cd "$REPO_ROOT" && gh pr view --json title --jq .title 2>/dev/null || true)"
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
$PREFIX BLOCKED: PR title does not match Developer format.
  Task.md:  $TASK_MD
  Template: $title_template
  Expected: $expected_title
  Actual:   $ACTUAL_TITLE

Fix:
  gh pr edit --title "$expected_title"
EOF
exit 2
