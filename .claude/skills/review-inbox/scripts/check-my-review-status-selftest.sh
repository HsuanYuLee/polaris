#!/usr/bin/env bash
# Selftest for check-my-review-status.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checker="$script_dir/check-my-review-status.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mock_bin="$tmp/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" != "api" ]]; then
  echo "mock gh only supports api" >&2
  exit 2
fi
shift
endpoint="$1"
shift
jq_filter=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) jq_filter="$2"; shift 2 ;;
    --paginate) shift ;;
    *) shift ;;
  esac
done

number="$(sed -E 's#.*pulls/([0-9]+).*#\1#' <<<"$endpoint")"
if [[ "$endpoint" == *"/issues/"* ]]; then
  number="$(sed -E 's#.*issues/([0-9]+).*#\1#' <<<"$endpoint")"
fi

payload='[]'
case "$endpoint" in
  */pulls/1/reviews) payload='[]' ;;
  */pulls/1/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/1/comments|*/issues/1/comments) payload='[]' ;;

  */pulls/2/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T10:00:00Z"}]' ;;
  */pulls/2/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/2/comments|*/issues/2/comments) payload='[]' ;;

  */pulls/3/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z"}]' ;;
  */pulls/3/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/3/comments) payload='[{"user":{"login":"carol"},"created_at":"2026-05-06T10:30:00Z"}]' ;;
  */issues/3/comments) payload='[]' ;;

  */pulls/4/reviews) payload='[{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z"}]' ;;
  */pulls/4/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T11:00:00Z"}}}]' ;;
  */pulls/4/comments|*/issues/4/comments) payload='[]' ;;

  */pulls/5/reviews) payload='[{"user":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submitted_at":"2026-05-06T10:00:00Z"}]' ;;
  */pulls/5/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T11:00:00Z"}}}]' ;;
  */pulls/5/comments) payload='[{"user":{"login":"erin"},"created_at":"2026-05-06T11:30:00Z"}]' ;;
  */issues/5/comments) payload='[]' ;;

  */pulls/6/reviews) payload='[{"user":{"login":"reviewer"},"state":"COMMENTED","submitted_at":"2026-05-06T08:00:00Z"},{"user":{"login":"reviewer"},"state":"APPROVED","submitted_at":"2026-05-06T10:00:00Z"}]' ;;
  */pulls/6/commits) payload='[{"commit":{"committer":{"date":"2026-05-06T09:00:00Z"}}}]' ;;
  */pulls/6/comments|*/issues/6/comments) payload='[]' ;;
esac

if [[ -n "$jq_filter" ]]; then
  jq -r "$jq_filter" <<<"$payload"
else
  printf '%s\n' "$payload"
fi
MOCK
chmod +x "$mock_bin/gh"

candidates="$tmp/candidates.json"
cat > "$candidates" <<'JSON'
[
  {"repo":"demo","number":1,"title":"first","url":"https://github.com/acme/demo/pull/1","author":"alice","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":2,"title":"commented no push","url":"https://github.com/acme/demo/pull/2","author":"bob","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":3,"title":"changes no push","url":"https://github.com/acme/demo/pull/3","author":"carol","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":4,"title":"approved stale","url":"https://github.com/acme/demo/pull/4","author":"dan","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":5,"title":"changes replied with push","url":"https://github.com/acme/demo/pull/5","author":"erin","created_at":"2026-05-06T08:00:00Z"},
  {"repo":"demo","number":6,"title":"multiple reviews latest approved no push","url":"https://github.com/acme/demo/pull/6","author":"frank","created_at":"2026-05-06T08:00:00Z"}
]
JSON

assert_actionable() {
  local out="$1"
  python3 - "$out" <<'PY'
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text())
by_number = {item["number"]: item for item in items}
if sorted(by_number) != [1, 4, 5]:
    raise SystemExit(f"unexpected actionable PRs: {sorted(by_number)}")
if by_number[1]["review_status"] != "needs_first_review":
    raise SystemExit("PR 1 should need first review")
if by_number[4]["review_status"] != "needs_re_approve":
    raise SystemExit("PR 4 should need re-approve")
if by_number[5]["review_status"] != "needs_re_review":
    raise SystemExit("PR 5 should need re-review")
PY
}

out_positional="$tmp/out-positional.json"
PATH="$mock_bin:$PATH" ORG=acme "$checker" reviewer < "$candidates" > "$out_positional"
assert_actionable "$out_positional"

out_flags="$tmp/out-flags.json"
PATH="$mock_bin:$PATH" "$checker" --my-user reviewer --org acme < "$candidates" > "$out_flags"
assert_actionable "$out_flags"

if PATH="$mock_bin:$PATH" "$checker" --my-user reviewer < "$candidates" >/dev/null 2>&1; then
  echo "missing org should fail" >&2
  exit 1
fi

echo "check-my-review-status selftest: PASS"
