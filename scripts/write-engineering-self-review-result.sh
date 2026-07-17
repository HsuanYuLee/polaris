#!/usr/bin/env bash
# Canonical writer for the LLM-owned Critic verdict transition.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/tool-resolution.sh
source "$ROOT/scripts/lib/tool-resolution.sh"
VALIDATOR="$ROOT/scripts/validate-engineering-self-review-result.sh"
REPO=""
WORK_ITEM_ID=""
CRITIC_RESULT=""
REVIEW_ROUND=""
PRIOR_RESULT=""

usage() {
  cat >&2 <<'USAGE'
usage: write-engineering-self-review-result.sh
  --repo <git-worktree>
  --work-item-id <DP-NNN-Tn|JIRA-NNN-Tn>
  --critic-result <critic-result.json>
  --review-round <1|2|3|4>
  [--prior-result <previous-result.json>]
USAGE
  exit 2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --work-item-id) WORK_ITEM_ID="$2"; shift 2 ;;
    --critic-result) CRITIC_RESULT="$2"; shift 2 ;;
    --review-round) REVIEW_ROUND="$2"; shift 2 ;;
    --prior-result) PRIOR_RESULT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$WORK_ITEM_ID" && -n "$CRITIC_RESULT" && -n "$REVIEW_ROUND" ]] ||
  usage
if [[ ! "$WORK_ITEM_ID" =~ ^[A-Z][A-Z0-9]*-[0-9]+-[TV][0-9]+[a-z]*$ ]]; then
  echo "ERROR: --work-item-id must be a canonical DP/JIRA task id" >&2
  exit 2
fi
[[ -d "$REPO" ]] || { echo "ERROR: repo not found: $REPO" >&2; exit 2; }
if [[ ! -f "$CRITIC_RESULT" ]]; then
  echo "ERROR: critic result not found: $CRITIC_RESULT" >&2
  exit 2
fi
if [[ ! "$REVIEW_ROUND" =~ ^[1-4]$ ]]; then
  echo "ERROR: --review-round must be 1..4" >&2
  exit 2
fi
if [[ "$REVIEW_ROUND" -gt 1 && -z "$PRIOR_RESULT" ]]; then
  echo "ERROR: round > 1 requires --prior-result" >&2
  exit 2
fi
if [[ "$REVIEW_ROUND" -eq 1 && -n "$PRIOR_RESULT" ]]; then
  echo "ERROR: round 1 must not provide --prior-result" >&2
  exit 2
fi
if [[ -n "$PRIOR_RESULT" && ! -f "$PRIOR_RESULT" ]]; then
  echo "ERROR: prior result not found: $PRIOR_RESULT" >&2
  exit 2
fi

REPO="$(cd "$REPO" && pwd)"
PYTHON_BIN="$(polaris_require_python)"
current_state="$(bash "$VALIDATOR" --print-current-state --repo "$REPO")"
head_sha="$(polaris_with_runtime_tools jq -r '.reviewed_head_sha' <<<"$current_state")"
state_sha="$(polaris_with_runtime_tools jq -r '.reviewed_state_sha256' <<<"$current_state")"

critic_check="$("$PYTHON_BIN" - "$CRITIC_RESULT" "$head_sha" "$state_sha" <<'PY'
import json
import sys
from pathlib import Path, PurePosixPath

path, expected_head, expected_state = sys.argv[1:4]
try:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
except Exception as exc:
    print(f"critic result is not readable JSON: {exc}", file=sys.stderr)
    raise SystemExit(2)
if not isinstance(data, dict):
    print("critic result must be a JSON object", file=sys.stderr)
    raise SystemExit(2)
if type(data.get("passed")) is not bool:
    print("critic result passed must be boolean", file=sys.stderr)
    raise SystemExit(2)
if data.get("reviewed_head_sha") != expected_head:
    print("POLARIS_ENGINEERING_SELF_REVIEW_STALE:critic reviewed_head_sha mismatch", file=sys.stderr)
    raise SystemExit(2)
if data.get("reviewed_state_sha256") != expected_state:
    print("POLARIS_ENGINEERING_SELF_REVIEW_STALE:critic reviewed_state_sha256 mismatch", file=sys.stderr)
    raise SystemExit(2)
for field in ("blocking", "non_blocking"):
    if not isinstance(data.get(field), list):
        print(f"critic result {field} must be an array", file=sys.stderr)
        raise SystemExit(2)
    for index, finding in enumerate(data[field]):
        if not isinstance(finding, dict):
            print(f"critic result {field}[{index}] must be an object", file=sys.stderr)
            raise SystemExit(2)
        file_path = finding.get("file")
        if not isinstance(file_path, str) or not file_path.strip():
            print(f"critic result {field}[{index}].file must be non-empty", file=sys.stderr)
            raise SystemExit(2)
        normalized = PurePosixPath(file_path)
        if normalized.is_absolute() or ".." in normalized.parts:
            print(f"critic result {field}[{index}].file must be repo-relative", file=sys.stderr)
            raise SystemExit(2)
        if type(finding.get("line")) is not int or finding["line"] < 1:
            print(f"critic result {field}[{index}].line must be positive", file=sys.stderr)
            raise SystemExit(2)
        for required in ("rule", "message"):
            value = finding.get(required)
            if not isinstance(value, str) or not value.strip():
                print(f"critic result {field}[{index}].{required} must be non-empty", file=sys.stderr)
                raise SystemExit(2)
if not isinstance(data.get("summary"), str) or not data["summary"].strip():
    print("critic result summary must be non-empty", file=sys.stderr)
    raise SystemExit(2)
if data["passed"] and data["blocking"]:
    print("critic PASS must have empty blocking", file=sys.stderr)
    raise SystemExit(2)
if not data["passed"] and not data["blocking"]:
    print("critic FAIL must have blocking findings", file=sys.stderr)
    raise SystemExit(2)
print("PASS" if data["passed"] else "FAIL")
PY
)" || exit $?

common_dir="$(git -C "$REPO" rev-parse --git-common-dir)"
if [[ "$common_dir" != /* ]]; then
  common_dir="$(cd "$REPO" && cd "$common_dir" && pwd)"
fi
checkout_root="$(dirname "$common_dir")"
OUT="$checkout_root/.polaris/evidence/engineering-self-review/$WORK_ITEM_ID-r$REVIEW_ROUND-$head_sha.json"

if [[ -n "$PRIOR_RESULT" ]]; then
  bash "$VALIDATOR" "$PRIOR_RESULT" --repo "$REPO" --validate-history >/dev/null
  "$PYTHON_BIN" - "$PRIOR_RESULT" "$WORK_ITEM_ID" "$REVIEW_ROUND" "$head_sha" "$state_sha" <<'PY'
import json
import sys
from pathlib import Path

path, work_item_id, round_raw, head_sha, state_sha = sys.argv[1:6]
prior = json.loads(Path(path).read_text(encoding="utf-8"))
review_round = int(round_raw)
if prior.get("work_item_id") != work_item_id:
    raise SystemExit("ERROR: prior work_item_id mismatch")
if prior.get("review_round") != review_round - 1:
    raise SystemExit("ERROR: prior review_round mismatch")
if prior.get("verdict") != "FAIL" or prior.get("next_action") != "remediate":
    raise SystemExit("ERROR: prior must be a remediable FAIL")
if (
    prior.get("reviewed_head_sha") == head_sha
    and prior.get("reviewed_state_sha256") == state_sha
):
    raise SystemExit("ERROR: remediation must change HEAD or worktree state")
PY
fi

mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -p "$(dirname "$OUT")" .engineering-self-review.XXXXXX.tmp)"
backup=""
trap 'rm -f "$tmp" "$backup"' EXIT

"$PYTHON_BIN" - "$CRITIC_RESULT" "$WORK_ITEM_ID" "$REVIEW_ROUND" "$critic_check" "$tmp" "$PRIOR_RESULT" <<'PY'
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

critic_path, work_item_id, round_raw, verdict, out, prior_path = sys.argv[1:7]
critic_bytes = Path(critic_path).read_bytes()
critic = json.loads(critic_bytes)
review_round = int(round_raw)
prior_bytes = Path(prior_path).read_bytes() if prior_path else b""
next_action = (
    "proceed"
    if verdict == "PASS"
    else ("human_review" if review_round == 4 else "remediate")
)
payload = {
    "schema_version": 1,
    "marker_kind": "engineering_self_review",
    "writer": "write-engineering-self-review-result.sh",
    "owning_skill": "engineering",
    "reviewer": "critic",
    "work_item_id": work_item_id,
    "reviewed_head_sha": critic["reviewed_head_sha"],
    "reviewed_state_sha256": critic["reviewed_state_sha256"],
    "review_round": review_round,
    "remediation_count": review_round - 1,
    "terminal_review": review_round == 4,
    "verdict": verdict,
    "blocking": critic["blocking"],
    "non_blocking": critic["non_blocking"],
    "summary": critic["summary"],
    "next_action": next_action,
    "critic_result_sha256": "sha256:" + hashlib.sha256(critic_bytes).hexdigest(),
    "reviewed_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "prior_result_file": Path(prior_path).resolve().name if prior_path else None,
    "prior_result_sha256": (
        "sha256:" + hashlib.sha256(prior_bytes).hexdigest() if prior_path else None
    ),
}
Path(out).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
PY

if [[ -f "$OUT" ]]; then
  backup="$(mktemp -p "$(dirname "$OUT")" .engineering-self-review.XXXXXX.backup)"
  cp "$OUT" "$backup"
fi
mv "$tmp" "$OUT"
if [[ -n "$PRIOR_RESULT" ]]; then
  if ! bash "$VALIDATOR" "$OUT" --repo "$REPO" --prior "$PRIOR_RESULT" >/dev/null; then
    [[ -n "$backup" ]] && mv "$backup" "$OUT" || rm -f "$OUT"
    echo "ERROR: generated engineering self-review result failed validation" >&2
    exit 2
  fi
else
  if ! bash "$VALIDATOR" "$OUT" --repo "$REPO" >/dev/null; then
    [[ -n "$backup" ]] && mv "$backup" "$OUT" || rm -f "$OUT"
    echo "ERROR: generated engineering self-review result failed validation" >&2
    exit 2
  fi
fi
rm -f "$backup"
trap - EXIT
echo "WROTE: $OUT"
