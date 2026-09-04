#!/usr/bin/env python3
"""channel dump 讀完了沒：時間窗翻到底了嗎、窗內有新回覆的 thread 讀進來了嗎。

存在的理由：這兩件事以前寫在 review-inbox-discovery-flow.md 的散文裡，由 discovery
sub-agent 執行。2026-09-04 兩輪各驗了一次，兩輪都沒有執行：dump 停在 66 則（MCP 明確
回了 cursor）、而團隊的「我改好了，再看一次」幾乎全在 thread 回覆裡。**兩輪的產出都是
POLARIS_DISCOVERY_OK**——一份不完整的資料跟一份完整的資料，在原本那四個狀態底下長得
一模一樣。

判準都從 dump 自己讀得出來，不需要再打一次 Slack：
  - 每則有回覆的訊息底下有一行 `Thread: N replies (latest: YYYY-MM-DD HH:MM:SS CST)`；
  - `extract-pr-urls.py --emit-normalized` 會把 payload 的 cursor 寫成一行
    `Pagination cursor: <值>`（讀完了寫 `(none)`）；
  - 讀進來的 thread 由 `=== Thread replies for TS <parent> ===` 這一行證明。

時區不寫死：訊息抬頭的牆上時間與同一則的 `Message TS` 一起出現，兩者相減就是這個
workspace 的偏移量。寫死 +8 的話，換一個 workspace 就會安靜地把窗算錯。

用法：analyze-channel-dump.py --dump <file> --window-seconds N [--now-epoch E]
離場：0＝讀完了、2＝沒讀完（逐條指名）、3＝量不到（dump 裡沒有可校準的訊息）
"""

import argparse
import re
import sys
from datetime import datetime, timezone

HEADER_RE = re.compile(
    r"^=== Message from .+? \(U[A-Z0-9]+\) at "
    r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) CST ===",
)
TS_RE = re.compile(r"^Message TS: (\d+\.\d+)")
THREAD_RE = re.compile(
    r"^Thread: (\d+) repl(?:y|ies) \(latest: "
    r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) CST\)"
)
SECTION_RE = re.compile(r"^=== Thread replies for TS (\d+\.\d+) ===$")
CURSOR_RE = re.compile(r"^Pagination cursor: (.+)$")
NO_CURSOR = "(none)"


def naive_epoch(text):
    """Parse a wall-clock string as if it were UTC; the caller applies the offset."""
    return datetime.strptime(text, "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=timezone.utc
    ).timestamp()


def parse(lines):
    """Walk the dump once, collecting everything the two checks need."""
    messages = []      # {ts, wall, thread_replies: (count, latest_wall) | None}
    read_sections = set()
    cursors = []
    current = None
    pending_wall = None

    for line in lines:
        section = SECTION_RE.match(line)
        if section:
            read_sections.add(section.group(1))
            current = None
            continue
        cursor = CURSOR_RE.match(line)
        if cursor:
            cursors.append(cursor.group(1).strip())
            continue
        header = HEADER_RE.match(line)
        if header:
            pending_wall = header.group(1)
            continue
        ts_line = TS_RE.match(line)
        if ts_line:
            current = {"ts": float(ts_line.group(1)), "wall": pending_wall,
                       "thread": None}
            messages.append(current)
            pending_wall = None
            continue
        thread = THREAD_RE.match(line)
        if thread and current is not None:
            current["thread"] = (int(thread.group(1)), thread.group(2))

    return messages, read_sections, cursors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True)
    parser.add_argument("--window-seconds", type=int, required=True)
    parser.add_argument("--now-epoch", type=int, default=None)
    args = parser.parse_args()

    now = args.now_epoch
    if now is None:
        now = int(datetime.now(timezone.utc).timestamp())
    window_start = now - args.window_seconds

    with open(args.dump, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")

    messages, read_sections, cursors = parse(lines)

    if not messages:
        print("POLARIS_DISCOVERY_DUMP_UNMEASURABLE")
        print("這份 dump 裡一則 `Message TS:` 都沒有，涵蓋範圍算不出來")
        return 3

    # 偏移量從 dump 自己算：同一則訊息的 epoch 與牆上時間相減。取中位數，一則抬頭
    # 解不出來不會把整份帶偏。
    offsets = sorted(
        m["ts"] - naive_epoch(m["wall"]) for m in messages if m["wall"]
    )
    if not offsets:
        print("POLARIS_DISCOVERY_DUMP_UNMEASURABLE")
        print("這份 dump 有 TS 但沒有任何一則帶得出牆上時間，時區偏移量校準不了")
        return 3
    offset = offsets[len(offsets) // 2]

    problems = []

    # --- 沒讀到的 thread -----------------------------------------------------------
    unread = []
    for message in messages:
        if not message["thread"]:
            continue
        count, latest_wall = message["thread"]
        latest_epoch = naive_epoch(latest_wall) + offset
        if latest_epoch < window_start:
            continue
        key = f"{message['ts']:.6f}"
        if key in read_sections:
            continue
        unread.append((key, count, latest_wall))

    if unread:
        problems.append("POLARIS_DISCOVERY_UNREAD_THREADS")
        problems.append(
            f"{len(unread)} 條 thread 的最新回覆落在時間窗內，但它們的回覆沒有被讀進來。"
            "這個團隊的「改好了，再看一次」多半就寫在那裡面："
        )
        for key, count, latest_wall in unread:
            problems.append(f"  Message TS {key}：{count} 則回覆，最新 {latest_wall} CST")
        problems.append(
            "  修法：對每一條跑 slack_read_thread，然後把它接到 dump 後面："
        )
        problems.append(
            "    python3 extract-pr-urls.py --org <org> "
            "--emit-normalized-thread <那個 TS> < <thread payload> >> <dump>"
        )

    # --- 沒翻完的時間窗 -------------------------------------------------------------
    if not cursors:
        problems.append("POLARIS_DISCOVERY_NO_PAGINATION_MARKER")
        problems.append(
            "這份 dump 沒有 `Pagination cursor:` 那一行，所以「還有沒有更舊的」問不到。"
        )
        problems.append(
            "  修法：channel payload 要走 `extract-pr-urls.py --emit-normalized` "
            "產生 dump，那一步才會把 cursor 留下來。"
        )
    elif cursors[-1] != NO_CURSOR:
        oldest = min(m["ts"] for m in messages)
        if oldest > window_start:
            short = int(oldest - window_start)
            problems.append("POLARIS_DISCOVERY_UNPAGED")
            problems.append(
                f"最舊的一則是 {oldest:.0f}，時間窗起點是 {window_start}，還差 {short} 秒"
                "才涵蓋整個窗，而來源說還有更舊的沒取。"
            )
            problems.append(f"  修法：帶 cursor `{cursors[-1]}` 再讀一頁，接到 dump 後面。")

    if problems:
        for line in problems:
            print(line)
        return 2

    oldest = min(m["ts"] for m in messages)
    print("POLARIS_DISCOVERY_WINDOW_COVERED")
    print(
        f"涵蓋範圍夠了：{len(messages)} 則訊息、最舊 {oldest:.0f}"
        f"（窗起點 {window_start}）、"
        f"窗內有新回覆的 thread {len(read_sections)} 條都讀過了"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
