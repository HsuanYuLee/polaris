#!/usr/bin/env bash
# Require explicit disposition for unresolved, current GitHub PR review threads.
#
# Usage:
#   pr-review-thread-disposition-gate.sh --repo OWNER/REPO --pr NUMBER --manifest PATH
#   pr-review-thread-disposition-gate.sh --threads-json PATH --manifest PATH
#
# Manifest schema:
# {
#   "version": 1,
#   "pr": "https://github.com/OWNER/REPO/pull/NUMBER",
#   "threads": [
#     {
#       "thread_id": "PRRT_...",
#       "disposition": "fixed|reply_only|not_actionable|deferred_with_reason",
#       "reason": "short human reason"
#     }
#   ]
# }

set -uo pipefail

REPO=""
PR_NUMBER=""
MANIFEST=""
THREADS_JSON=""

usage() {
  cat >&2 <<'EOF'
Usage:
  pr-review-thread-disposition-gate.sh --repo OWNER/REPO --pr NUMBER --manifest PATH
  pr-review-thread-disposition-gate.sh --threads-json PATH --manifest PATH

Fails when an open PR has unresolved, not-outdated review threads without an
explicit disposition manifest entry.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR_NUMBER="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --threads-json) THREADS_JSON="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "pr-review-thread-disposition-gate: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$MANIFEST" ]]; then
  echo "pr-review-thread-disposition-gate: --manifest is required" >&2
  usage
  exit 2
fi

TMP_JSON=""
cleanup() {
  [[ -n "$TMP_JSON" ]] && rm -f "$TMP_JSON" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -n "$THREADS_JSON" ]]; then
  if [[ ! -f "$THREADS_JSON" ]]; then
    echo "pr-review-thread-disposition-gate: --threads-json not found: $THREADS_JSON" >&2
    exit 1
  fi
  INPUT_JSON="$THREADS_JSON"
else
  if [[ -z "$REPO" || -z "$PR_NUMBER" ]]; then
    echo "pr-review-thread-disposition-gate: --repo and --pr are required unless --threads-json is provided" >&2
    usage
    exit 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "pr-review-thread-disposition-gate: gh CLI is required" >&2
    exit 1
  fi
  OWNER="${REPO%%/*}"
  NAME="${REPO#*/}"
  TMP_JSON="$(mktemp -t polaris-pr-review-threads.XXXXXX.json)"
  if ! gh api graphql \
    -f owner="$OWNER" \
    -f repo="$NAME" \
    -F number="$PR_NUMBER" \
    -f query='query($owner:String!,$repo:String!,$number:Int!){ repository(owner:$owner,name:$repo){ pullRequest(number:$number){ url reviewThreads(first:100){ nodes{ id isResolved isOutdated path line originalLine comments(first:20){ nodes{ author{login} body url createdAt path line originalLine } } } } } } }' \
    >"$TMP_JSON"; then
    echo "pr-review-thread-disposition-gate: failed to fetch review threads for $REPO#$PR_NUMBER" >&2
    exit 1
  fi
  INPUT_JSON="$TMP_JSON"
fi

python3 - "$INPUT_JSON" "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

threads_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])

try:
    data = json.loads(threads_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: invalid threads JSON: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    pr = data["data"]["repository"]["pullRequest"]
except Exception:
    # Selftest fixtures may provide the pullRequest object directly.
    pr = data.get("pullRequest")
if not isinstance(pr, dict):
    print("FAIL: threads JSON does not contain pullRequest", file=sys.stderr)
    sys.exit(1)

nodes = (((pr.get("reviewThreads") or {}).get("nodes")) or [])
active = [
    thread for thread in nodes
    if not thread.get("isResolved") and not thread.get("isOutdated")
]

if not active:
    print("PASS: no unresolved current review threads")
    sys.exit(0)

if not manifest_path.exists():
    print(
        f"FAIL: {len(active)} unresolved current review thread(s), but manifest is missing: {manifest_path}",
        file=sys.stderr,
    )
    for thread in active:
        first = ((thread.get("comments") or {}).get("nodes") or [{}])[0]
        print(
            f"- {thread.get('id')} {thread.get('path')}:{thread.get('line') or thread.get('originalLine')} {first.get('url', '')}",
            file=sys.stderr,
        )
    sys.exit(1)

try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"FAIL: invalid manifest JSON: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(manifest, dict):
    print("FAIL: manifest must be a JSON object", file=sys.stderr)
    sys.exit(1)

entries = manifest.get("threads")
if not isinstance(entries, list):
    print("FAIL: manifest.threads must be a list", file=sys.stderr)
    sys.exit(1)

allowed = {"fixed", "reply_only", "not_actionable", "deferred_with_reason"}
by_id = {}
errors = []
for idx, entry in enumerate(entries):
    if not isinstance(entry, dict):
        errors.append(f"threads[{idx}] must be an object")
        continue
    thread_id = str(entry.get("thread_id") or "").strip()
    disposition = str(entry.get("disposition") or "").strip()
    reason = str(entry.get("reason") or "").strip()
    if not thread_id:
        errors.append(f"threads[{idx}].thread_id is required")
        continue
    if disposition not in allowed:
        errors.append(f"threads[{idx}].disposition must be one of {sorted(allowed)}")
    if len(reason) < 8:
        errors.append(f"threads[{idx}].reason is required and must be specific")
    by_id[thread_id] = entry

missing = []
for thread in active:
    if thread.get("id") not in by_id:
        first = ((thread.get("comments") or {}).get("nodes") or [{}])[0]
        missing.append(
            f"{thread.get('id')} {thread.get('path')}:{thread.get('line') or thread.get('originalLine')} {first.get('url', '')}"
        )

if missing:
    errors.append("missing disposition for active thread(s):")
    errors.extend(f"  {item}" for item in missing)

if errors:
    print("FAIL: review thread disposition gate failed", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: {len(active)} unresolved current review thread(s) have explicit disposition")
PY
