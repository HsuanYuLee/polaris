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
"""

import json
import re
import sys
import argparse
import unicodedata
from datetime import datetime, timezone, timedelta


TICKET_RE = re.compile(r"\b(GT-\d+|KB2CW-\d+|[A-Z][A-Z0-9]+-\d+)\b")
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
    return parser.parse_args()


def timestamp_to_slack_ts(ts_str):
    """Convert 'YYYY-MM-DD HH:MM:SS CST' to approximate Slack ts (Unix epoch)."""
    try:
        # CST = UTC+8
        cst = timezone(timedelta(hours=8))
        dt = datetime.strptime(ts_str.strip(), "%Y-%m-%d %H:%M:%S")
        dt = dt.replace(tzinfo=cst)
        return f"{int(dt.timestamp())}.000000"
    except (ValueError, AttributeError):
        return None


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

    Supports two MCP output formats:
    1. Legacy: split by [YYYY-MM-DD HH:MM:SS CST] timestamp markers
    2. Current: split by '=== Message from ... at TIMESTAMP CST ===' headers
       with 'Message TS: XXXX' on the following line

    Returns:
        urls: list of unique PR URLs (deduplicated, preserving order)
        mapping: dict of { pr_url: { "thread_ts": "...", "author": "..." } }
    """
    pr_url_pattern = re.compile(
        rf'https://github\.com/{re.escape(org)}/[^/|>\s]+/pull/\d+'
    )

    # Detect format: current MCP uses '=== Message from ... at ... CST ==='
    current_fmt_header = re.compile(
        r'=== Message from (.+?) \(U[A-Z0-9]+\) at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) CST ==='
    )
    current_fmt_ts = re.compile(r'Message TS: (\d+\.\d+)')

    seen_urls = set()
    ordered_urls = []
    mapping = {}

    if current_fmt_header.search(messages_text):
        # Current MCP format: split on '=== Message from ...' headers
        # Each block: header line, Message TS line, then body content
        blocks = current_fmt_header.split(messages_text)
        # blocks: [pre_header, author1, ts1, body1, author2, ts2, body2, ...]
        # split() with 2 groups gives triples: (author, timestamp, body) per message

        i = 1  # skip pre-header content
        while i + 2 < len(blocks):
            author_raw = blocks[i].replace('\u200b', '').strip()
            ts_str = blocks[i + 1]  # YYYY-MM-DD HH:MM:SS
            body = blocks[i + 2]

            # Extract the real Slack ts from 'Message TS: XXXX' line
            ts_match = current_fmt_ts.search(body)
            slack_ts = ts_match.group(1) if ts_match else timestamp_to_slack_ts(ts_str)

            # Strip display name suffixes (e.g. " (WFH)") — keep first word(s)
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
    else:
        # Legacy format: split by [YYYY-MM-DD HH:MM:SS CST]
        timestamp_pattern = re.compile(r'\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) CST\]')
        segments = timestamp_pattern.split(messages_text)
        # segments alternates: [content0, ts0, content1, ts1, ...]

        for i in range(0, len(segments) - 1, 2):
            content = segments[i].strip()
            ts_str = segments[i + 1] if i + 1 < len(segments) else None

            urls_in_segment = pr_url_pattern.findall(content)
            if not urls_in_segment:
                continue

            slack_ts = timestamp_to_slack_ts(ts_str) if ts_str else None
            root_ticket_key = root_ticket_key_for_text(content)
            root_topic_key = None if root_ticket_key else root_topic_key_for_text(content, org)

            lines = content.split('\n')
            author = "unknown"
            for line in lines:
                line = line.strip()
                if line and ':' in line and not line.startswith('Channel:'):
                    author_match = re.match(r'^([^:<]+):', line)
                    if author_match:
                        author = author_match.group(1).replace('\u200b', '').strip()
                        break

            for url in urls_in_segment:
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
