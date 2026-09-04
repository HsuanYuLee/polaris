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

# --- Gap 3 shared decoder (DP-312-T3, AC3 / AC-NEG2) -----------------------------------
# The Slack MCP "detailed" channel dump can arrive as a single-line escaped-JSON string
# (real newlines collapsed into literal `\n`). A single canonical decoder
# (`extract-pr-urls.py --emit-normalized`) normalizes that input to a real-newline
# detailed dump so BOTH consumers see the same input:
#   - extract-pr-urls.py (channel mode) parses PR URLs from the normalized text
#   - review-inbox-discovery-probe.sh keys off `=== Message from` / `Message TS:` lines
# Three-state contract:
#   C) escaped-JSON single line  -> decode correctly, both consumers parse
#   D) real-newline detailed dump -> passthrough unchanged (no double-decode / breakage)
#   E) empty input               -> stays empty; probe still reports SOURCE_UNAVAILABLE
probe="$script_dir/review-inbox-discovery-probe.sh"
[[ -r "$probe" ]] || { echo "FAIL: probe not found at $probe" >&2; exit 1; }

# Canonical real-newline detailed dump used to build the escaped-JSON fixture. Use a
# fresh Message TS so the probe's default 24h staleness window does not trip.
now_epoch="$(date +%s)"
fresh_ts="${now_epoch}.000000"

canonical_dump="$tmp/canonical-detailed.txt"
cat > "$canonical_dump" <<TEXT
Channel: #product-pr (C012EXAMPLE)

=== Message from Reviewer (U123456789) at 2026-06-01 10:00:00 CST ===
Message TS: ${fresh_ts}
[APP-5000] please review
<https://github.com/example-org/example-web/pull/5000>
TEXT

# --- Fixture C: escaped-JSON single line (AC3) -----------------------------------------
# Build a single-line escaped-JSON payload: {"messages": "<escaped detailed dump>"}.
raw_c="$tmp/slack-fixture-c.json"
python3 - "$canonical_dump" "$raw_c" <<'PY'
import json
import sys
from pathlib import Path

dump = Path(sys.argv[1]).read_text()
# One physical line, real newlines escaped to literal \n inside the JSON string.
Path(sys.argv[2]).write_text(json.dumps({"messages": dump}))
PY

# Guard: the fixture must genuinely be a single physical line of escaped JSON.
line_count_c="$(wc -l < "$raw_c" | tr -d '[:space:]')"
[[ "$line_count_c" -eq 0 || "$line_count_c" -eq 1 ]] || {
  echo "FAIL: fixture C should be a single-line escaped-JSON payload (lines=$line_count_c)" >&2
  exit 1
}

normalized_c="$tmp/normalized-c.txt"
"$extractor" --org example-org --emit-normalized < "$raw_c" > "$normalized_c"

# Both consumers see the SAME normalized canonical dump.
urls_c="$tmp/urls-c.txt"
mapping_c="$tmp/mapping-c.json"
"$extractor" --org example-org --mapping "$mapping_c" < "$normalized_c" > "$urls_c"

python3 - "$normalized_c" "$urls_c" "$mapping_c" <<'PY'
import json
import sys
from pathlib import Path

normalized = Path(sys.argv[1]).read_text()
urls = [line for line in Path(sys.argv[2]).read_text().splitlines() if line]
mapping = json.loads(Path(sys.argv[3]).read_text())

# Decoded to a real-newline detailed dump that carries the detailed markers.
assert "=== Message from" in normalized, normalized
assert "Message TS:" in normalized, normalized
assert "\\n" not in normalized, "normalized output must not contain literal \\n escapes"
# DP-681：分頁狀態要跟著 normalized dump 一起交出去。payload 沒帶 pagination_info 時
# 寫成 `(none)`——「沒有這一行」與「這一行說讀完了」在下游是兩件事。
assert "Pagination cursor: (none)" in normalized, normalized

target = "https://github.com/example-org/example-web/pull/5000"
assert urls == [target], f"expected decoded PR URL, got {urls}"
assert mapping[target]["root_ticket_key"] == "APP-5000", mapping[target]
PY

# Probe must NOT report SOURCE_UNAVAILABLE on the normalized dump (source is healthy).
probe_out_c="$tmp/probe-c.txt"
set +e
bash "$probe" --raw-dump "$normalized_c" --candidates "$urls_c" \
  --window-seconds 604800 --now-epoch "$now_epoch" > "$probe_out_c" 2>&1
probe_rc_c=$?
set -e
grep -q 'POLARIS_DISCOVERY_OK' "$probe_out_c" || {
  echo "FAIL: probe should report OK on normalized escaped-JSON dump, got:" >&2
  cat "$probe_out_c" >&2
  exit 1
}
[[ "$probe_rc_c" -eq 0 ]] || { echo "FAIL: probe exit $probe_rc_c on fixture C" >&2; exit 1; }
grep -q 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE' "$probe_out_c" && {
  echo "FAIL: probe must not report SOURCE_UNAVAILABLE on a healthy normalized dump" >&2
  exit 1
}

# --- Fixture D: real-newline detailed dump passthrough (AC-NEG2) -----------------------
# A genuine real-newline detailed dump (webapi fallback shape) must pass through the
# decoder byte-for-byte: no double-decode, no breakage.
normalized_d="$tmp/normalized-d.txt"
"$extractor" --org example-org --emit-normalized < "$canonical_dump" > "$normalized_d"
diff "$canonical_dump" "$normalized_d" || {
  echo "FAIL: real-newline detailed dump must pass through normalize unchanged" >&2
  exit 1
}

# And the extractor still parses URLs from the passthrough output.
urls_d="$tmp/urls-d.txt"
mapping_d="$tmp/mapping-d.json"
"$extractor" --org example-org --mapping "$mapping_d" < "$normalized_d" > "$urls_d"
python3 - "$urls_d" <<'PY'
import sys
from pathlib import Path

urls = [line for line in Path(sys.argv[1]).read_text().splitlines() if line]
assert urls == ["https://github.com/example-org/example-web/pull/5000"], urls
PY

# --- Fixture E: empty input stays source-unavailable (AC-NEG2) -------------------------
# A genuinely empty / failed-fetch input must NOT be masked by normalize; the probe must
# still classify it as SOURCE_UNAVAILABLE (fail-closed).
raw_e="$tmp/slack-fixture-e.txt"
: > "$raw_e"

normalized_e="$tmp/normalized-e.txt"
"$extractor" --org example-org --emit-normalized < "$raw_e" > "$normalized_e"
[[ ! -s "$normalized_e" ]] || {
  echo "FAIL: empty input must normalize to empty output, not synthesize content" >&2
  cat "$normalized_e" >&2
  exit 1
}

urls_e="$tmp/urls-e.txt"
: > "$urls_e"
probe_out_e="$tmp/probe-e.txt"
set +e
bash "$probe" --raw-dump "$normalized_e" --candidates "$urls_e" \
  --window-seconds 604800 --now-epoch "$now_epoch" > "$probe_out_e" 2>&1
probe_rc_e=$?
set -e
grep -q 'POLARIS_DISCOVERY_SOURCE_UNAVAILABLE' "$probe_out_e" || {
  echo "FAIL: empty normalized dump must report SOURCE_UNAVAILABLE, got:" >&2
  cat "$probe_out_e" >&2
  exit 1
}
[[ "$probe_rc_e" -eq 2 ]] || { echo "FAIL: probe should fail-closed (exit 2) on empty input, got $probe_rc_e" >&2; exit 1; }

# --- Fixture F: thread 回覆接進 channel dump（DP-681 A-P3） -----------------------------
# 這個團隊的「我改好了，再看一次」幾乎都是回在原本那條 thread 裡，而 channel scan 只讀
# top-level。所以 thread 的回覆要接得進來，接進來之後：
#   1. 只出現在回覆裡的 PR URL 進得了 candidate；
#   2. 它的 thread_ts 是那條 thread 的根，不是那則回覆自己的 ts——掛錯根會讓姊妹單分群
#      拆散，也會讓回覆貼到一個沒有人在看的地方。
# slack_read_thread 的 detailed 用的是 From/Time/Message TS 三行，跟 channel 的
# `=== Message from … ===` 不是同一種格式，所以 --emit-normalized-thread 要翻過來。
raw_f="$tmp/slack-thread-f.json"
python3 - "$raw_f" <<'PY2'
import json
import sys
from pathlib import Path

thread = "\n".join([
    "=== THREAD PARENT MESSAGE ===",
    "From: Root <root@example.com> (U0000000010)",
    "Time: 2026-06-01 10:00:00 CST",
    "Message TS: 1717000000.100000",
    "[APP-5000] please review",
    "<https://github.com/example-org/example-web/pull/5000>",
    "",
    "=== THREAD REPLIES (1 total) ===",
    "",
    "--- Reply 1 of 1 ---",
    "From: Author <author@example.com> (U0000000011)",
    "Time: 2026-06-01 11:00:00 CST",
    "Message TS: 1717003600.200000",
    "fixed and pushed, please look again "
    "<https://github.com/example-org/example-web/pull/5001>",
])
Path(sys.argv[1]).write_text(
    json.dumps({"messages": thread,
                "pagination_info": "There are no more messages in this thread.\n"})
)
PY2

section_f="$tmp/section-f.txt"
"$extractor" --org example-org --emit-normalized-thread 1717000000.100000 \
  < "$raw_f" > "$section_f"

combined_f="$tmp/combined-f.txt"
cat "$normalized_c" > "$combined_f"
cat "$section_f" >> "$combined_f"

urls_f="$tmp/urls-f.txt"
mapping_f="$tmp/mapping-f.json"
"$extractor" --org example-org --mapping "$mapping_f" < "$combined_f" > "$urls_f"

python3 - "$section_f" "$urls_f" "$mapping_f" <<'PY3'
import json
import sys
from pathlib import Path

section = Path(sys.argv[1]).read_text()
urls = [line for line in Path(sys.argv[2]).read_text().splitlines() if line]
mapping = json.loads(Path(sys.argv[3]).read_text())

marker = "=== Thread replies for TS 1717000000.100000 ==="
assert section.startswith(marker), section[:120]
# From/Time 三行要被翻成 channel 的抬頭，否則 channel parser 一則都認不得。
assert "=== Message from Author <author@example.com> (U0000000011) at " \
       "2026-06-01 11:00:00 CST ===" in section, section

only_in_reply = "https://github.com/example-org/example-web/pull/5001"
assert only_in_reply in urls, f"只出現在 thread 回覆裡的 PR 沒進 candidate：{urls}"
got = mapping[only_in_reply]["thread_ts"]
assert got == "1717000000.100000", (
    f"thread 回覆裡的 PR 要掛在 thread 根上，拿到 {got}（那是回覆自己的 ts）"
)
print("A-P3 PASS：只出現在 thread 回覆裡的 PR 進了 candidate，thread_ts 是 thread 根")
PY3

echo "extract-pr-urls selftest: PASS"
