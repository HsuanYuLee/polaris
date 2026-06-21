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
    parser.add_argument("--emit-normalized", action="store_true",
                        help="Decode single-line escaped-JSON detailed dump to canonical "
                             "real-newline text and write it to stdout; the same canonical "
                             "text can then feed both this parser and the discovery probe.")
    return parser.parse_args()


# Detailed-dump markers that the channel-mode parser and the discovery probe both key off.
# Detecting either marker confirms the decoded payload is a Slack MCP "detailed" dump.
DETAILED_DUMP_MARKERS = ("=== Message from ", "Message TS: ")


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

    if isinstance(data, str):
        decoded = data
    elif isinstance(data, dict) and isinstance(data.get("messages"), str):
        decoded = data["messages"]
    else:
        return raw

    # Only treat it as a decoded detailed dump when the markers are present; otherwise
    # leave the original raw for the existing webapi / thread code paths to handle.
    if _looks_like_detailed_dump(decoded):
        return decoded
    return raw


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

    blocks = current_fmt_header.split(messages_text)
    # blocks: [pre_header, author1, ts_str1, body1, author2, ts_str2, body2, ...]

    seen_urls = set()
    ordered_urls = []
    mapping = {}

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
        slack_ts = ts_match.group(1)

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
