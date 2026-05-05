#!/usr/bin/env bash
# Selftest for extract-pr-urls.py Slack root ticket mapping.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extractor="$script_dir/extract-pr-urls.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

raw="$tmp/slack.txt"
urls="$tmp/urls.txt"
mapping="$tmp/mapping.json"

cat > "$raw" <<'TEXT'
Channel: #product-pr (C012EXAMPLE)

=== Message from Reviewer (U123456789) at 2026-05-04 18:16:14 CST ===
Message TS: 1777889774.622759
*[Pricing Service Review Request]* DEMO-493 / APP-3853

本批 PR 橫跨 3 個 repo，共 3 個 PR。

<https://github.com/example-org/example-web/pull/2223
>[APP-3854] server utility

<https://github.com/example-org/example-core/pull/12282
>[APP-3857] core helper

<https://github.com/example-org/example-mobile/pull/10473
>[APP-3859] mobile helper

=== Message from Reviewer (U123456789) at 2026-05-04 18:30:00 CST ===
Message TS: 1777890600.000000
Hi team, please review this cross-repo patch:
*JsBridgeUtils platform case insensitive*

<https://github.com/example-org/example-web/pull/2243>
<https://github.com/example-org/example-core/pull/12299>
<https://github.com/example-org/example-mobile/pull/10489>

=== Message from Reviewer (U123456789) at 2026-05-05 14:49:38 CST ===
Message TS: 1777963778.044189
fix: [APP-4040] fix signup modal checkbox
<https://github.com/example-org/example-web/pull/2256>
TEXT

"$extractor" --org example-org --mapping "$mapping" < "$raw" > "$urls"

python3 - "$urls" "$mapping" <<'PY'
import json
import sys
from pathlib import Path

urls = Path(sys.argv[1]).read_text().splitlines()
mapping = json.loads(Path(sys.argv[2]).read_text())

assert len(urls) == 7, urls
for url in [
    "https://github.com/example-org/example-web/pull/2223",
    "https://github.com/example-org/example-core/pull/12282",
    "https://github.com/example-org/example-mobile/pull/10473",
]:
    assert mapping[url]["thread_ts"] == "1777889774.622759", mapping[url]
    assert mapping[url]["root_ticket_key"] == "DEMO-493", mapping[url]

for url in [
    "https://github.com/example-org/example-web/pull/2243",
    "https://github.com/example-org/example-core/pull/12299",
    "https://github.com/example-org/example-mobile/pull/10489",
]:
    assert mapping[url]["thread_ts"] == "1777890600.000000", mapping[url]
    assert mapping[url]["root_topic_key"] == "topic:jsbridgeutils-platform-case-insensitive", mapping[url]
    assert "root_ticket_key" not in mapping[url], mapping[url]

hotfix = "https://github.com/example-org/example-web/pull/2256"
assert mapping[hotfix]["root_ticket_key"] == "APP-4040", mapping[hotfix]
PY

echo "extract-pr-urls selftest: PASS"
