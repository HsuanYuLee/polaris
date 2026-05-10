#!/usr/bin/env python3
"""Scrub secrets and apply 20KB size cap to handoff artifact files.

Part of Polaris DP-024 P4 pipeline handoff artifact mechanism. See
`skills/references/handoff-artifact.md` for the artifact format spec.

Reads a handoff artifact markdown file with `## Summary` + `## Raw Evidence`
sections, scrubs known secret patterns from the Raw Evidence section, caps
total Raw Evidence bytes at 20KB using head+tail truncation, and updates the
frontmatter `scrubbed` / `truncated` flags. Writes back in place by default.

Usage:
    python3 scripts/snapshot-scrub.py --file PATH
    cat artifact.md | python3 scripts/snapshot-scrub.py --stdin > scrubbed.md
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

RAW_EVIDENCE_CAP_BYTES = 20 * 1024  # 20 KB hard limit on Raw Evidence section
HEAD_KEEP_BYTES = 13_000
TAIL_KEEP_BYTES = 6_000

SECRET_PATTERNS: list[tuple[re.Pattern, str]] = [
    # GitHub tokens
    (re.compile(r"ghp_[A-Za-z0-9]{36}"), "[REDACTED:github-pat]"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{82}"), "[REDACTED:github-pat]"),
    (re.compile(r"gho_[A-Za-z0-9]{36}"), "[REDACTED:github-oauth]"),
    (re.compile(r"ghs_[A-Za-z0-9]{36}"), "[REDACTED:github-server]"),
    (re.compile(r"ghr_[A-Za-z0-9]{36}"), "[REDACTED:github-refresh]"),
    # Anthropic (check before OpenAI: sk-ant-* would also match sk-*)
    (re.compile(r"sk-ant-[A-Za-z0-9_\-]{20,}"), "[REDACTED:anthropic]"),
    # OpenAI-like
    (re.compile(r"sk-(?:proj-)?[A-Za-z0-9_\-]{20,}"), "[REDACTED:openai-like]"),
    # Slack tokens
    (re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"), "[REDACTED:slack-token]"),
    # AWS access keys
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "[REDACTED:aws-access-key]"),
    (re.compile(r"\bASIA[0-9A-Z]{16}\b"), "[REDACTED:aws-temp-key]"),
    # Bearer tokens in HTTP headers (Authorization: Bearer XXX)
    (
        re.compile(r"(?i)(bearer\s+)[A-Za-z0-9\-._~+/]{20,}=*"),
        r"\1[REDACTED:bearer]",
    ),
    # Basic auth embedded in URLs (https://user:pass@host)
    (
        re.compile(r"(https?://)[^:/\s@]+:[^@\s]+@"),
        r"\1[REDACTED:basic-auth]@",
    ),
    # API token params in URLs (?api_token=xxx, ?token=xxx, ?access_token=xxx)
    (
        re.compile(
            r"(?i)([?&](?:api[_-]?token|access[_-]?token|auth[_-]?token|token)=)"
            r"[^&\s\"'<>]{8,}"
        ),
        r"\1[REDACTED:url-token]",
    ),
    # Generic labelled secret strings: password / secret / api_key / api_token = ...
    (
        re.compile(
            r"(?i)\b(password|passwd|secret|api[_-]?key|api[_-]?token)"
            r"(\s*[=:]\s*[\"']?)"
            r"[^\s\"'<>]{8,}"
        ),
        r"\1\2[REDACTED:secret]",
    ),
]


def scrub_secrets(text: str) -> tuple[str, int]:
    """Apply all secret patterns to text. Return (scrubbed_text, hit_count)."""
    hits = 0
    for pattern, replacement in SECRET_PATTERNS:
        text, n = pattern.subn(replacement, text)
        hits += n
    return text, hits


def apply_size_cap(raw_evidence: str) -> tuple[str, bool, int]:
    """Cap Raw Evidence to 20KB via head+tail truncation.

    Returns (capped_text, truncated_flag, original_byte_count).
    """
    encoded = raw_evidence.encode("utf-8")
    original_size = len(encoded)
    if original_size <= RAW_EVIDENCE_CAP_BYTES:
        return raw_evidence, False, original_size

    head = encoded[:HEAD_KEEP_BYTES].decode("utf-8", errors="ignore")
    tail = encoded[-TAIL_KEEP_BYTES:].decode("utf-8", errors="ignore")
    omitted = original_size - len(head.encode("utf-8")) - len(tail.encode("utf-8"))
    marker = f"\n\n[truncated, {omitted} bytes omitted]\n\n"
    return head + marker + tail, True, original_size


FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
RAW_EVIDENCE_RE = re.compile(r"(?ms)^## Raw Evidence\s*\n(.*)\Z")


def update_frontmatter_flag(frontmatter: str, key: str, value: bool) -> str:
    """Set or insert `key: value` in the YAML frontmatter block."""
    line_re = re.compile(rf"(?m)^{re.escape(key)}\s*:\s*\S+\s*$")
    new_line = f"{key}: {'true' if value else 'false'}"
    if line_re.search(frontmatter):
        return line_re.sub(new_line, frontmatter)
    return frontmatter.rstrip("\n") + "\n" + new_line


def process(content: str) -> tuple[str, dict]:
    fm_match = FRONTMATTER_RE.match(content)
    if not fm_match:
        raise ValueError(
            "artifact missing YAML frontmatter (expected `---` block at top)"
        )
    frontmatter = fm_match.group(1)
    body = content[fm_match.end():]

    raw_match = RAW_EVIDENCE_RE.search(body)
    if not raw_match:
        raise ValueError(
            "artifact missing `## Raw Evidence` section — nothing to scrub"
        )

    raw_before = raw_match.group(1)
    scrubbed_raw, hits = scrub_secrets(raw_before)
    capped_raw, truncated, original_size = apply_size_cap(scrubbed_raw)

    body_new = body[: raw_match.start(1)] + capped_raw
    frontmatter = update_frontmatter_flag(frontmatter, "scrubbed", True)
    frontmatter = update_frontmatter_flag(frontmatter, "truncated", truncated)

    result = f"---\n{frontmatter}\n---\n{body_new}"
    stats = {
        "secret_hits": hits,
        "truncated": truncated,
        "original_raw_bytes": original_size,
        "final_raw_bytes": len(capped_raw.encode("utf-8")),
    }
    return result, stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--file", type=Path, help="Artifact file to scrub in place")
    group.add_argument(
        "--stdin",
        action="store_true",
        help="Read artifact from stdin, write scrubbed version to stdout",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress stats line on stderr (file mode only)",
    )
    args = parser.parse_args()

    if args.stdin:
        content = sys.stdin.read()
        try:
            result, _ = process(content)
        except ValueError as exc:
            print(f"snapshot-scrub: {exc}", file=sys.stderr)
            return 2
        sys.stdout.write(result)
        return 0

    path: Path = args.file
    if not path.exists():
        print(f"snapshot-scrub: file not found: {path}", file=sys.stderr)
        return 2
    content = path.read_text(encoding="utf-8")
    try:
        result, stats = process(content)
    except ValueError as exc:
        print(f"snapshot-scrub: {exc}", file=sys.stderr)
        return 2
    path.write_text(result, encoding="utf-8")
    if not args.quiet:
        print(
            f"snapshot-scrub: {path} "
            f"secrets={stats['secret_hits']} "
            f"truncated={stats['truncated']} "
            f"raw_bytes={stats['original_raw_bytes']}"
            f"->{stats['final_raw_bytes']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
