#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/refresh-baseline-snapshot.sh --repo PATH --task-md PATH [--head-sha SHA] [--evidence PATH]

Refreshes planner-owned baseline snapshot after breakdown route=task_update.
Existing snapshots for the same task are renamed to *.superseded.
USAGE
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

REPO=""
TASK_MD=""
HEAD_SHA=""
EVIDENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$TASK_MD" ]] || usage
[[ -d "$REPO" ]] || { echo "ERROR: repo not found: $REPO" >&2; exit 2; }
[[ -f "$TASK_MD" ]] || { echo "ERROR: task-md not found: $TASK_MD" >&2; exit 2; }
[[ -z "$EVIDENCE" || -f "$EVIDENCE" ]] || { echo "ERROR: evidence not found: $EVIDENCE" >&2; exit 2; }

if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git -C "$REPO" rev-parse --verify HEAD 2>/dev/null || true)"
fi
[[ -n "$HEAD_SHA" ]] || { echo "ERROR: unable to resolve head sha" >&2; exit 2; }

python3 - "$PARSE_TASK_MD" "$REPO" "$TASK_MD" "$HEAD_SHA" "$EVIDENCE" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

parser, repo, task_md, head_sha, evidence = sys.argv[1:6]
repo_path = Path(repo).resolve()
task_path = Path(task_md).resolve()

def evidence_root(repo_root: Path) -> Path:
    git_file = repo_root / ".git"
    if git_file.is_file():
        text = git_file.read_text(encoding="utf-8", errors="ignore").strip()
        if text.startswith("gitdir:"):
            git_dir = (git_file.parent / text.split(":", 1)[1].strip()).resolve()
            common = git_dir.parent.parent
            if common.name == ".git":
                return common.parent
    return repo_root

proc = subprocess.run(
    ["bash", parser, str(task_path), "--no-resolve"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    check=True,
)
data = json.loads(proc.stdout)
identity = data.get("identity") or {}
op = data.get("operational_context") or {}
task_id = identity.get("work_item_id") or op.get("task_id") or op.get("task_jira_key")
if not task_id:
    raise SystemExit("missing task identity for baseline snapshot")

def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

planner_owned = {
    "verify_command": data.get("verify_command") or "",
    "depends_on": (data.get("frontmatter") or {}).get("depends_on") or [],
    "base_branch": op.get("base_branch") or "",
    "allowed_files": data.get("allowed_files") or [],
}
snapshot = {
    "schema_version": 1,
    "writer": "refresh-baseline-snapshot.sh",
    "refresh_reason": "breakdown_escalation_intake_task_update",
    "refresh_evidence": str(Path(evidence).resolve()) if evidence else "N/A",
    "task_id": task_id,
    "task_md": str(task_path),
    "head_sha": head_sha,
    "planner_owned": planner_owned,
    "hashes": {
        "verify_command_sha256": digest(planner_owned["verify_command"]),
        "depends_on_sha256": digest(planner_owned["depends_on"]),
        "base_branch_sha256": digest(planner_owned["base_branch"]),
        "allowed_files_sha256": digest(planner_owned["allowed_files"]),
    },
    "task_artifact_sha256": hashlib.sha256(task_path.read_bytes()).hexdigest(),
}

out_dir = evidence_root(repo_path) / ".polaris" / "evidence" / "baseline-snapshot"
out_dir.mkdir(parents=True, exist_ok=True)
target = out_dir / f"{task_id}-{head_sha}.json"
for old in out_dir.glob(f"{task_id}-*.json"):
    if old == target or old.name.endswith(".superseded"):
        continue
    superseded = old.with_name(old.name + ".superseded")
    if superseded.exists():
        superseded.unlink()
    old.rename(superseded)
target.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(target)
PY
