#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PUBLISH="$ROOT/scripts/publish-delivery-evidence.sh"
TMPROOT="$(mktemp -d -t polaris-delivery-evidence-selftest.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

TICKET="TASK-123"
HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
PR_URL="https://github.com/demo/example/pull/7"

make_repo() {
  local repo="$1"
  mkdir -p "$repo/.polaris/evidence/behavior/$TICKET/compare-ctx"
  printf 'language: zh-TW\n' >"$repo/workspace-config.yaml"
  printf 'fake-screenshot\n' >"$repo/.polaris/evidence/behavior/$TICKET/compare-ctx/screen.png"
  printf 'fake-video\n' >"$repo/.polaris/evidence/behavior/$TICKET/compare-ctx/behavior.webm"
  cat >"$repo/.polaris/evidence/behavior/$TICKET/polaris-behavior-${TICKET}-${HEAD_SHA}-ctx.json" <<JSON
{
  "schema_version": 1,
  "ticket": "$TICKET",
  "head_sha": "$HEAD_SHA",
  "writer": "run-behavior-contract.sh",
  "mode": "compare",
  "behavior_mode": "parity",
  "status": "PASS",
  "context_hash": "ctx",
  "screenshots": ["$repo/.polaris/evidence/behavior/$TICKET/compare-ctx/screen.png"],
  "videos": ["$repo/.polaris/evidence/behavior/$TICKET/compare-ctx/behavior.webm"]
}
JSON
}

install_mock_gh() {
  local bin="$1"
  local output="$2"
  mkdir -p "$bin"
  cat >"$bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "pr" && "${2:-}" == "comment" ]]; then
  body_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body-file) body_file="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -n "$body_file" ]] || { echo "missing --body-file" >&2; exit 2; }
  cp "$body_file" "$GH_BODY_OUT"
  echo "https://github.com/demo/example/pull/7#issuecomment-1"
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 2
SH
  chmod +x "$bin/gh"
  export GH_BODY_OUT="$output"
}

make_uploader() {
  local file="$1"
  cat >"$file" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
issue="$1"
shift
for source in "$@"; do
  name="$(basename "$source")"
  printf '{"filename":"%s","id":"att-%s","url":"https://example.atlassian.net/rest/api/3/attachment/content/%s/%s","mimeType":"application/octet-stream"}\n' "$name" "$name" "$issue" "$name"
done
SH
  chmod +x "$file"
}

assert_contains() {
  local file="$1"
  local text="$2"
  grep -qF "$text" "$file" || {
    echo "missing expected text: $text" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  }
}

repo="$TMPROOT/repo"
make_repo "$repo"
mockbin="$TMPROOT/bin"
comment_body="$TMPROOT/comment.md"
install_mock_gh "$mockbin" "$comment_body"
uploader="$TMPROOT/mock-uploader.sh"
make_uploader "$uploader"
manifest="$TMPROOT/jira-publication.json"

PATH="$mockbin:$PATH" "$PUBLISH" \
  --mode jira-comment \
  --repo "$repo" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --pr-url "$PR_URL" \
  --jira-key "$TICKET" \
  --uploader "$uploader" \
  --manifest-file "$manifest" >/dev/null

assert_contains "$comment_body" "polaris-jira-evidence:v1 ticket=$TICKET head=$HEAD_SHA"
assert_contains "$comment_body" "example.atlassian.net/rest/api/3/attachment/content"
assert_contains "$comment_body" "| 情境 | 嵌入預覽 | 驗證結果 | 影片或原始檔 |"
assert_contains "$comment_body" "!screen.png|thumbnail!"
assert_contains "$comment_body" "behavior.webm"
if grep -qF '![' "$comment_body"; then
  echo "Jira evidence body must not use GitHub Markdown image syntax" >&2
  cat "$comment_body" >&2
  exit 1
fi

python3 - "$manifest" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
remote = manifest.get("remote_publication") or {}
assert remote.get("status") == "uploaded", remote
attachments = [
    (item.get("jira_attachment") or {})
    for item in manifest.get("artifacts", [])
    if (item.get("jira_attachment") or {}).get("url")
]
assert len(attachments) >= 3, attachments
assert all(item.get("url") for item in attachments), attachments
PY

set +e
missing_key_output="$("$PUBLISH" \
  --mode jira-comment \
  --repo "$repo" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --pr-url "$PR_URL" 2>&1)"
missing_key_rc=$?
set -e
[[ "$missing_key_rc" == "64" ]] || {
  echo "expected missing jira key rc=64, got $missing_key_rc" >&2
  echo "$missing_key_output" >&2
  exit 1
}
[[ "$missing_key_output" == *"--jira-key is required"* ]] || {
  echo "expected missing jira key message" >&2
  echo "$missing_key_output" >&2
  exit 1
}

failing_uploader="$TMPROOT/failing-uploader.sh"
cat >"$failing_uploader" <<'SH'
#!/usr/bin/env bash
echo "upload failed" >&2
exit 9
SH
chmod +x "$failing_uploader"

set +e
PATH="$mockbin:$PATH" "$PUBLISH" \
  --mode jira-comment \
  --repo "$repo" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --pr-url "$PR_URL" \
  --jira-key "$TICKET" \
  --uploader "$failing_uploader" >/tmp/polaris-publish-delivery-fail.out 2>&1
fail_rc=$?
set -e
[[ "$fail_rc" == "2" ]] || {
  echo "expected uploader failure rc=2, got $fail_rc" >&2
  cat /tmp/polaris-publish-delivery-fail.out >&2
  exit 1
}

legacy_body="$TMPROOT/legacy-comment.md"
install_mock_gh "$mockbin" "$legacy_body"
PATH="$mockbin:$PATH" "$PUBLISH" \
  --mode comment \
  --repo "$repo" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --pr-url "$PR_URL" >/dev/null
assert_contains "$legacy_body" "polaris-evidence-publication:v1 ticket=$TICKET head=$HEAD_SHA"
assert_contains "$legacy_body" "| 情境 | 嵌入預覽 | 驗證結果 | 影片或原始檔 |"
assert_contains "$legacy_body" "![screen.png]"
assert_contains "$legacy_body" "behavior.webm"

echo "PASS: publish-delivery-evidence selftest"
