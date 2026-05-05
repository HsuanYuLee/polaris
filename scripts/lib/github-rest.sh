#!/usr/bin/env bash
# Shared GitHub REST helpers for Polaris shell scripts.
#
# Prefer these helpers over `gh pr view/list/checks --json` for metadata reads.
# The gh PR subcommands use GraphQL for several JSON fields; these wrappers use
# REST endpoints through `gh api` and add a small retry loop for rate-limit cases.

polaris_gh_api() {
  local attempt=1
  local max_attempts="${POLARIS_GH_API_MAX_ATTEMPTS:-3}"
  local delay="${POLARIS_GH_API_BACKOFF_SECONDS:-2}"
  local out_file=""
  local err_file=""
  local rc=0
  local had_errexit=0

  out_file="$(mktemp -t polaris-gh-api-out.XXXXXX)"
  err_file="$(mktemp -t polaris-gh-api-err.XXXXXX)"

  while [[ "$attempt" -le "$max_attempts" ]]; do
    : >"$out_file"
    : >"$err_file"
    case "$-" in
      *e*) had_errexit=1; set +e ;;
      *) had_errexit=0 ;;
    esac
    gh api "$@" >"$out_file" 2>"$err_file"
    rc=$?
    [[ "$had_errexit" -eq 1 ]] && set -e
    if [[ "$rc" -eq 0 ]]; then
      cat "$out_file"
      rm -f "$out_file" "$err_file"
      return 0
    fi

    if grep -qiE 'rate limit|secondary rate|abuse detection|api rate' "$err_file" && [[ "$attempt" -lt "$max_attempts" ]]; then
      printf '[polaris github-rest] rate limit detected; retrying in %ss (attempt %s/%s)\n' "$delay" "$attempt" "$max_attempts" >&2
      sleep "$delay"
      delay=$((delay * 2))
      attempt=$((attempt + 1))
      continue
    fi

    cat "$err_file" >&2
    rm -f "$out_file" "$err_file"
    return "$rc"
  done

  rm -f "$out_file" "$err_file"
  return 1
}

polaris_github_repo_slug() {
  local repo_root="$1"
  local remote=""

  remote="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$remote" ]] || return 1

  python3 - "$remote" <<'PY'
import re
import sys

remote = sys.argv[1].strip()
remote = re.sub(r"^git@github\.com:", "", remote)
remote = re.sub(r"^https://github\.com/", "", remote)
remote = re.sub(r"\.git$", "", remote)
remote = remote.strip("/")
if re.fullmatch(r"[^/]+/[^/]+", remote):
    print(remote)
else:
    raise SystemExit(1)
PY
}

polaris_pr_rest_to_gh_json() {
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
if isinstance(data, list):
    if not data:
        raise SystemExit(1)
    data = data[0]

state = (data.get("state") or "").upper()
if state == "CLOSED" and data.get("merged_at"):
    state = "MERGED"

head = data.get("head") or {}
base = data.get("base") or {}
user = data.get("user") or {}

print(json.dumps({
    "number": data.get("number"),
    "title": data.get("title") or "",
    "body": data.get("body") or "",
    "author": {"login": user.get("login") or ""},
    "state": state,
    "url": data.get("html_url") or "",
    "isDraft": bool(data.get("draft")),
    "headRefName": head.get("ref") or "",
    "headRefOid": head.get("sha") or "",
    "baseRefName": base.get("ref") or "",
}, separators=(",", ":")))
'
}

polaris_pr_view_rest() {
  local gh_repo="$1"
  local pr_number="$2"

  polaris_gh_api "repos/${gh_repo}/pulls/${pr_number}" | polaris_pr_rest_to_gh_json
}

polaris_current_branch_pr_rest() {
  local repo_root="$1"
  local gh_repo=""
  local owner=""
  local branch=""

  gh_repo="$(polaris_github_repo_slug "$repo_root")" || return 1
  owner="${gh_repo%%/*}"
  branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 1

  polaris_gh_api "repos/${gh_repo}/pulls" \
    --method GET \
    -f "head=${owner}:${branch}" \
    -f "state=open" \
    -f "per_page=1" | polaris_pr_rest_to_gh_json
}

polaris_pr_checks_rest() {
  local gh_repo="$1"
  local pr_number="$2"
  local pr_json=""
  local head_sha=""
  local checks_json=""
  local statuses_json=""

  pr_json="$(polaris_pr_view_rest "$gh_repo" "$pr_number")" || return 1
  head_sha="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("headRefOid") or "")')"
  [[ -n "$head_sha" ]] || return 1

  checks_json="$(polaris_gh_api "repos/${gh_repo}/commits/${head_sha}/check-runs" --method GET -f "per_page=100" 2>/dev/null || echo '{"check_runs":[]}')"
  statuses_json="$(polaris_gh_api "repos/${gh_repo}/commits/${head_sha}/statuses" --method GET -f "per_page=100" 2>/dev/null || echo '[]')"

  python3 - "$checks_json" "$statuses_json" <<'PY'
import json
import sys

checks_payload = json.loads(sys.argv[1] or '{"check_runs":[]}')
statuses_payload = json.loads(sys.argv[2] or "[]")

def check_state(run):
    status = run.get("status") or ""
    conclusion = run.get("conclusion") or ""
    if status != "completed":
        return "PENDING"
    if conclusion in {"success", "neutral", "skipped"}:
        return "SUCCESS"
    if conclusion in {"failure", "cancelled", "timed_out", "action_required", "stale"}:
        return "FAILURE"
    return "PENDING"

def status_state(status):
    value = status.get("state") or ""
    if value == "success":
        return "SUCCESS"
    if value in {"failure", "error"}:
        return "FAILURE"
    return "PENDING"

items = []
for run in checks_payload.get("check_runs") or []:
    items.append({
        "name": run.get("name") or "",
        "state": check_state(run),
        "description": run.get("output", {}).get("summary") or run.get("conclusion") or run.get("status") or "",
    })

seen = {item["name"] for item in items}
for status in statuses_payload or []:
    name = status.get("context") or ""
    if name in seen:
        continue
    seen.add(name)
    items.append({
        "name": name,
        "state": status_state(status),
        "description": status.get("description") or "",
    })

print(json.dumps(items, separators=(",", ":")))
PY
}
