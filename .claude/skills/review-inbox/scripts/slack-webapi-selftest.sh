#!/usr/bin/env bash
# Selftest for Slack Web API fallback argument normalization.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/slack-webapi.sh"

[[ "$("$script" normalize-oldest 1712841600)" == "1712841600" ]]
[[ "$("$script" normalize-oldest 1712841600.123456)" == "1712841600.123456" ]]
[[ "$("$script" normalize-oldest 1970-01-01T00:00:00Z)" == "0" ]]
[[ "$("$script" normalize-oldest 1970-01-01T08:00:00+08:00)" == "0" ]]

if "$script" normalize-oldest not-a-date >/tmp/slack-webapi-selftest-invalid.out 2>&1; then
  echo "expected invalid ISO input to fail" >&2
  exit 1
fi
rg -q "must be a Slack timestamp or ISO datetime" /tmp/slack-webapi-selftest-invalid.out

echo "slack-webapi selftest: PASS"
