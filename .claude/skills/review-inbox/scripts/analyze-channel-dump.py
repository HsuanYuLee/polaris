#!/usr/bin/env python3
"""channel dump 讀完了沒、而且只有這一趟嗎。

三個問題：時間窗翻到底了嗎、窗內有新回覆的 thread 讀進來了嗎、這份 dump 裡的 thread
區段是不是全都屬於這一趟。

存在的理由：這兩件事以前寫在 review-inbox-discovery-flow.md 的散文裡，由 discovery
sub-agent 執行。2026-09-04 兩輪各驗了一次，兩輪都沒有執行：dump 停在 66 則（MCP 明確
回了 cursor）、而團隊的「我改好了，再看一次」幾乎全在 thread 回覆裡。**兩輪的產出都是
POLARIS_DISCOVERY_OK**——一份不完整的資料跟一份完整的資料，在原本那四個狀態底下長得
一模一樣。

判準都從 dump 自己讀得出來，不需要再打一次 Slack：
  - 每則有回覆的訊息底下有一行 `Thread: N replies (latest: YYYY-MM-DD HH:MM:SS CST)`；
  - `extract-pr-urls.py --emit-normalized` 會把 payload 的 cursor 寫成一行
    `Pagination cursor: <值>`（讀完了寫 `(none)`）；
  - 讀進來的 thread 由 `=== Thread replies for TS <parent> ===` 這一行證明；同一行也
    說得出它屬不屬於這一趟——這一趟該讀的 thread 只有一個來源，就是這份 dump 裡那幾則
    「帶 `Thread:` 行、最新回覆落在窗內」的訊息（DP-710）。

「讀完了」與「只有這一趟」是兩個方向相反的問題，少了後面那個，多接進來的東西一律安靜：
session 的 scratchpad 跨天重用時，`threads/*.json` 這種 glob 會把上一輪的 payload 一起接
上去。2026-09-14 量到的：正確的 dump 100 顆候選，接上 47 個舊 payload 之後 108 顆，多出來
的 8 顆全是舊窗的 PR——而兩種情況這裡都回 `POLARIS_DISCOVERY_WINDOW_COVERED`。多看幾顆
沒有人會抱怨，所以這個誤差方向永遠不會有人來報。

時區不寫死：訊息抬頭的牆上時間與同一則的 `Message TS` 一起出現，兩者相減就是這個
workspace 的偏移量。寫死 +8 的話，換一個 workspace 就會安靜地把窗算錯。

用法：analyze-channel-dump.py --dump <file> --window-seconds N [--now-epoch E]
離場：0＝讀完了而且只有這一趟、2＝沒讀完或混進了別趟的東西（逐條指名）、
      3＝量不到（dump 裡沒有可校準的訊息）
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



# 一個回合發幾條。**這個數字在這裡，不在散文裡**——散文說了不算，讀指示的那一端照著它做。
#
# 挑 10 的理由是往返成本：2026-09-16 實測一趟 discovery 59 分 30 秒，其中 52 分鐘（88%）
# 花在逐條讀 43 條 thread——每條 72 秒，而那 72 秒幾乎都是往返，不是 Slack 回應本身。
# 43 條照這個上限是 5 批，不是 43 個回合。
THREAD_READ_BATCH_SIZE = 10


def unread_batch_instructions(keys):
    """把該讀的那幾條切成批，每一批講成「一個回合做完」的一組動作。

    以前這裡印的是「對每一條跑 slack_read_thread」——而讀指示的那一端照著做，就是 N 個
    回合。切批之後回合數是 N 除以上限無條件進位：N 變大數倍，回合只多一個。

    **切批不改「哪幾條該讀」**。傳進來的就是涵蓋判定算出來的那一組，這裡一條都不丟——
    少讀幾條換到的時間，買的是一份不完整的 dump，而它跟完整的那一份長得一樣。
    """
    lines = []
    total = len(keys)
    batches = [
        keys[i : i + THREAD_READ_BATCH_SIZE]
        for i in range(0, total, THREAD_READ_BATCH_SIZE)
    ]
    lines.append(
        f"  修法：分成 {len(batches)} 批讀完（一批 {THREAD_READ_BATCH_SIZE} 條）。"
        f"**每一批的 slack_read_thread 在同一個回合裡一起發出去**，不要一條一條輪流："
    )
    for index, batch in enumerate(batches, start=1):
        lines.append(f"  ── 第 {index}／{len(batches)} 批（{len(batch)} 條）")
        lines.append("     這一批一起發：" + " ".join(batch))
        lines.append(
            "     每一條的回應各存成 threads/<TS>.json，然後這一批用一條命令接進 dump："
        )
        lines.append(
            "       for ts in " + " ".join(batch) + "; do \\"
        )
        lines.append(
            "         python3 extract-pr-urls.py --org <org> "
            "--emit-normalized-thread \"$ts\" < threads/\"$ts\".json >> <dump>; \\"
        )
        lines.append("       done")
    lines.append(
        "  上面那個迴圈明列這一趟的那幾個 TS，**不要換成 threads/*.json**："
        "scratchpad 跨天重用，萬用字元會把上一輪的 payload 一起接回來。"
    )
    return lines


def parse(lines):
    """Walk the dump once, collecting everything the three checks need.

    `in_section` 分開兩種訊息：channel 那一頁的 top-level，以及 thread 區段裡的。少了這一格
    就分不開，而它們**會撞在同一個 ts 上**——`slack_read_thread` 的第一則就是 parent 自己，
    區段裡因此有一份它的影子，那一份沒有 `Thread:` 行（DP-712）。
    """
    messages = []      # {ts, wall, thread: (count, latest_wall) | None, in_section: bool}
    read_sections = set()
    cursors = []
    current = None
    pending_wall = None
    in_section = False

    for line in lines:
        section = SECTION_RE.match(line)
        if section:
            read_sections.add(section.group(1))
            current = None
            in_section = True
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
                       "thread": None, "in_section": in_section}
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

    # channel 那一頁的 top-level。三條判定裡有兩條問的是它，不是「dump 裡所有的訊息」
    # ——thread 區段裡的回覆不屬於這一頁，拿它們回答「這一頁翻到哪」會答錯（DP-712）。
    page = [m for m in messages if not m["in_section"]]
    if not page:
        print("POLARIS_DISCOVERY_DUMP_UNMEASURABLE")
        print("這份 dump 只有 thread 區段，沒有 channel 那一頁的訊息，涵蓋範圍算不出來")
        return 3

    problems = []

    # --- 沒讀到的 thread -----------------------------------------------------------
    unread = []
    for message in page:
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
        problems.extend(unread_batch_instructions([key for key, _, _ in unread]))

    # --- 不屬於這一趟的 thread 區段 (DP-710) --------------------------------------
    # 判準是那一段的 parent，不是那一段裡面那幾則回覆的時間：讀一條 thread 本來就會帶回
    # 它全部的回覆，而長壽 thread 是這個團隊的常態（那條公告 thread 的根落在窗外 14 天）。
    # parent 只從這一頁的 top-level 找。區段裡那一份 parent 的影子沒有 `Thread:` 行，
    # 用它來判的話每一段都會被判成外來——DP-712 之前就是這樣，work-30 一趟 52 段全紅。
    by_ts = {message["ts"]: message for message in page}
    foreign = []
    for raw in sorted(read_sections):
        parent = by_ts.get(float(raw))
        if parent is None:
            foreign.append((raw, "這份 dump 裡沒有這則 top-level 訊息"))
            continue
        if not parent["thread"]:
            foreign.append((raw, "這則訊息身上沒有 `Thread:` 那一行，它沒有回覆"))
            continue
        latest_epoch = naive_epoch(parent["thread"][1]) + offset
        if latest_epoch < window_start:
            foreign.append(
                (raw, f"這條 thread 的最新回覆是 {parent['thread'][1]} CST，落在窗外")
            )

    if foreign:
        problems.append("POLARIS_DISCOVERY_NOT_ONLY_THIS_RUN")
        problems.append(
            f"{len(foreign)} 段 thread 回覆不屬於這一趟。這一趟該讀的 thread 只有一個來源"
            "——這份 dump 裡那幾則帶 `Thread:` 行、最新回覆落在窗內的訊息："
        )
        for raw, why in foreign:
            problems.append(f"  Thread replies for TS {raw}：{why}")
        problems.append(
            "  修法：把不屬於這一趟的那幾段從 dump 裡拿掉。"
            "接 dump 的時候明列這一趟的 TS，不要用 `threads/*.json` 這種 glob"
            "——跨天重用的 scratchpad 裡躺著上一輪的 payload。"
        )
        problems.append(
            "  那一條真的要讀的話，先把 channel 那一頁翻到涵蓋它的 top-level 訊息，"
            "它才有辦法被算成這一趟的一部分。"
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
        oldest = min(m["ts"] for m in page)
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

    oldest = min(m["ts"] for m in page)
    print("POLARIS_DISCOVERY_WINDOW_COVERED")
    print(
        f"涵蓋範圍夠了：這一頁 {len(page)} 則訊息、最舊 {oldest:.0f}"
        f"（窗起點 {window_start}）、"
        f"窗內有新回覆的 thread {len(read_sections)} 條都讀過了，"
        f"而且沒有不屬於這一趟的 thread 區段"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
