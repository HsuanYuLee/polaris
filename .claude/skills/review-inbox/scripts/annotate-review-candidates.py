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

    # --paginate --slurp 交回的是「每頁一個陣列」包成的一個陣列，投影在這裡做。
    # 只帶 --paginate 配 --jq 的話 gh 逐頁套用投影，超過一頁的 PR 會吐出兩個並排的
    # JSON 陣列——json.loads 對它丟 JSONDecodeError，而底下這個 except 把它吞掉，於是
    # 檔案清單整份不見、一行輸出都沒有。--slurp 不能跟 --jq 併用（gh 自己會拒絕）。
    try:
        pages = json.loads(
            subprocess.check_output(
                [
                    "gh",
                    "api",
                    f"repos/{owner}/{repo}/pulls/{number}/files",
                    "--paginate",
                    "--slurp",
                ],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        )
    except Exception:
        return

    if not isinstance(pages, list):
        return
    candidate["files"] = [
        {
            "filename": item.get("filename"),
            "additions": item.get("additions"),
            "deletions": item.get("deletions"),
            "status": item.get("status"),
            # 區塊就在同一份回應裡，不用多打一次 API。留的是 base 那一側的行號範圍，
            # 不是整份 patch：兩顆 PR 從同一個 base 長出來，只有 base 那一側可比——
            # 新的那一側各自被自己的新增行推移過，比出來的重疊是假的。
            "hunks": old_side_hunks(item),
        }
        for page in pages
        if isinstance(page, list)
        for item in page
        if isinstance(item, dict)
    ]


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


HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+")

# 整個檔案都算數的那一種：新增或刪除掉整個檔案時，base 那一側沒有可比的行號範圍，
# 而「兩顆 PR 都動了同一個路徑的存在與否」本來就是最強的交集。
WHOLE_FILE = "whole-file"


def old_side_hunks(item: dict) -> list | str:
    """一個檔案在 base 那一側被動到的行號範圍。"""
    if item.get("status") in ("added", "removed", "renamed"):
        return WHOLE_FILE
    patch = item.get("patch")
    if not isinstance(patch, str) or not patch:
        # 二進位檔、或 GitHub 因為太大而省略 patch 的檔案。**不要當成沒動到**——
        # 回 None 讓上層讀成「這個檔量不到」，而量不到走完整 review。
        return None
    ranges = []
    for line in patch.splitlines():
        match = HUNK_RE.match(line)
        if not match:
            continue
        start = int(match.group(1))
        count = int(match.group(2)) if match.group(2) is not None else 1
        # count 0 是純插入：base 那一側沒有被刪掉的行，插入點本身就是它的位置。
        ranges.append((start, start + count - 1) if count else (start, start))
    return ranges or None


def hunks_by_file(candidate: dict) -> dict | None:
    """這顆 PR 每個檔案在 base 那一側動到哪裡。整顆量不到就回 None。"""
    files = candidate.get("files")
    if not isinstance(files, list) or not files:
        return None
    out = {}
    for item in files:
        if not isinstance(item, dict):
            continue
        name = item.get("filename")
        if not name:
            continue
        out[str(name)] = item.get("hunks", None)
    return out or None


def shared_change(left: dict, right: dict) -> tuple[bool, str]:
    """兩顆 PR 的改動有沒有交集，以及一句說得出憑什麼的理由。

    回 (False, 理由) 的三種情形要分得開，因為它們要人做的事不同：沒有共用檔案、
    共用了而區塊不重疊、以及根本量不到。**量不到不得讀成有交集**——判錯成 cluster
    的代價是一顆 PR 只被半審過，判錯成 standalone 的代價只是多花一次 review。
    """
    left_files = hunks_by_file(left)
    right_files = hunks_by_file(right)
    if left_files is None or right_files is None:
        return False, "same_repo_unmeasurable:兩顆之中有一顆量不到改動清單"

    shared = sorted(set(left_files) & set(right_files))
    if not shared:
        return False, "same_repo_no_shared_file:兩顆沒有共用任何一個檔案"

    unmeasurable = []
    for name in shared:
        lh = left_files[name]
        rh = right_files[name]
        if lh is None or rh is None:
            unmeasurable.append(name)
            continue
        if lh == WHOLE_FILE or rh == WHOLE_FILE:
            return True, f"same_repo_overlap:{name}（整個檔案）"
        for l_start, l_end in lh:
            for r_start, r_end in rh:
                if l_start <= r_end and r_start <= l_end:
                    return True, f"same_repo_overlap:{name}@{l_start}-{l_end}"

    if unmeasurable:
        return False, (
            "same_repo_unmeasurable:共用 "
            + ", ".join(unmeasurable)
            + " 而這幾個檔沒有區塊資訊"
        )
    return False, (
        "same_repo_disjoint_hunks:共用 " + ", ".join(shared) + " 而區塊完全不重疊"
    )


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
    return name.startswith("nuxt.config.") or name == "package.json" or is_safe_asset(path)


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
            return "small_fast", "asset/config-only files"

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
        candidate["cluster_reason"] = "standalone:沒有第二顆 PR 共用這個 cluster 鍵" if cluster_key else "standalone:算不出 cluster 鍵"
        enriched.append(candidate)
        if cluster_key:
            cluster_groups.setdefault(cluster_key, []).append(candidate)

    for group in cluster_groups.values():
        if len(group) < 2:
            continue
        group.sort(key=lambda item: (str(item.get("repo") or ""), int(item.get("number") or 0)))
        lead = group[0]

        # 鍵相同不等於同一批改動。**同一個 repo 的兩顆要量得到交集才算 sibling**——
        # 一則 Slack thread 裡放兩張不同單的 PR 是常態，而 sibling 走的是 lead summary
        # 的六條判準，不做完整 review。真跑量到過一次：兩張不同單的 PR 落在同一則
        # thread，同一個 repo、同一個 controller 檔案，而區塊零重疊。
        #
        # **跨 repo 的兩顆不套這條**，因為那裡量不到交集，而「同一件事在三個 repo 各開
        # 一顆」正是 sister PR 這個功能要服務的形狀。這一格是刻意放行的，理由字串說得出來。
        kept = [lead]
        for item in group[1:]:
            if str(item.get("repo") or "") != str(lead.get("repo") or ""):
                item["cluster_reason"] = "cross_repo_key_only:跨 repo，改動交集量不到，鍵相同即成立"
                kept.append(item)
                continue
            overlaps, reason = shared_change(lead, item)
            item["cluster_reason"] = reason
            if overlaps:
                kept.append(item)

        if len(kept) < 2:
            # 只剩 lead 自己：這一組不是 cluster。**lead 的理由要覆寫**——它進來時帶著
            # 「沒有第二顆 PR 共用這個 cluster 鍵」那句預設，而那句在這裡是假的：有第二顆，
            # 只是它量不到交集。寫成 `or` 的那一版永遠不會覆寫，因為預設值恆為真值。
            lead["cluster_reason"] = (
                f"demoted:鍵相同的有 {len(group)} 顆，沒有一顆量得到與這一顆的改動交集"
            )
            continue

        lead["cluster_reason"] = "cluster_lead:這一組的 lead"
        for item in kept:
            item["cluster_size"] = len(kept)
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
