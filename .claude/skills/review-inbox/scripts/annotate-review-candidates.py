#!/usr/bin/env python3
"""Annotate review-inbox candidates with model tier and sister PR cluster data."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


SAFE_EXTENSIONS = {".ico", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif"}
TICKET_RE = re.compile(r"\b(KB2CW-\d+|[A-Z][A-Z0-9]+-\d+)\b")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Add model_tier and review_cluster fields to PR candidates.")
    parser.add_argument("--mapping", default="", help="Optional PR URL -> Slack thread mapping JSON from extract-pr-urls.py.")
    parser.add_argument("--offline", action="store_true", help="Do not call gh for missing PR file metadata.")
    return parser.parse_args()


def load_mapping(path: str) -> dict:
    if not path:
        return {}
    mapping_path = Path(path)
    if not mapping_path.exists():
        return {}
    with mapping_path.open() as handle:
        data = json.load(handle)
    return data if isinstance(data, dict) else {}


def owner_repo_number(candidate: dict) -> tuple[str | None, str | None, int | None]:
    url = str(candidate.get("url") or "")
    match = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", url)
    if not match:
        return None, candidate.get("repo"), candidate.get("number")
    return match.group(1), match.group(2), int(match.group(3))


def fetch_file_metadata(candidate: dict, offline: bool) -> None:
    if offline or candidate.get("files"):
        return

    owner, repo, number = owner_repo_number(candidate)
    if not owner or not repo or not number:
        return

    try:
        pr_meta = subprocess.check_output(
            [
                "gh",
                "api",
                f"repos/{owner}/{repo}/pulls/{number}",
                "--jq",
                "{changed_files: .changed_files, additions: .additions, deletions: .deletions}",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        candidate.update(json.loads(pr_meta))
    except Exception:
        return

    try:
        files = subprocess.check_output(
            [
                "gh",
                "api",
                f"repos/{owner}/{repo}/pulls/{number}/files",
                "--paginate",
                "--jq",
                "[.[] | {filename, additions, deletions, status}]",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        parsed_files = json.loads(files)
        if isinstance(parsed_files, list):
            candidate["files"] = parsed_files
    except Exception:
        return


def ticket_key(candidate: dict) -> str | None:
    haystack = " ".join(str(candidate.get(key) or "") for key in ("title", "url", "repo"))
    match = TICKET_RE.search(haystack)
    return match.group(1) if match else None


def root_ticket_key(candidate: dict, mapping: dict) -> str | None:
    url = str(candidate.get("url") or "")
    mapped = mapping.get(url)
    if isinstance(mapped, dict) and mapped.get("root_ticket_key"):
        return str(mapped["root_ticket_key"])
    if candidate.get("root_ticket_key"):
        return str(candidate["root_ticket_key"])
    return None


def root_topic_key(candidate: dict, mapping: dict) -> str | None:
    url = str(candidate.get("url") or "")
    mapped = mapping.get(url)
    if isinstance(mapped, dict) and mapped.get("root_topic_key"):
        return str(mapped["root_topic_key"])
    if candidate.get("root_topic_key"):
        return str(candidate["root_topic_key"])
    return None


def thread_ts(candidate: dict, mapping: dict) -> str | None:
    url = str(candidate.get("url") or "")
    mapped = mapping.get(url)
    if isinstance(mapped, dict) and mapped.get("thread_ts"):
        return str(mapped["thread_ts"])
    for key in ("thread_ts", "slack_thread_ts"):
        if candidate.get(key):
            return str(candidate[key])
    return None


def file_names(candidate: dict) -> list[str]:
    files = candidate.get("files")
    if not isinstance(files, list):
        return []
    names = []
    for item in files:
        if isinstance(item, dict) and item.get("filename"):
            names.append(str(item["filename"]))
        elif isinstance(item, str):
            names.append(item)
    return names


def is_safe_asset(path: str) -> bool:
    return any(path.endswith(ext) for ext in SAFE_EXTENSIONS)


def is_safe_config(path: str) -> bool:
    name = Path(path).name
    return path.startswith(".changeset/") or name.startswith("nuxt.config.") or name == "package.json" or is_safe_asset(path)


def line_delta(candidate: dict) -> int | None:
    additions = candidate.get("additions")
    deletions = candidate.get("deletions")
    if isinstance(additions, int) and isinstance(deletions, int):
        return additions + deletions

    total = 0
    saw_file_delta = False
    for file_info in candidate.get("files") or []:
        if not isinstance(file_info, dict):
            continue
        add = file_info.get("additions")
        delete = file_info.get("deletions")
        if isinstance(add, int) and isinstance(delete, int):
            saw_file_delta = True
            total += add + delete
    return total if saw_file_delta else None


def classify_model_tier(candidate: dict, cluster_role: str) -> tuple[str, str]:
    if cluster_role == "cluster_sibling":
        return "small_fast", "sibling PR diff/sanity mode"

    names = file_names(candidate)
    changed_files = candidate.get("changed_files")
    if not isinstance(changed_files, int):
        changed_files = len(names) if names else None
    delta = line_delta(candidate)

    if changed_files == 1 and delta is not None and delta <= 50:
        return "small_fast", "single-file <=50 line delta"

    if names and all(is_safe_config(name) for name in names):
        if delta is None or delta <= 120:
            return "small_fast", "asset/config/changeset-only files"

    return "standard_coding", "default review risk"


def annotate(candidates: list[dict], mapping: dict, offline: bool) -> list[dict]:
    enriched = []
    cluster_groups: dict[str, list[dict]] = {}

    for raw in candidates:
        candidate = dict(raw)
        fetch_file_metadata(candidate, offline)

        ticket = ticket_key(candidate)
        root_ticket = root_ticket_key(candidate, mapping)
        root_topic = root_topic_key(candidate, mapping)
        ts = thread_ts(candidate, mapping)
        cluster_ticket = root_ticket or root_topic or ticket
        cluster_key = f"{ts}:{cluster_ticket}" if ts and cluster_ticket else ""
        candidate["ticket_key"] = ticket
        candidate["root_ticket_key"] = root_ticket
        candidate["root_topic_key"] = root_topic
        candidate["slack_thread_ts"] = ts
        candidate["cluster_key"] = cluster_key
        candidate["cluster_role"] = "standalone"
        candidate["cluster_size"] = 1
        candidate["cluster_lead_url"] = ""
        candidate["cluster_lead_summary"] = str(candidate.get("cluster_lead_summary") or "")
        enriched.append(candidate)
        if cluster_key:
            cluster_groups.setdefault(cluster_key, []).append(candidate)

    for group in cluster_groups.values():
        if len(group) < 2:
            continue
        group.sort(key=lambda item: (str(item.get("repo") or ""), int(item.get("number") or 0)))
        lead = group[0]
        for item in group:
            item["cluster_size"] = len(group)
            item["cluster_lead_url"] = lead.get("url") or ""
            item["cluster_role"] = "cluster_lead" if item is lead else "cluster_sibling"

    for candidate in enriched:
        tier, reason = classify_model_tier(candidate, candidate["cluster_role"])
        candidate["model_tier"] = tier
        candidate["model_tier_reason"] = reason

    return enriched


def main() -> int:
    args = parse_args()
    try:
        candidates = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"annotate-review-candidates: invalid JSON input: {exc}", file=sys.stderr)
        return 2
    if not isinstance(candidates, list):
        print("annotate-review-candidates: input must be a JSON array", file=sys.stderr)
        return 2

    mapping = load_mapping(args.mapping)
    json.dump(annotate(candidates, mapping, args.offline), sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
