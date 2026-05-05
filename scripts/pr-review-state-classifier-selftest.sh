#!/usr/bin/env bash
# Selftest for pr-review-state-classifier.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFIER="$SCRIPT_DIR/pr-review-state-classifier.sh"
TMPROOT="$(mktemp -d -t polaris-pr-state-classifier-XXXXXX)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPROOT" 2>/dev/null || true
}
trap cleanup EXIT

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s — want=%s got=%s\n' "$label" "$want" "$got" >&2
  fi
}

write_pr() {
  local path="$1" decision="$2" state_json="$3"
  cat >"$path" <<JSON
{
  "state": "OPEN",
  "reviewDecision": "$decision",
  "statusCheckRollup": $state_json
}
JSON
}

write_threads() {
  local path="$1" resolved="$2" outdated="$3"
  cat >"$path" <<JSON
{
  "pullRequest": {
    "reviewThreads": {
      "nodes": [
        {
          "id": "PRRT_1",
          "isResolved": $resolved,
          "isOutdated": $outdated,
          "path": "src/file.ts",
          "line": 12,
          "comments": { "nodes": [ { "url": "https://example.invalid/thread" } ] }
        }
      ]
    }
  }
}
JSON
}

classification_of() {
  local pr="$1" threads="${2:-}" disposition="${3:-}"
  local out="$TMPROOT/out.json"
  if [[ -n "$threads" && -n "$disposition" ]]; then
    "$CLASSIFIER" --pr-json "$pr" --threads-json "$threads" --disposition "$disposition" >"$out"
  elif [[ -n "$threads" ]]; then
    "$CLASSIFIER" --pr-json "$pr" --threads-json "$threads" >"$out"
  else
    "$CLASSIFIER" --pr-json "$pr" >"$out"
  fi
  python3 - "$out" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["classification"])
PY
}

route_of() {
  local pr="$1" threads="${2:-}" disposition="${3:-}"
  local out="$TMPROOT/route.json"
  if [[ -n "$threads" && -n "$disposition" ]]; then
    "$CLASSIFIER" --pr-json "$pr" --threads-json "$threads" --disposition "$disposition" >"$out"
  elif [[ -n "$threads" ]]; then
    "$CLASSIFIER" --pr-json "$pr" --threads-json "$threads" >"$out"
  else
    "$CLASSIFIER" --pr-json "$pr" >"$out"
  fi
  python3 - "$out" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["route"])
PY
}

GREEN='[{"__typename":"StatusContext","state":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]'
RED='[{"__typename":"StatusContext","state":"FAILURE"}]'
PENDING='[{"__typename":"StatusContext","state":"PENDING"}]'

echo "== pr-review-state-classifier selftest =="

PR1="$TMPROOT/pr1.json"
write_pr "$PR1" "CHANGES_REQUESTED" "$GREEN"
assert_eq "changes requested + green + no threads -> awaiting re-review" "$(classification_of "$PR1")" "AWAITING_RE_REVIEW"
assert_eq "awaiting re-review routes to check-pr-approvals" "$(route_of "$PR1")" "check-pr-approvals"

PR2="$TMPROOT/pr2.json"; TH2="$TMPROOT/th2.json"
write_pr "$PR2" "CHANGES_REQUESTED" "$GREEN"
write_threads "$TH2" "false" "false"
assert_eq "active unresolved thread without disposition -> engineering" "$(classification_of "$PR2" "$TH2")" "HAS_UNRESOLVED_COMMENTS"

DISP="$TMPROOT/disposition.json"
cat >"$DISP" <<'JSON'
{
  "version": 1,
  "threads": [
    {
      "thread_id": "PRRT_1",
      "disposition": "fixed",
      "reason": "fixed in the latest pushed commit"
    }
  ]
}
JSON
assert_eq "active fixed thread + green + changes requested -> awaiting re-review" "$(classification_of "$PR2" "$TH2" "$DISP")" "AWAITING_RE_REVIEW"

PR3="$TMPROOT/pr3.json"
write_pr "$PR3" "CHANGES_REQUESTED" "$RED"
assert_eq "failed check wins over review decision" "$(classification_of "$PR3")" "CI_RED"

PR4="$TMPROOT/pr4.json"
write_pr "$PR4" "APPROVED" "$GREEN"
assert_eq "approved + green -> ready to merge" "$(classification_of "$PR4")" "READY_TO_MERGE"

PR5="$TMPROOT/pr5.json"
write_pr "$PR5" "CHANGES_REQUESTED" "$PENDING"
assert_eq "pending check blocks handoff" "$(classification_of "$PR5")" "CI_PENDING"

echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
