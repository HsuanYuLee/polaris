#!/usr/bin/env bash
# Selftest for extract-pr-urls.py Slack root ticket mapping.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extractor="$script_dir/extract-pr-urls.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Fixture: happy path (every message has Message TS) ---
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

# --- Fixture A: all messages missing Message TS (DP-181 AC-F3) ---
raw_a="$tmp/slack-fixture-a.txt"
urls_a="$tmp/urls-a.txt"
mapping_a="$tmp/mapping-a.json"
stderr_a="$tmp/stderr-a.txt"

cat > "$raw_a" <<'TEXT'
Channel: #product-pr (C012EXAMPLE)

=== Message from Author1 (U111111111) at 2026-05-15 17:19:39 CST ===
本訊息缺少 Message TS 行，應整則 skip。
<https://github.com/example-org/example-web/pull/9001>

=== Message from Author2 (U222222222) at 2026-05-15 17:30:00 CST ===
同樣缺 Message TS。
<https://github.com/example-org/example-web/pull/9002>
TEXT

"$extractor" --org example-org --mapping "$mapping_a" < "$raw_a" > "$urls_a" 2> "$stderr_a"

python3 - "$urls_a" "$mapping_a" "$stderr_a" <<'PY'
import json
import sys
from pathlib import Path

urls = [line for line in Path(sys.argv[1]).read_text().splitlines() if line]
mapping = json.loads(Path(sys.argv[2]).read_text())
stderr = Path(sys.argv[3]).read_text()

assert urls == [], f"expected no URLs, got {urls}"
assert mapping == {}, f"expected empty mapping, got {mapping}"

warn_lines = [line for line in stderr.splitlines() if line.startswith("WARN:")]
assert len(warn_lines) == 2, f"expected 2 WARN lines, got {warn_lines!r}"
for line in warn_lines:
    assert "Message TS" in line, line
PY

# --- Fixture B: mixed (some with, some without Message TS, DP-181 AC-F4) ---
raw_b="$tmp/slack-fixture-b.txt"
urls_b="$tmp/urls-b.txt"
mapping_b="$tmp/mapping-b.json"
stderr_b="$tmp/stderr-b.txt"

cat > "$raw_b" <<'TEXT'
Channel: #product-pr (C012EXAMPLE)

=== Message from GoodAuthor (U333333333) at 2026-05-15 18:00:00 CST ===
Message TS: 1778839200.111111
有 Message TS，PR URL 應正常進 mapping。
<https://github.com/example-org/example-web/pull/9100>

=== Message from BadAuthor (U444444444) at 2026-05-15 18:05:00 CST ===
缺 Message TS，PR URL 應被 skip。
<https://github.com/example-org/example-web/pull/9101>

=== Message from GoodAuthor2 (U555555555) at 2026-05-15 18:10:00 CST ===
Message TS: 1778839800.222222
再一個有 Message TS 的訊息。
<https://github.com/example-org/example-web/pull/9102>
TEXT

"$extractor" --org example-org --mapping "$mapping_b" < "$raw_b" > "$urls_b" 2> "$stderr_b"

python3 - "$urls_b" "$mapping_b" "$stderr_b" <<'PY'
import json
import sys
from pathlib import Path

urls = [line for line in Path(sys.argv[1]).read_text().splitlines() if line]
mapping = json.loads(Path(sys.argv[2]).read_text())
stderr = Path(sys.argv[3]).read_text()

good1 = "https://github.com/example-org/example-web/pull/9100"
bad   = "https://github.com/example-org/example-web/pull/9101"
good2 = "https://github.com/example-org/example-web/pull/9102"

assert urls == [good1, good2], f"expected only good URLs, got {urls}"
assert bad not in mapping, f"bad URL should not be in mapping: {mapping}"
assert mapping[good1]["thread_ts"] == "1778839200.111111", mapping[good1]
assert mapping[good2]["thread_ts"] == "1778839800.222222", mapping[good2]

warn_lines = [line for line in stderr.splitlines() if line.startswith("WARN:")]
assert len(warn_lines) == 1, f"expected 1 WARN line, got {warn_lines!r}"
assert "BadAuthor" in warn_lines[0], warn_lines[0]
PY

echo "extract-pr-urls selftest: PASS"
