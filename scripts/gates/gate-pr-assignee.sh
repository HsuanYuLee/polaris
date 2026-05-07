#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris gate-pr-assignee]"
REPO_ROOT=""
GH_REPO=""
PR_NUMBER=""
PR_JSON=""
POLICY=""

usage() {
  cat >&2 <<'EOF'
usage: gate-pr-assignee.sh --repo <path> --gh-repo <owner/repo> --pr-number <n> [--pr-json <path>]

Policy:
  workspace-config.yaml may declare `pr_assignee_policy: required|optional|off`.
  Default is `required`.
EOF
}

read_policy() {
  local repo_root="$1"
  python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import sys

start = Path(sys.argv[1]).resolve()
for root in [start, *start.parents]:
    cfg = root / "workspace-config.yaml"
    if not cfg.exists():
        continue
    text = cfg.read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r"\s*pr_assignee_policy\s*:\s*([^#]+)", line)
        if m:
            print(m.group(1).strip().strip('"').strip("'"))
            raise SystemExit(0)
print("required")
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --gh-repo) GH_REPO="${2:-}"; shift 2 ;;
    --pr-number) PR_NUMBER="${2:-}"; shift 2 ;;
    --pr-json) PR_JSON="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]] || { echo "$PREFIX --repo is required" >&2; exit 2; }
[[ -n "$GH_REPO" ]] || { echo "$PREFIX --gh-repo is required" >&2; exit 2; }
[[ -n "$PR_NUMBER" ]] || { echo "$PREFIX --pr-number is required" >&2; exit 2; }
if [[ -n "$PR_JSON" && ! -f "$PR_JSON" ]]; then
  echo "$PREFIX --pr-json not found: $PR_JSON" >&2
  exit 2
fi

POLICY="$(read_policy "$REPO_ROOT")"
case "$POLICY" in
  off)
    echo "$PREFIX policy=off — skipping assignee gate." >&2
    exit 0
    ;;
  optional)
    echo "$PREFIX policy=optional — assignee gate advisory only." >&2
    exit 0
    ;;
  required|"")
    POLICY="required"
    ;;
  *)
    echo "$PREFIX invalid policy '$POLICY'; treating as required." >&2
    POLICY="required"
    ;;
esac

set +e
gate_output="$(python3 - "$GH_REPO" "$PR_NUMBER" "${PR_JSON:-__NULL__}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

gh_repo, pr_number, pr_json_path = sys.argv[1:4]


def load(path):
    if path in {"", "__NULL__"}:
        return None
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return None


def names_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    assignees = payload.get("assignees")
    if isinstance(assignees, list):
        return [str(item.get("login") or "").strip() for item in assignees if isinstance(item, dict)]
    return None


payload = load(pr_json_path)
names = names_from_payload(payload)
if names is not None:
    source = "pr-json"
else:
    try:
        raw = subprocess.check_output(
            ["gh", "api", f"repos/{gh_repo}/issues/{pr_number}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        payload = json.loads(raw)
    except Exception:
        print("WARN metadata unavailable", file=sys.stderr)
        raise SystemExit(0)
    names = names_from_payload(payload)
    source = "issues-api"

if names is None:
    print("WARN assignee metadata unreadable", file=sys.stderr)
    raise SystemExit(0)

names = [name for name in names if name]
if not names:
    print(f"BLOCKED: final assignee metadata is empty ({source})", file=sys.stderr)
    raise SystemExit(2)

print(",".join(names))
PY
)"
status=$?
set -e

if [[ "$status" -eq 2 ]]; then
  echo "$PREFIX BLOCKED: final PR assignee metadata is empty for ${GH_REPO}#${PR_NUMBER}" >&2
  echo "$PREFIX Policy is framework-enforced (required). Add an assignee before claiming readiness." >&2
  exit 2
fi

if [[ "$status" -ne 0 ]]; then
  echo "$PREFIX WARN: unable to confirm assignee metadata for ${GH_REPO}#${PR_NUMBER}; continuing without blocking." >&2
  exit 0
fi

echo "$PREFIX ✅ assignee metadata present for ${GH_REPO}#${PR_NUMBER}" >&2
