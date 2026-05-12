#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris gate-pr-review-label]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_SCRIPTS="${SCRIPT_DIR}/.."
REVIEW_LABEL_LIB="${WORKSPACE_SCRIPTS}/lib/pr-review-label.sh"

REPO_ROOT=""
GH_REPO=""
PR_NUMBER=""
PR_JSON=""

usage() {
  cat >&2 <<'EOF'
usage: gate-pr-review-label.sh --repo <path> --gh-repo <owner/repo> --pr-number <n> [--pr-json <path>]

Policy:
  projects[].delivery.pr_review_label.policy = required|optional|off.
  labels are checked in order from projects[].delivery.pr_review_label.labels.
EOF
}

if [[ -f "$REVIEW_LABEL_LIB" ]]; then
  # shellcheck source=../lib/pr-review-label.sh
  . "$REVIEW_LABEL_LIB"
else
  echo "$PREFIX missing helper: $REVIEW_LABEL_LIB" >&2
  exit 2
fi

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

cfg="$(polaris_pr_review_label_config "$REPO_ROOT")"
policy="$(printf '%s' "$cfg" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("policy") or "off").strip())')"
configured_labels="$(printf '%s' "$cfg" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("labels") or []))')"

case "$policy" in
  off)
    echo "$PREFIX policy=off — skipping review label gate." >&2
    exit 0
    ;;
  optional|required|"")
    [[ -n "$policy" ]] || policy="optional"
    ;;
  *)
    echo "$PREFIX invalid policy '$policy'; treating as required." >&2
    policy="required"
    ;;
esac

if [[ -z "$configured_labels" ]]; then
  if [[ "$policy" == "required" ]]; then
    echo "$PREFIX BLOCKED: review label policy is required but no labels are configured." >&2
    exit 2
  fi
  echo "$PREFIX WARN: no review labels configured; continuing because policy=${policy}." >&2
  exit 0
fi

set +e
gate_status="$(python3 - "$GH_REPO" "$PR_NUMBER" "${PR_JSON:-__NULL__}" "$cfg" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

gh_repo, pr_number, pr_json_path, cfg_raw = sys.argv[1:5]
cfg = json.loads(cfg_raw)
wanted = {str(label).strip() for label in cfg.get("labels") or [] if str(label).strip()}

def load(path):
    if path in {"", "__NULL__"}:
        return None
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return None

def labels_from_payload(payload):
    if not isinstance(payload, dict):
        return None
    labels = payload.get("labels")
    if isinstance(labels, list):
        return [str(item.get("name") or "").strip() for item in labels if isinstance(item, dict)]
    return None

payload = load(pr_json_path)
names = labels_from_payload(payload)
source = "pr-json"

if names is None:
    try:
        raw = subprocess.check_output(
            ["gh", "api", f"repos/{gh_repo}/issues/{pr_number}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        payload = json.loads(raw)
        names = labels_from_payload(payload)
        source = "issues-api"
    except Exception:
        print("BLOCKED: review label metadata unavailable", file=sys.stderr)
        raise SystemExit(3)

if names is None:
    print("BLOCKED: review label metadata unreadable", file=sys.stderr)
    raise SystemExit(3)

present = {name for name in names if name}
matched = sorted(present & wanted)
if not matched:
    print(f"BLOCKED: configured review label missing ({source}); present={sorted(present)} wanted={sorted(wanted)}", file=sys.stderr)
    raise SystemExit(2)

print(f"OK {','.join(matched)}")
PY
)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "$PREFIX ✅ review label present for ${GH_REPO}#${PR_NUMBER}: ${gate_status#OK }" >&2
  exit 0
fi

if [[ "$policy" == "optional" ]]; then
  echo "$PREFIX WARN: review label not confirmed for ${GH_REPO}#${PR_NUMBER}; continuing because policy=optional." >&2
  [[ -n "$gate_status" ]] && echo "$PREFIX ${gate_status}" >&2
  exit 0
fi

if [[ "$status" -eq 2 ]]; then
  echo "$PREFIX BLOCKED: configured review label is missing for ${GH_REPO}#${PR_NUMBER}" >&2
  echo "$PREFIX Configured labels: $(tr '\n' ',' <<<"$configured_labels" | sed 's/,$//')" >&2
  [[ -n "$gate_status" ]] && echo "$PREFIX ${gate_status}" >&2
  exit 2
fi

echo "$PREFIX BLOCKED: unable to confirm review label metadata for ${GH_REPO}#${PR_NUMBER}" >&2
[[ -n "$gate_status" ]] && echo "$PREFIX ${gate_status}" >&2
exit 2
