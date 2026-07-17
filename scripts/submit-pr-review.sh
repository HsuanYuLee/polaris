#!/usr/bin/env bash
# Purpose: build and optionally submit the canonical GitHub pull-request review payload.
# Inputs: repository, pull number, review event, body file, optional comments file.
# Outputs: validated JSON on stdout, or GitHub API response with --submit.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: submit-pr-review.sh --repository OWNER/REPO --pull-number N --event EVENT \
  --body-file PATH [--comments-file PATH] [--tool-identity github.pull_request_review.submit] [--submit]
USAGE
  exit 2
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="" pull_number="" event="" body_file="" comments_file="" submit=0
tool_identity="github.pull_request_review.submit"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository) repository="${2:-}"; shift 2 ;;
    --pull-number) pull_number="${2:-}"; shift 2 ;;
    --event) event="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --comments-file) comments_file="${2:-}"; shift 2 ;;
    --tool-identity) tool_identity="${2:-}"; shift 2 ;;
    --submit) submit=1; shift ;;
    -h|--help) usage ;;
    *) echo "POLARIS_SUBMIT_PR_REVIEW_UNKNOWN_ARGUMENT:$1" >&2; usage ;;
  esac
done

[[ "$repository" =~ ^[^/]+/[^/]+$ ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_REPOSITORY_INVALID:$repository" >&2; exit 2; }
[[ "$pull_number" =~ ^[1-9][0-9]*$ ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_NUMBER_INVALID:$pull_number" >&2; exit 2; }
[[ "$event" == "APPROVE" || "$event" == "COMMENT" || "$event" == "REQUEST_CHANGES" ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_EVENT_INVALID:$event" >&2; exit 2; }
[[ -f "$body_file" ]] || { echo "POLARIS_SUBMIT_PR_REVIEW_BODY_MISSING:$body_file" >&2; exit 2; }
[[ "$tool_identity" == "github.pull_request_review.submit" ]] || { echo "POLARIS_EXTERNAL_WRITE_TOOL_IDENTITY_INVALID:$tool_identity" >&2; exit 2; }

tmp="$(mktemp -t polaris-pr-review.XXXXXX.json)"
trap 'rm -f "$tmp"' EXIT
python3 - "$repository" "$pull_number" "$event" "$body_file" "$comments_file" "$tmp" <<'PY'
import json, sys
from pathlib import Path
repository, pull_number, event, body_path, comments_path, output = sys.argv[1:]
owner, repo = repository.split("/", 1)
comments = []
if comments_path:
    try:
        comments = json.loads(Path(comments_path).read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"POLARIS_EXTERNAL_WRITE_PAYLOAD_INVALID:comments:{exc}", file=sys.stderr)
        raise SystemExit(2)
payload = {
    "owner": owner,
    "repo": repo,
    "pull_number": int(pull_number),
    "event": event,
    "body": Path(body_path).read_text(encoding="utf-8"),
    "comments": comments,
}
Path(output).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

POLARIS_EXTERNAL_WRITE_WRITER=review-pr:github-review \
  bash "$ROOT/scripts/polaris-external-write-gate.sh" \
    --surface github-review --body-file "$body_file" \
    --tool-identity "$tool_identity" --payload-file "$tmp" \
    --workspace-root "$ROOT" >/dev/null

if [[ "$submit" -eq 0 ]]; then
  cat "$tmp"
  exit 0
fi

GH_BIN="${POLARIS_GH_BIN:-gh}"
"$GH_BIN" api --method POST "repos/$repository/pulls/$pull_number/reviews" --input "$tmp"
