#!/usr/bin/env python3
"""
Extract GitHub PR URLs and thread_ts mapping from Slack output.

Input:  Slack MCP output OR Slack Web API JSON (from conversations.history / replies)
Output: PR URLs to stdout (one per line, for piping to fetch-prs-by-url.sh)
Side:   Writes thread mapping to --mapping file (default /tmp/pr-thread-mapping.json)

Usage:
  # Channel mode (default): parse per-message thread_ts from MCP format
  cat /tmp/slack-raw.json | python3 extract-pr-urls.py --org your-org

  # Thread mode: all URLs map to the given thread_ts (for slack_read_thread output)
  cat /tmp/slack-thread.json | python3 extract-pr-urls.py --org your-org --thread-ts 1776130982.981829

thread_ts 來源只有兩種：Slack Web API 真實 ts，或 MCP text dump 的 `Message TS:` 行。
不存在從人類時間字串反推 ts 的 code path（DP-181）。
"""

import json
import re
import sys
import argparse
import unicodedata


# 邊界不能用 \b：底線在 regex 裡是 word 字元，所以 Slack 斜體 `_DEMO-1 …_` 的 `_` 與 `D`
# 之間不構成邊界，整個單號抓不到。但也不能一律放行底線——`x_DEMO-1` 是一個識別字的一段，
# 不是被標記包起來的單號。所以左邊分兩種寫法：一串底線（它自己左邊不能是英數等 word 字元），
# 或是一個一般的非 word 邊界。右邊同理，只放行底線。
TICKET_RE = re.compile(
    r"(?:(?<![^\W_])_+|(?<!\w))(GT-\d+|KB2CW-\d+|[A-Z][A-Z0-9]+-\d+)(?![^\W_])"
)
TOPIC_TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)?")
GENERIC_TOPIC_TOKENS = {
    "a",
    "an",
    "and",
    "approve",
    "author",
    "b2c",
    "bridge",
    "code",
    "cross",
    "for",
    "help",
    "hi",
    "ios",
    "js",
    "lu",
    "m",
    "member",
    "message",
    "mobile",
    "native",
    "nuxt",
    "patch",
    "pc",
    "please",
    "pr",
    "pray",
    "pull",
    "repo",
    "review",
    "skin",
    "thanks",
    "team",
    "the",
    "these",
    "this",
    "tone",
    "web",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Extract PR URLs from Slack MCP output")
    parser.add_argument("--org", required=True, help="GitHub org to filter (e.g. your-org)")
    parser.add_argument("--mapping", default="/tmp/pr-thread-mapping.json",
                        help="Output path for PR URL → thread_ts mapping")
    parser.add_argument("--thread-ts", default=None,
                        help="Thread mode: skip per-message parsing, map all URLs to this thread_ts")
    parser.add_argument("--emit-normalized", action="store_true",
                        help="Decode single-line escaped-JSON detailed dump to canonical "
                             "real-newline text and write it to stdout; the same canonical "
                             "text can then feed both this parser and the discovery probe.")
    parser.add_argument("--emit-normalized-thread", metavar="PARENT_TS", default=None,
                        help="Decode a slack_read_thread payload into the same canonical "
                             "channel-dump shape, wrapped in a "
                             "'=== Thread replies for TS <PARENT_TS> ===' section marker. "
                             "Append the output to the channel dump: the parser then maps "
                             "every URL in it to PARENT_TS, and the discovery probe reads "
                             "the marker as proof that this thread was actually read.")
    return parser.parse_args()


# Detailed-dump markers that the channel-mode parser and the discovery probe both key off.
# Detecting either marker confirms the decoded payload is a Slack MCP "detailed" dump.
DETAILED_DUMP_MARKERS = ("=== Message from ", "Message TS: ")

# 分頁狀態必須留在 normalized dump 裡（DP-681）。MCP 的 payload 把 cursor 放在 `messages`
# 隔壁的 `pagination_info` 那一格，而這支以前只把 `messages` 解出來就交出去——於是「還有
# 更舊的沒讀」這件事在管線的第一步就消失了，下游沒有任何人看得到它。2026-09-04 兩輪
# channel scan 都只讀了最新那一頁（66 則、回溯到窗內），而 cursor 一直在 payload 裡。
#
# 沒有下一頁的時候也要寫一行，值是 NO_CURSOR_SENTINEL：一個「沒有標記」與一個「標記說
# 讀完了」在檔案裡長得不一樣，而它們要人做的事相反。
PAGINATION_MARKER = "Pagination cursor: "
NO_CURSOR_SENTINEL = "(none)"
CURSOR_RE = re.compile(r"cursor:\s*`?([A-Za-z0-9_=+/-]+)`?")

# 一段 thread 回覆被接進 channel dump 時，前面加這一行。它有兩個用途：
#   1. probe 拿它回答「窗內有新回覆的 thread，回覆讀進來了沒」；
#   2. 這支的 channel parser 拿它把後面那些訊息的 thread 歸屬指回根訊息——回覆自己的
#      `Message TS` 是它自己的 ts，直接拿來當 thread_ts 會把姊妹單分群拆散、也會讓
#      回覆貼到錯的地方。
THREAD_SECTION_PREFIX = "=== Thread replies for TS "
THREAD_SECTION_SUFFIX = " ==="
THREAD_SECTION_RE = re.compile(
    r"^=== Thread replies for TS (\d+\.\d+) ===$", re.MULTILINE
)


def _looks_like_detailed_dump(text):
    """Return True when text carries a Slack MCP detailed-dump marker."""
    return any(marker in text for marker in DETAILED_DUMP_MARKERS)


def normalize_detailed_dump(raw):
    """Decode a single-line escaped-JSON detailed dump to canonical real-newline text.

    The Slack MCP "detailed" channel output can arrive as a single-line escaped-JSON
    payload (real newlines collapsed into literal `\\n`), either as a bare JSON string
    or wrapped in `{"messages": "<escaped dump>"}`. This is the single shared decoder:
    its canonical real-newline output is consumed identically by this parser's channel
    mode and by review-inbox-discovery-probe.sh, so the two never drift on the same
    input (DP-312-T3, AC3).

    Inputs that are not escaped-JSON detailed dumps pass through unchanged (AC-NEG2):
    an already real-newline detailed dump, plain text, or a genuinely empty / failed
    fetch are returned as-is so a real source-unavailable state is never masked.

    Args:
        raw: Raw stdin text (escaped-JSON single line, real-newline dump, or empty).

    Returns:
        Canonical real-newline detailed-dump text when raw was escaped-JSON; otherwise
        raw unchanged.
    """
    stripped = raw.strip()
    if not stripped:
        return raw

    # Only single-physical-line input is a normalize candidate; a real-newline dump
    # already has its newlines and must pass through untouched.
    if "\n" in stripped:
        return raw

    try:
        data = json.loads(stripped)
    except json.JSONDecodeError:
        return raw

    pagination = None
    if isinstance(data, str):
        decoded = data
    elif isinstance(data, dict) and isinstance(data.get("messages"), str):
        decoded = data["messages"]
        pagination = data.get("pagination_info")
    else:
        return raw

    # Only treat it as a decoded detailed dump when the markers are present; otherwise
    # leave the original raw for the existing webapi / thread code paths to handle.
    if not _looks_like_detailed_dump(decoded):
        return raw

    return decoded.rstrip("\n") + "\n" + pagination_marker_line(pagination) + "\n"


def pagination_marker_line(pagination_info):
    """Render the canonical one-line pagination marker for a channel payload.

    `pagination_info` is the MCP payload's sibling field; it is prose that carries the
    cursor when more pages exist and is absent / empty when the channel is exhausted.
    Either way this returns a line, because "no marker" and "marker says done" must not
    look the same downstream.
    """
    if isinstance(pagination_info, str):
        match = CURSOR_RE.search(pagination_info)
        if match:
            return PAGINATION_MARKER + match.group(1)
    return PAGINATION_MARKER + NO_CURSOR_SENTINEL


# slack_read_thread 的 detailed 輸出跟 channel scan 不是同一種格式：它用
#   From: {Name} <{email}> ({UID})
#   Time: {YYYY-MM-DD HH:MM:SS} CST
#   Message TS: {epoch}
# 三行，channel scan 用一行 `=== Message from {Name} ({UID}) at {time} CST ===`。
# 直接把 thread dump 接到 channel dump 後面，channel parser 一則都認不得——它只認
# `=== Message from` 那一行。所以這裡把它翻成 channel 的形狀，翻完兩個消費端（這支的
# parser 與 probe）看到的仍然是同一份文字。
_THREAD_FROM_RE = re.compile(r"^From:\s*(.+?)\s*$")
_THREAD_TIME_RE = re.compile(r"^Time:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*CST\s*$")
_THREAD_TS_RE = re.compile(r"^Message TS:\s*(\d+\.\d+)\s*$")


def normalize_thread_dump(raw, parent_ts):
    """Turn a slack_read_thread payload into a channel-shaped, section-marked dump.

    Returns the section text (marker line + rewritten messages). The caller appends it
    to the channel dump; `extract_from_messages` then maps every URL inside the section
    to `parent_ts`, and review-inbox-discovery-probe.sh reads the marker as the evidence
    that this thread's replies were fetched.
    """
    stripped = raw.strip()
    decoded = stripped
    if stripped and "\n" not in stripped:
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            data = None
        if isinstance(data, str):
            decoded = data
        elif isinstance(data, dict) and isinstance(data.get("messages"), str):
            decoded = data["messages"]

    lines = decoded.split("\n")
    out = [THREAD_SECTION_PREFIX + parent_ts + THREAD_SECTION_SUFFIX]
    i = 0
    emitted = 0
    while i < len(lines):
        from_match = _THREAD_FROM_RE.match(lines[i])
        if not from_match:
            out.append(lines[i])
            i += 1
            continue
        # From / Time / Message TS 三行要連著出現才算一則訊息的抬頭；只對上 From 的
        # 那一行是正文裡剛好長成那樣的字，原樣留著。
        time_match = _THREAD_TIME_RE.match(lines[i + 1]) if i + 1 < len(lines) else None
        ts_match = _THREAD_TS_RE.match(lines[i + 2]) if i + 2 < len(lines) else None
        if not (time_match and ts_match):
            out.append(lines[i])
            i += 1
            continue
        out.append(
            f"=== Message from {from_match.group(1)} at {time_match.group(1)} CST ==="
        )
        out.append(f"Message TS: {ts_match.group(1)}")
        emitted += 1
        i += 3

    if emitted == 0:
        print(
            f"WARN: thread {parent_ts} 的 dump 裡一則訊息抬頭都沒認出來，這一段是空的",
            file=sys.stderr,
        )
    return "\n".join(out) + "\n"


def root_ticket_key_for_text(text):
    """Return the first ticket key before the first PR URL in a Slack root message."""
    first_url = re.search(r'https://github\.com/[^/|>\s]+/[^/|>\s]+/pull/\d+', text)
    prefix = text[:first_url.start()] if first_url else text
    match = TICKET_RE.search(prefix)
    return match.group(1) if match else None


def org_topic_tokens(org):
    """Return generic org fragments that should not become topic keys."""
    return {
        token
        for token in re.split(r"[^A-Za-z0-9]+", org.lower())
        if len(token) >= 2
    }


def root_topic_key_for_text(text, org=""):
    """Return a deterministic topic key for topic-only multi-PR Slack root messages."""
    first_url = re.search(r'https://github\.com/[^/|>\s]+/[^/|>\s]+/pull/\d+', text)
    prefix = text[:first_url.start()] if first_url else text
    prefix = unicodedata.normalize("NFKC", prefix)
    prefix = TICKET_RE.sub(" ", prefix)
    prefix = re.sub(r"<@[^>]+>", " ", prefix)
    prefix = re.sub(r":[A-Za-z0-9_+\-]+:", " ", prefix)
    prefix = re.sub(r"[*_~`|>#\[\](){}]", " ", prefix)
    tokens = []
    has_strong_topic_signal = False
    for match in TOPIC_TOKEN_RE.finditer(prefix):
        raw = match.group(0)
        if "." in raw or re.search(r"[a-z][A-Z]", raw):
            has_strong_topic_signal = True
        lowered = raw.lower().replace("_", "-")
        if lowered in GENERIC_TOPIC_TOKENS or lowered in org_topic_tokens(org):
            continue
        if len(lowered) < 3 and "." not in lowered:
            continue
        tokens.append(lowered)
    if not tokens or not has_strong_topic_signal:
        return None

    # Keep a compact, readable key. The Slack thread_ts still scopes uniqueness.
    deduped = []
    seen = set()
    for token in tokens:
        slug = re.sub(r"[^a-z0-9]+", "-", token).strip("-")
        if not slug or slug in seen:
            continue
        seen.add(slug)
        deduped.append(slug)
        if len(deduped) >= 6:
            break
    return f"topic:{'-'.join(deduped)}" if deduped else None


def extract_from_messages(messages_text, org):
    """Parse the formatted Slack MCP output text.

    Expects the current MCP format with headers
    `=== Message from {Name} ({UID}) at YYYY-MM-DD HH:MM:SS CST ===`
    and bodies containing `Message TS: <real_ts>`.

    thread_ts 一律從 body 的 `Message TS:` 取得；缺少該行的訊息整則 skip 並 stderr WARN
    （DP-181：不再從人類時間字串反推 ts，避免 Slack 把 fake ts 當成 channel 頂層訊息）。

    例外是被 `=== Thread replies for TS <parent> ===` 圈起來的那幾段（DP-681）：那裡面
    每一則的 `Message TS` 是回覆自己的 ts，不是它所屬的 thread。那一段裡的 URL 一律掛在
    <parent> 上——這個團隊的「我改好了，再看一次」幾乎都是回在原本那條 thread 裡，掛錯
    根會讓姊妹單分群拆散，也會讓回覆貼到一個沒有人在看的地方。

    Returns:
        urls: list of unique PR URLs (deduplicated, preserving order)
        mapping: dict of { pr_url: { "thread_ts": "...", "author": "..." } }
    """
    pr_url_pattern = re.compile(
        rf'https://github\.com/{re.escape(org)}/[^/|>\s]+/pull/\d+'
    )

    current_fmt_header = re.compile(
        r'=== Message from (.+?) \(U[A-Z0-9]+\) at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) CST ==='
    )
    current_fmt_ts = re.compile(r'Message TS: (\d+\.\d+)')

    if not current_fmt_header.search(messages_text):
        print("WARN: 找不到 '=== Message from' headers，跳過所有 URL", file=sys.stderr)
        return [], {}

    seen_urls = set()
    ordered_urls = []
    mapping = {}

    def parse_section(section_text, forced_thread_ts):
        blocks = current_fmt_header.split(section_text)
        # blocks: [pre_header, author1, ts_str1, body1, author2, ts_str2, body2, ...]
        i = 1
        while i + 2 < len(blocks):
            author_raw = blocks[i].replace('​', '').strip()
            body = blocks[i + 2]

            ts_match = current_fmt_ts.search(body)
            if not ts_match:
                print(
                    f"WARN: 跳過缺少 Message TS 的訊息 (author={author_raw})",
                    file=sys.stderr,
                )
                i += 3
                continue
            slack_ts = forced_thread_ts or ts_match.group(1)

            author = re.sub(r'\s*\([^)]*\)\s*$', '', author_raw).strip()
            root_ticket_key = root_ticket_key_for_text(body)
            root_topic_key = None if root_ticket_key else root_topic_key_for_text(body, org)

            urls_in_block = pr_url_pattern.findall(body)
            for url in urls_in_block:
                url = re.sub(r'#.*$', '', url)
                if url not in seen_urls:
                    seen_urls.add(url)
                    ordered_urls.append(url)
                    mapping[url] = {
                        "thread_ts": slack_ts,
                        "author": author,
                    }
                    if root_ticket_key:
                        mapping[url]["root_ticket_key"] = root_ticket_key
                    if root_topic_key:
                        mapping[url]["root_topic_key"] = root_topic_key
            i += 3

    # 先照 thread 區段切開：`re.split` 對帶一個捕捉群組的樣式交回
    # [段0, parent1, 段1, parent2, 段2, ...]，段 0 是 channel 的 top-level。
    parts = THREAD_SECTION_RE.split(messages_text)
    parse_section(parts[0], None)
    for idx in range(1, len(parts) - 1, 2):
        parse_section(parts[idx + 1], parts[idx])

    return ordered_urls, mapping


def extract_urls_for_thread(text, org, thread_ts):
    """Thread mode: extract all PR URLs from text, map all to the given thread_ts.

    Used with slack_read_thread output where the thread_ts is already known
    from the Slack URL. No per-message parsing needed — just find URLs.
    """
    pr_url_pattern = re.compile(
        rf'https://github\.com/{re.escape(org)}/[^/|>\s]+/pull/\d+'
    )

    seen_urls = set()
    ordered_urls = []
    mapping = {}
    root_ticket_key = root_ticket_key_for_text(text)
    root_topic_key = None if root_ticket_key else root_topic_key_for_text(text, org)

    for match in pr_url_pattern.finditer(text):
        url = re.sub(r'#.*$', '', match.group())
        if url not in seen_urls:
            seen_urls.add(url)
            ordered_urls.append(url)
            mapping[url] = {"thread_ts": thread_ts}
            if root_ticket_key:
                mapping[url]["root_ticket_key"] = root_ticket_key
            if root_topic_key:
                mapping[url]["root_topic_key"] = root_topic_key

    return ordered_urls, mapping


def extract_from_webapi_messages(messages, org):
    """Parse Slack Web API messages array.

    Supports payloads from:
    - conversations.history
    - conversations.replies
    """
    pr_url_pattern = re.compile(
        rf'https://github\.com/{re.escape(org)}/[^/|>\s]+/pull/\d+'
    )

    seen_urls = set()
    ordered_urls = []
    mapping = {}

    for msg in messages:
        text = msg.get("text", "") or ""
        if not text:
            continue

        message_ts = msg.get("ts")
        thread_ts = msg.get("thread_ts") or message_ts
        author = msg.get("user", "unknown")
        root_ticket_key = root_ticket_key_for_text(text)
        root_topic_key = None if root_ticket_key else root_topic_key_for_text(text, org)

        for match in pr_url_pattern.finditer(text):
            url = re.sub(r'#.*$', '', match.group())
            if url in seen_urls:
                continue
            seen_urls.add(url)
            ordered_urls.append(url)
            mapping[url] = {
                "thread_ts": thread_ts,
                "author": author,
            }
            if root_ticket_key:
                mapping[url]["root_ticket_key"] = root_ticket_key
            if root_topic_key:
                mapping[url]["root_topic_key"] = root_topic_key

    return ordered_urls, mapping


def main():
    args = parse_args()

    raw = sys.stdin.read()

    if args.emit_normalized_thread:
        sys.stdout.write(normalize_thread_dump(raw, args.emit_normalized_thread))
        return

    # Single shared decoder: collapse a single-line escaped-JSON detailed dump into
    # canonical real-newline text up front (DP-312-T3). Both this parser and the
    # discovery probe then see the same canonical input; non-escaped input is unchanged.
    raw = normalize_detailed_dump(raw)

    if args.emit_normalized:
        sys.stdout.write(raw)
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        data = None

    if isinstance(data, dict) and isinstance(data.get("messages"), list):
        urls, mapping = extract_from_webapi_messages(data["messages"], args.org)
        if args.thread_ts:
            for url in mapping:
                mapping[url]["thread_ts"] = args.thread_ts
    else:
        if isinstance(data, dict):
            messages_text = data.get("messages", "")
        else:
            # If not JSON, treat as plain text (e.g. MCP returned raw string)
            messages_text = raw

        if args.thread_ts:
            urls, mapping = extract_urls_for_thread(messages_text, args.org, args.thread_ts)
        else:
            urls, mapping = extract_from_messages(messages_text, args.org)

    # Write mapping file
    with open(args.mapping, "w") as f:
        json.dump(mapping, f, indent=2, ensure_ascii=False)

    # Output URLs to stdout (for piping)
    for url in urls:
        print(url)


if __name__ == "__main__":
    main()
