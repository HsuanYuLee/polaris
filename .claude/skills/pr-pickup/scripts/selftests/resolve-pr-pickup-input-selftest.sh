#!/usr/bin/env bash
# Selftest for resolve-pr-pickup-input.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolver="$script_dir/resolve-pr-pickup-input.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "ASSERT FAIL [$label]: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_json_expr() {
  local json="$1"
  local expr="$2"
  python3 - "$json" "$expr" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
expr = sys.argv[2]

env = {"data": data}
if not eval(expr, {"__builtins__": {}}, env):
    raise SystemExit(f"assertion failed: {expr}\n{json.dumps(data, ensure_ascii=False, indent=2)}")
PY
}

# Case 1: direct PR URL only
out="$("$resolver" --input '幫我處理 https://github.com/acme/demo/pull/123' --format json)"
assert_json_expr "$out" 'data["source_type"] == "direct_pr_url"'
assert_json_expr "$out" 'data["slack_source"] is False'
assert_json_expr "$out" 'data["pr_count"] == 1'
assert_json_expr "$out" 'data["pr_urls"] == ["https://github.com/acme/demo/pull/123"]'

# Case 2: Slack URL with direct PR URL preserves thread context
out="$("$resolver" \
  --input '接這個 PR https://acme.slack.com/archives/C123ABC456/p1773631805068619 https://github.com/acme/demo/pull/456' \
  --format json)"
assert_json_expr "$out" 'data["source_type"] == "direct_pr_with_slack_context"'
assert_json_expr "$out" 'data["slack_source"] is True'
assert_json_expr "$out" 'data["slack_channel_id"] == "C123ABC456"'
assert_json_expr "$out" 'data["slack_thread_ts"] == "1773631805.068619"'
assert_json_expr "$out" 'data["pr_urls"] == ["https://github.com/acme/demo/pull/456"]'

# Case 3: Slack context only is allowed in pre-read mode
out="$("$resolver" \
  --input '處理這串 https://acme.slack.com/archives/C999THREAD/p1774000000123456' \
  --allow-empty-prs \
  --format json)"
assert_json_expr "$out" 'data["source_type"] == "slack_context_only"'
assert_json_expr "$out" 'data["needs_slack_thread_read"] is True'
assert_json_expr "$out" 'data["pr_count"] == 0'

# Case 4: Slack thread export resolves PR URLs and deduplicates direct + thread URLs
thread_raw="$tmp/thread.txt"
cat > "$thread_raw" <<'TEXT'
=== Message from Reviewer (U123456789) at 2026-05-08 12:00:00 CST ===
Message TS: 1778203200.123456
請幫忙處理這批：
<https://github.com/acme/demo/pull/777>
<https://github.com/acme/api/pull/778>
TEXT

out="$("$resolver" \
  --input 'pickup https://acme.slack.com/archives/C777THREAD/p1778203200123456 https://github.com/acme/demo/pull/777' \
  --org acme \
  --slack-thread-file "$thread_raw" \
  --format json)"
assert_json_expr "$out" 'data["source_type"] == "slack_thread_url"'
assert_json_expr "$out" 'data["slack_source"] is True'
assert_json_expr "$out" 'data["slack_channel_id"] == "C777THREAD"'
assert_json_expr "$out" 'data["slack_thread_ts"] == "1778203200.123456"'
assert_json_expr "$out" 'data["pr_count"] == 2'
assert_json_expr "$out" 'data["pr_urls"] == ["https://github.com/acme/demo/pull/777", "https://github.com/acme/api/pull/778"]'

# Case 5: missing org for Slack thread export must fail
if "$resolver" \
  --input 'pickup https://acme.slack.com/archives/C777THREAD/p1778203200123456' \
  --slack-thread-file "$thread_raw" \
  --allow-empty-prs >/tmp/pr-pickup-selftest.out 2>/tmp/pr-pickup-selftest.err; then
  echo "ASSERT FAIL [missing-org]: expected resolver to fail" >&2
  exit 1
fi
grep -q -- '--org is required' /tmp/pr-pickup-selftest.err

echo "resolve-pr-pickup-input selftest: PASS"
