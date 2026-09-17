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
    parser.add_argument(
        "--open-prs",
        default="",
        help="Optional JSON: per-repo open PR heads and default branch, from scan-unreviewed-prs.sh --open-prs-out.",
    )
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


def load_open_prs(path: str) -> dict:
    """該 repo **全部** open PR 的 head 表，加上它的預設分支。

    **候選集決定誰被派，不決定誰算 parent。** 這兩件事以前是同一份表，於是一顆 PR 疊在
    一顆「我投過票、head 沒動」的 open PR 上的時候，判定說它沒有疊在任何人身上——而那句話
    的主詞是錯的：它問的是候選集，講出來的是全世界。2026-09-17 一輪裡三個實例，其中一個
    打到 9 層 stack 的 lead（#3222 疊在 draft 的 #3133 上）。

    **所以這份表要取濾網之前那一份。** 產它的第三腿有三道濾網（draft、作者、更新窗），
    而 parent 正是那三道各濾掉一種：#3224／#3229 是「我投過票」、#3133 是 draft。
    """
    if not path:
        return {}
    open_prs_path = Path(path)
    if not open_prs_path.exists():
        return {}
    with open_prs_path.open() as handle:
        data = json.load(handle)
    return data if isinstance(data, dict) else {}


def owner_repo_number(candidate: dict) -> tuple[str | None, str | None, int | None]:
    url = str(candidate.get("url") or "")
    match = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", url)
    if not match:
        return None, candidate.get("repo"), candidate.get("number")
    return match.group(1), match.group(2), int(match.group(3))


def fetch_default_branch(candidate: dict, offline: bool, cache: dict) -> str:
    """這個 repo 的預設分支。**別寫死成 master 或 main**——真跑那個 repo 是 `develop`。

    它跟 open PR 的 head 表是**兩件事**，所以分開問：base 是預設分支的時候，「它不是任何
    PR 的 head」不需要任何表就成立。少了這一分，沒帶 `--open-prs` 的那幾輪會把每一顆正常
    PR 都判成問不到——而 cluster 這個功能等於關掉，跨 repo 的 sister PR 首當其衝。

    一個 repo 只問一次（cache 的鍵是 owner/repo）。`--offline` 底下不問，答不出來就是
    答不出來。
    """
    owner, repo, _ = owner_repo_number(candidate)
    if not owner or not repo:
        return ""
    key = f"{owner}/{repo}"
    if key in cache:
        return cache[key]
    if offline:
        cache[key] = ""
        return ""
    try:
        branch = subprocess.check_output(
            ["gh", "api", f"repos/{owner}/{repo}", "--jq", ".default_branch"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        branch = ""
    cache[key] = branch
    return branch


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
                (
                    "{changed_files: .changed_files, additions: .additions, "
                    "deletions: .deletions, base_ref: .base.ref, head_ref: .head.ref}"
                ),
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


def link_stacked_edges(
    candidates: list[dict], open_prs: dict | None = None, default_branches: dict | None = None
) -> None:
    """誰站在誰身上。**這一問不需要兩顆屬於同一組，也不需要 parent 在這一輪。**

    cluster 那一層問的是「這幾顆是不是同一批改動」，所以它以成組為前提；而三顆不同單、
    落在不同 Slack thread 的 PR 鍵不同，從頭就沒有進同一組。它們之間仍然有一條真的關係：
    **這一顆的 base 是另一顆 open PR 的 head。** 那是一條邊，不是一個組。

    邊帶來的不是深度（每一顆都該走完整 review），是兩件便宜的事：底下那顆先派（前提是它
    被派得到），上面那幾顆的 packet 說得出自己站在誰身上。

    **parent 分兩種，而它們給 reviewer 的指示不一樣**：

    - `stacked_on_candidate`：那一顆這一輪也在被 review，結論待會兒出來，可能影響你。
    - `stacked_on_open_pr`：那一顆是 open PR 但不在這一輪。意思是你的 base 裡有一段沒有人
      在看的改動，而它可能還帶著沒解除的 CHANGES_REQUESTED。

    第二種以前判成 `not_stacked`。2026-09-17：#3225 疊在 #3224、#3232 疊在 #3229、#3222
    疊在 #3133，三顆 parent 都 open，都因為不在候選集而看不見，而 #3232 是那條 9 層 stack
    唯一的修正收斂點（44 個檔）。

    **base 是預設分支的時候不需要任何表。** 預設分支不會是誰的 head，所以那一格是量到的
    結論，不是退回來的——少了這一分，沒有 open PR 表的那幾輪會把每一顆正常 PR 都判成
    問不到，而 cluster 這個功能等於關掉。
    """
    open_prs = open_prs or {}
    default_branches = default_branches or {}

    # 候選集自己的 head 也算數：`--open-prs` 沒給的時候它是唯一的表，給了的時候它是
    # 那份表的子集（候選都是 open PR），兩種情形都不衝突。
    heads: dict[tuple, dict] = {}
    for item in candidates:
        repo = str(item.get("repo") or "")
        head = str(item.get("head_ref") or "")
        if repo and head:
            heads[(repo, head)] = item

    for item in candidates:
        item.setdefault("stacked_on", None)
        item.setdefault("stacked_by", [])

    for item in candidates:
        repo = str(item.get("repo") or "")
        base = str(item.get("base_ref") or "")
        if not repo or not base:
            # 問不到這一顆從哪裡長出來的。**不得因此宣稱它沒有疊在別人身上**——
            # 那跟「問到了而且它站在預設分支上」是兩件事。
            item["stacked_reason"] = "unmeasurable:問不到這一顆的 base"
            continue

        repo_info = open_prs.get(repo) or {}
        # 表裡帶的優先（它跟那份 head 表是同一次問到的，所以一定對得起來）；沒有表就用
        # 逐 repo 問到的那一份。
        default_branch = str(repo_info.get("default_branch") or default_branches.get(repo) or "")
        if default_branch and base == default_branch:
            item["stacked_reason"] = (
                f"not_stacked:base 是這個 repo 的預設分支（{default_branch}），"
                "預設分支不會是任何一顆 PR 的 head"
            )
            continue

        parent = heads.get((repo, base))
        if parent is not None and parent is not item:
            item["stacked_on"] = {
                "url": parent.get("url") or "",
                "number": parent.get("number"),
                "branch": base,
                # 讀 packet 的人要知道的不只是「疊在誰身上」，還有「那一顆這一輪有沒有人在看」
                # ——兩種狀態給的指示不一樣，而它們在 stacked_on 裡長得一模一樣。
                "in_this_round": True,
            }
            item["stacked_reason"] = (
                f"stacked_on_candidate:base 是 #{parent.get('number')} 的 head（{base}），"
                "那一顆同一輪也在被 review"
            )
            parent.setdefault("stacked_by", []).append(item.get("number"))
            continue

        repo_heads = repo_info.get("heads") or {}
        outside = repo_heads.get(base) if isinstance(repo_heads, dict) else None
        if isinstance(outside, dict):
            item["stacked_on"] = {
                "url": str(outside.get("url") or ""),
                "number": outside.get("number"),
                "branch": base,
                "in_this_round": False,
            }
            item["stacked_reason"] = (
                f"stacked_on_open_pr:base 是 #{outside.get('number')} 的 head（{base}），"
                "那一顆是 open PR，但這一輪不在 review 範圍內——你的 base 裡有一段沒有人在看的改動"
            )
            continue

        if not repo_info:
            # 一個**出現在表裡、heads 是空的** repo 不算問不到：那句話的意思是「這個 repo
            # 現在沒有任何 open PR 的 head 對得上」。分不開的話，一個真的沒有 stack 的
            # repo 會被整批判成問不到。
            # **問不到不得說成沒有疊。** base 不是預設分支，而手上沒有這個 repo 的 open PR
            # 清單——它疊在誰身上這一輪答不出來。走完整 review，理由說出這是問不到。
            known = f"預設分支是 {default_branch}" if default_branch else "連預設分支是哪一條都問不到"  # noqa: E501
            item["stacked_reason"] = (
                f"unmeasurable:沒有 {repo} 的 open PR 清單（{known}），而 base（{base}）"
                "不是候選集裡任何一顆的 head——分不出它疊在誰身上"
            )
            continue

        item["stacked_reason"] = (
            f"not_stacked:base（{base}）不是這個 repo 任何一顆 open PR 的 head"
        )


def annotate(candidates: list[dict], mapping: dict, offline: bool, open_prs: dict | None = None) -> list[dict]:
    enriched = []
    cluster_groups: dict[str, list[dict]] = {}

    default_branches: dict[str, str] = {}
    branch_cache: dict[str, str] = {}

    for raw in candidates:
        candidate = dict(raw)
        fetch_file_metadata(candidate, offline)
        repo_name = str(candidate.get("repo") or "")
        if repo_name and repo_name not in default_branches:
            branch = fetch_default_branch(candidate, offline, branch_cache)
            if branch:
                default_branches[repo_name] = branch

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

    # **站在誰身上這一問排在分組前面。** 它跨整份候選、而且看得到候選集以外的 open PR，
    # 所以它答得出的東西比分組多；而分組那一層要用它的答案（串行堆疊的第 N 顆不是附屬顆）。
    # 以前這一問在分組之後跑，於是同一件事被問了兩次——組內一次、跨組一次，兩份表各自
    # 只看候選集。合成一份之後，組內那一問直接讀這裡的結論。
    link_stacked_edges(enriched, open_prs, default_branches)

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
            # **同一個 repo 的兩顆，先問它們是不是疊在一起的。** 交集對串行堆疊恆為真，
            # 所以這一問要排在交集前面，不然第 N 顆每次都被判成附屬顆。答案上面已經算好了
            # ——而且它看得到候選集以外的 open PR，所以 parent 不在這一輪的那幾顆也擋得下來。
            parent_ref = item.get("stacked_on")
            if parent_ref:
                item["cluster_reason"] = (
                    f"stacked_on_pr:base 是 #{parent_ref.get('number')} 的 head"
                    f"（{parent_ref.get('branch')}），同一個 repo 串行的第 N 顆，走完整 review"
                )
                continue
            if str(item.get("stacked_reason") or "").startswith("unmeasurable:"):
                # **問不到它疊在誰身上，就不當附屬顆。** 交集對串行堆疊恆為真，所以這裡
                # 判錯的方向是固定的：第 N 顆被 lead 的 summary 半審過去。沒有 open PR 表
                # 的那幾輪要落在這一格，不是落在交集那一格。
                item["cluster_reason"] = (
                    f"same_repo_lineage_unmeasurable:{item.get('stacked_reason')}"
                )
                continue
            if not item.get("base_ref") or not lead.get("base_ref"):
                # 問不到其中一顆從哪裡長出來的，就分不出平行與串行。**量不到不得判成附屬顆**
                # ——判錯成附屬顆的代價是一顆 PR 只被半審過，判成自己一顆只是多花一次 review。
                item["cluster_reason"] = (
                    "same_repo_lineage_unmeasurable:問不到其中一顆的 base，分不出平行與串行"
                )
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
                f"demoted:鍵相同的有 {len(group)} 顆，沒有一顆跟這一顆成立為同一批改動"
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
    open_prs = load_open_prs(args.open_prs)
    json.dump(annotate(candidates, mapping, args.offline, open_prs), sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
