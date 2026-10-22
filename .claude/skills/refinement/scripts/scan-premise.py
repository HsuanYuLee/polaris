#!/usr/bin/env python3
"""scan-premise.py — 一個前提要改的時候，列出哪幾張單的哪幾條建立在它上面。

為什麼是一支腳本：一條前提被推翻時，依賴它的 `assumes_*` 與凍結塊條目散在好幾張單裡，
而它們不會自己失效。2026-10-22 的標本：一個狀態詞的定義要改，兩張子單都有條目建立在
它上面，那一刻沒有人列得出來。

它只列，不判：哪一條真的要重簽，是讀的人的事。沒命中就說沒命中。

掃的範圍：單的根目錄底下每一張單（帶 `.spine/` 的目錄）的 `index.md`：
  - frontmatter 裡每一個 `assumes_*` 區塊的 `claim` 與 `observed`；
  - 每一組凍結塊（`<!-- POLARIS-FROZEN-X-BEGIN -->`…`END`）裡的每一行。
格子讀 `.spine/placement.json` 的 `slot`。

Usage:
  scan-premise.py --issues <單的根目錄> <關鍵字> [<關鍵字> ...]
"""
import argparse
import json
import os
import re
import sys

FENCE_BEGIN = re.compile(r"<!--\s*POLARIS-FROZEN-([A-Za-z0-9]+)-BEGIN\s*-->")
FENCE_END = re.compile(r"<!--\s*POLARIS-FROZEN-([A-Za-z0-9]+)-END\s*-->")
ASSUMES = re.compile(r"^\s+(assumes_[A-Za-z0-9_]+):\s*$")
ASSUMES_FIELD = re.compile(r"^\s+(claim|observed):")
ITEM = re.compile(r"\*\*([A-Z]+-[A-Z]*\d+)")


def slot_of(issue):
    try:
        with open(os.path.join(issue, ".spine", "placement.json"), encoding="utf-8") as fh:
            return json.load(fh).get("slot") or "（placement 沒有 slot）"
    except (OSError, ValueError):
        return "（沒有 placement）"


def hits_in(path, keywords):
    """回傳 [(條目名, 行號, 那一行)]。"""
    try:
        with open(path, encoding="utf-8") as fh:
            rows = fh.read().splitlines()
    except OSError:
        return []
    out, in_front, assumes, fence = [], False, None, None
    for no, row in enumerate(rows, 1):
        if no == 1 and row.strip() == "---":
            in_front = True
            continue
        if in_front:
            if row.strip() == "---":
                in_front, assumes = False, None
                continue
            m = ASSUMES.match(row)
            if m:
                assumes = m.group(1)
            elif assumes and not row.startswith("    ") and row.strip():
                assumes = None
            if assumes and ASSUMES_FIELD.match(row) and any(k in row for k in keywords):
                out.append((assumes, no, row.strip()))
            continue
        b = FENCE_BEGIN.search(row)
        if b:
            fence = b.group(1)
            continue
        if fence and FENCE_END.search(row):
            fence = None
            continue
        if fence and any(k in row for k in keywords):
            m = ITEM.search(row)
            out.append((m.group(1) if m else f"凍結塊 {fence}", no, row.strip()))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--issues", default="issues")
    ap.add_argument("keywords", nargs="+")
    args = ap.parse_args(argv)
    if not os.path.isdir(args.issues):
        print(f"單的根目錄不在：{args.issues}", file=sys.stderr)
        return 2
    found, scanned = [], 0
    for dirpath, dirnames, filenames in os.walk(args.issues):
        dirnames[:] = sorted(d for d in dirnames if d != ".git" and d != ".spine")
        if "index.md" not in filenames or not os.path.isdir(os.path.join(dirpath, ".spine")):
            continue
        scanned += 1
        for item, no, row in hits_in(os.path.join(dirpath, "index.md"), args.keywords):
            found.append((os.path.basename(dirpath), slot_of(dirpath), item,
                          f"{os.path.join(dirpath, 'index.md')}:{no}", row[:200]))
    kw = "、".join(args.keywords)
    if not found:
        print(f"「{kw}」在 {scanned} 張單的 assumes_* 與凍結塊裡都沒有命中。")
        return 0
    print(f"「{kw}」在 {scanned} 張單裡命中 {len(found)} 處（單 ｜ 格 ｜ 條目 ｜ 位置 ｜ 那一行）：")
    for row in found:
        print(" ｜ ".join(row))
    return 0


if __name__ == "__main__":
    sys.exit(main())
