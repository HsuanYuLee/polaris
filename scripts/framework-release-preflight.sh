#!/usr/bin/env bash
set -euo pipefail

PREFIX="[framework-release-preflight]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
TASK_MD=""
PR_URL=""
PR_HEAD_SHA=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/framework-release-preflight.sh --repo <workspace-repo> --task-md <task.md> [--pr-url <url>] [--pr-head-sha <sha>]

Validates framework-release preflight authority:
  1. remote PR head has head-bound PR create evidence;
  2. aggregate verify-AC V artifact has release-eligible disposition;
  3. release checkout is clean before closeout.
USAGE
}

die() {
  echo "$PREFIX BLOCKED: $1" >&2
  exit 2
}

abs_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (cd "$(dirname "$path")" && printf '%s/%s\n' "$(pwd)" "$(basename "$path")")
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --pr-url|--workspace-pr-url) PR_URL="${2:-}"; shift 2 ;;
    --pr-head-sha) PR_HEAD_SHA="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$REPO_ROOT" && -n "$TASK_MD" ]] || { usage; exit 64; }
[[ -d "$REPO_ROOT" ]] || die "repo not found: $REPO_ROOT"
[[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"

REPO_ROOT="$(abs_path "$REPO_ROOT")"
TASK_MD="$(abs_path "$TASK_MD")"

[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || die "repo is not a git checkout: $REPO_ROOT"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
  die "release worktree must be clean before framework-release closeout: $REPO_ROOT"
fi

task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field task_jira_key 2>/dev/null || true)"
case "$task_id" in
  ""|N/A|null)
    task_id="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field task_id 2>/dev/null || true)"
    ;;
esac
[[ -n "$task_id" && "$task_id" != "N/A" && "$task_id" != "null" ]] || die "cannot resolve task identity from $TASK_MD"

if [[ -z "$PR_URL" ]]; then
  PR_URL="$(bash "$SCRIPT_DIR/parse-task-md.sh" "$TASK_MD" --no-resolve --field deliverable_pr_url 2>/dev/null || true)"
fi
[[ -n "$PR_URL" && "$PR_URL" != "N/A" && "$PR_URL" != "null" ]] || die "workspace PR URL is required"

parse_pr_url() {
  python3 - "$1" <<'PY'
import re
import sys

value = sys.argv[1].strip()
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", value)
if not match:
    raise SystemExit(1)
owner, repo, number = match.groups()
print(f"{owner}/{repo}\t{number}")
PY
}

parsed="$(parse_pr_url "$PR_URL")" || die "workspace PR URL is not a GitHub PR URL: $PR_URL"
gh_repo="${parsed%%$'\t'*}"
pr_number="${parsed##*$'\t'}"

if [[ -z "$PR_HEAD_SHA" ]]; then
  command -v gh >/dev/null 2>&1 || die "gh is required to verify remote PR head"
  PR_HEAD_SHA="$(gh pr view "$PR_URL" --repo "$gh_repo" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
fi
[[ "$PR_HEAD_SHA" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "cannot resolve remote PR head SHA for $PR_URL"

resolve_evidence_repo() {
  local repo="$1"
  local common_git_dir=""
  if common_git_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    if [[ "$(basename "$common_git_dir")" == ".git" ]]; then
      dirname "$common_git_dir"
      return
    fi
  fi
  printf '%s\n' "$repo"
}

evidence_repo="$(resolve_evidence_repo "$REPO_ROOT")"
evidence_dir="${POLARIS_PR_CREATE_EVIDENCE_DIR:-$evidence_repo/.polaris/evidence/pr-create}"
pr_evidence="$evidence_dir/${task_id}-${PR_HEAD_SHA}.json"
[[ -f "$pr_evidence" ]] || die "missing head-bound PR create evidence: $pr_evidence"

python3 - "$pr_evidence" "$task_id" "$PR_HEAD_SHA" "$PR_URL" "$pr_number" <<'PY' || die "PR create evidence does not match remote PR head"
import json
import sys
from pathlib import Path

path, task_id, head_sha, pr_url, pr_number = sys.argv[1:6]
data = json.loads(Path(path).read_text(encoding="utf-8"))
assert data.get("writer") == "polaris-pr-create.sh", data
assert data.get("task_id") == task_id, data
assert str(data.get("head_sha")) == head_sha, data
assert data.get("pr_url") == pr_url, data
assert str(data.get("pr_number")) == str(pr_number), data
assert data.get("task_artifact_sha256"), data
assert data.get("gate_summary"), data
PY

source_container="$(python3 - "$TASK_MD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
parts = path.parts
if "tasks" not in parts:
    raise SystemExit(1)
idx = len(parts) - 1 - list(reversed(parts)).index("tasks")
print(Path(*parts[:idx]))
PY
)" || die "cannot resolve source container for $TASK_MD"

python3 - "$source_container" <<'PY' || die "verify-AC disposition is missing or not release-eligible"
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
tasks_dir = source / "tasks"
paths = []
if tasks_dir.exists():
    paths.extend(sorted(tasks_dir.glob("V*.md")))
    paths.extend(sorted(tasks_dir.glob("V*/index.md")))
    pr_release = tasks_dir / "pr-release"
    if pr_release.exists():
        paths.extend(sorted(pr_release.glob("V*.md")))
        paths.extend(sorted(pr_release.glob("V*/index.md")))

def frontmatter(path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    lines = text[4:end].splitlines()
    result = {}
    current = None
    for raw in lines:
        if not raw.startswith(" ") and ":" in raw:
            key, value = raw.split(":", 1)
            current = key.strip()
            result[current] = value.strip()
            continue
        if current == "ac_verification":
            stripped = raw.strip()
            if ":" in stripped:
                key, value = stripped.split(":", 1)
                result[f"ac_verification.{key.strip()}"] = value.strip().strip('"').strip("'")
    return result

if not paths:
    print("no V verification task found", file=sys.stderr)
    raise SystemExit(1)

eligible = False
errors = []
for path in paths:
    fm = frontmatter(path)
    status = fm.get("ac_verification.status", "")
    disposition = fm.get("ac_verification.human_disposition", "")
    summary = fm.get("ac_verification.summary", "")
    if not status:
        errors.append(f"{path}: missing ac_verification")
        continue
    if status == "PASS" and disposition == "passed":
        eligible = True
        continue
    if status == "MANUAL_REQUIRED" and disposition == "passed" and summary:
        eligible = True
        continue
    if status in {"FAIL", "UNCERTAIN", "BLOCKED_ENV", "IN_PROGRESS"}:
        errors.append(f"{path}: status {status} blocks release")
    else:
        errors.append(f"{path}: status={status or '<empty>'} human_disposition={disposition or '<empty>'} is not release-eligible")

if not eligible:
    print("; ".join(errors), file=sys.stderr)
    raise SystemExit(1)
PY

preflight_dir="${POLARIS_RELEASE_PREFLIGHT_DIR:-$evidence_repo/.polaris/evidence/framework-release-preflight}"
preflight_path="$preflight_dir/${task_id}-${PR_HEAD_SHA}.json"
python3 - "$preflight_path" "$task_id" "$PR_HEAD_SHA" "$PR_URL" "$pr_evidence" "$TASK_MD" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path, task_id, head_sha, pr_url, pr_evidence, task_md = sys.argv[1:7]
payload = {
    "schema_version": 1,
    "writer": "framework-release-preflight.sh",
    "written_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "task_id": task_id,
    "head_sha": head_sha,
    "pr_url": pr_url,
    "task_md": task_md,
    "pr_create_evidence": pr_evidence,
    "verify_ac": "release_eligible",
    "clean_worktree": True,
}
target = Path(path)
target.parent.mkdir(parents=True, exist_ok=True)
tmp = target.with_name(target.name + ".tmp")
tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
tmp.replace(target)
print(target)
PY
