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
Channel: #b2c-web-pr (C08NJ2GL204)

=== Message from Reviewer (U123456789) at 2026-05-04 18:16:14 CST ===
Message TS: 1777889774.622759
*[變價服務 Review 請求]* GT-493 / KB2CW-3853

本批 PR 橫跨 3 個 repo，共 3 個 PR。

<https://github.com/kkday-it/kkday-b2c-web/pull/2223
>[KB2CW-3854] server utility

<https://github.com/kkday-it/kkday-member-ci/pull/12282
>[KB2CW-3857] core helper

<https://github.com/kkday-it/kkday-mobile-member-ci/pull/10473
>[KB2CW-3859] mobile helper

=== Message from Reviewer (U123456789) at 2026-05-05 14:49:38 CST ===
Message TS: 1777963778.044189
fix: [KB2CW-4040] 修正註冊彈窗 checkbox 失效
<https://github.com/kkday-it/kkday-b2c-web/pull/2256>
TEXT

"$extractor" --org kkday-it --mapping "$mapping" < "$raw" > "$urls"

python3 - "$urls" "$mapping" <<'PY'
import json
import sys
from pathlib import Path

urls = Path(sys.argv[1]).read_text().splitlines()
mapping = json.loads(Path(sys.argv[2]).read_text())

assert len(urls) == 4, urls
for url in [
    "https://github.com/kkday-it/kkday-b2c-web/pull/2223",
    "https://github.com/kkday-it/kkday-member-ci/pull/12282",
    "https://github.com/kkday-it/kkday-mobile-member-ci/pull/10473",
]:
    assert mapping[url]["thread_ts"] == "1777889774.622759", mapping[url]
    assert mapping[url]["root_ticket_key"] == "GT-493", mapping[url]

hotfix = "https://github.com/kkday-it/kkday-b2c-web/pull/2256"
assert mapping[hotfix]["root_ticket_key"] == "KB2CW-4040", mapping[hotfix]
PY

echo "extract-pr-urls selftest: PASS"
