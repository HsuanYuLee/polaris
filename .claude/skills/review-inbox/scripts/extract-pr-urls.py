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
from datetime import datetime, timezone, timedelta


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

    for match in pr_url_pattern.finditer(text):
        url = re.sub(r'#.*$', '', match.group())
        if url not in seen_urls:
            seen_urls.add(url)
            ordered_urls.append(url)
            mapping[url] = {"thread_ts": thread_ts}

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
