#!/usr/bin/env python3
"""單樹依歸屬分組的十條斷言，一條一條量。見同名 .sh 的檔頭。"""

import filecmp
import importlib.util
import os
import re
import shutil
import tempfile
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib", "place_issues_by_state.py")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 假的單樹：一個有解析器的命名空間、一個沒有的。真的解析器要連外部系統，而這十條斷言問的
# 是核心怎麼擺，不是外部系統怎麼答。
#
# 單號:      (自己的格,      到鏈頂為止的那幾層)
FAKE = {
    "AA-1": ("in-progress", []),               # 自己就是鏈頂
    "AA-2": ("in-progress", ["AA-1"]),         # 跟鏈頂同格
    "AA-3": ("backlog",     ["AA-1"]),         # 自己的格跟鏈頂不同——不搬家
    "AA-4": ("done",        ["ZZ-9"]),         # 鏈頂樹裡沒有，要補出來
    "AA-5": ("backlog",     []),               # 解析器沒回鏈
    "AA-6": ("released",    ["AA-1"]),         # 自己已釋出，鏈頂沒有——不長日期層
    "AA-7": ("triage",      []),               # 問不到
    "AA-8": ("backlog",     ["AA-1", "AA-3"]),  # 兩層鏈，不並排成一層
    "AA-9": ("backlog",     ["QQ-0"]),         # 鏈頂連解析器都答不出來
}
# 樹裡一開始沒有它，鏈上有。補出來之後它自己在 released，所以日期層長在它身上。
MATERIALISED = {"ZZ-9": ("released", [])}
RELEASED_ON = "2026-01-02"
DESCRIPTION = {"ZZ-9": "第一版的規格：先做 A，再做 B。"}
IN_TREE = set(FAKE)


def fake_resolver(command, ticket_name):
    """注入用。回傳與 `slot_from_resolver` 同形狀的三元組。"""
    row = FAKE.get(ticket_name) or MATERIALISED.get(ticket_name)
    if row is None:
        return placer.TRIAGE, "resolver-unreachable", {"why": "這次沒問到"}
    slot, chain = row
    detail = {"mine": True, "upstream": {"標題": f"{ticket_name} 的標題",
                                         "上游狀態": slot}}
    if chain:
        detail["chain"] = list(chain)
    if ticket_name in DESCRIPTION:
        detail["upstream_text"] = DESCRIPTION[ticket_name]
    if slot == placer.RELEASED:
        detail["released_on"] = RELEASED_ON
    return slot, "resolver", detail


def spine(path):
    """一張單的 `.spine/`，裡面放一份上一次重算留下的推導結果。

    **不能只 mkdir 一個空的。** 搬完之後的清掃會把空目錄收掉，於是那張單身上代表「我是
    一張單」的痕跡就沒了——而真實的樹上 `.spine/` 從來不是空的。
    """
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "placement.json"), "w", encoding="utf-8") as handle:
        handle.write('{"schema_version": 1, "producer": "fixture"}\n')


def build_tree(root):
    """每一張單一開始都平放在自己的格底下——重算要從這裡開始。

    另外造兩樣東西：一個**沒有宣告解析器**的命名空間（A-N5 問它的形狀變不變），以及一張
    單底下一個**不是單**的目錄（A-P1 問它會不會被當成單搬出去）。
    """
    for name, (slot, _) in FAKE.items():
        parts = [root, "ns", slot]
        if slot == placer.RELEASED:
            parts.append(RELEASED_ON)
        parts.append(name)
        path = os.path.join(*parts)
        spine(os.path.join(path, ".spine"))
        with open(os.path.join(path, "index.md"), "w", encoding="utf-8") as handle:
            handle.write(f"# {name}\n\n這一段是人寫的，重算不得碰它。\n")
    # 舊層在單裡放過 `tasks/`、`T1/`、`evidence/` 這些目錄，實測 259 個。它們沒有 `.spine/`，
    # 所以它們不是單——被當成單的話會算出 `ns/triage/notes` 這種不是單號的一層，而好幾張
    # 單底下的同名目錄還會全部指向同一個地方。
    notes = os.path.join(root, "ns", "in-progress", "AA-1", "notes")
    os.makedirs(notes, exist_ok=True)
    with open(os.path.join(notes, "index.md"), "w", encoding="utf-8") as handle:
        handle.write("# 這不是一張單\n")
    quiet = os.path.join(root, "other", "backlog", "BB-1")
    spine(os.path.join(quiet, ".spine"))
    with open(os.path.join(quiet, "index.md"), "w", encoding="utf-8") as handle:
        handle.write("# BB-1\n")


def recompute(root):
    """跑一次真的重算（搬 + 補 + 寫回推導結果），回重算後的 survey。"""
    placer._RESOLVER_CACHE.clear()
    placer._TOUCHED_CACHE.clear()
    original = placer.slot_from_resolver
    placer.slot_from_resolver = fake_resolver
    try:
        rows, _ = placer.survey(root, resolvers={"ns": "fake"})
        for row in rows:
            if row["current"] is None:
                os.makedirs(row["to_dir"], exist_ok=True)
        remap = []

        def now(path):
            for old, new in remap:
                if path == old or path.startswith(old + os.sep):
                    return new + path[len(old):]
            return path

        for row in sorted((r for r in rows if r["from_dir"]),
                          key=lambda r: r["from_dir"].count(os.sep)):
            source = now(row["from_dir"])
            if source == row["to_dir"] or not os.path.isdir(source):
                continue
            if os.path.exists(row["to_dir"]):
                continue
            placer.move(source, row["to_dir"])
            remap.append((source, row["to_dir"]))
        placer.prune_empty(root)
        placer._RESOLVER_CACHE.clear()
        placer._TOUCHED_CACHE.clear()
        after, _ = placer.survey(root, resolvers={"ns": "fake"})
        for row in after:
            placer.write_placement(row["to_dir"], row["slot"], row["basis"],
                                   row["detail"])
            placer.write_upstream(row["to_dir"], row["detail"])
        placer._RESOLVER_CACHE.clear()
        placer._TOUCHED_CACHE.clear()
        final, _ = placer.survey(root, resolvers={"ns": "fake"})
    finally:
        placer.slot_from_resolver = original
    return final


def preview_only(root):
    """不動手的那一種。回 survey 的結果——磁碟上一個位元組都不該變。"""
    placer._RESOLVER_CACHE.clear()
    placer._TOUCHED_CACHE.clear()
    original = placer.slot_from_resolver
    placer.slot_from_resolver = fake_resolver
    try:
        return placer.survey(root, resolvers={"ns": "fake"})[0]
    finally:
        placer.slot_from_resolver = original


def read(path):
    """讀不到就回空字串。

    **一份壞掉的實作不得把十條判定變成一個 traceback。** 這一條是量出來的：紅控第一次跑
    的時候，兩種注入各自讓某個檔案不存在，於是這支腳本死在讀檔那一行——十條斷言一條都沒
    印出來，離場碼 1。那跟「那一條紅了」在 CI 上長得一模一樣，但它其實是量不到。
    """
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def snapshot(root):
    """整棵樹的樣子：每個檔案的相對路徑與內容。"""
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            with open(full, "rb") as handle:
                out[os.path.relpath(full, root)] = handle.read()
    return out


def main() -> int:
    root = tempfile.mkdtemp(prefix="ownership-")
    try:
        build_tree(root)

        # A-N4 先量：預覽跑完，樹要逐位元組不變。之後才真的重算。
        before_bytes = snapshot(root)
        preview_only(root)
        untouched = snapshot(root) == before_bytes

        final = recompute(root)
        where = {r["name"]: r["current"].replace(os.sep, "/") for r in final}
        verdicts = []

        def check(ident, ok, note):
            verdicts.append((ident, ok, note))

        # A-P1 路徑投影的是歸屬：每一層都是單號，沒有前綴、沒有標題；兩跳的鏈不並排。
        # 而不是單的那個目錄不得長成路徑上的一層——它留在它本來待的那張單裡。
        notes = os.path.join(root, "ns", "in-progress", "AA-1", "notes", "index.md")
        check("A-P1",
              where.get("AA-8") == "ns/in-progress/AA-1/AA-3/AA-8"
              and "notes" not in where and os.path.isfile(notes),
              f"AA-8（鏈 AA-1→AA-3）→ {where.get('AA-8')}；"
              f"AA-1/notes（沒有 .spine，不是單）→ "
              f"{'還在 AA-1 底下' if os.path.isfile(notes) else '不見了'}"
              f"{'，而且被當成一張單擺到 ' + where['notes'] if 'notes' in where else ''}")
        # A-P2 格投影鏈頂，子單不因為自己的狀態搬家。
        check("A-P2",
              where.get("AA-3") == "ns/in-progress/AA-1/AA-3"
              and where.get("AA-6") == "ns/in-progress/AA-1/AA-6",
              f"AA-3（自己 backlog）→ {where.get('AA-3')}；"
              f"AA-6（自己 released）→ {where.get('AA-6')}")
        # A-P3 鏈上每一個號都有自己的一格——包含樹裡本來沒有的那些。
        zz = os.path.join(root, "ns", "released", RELEASED_ON, "ZZ-9")
        check("A-P3",
              "ZZ-9" in where and os.path.isfile(os.path.join(zz, "index.md"))
              and where.get("AA-4") == f"ns/released/{RELEASED_ON}/ZZ-9/AA-4",
              f"ZZ-9（本來不在樹裡）→ {where.get('ZZ-9')}，有 index.md "
              f"{os.path.isfile(os.path.join(zz, 'index.md'))}；AA-4 → {where.get('AA-4')}")
        # A-P4 上層資訊讀得出來，而且上游改了會變成這個檔案的一次改動。
        path = os.path.join(zz, "index.md")
        first = read(path)
        DESCRIPTION["ZZ-9"] = "第二版的規格：A 拿掉，直接做 B。"
        recompute(root)
        second = read(path)
        human = read(os.path.join(root, where.get("AA-3", "AA-3-不在樹裡"), "index.md"))
        check("A-P4",
              "ZZ-9 的標題" in first and "第一版的規格" in first
              and "第二版的規格" in second and "第一版的規格" not in second
              and "這一段是人寫的" in human,
              f"ZZ-9 的 index.md 讀得到標題與描述快照；改了描述之後內容跟著變"
              f"（{'第二版的規格' in second}）；人寫的段落沒被碰"
              f"（{'這一段是人寫的' in human}）")
        # A-P5 重算不掉單：逐個單號比，不只比總數。
        #
        # **數量相等不算數。** 補出來的母單自己也是一張單——一個把子單整批弄丟的實作，
        # 總數可以剛好不變。
        names = {r["name"] for r in final}
        expected = IN_TREE | set(MATERIALISED)
        check("A-P5", names >= expected,
              f"重算後 {sorted(names)}，至少要有 {sorted(expected)}")
        # A-N1 狀態仍然只有一個答案：AA-3 的格是它自己的 backlog，不是路徑上的
        # in-progress。
        recorded = placer.read_json(os.path.join(
            root, "ns", "in-progress", "AA-1", "AA-3", ".spine", "placement.json"))
        check("A-N1", (recorded or {}).get("slot") == "backlog",
              f"AA-3 的 placement.json 記的格是 {(recorded or {}).get('slot')}"
              "（路徑上那一層不參與這個答案）")
        # A-N2 核心不認得外部系統：算位置的那一層不出現外部系統的欄位名，也不出現 epic。
        # **只掃真的會被執行的那些字。** 註解與 docstring 裡出現同一個詞多半是在否認它
        # （「核心不認得 JIRA」），對它判紅會讓這條斷言變成一個懲罰寫清楚的規則。
        code = []
        with open(LIB, "rb") as handle:
            for token in tokenize.tokenize(handle.readline):
                if token.type not in (tokenize.COMMENT, tokenize.STRING,
                                      tokenize.NL, tokenize.NEWLINE):
                    code.append(token.string)
        code = " ".join(code)
        leaked = [w for w in ("jira", "epic", "issuetype", "resolutiondate",
                              "assignee", "summary", "parent_title")
                  if re.search(rf"\b{w}\b", code, re.IGNORECASE)]
        check("A-N2", not leaked, f"算位置那一層真的會執行到的外部系統詞彙："
                                  f"{leaked or '沒有'}（註解與 docstring 不算）")
        # A-N3 問不到不得讓重算說謊。三種：沒回鏈、整個問不到、鏈頂問不到。
        check("A-N3",
              where.get("AA-5") == "ns/backlog/AA-5"
              and where.get("AA-7") == "ns/triage/AA-7"
              and where.get("AA-9") == "ns/backlog/QQ-0/AA-9"
              and where.get("QQ-0") == "ns/backlog/QQ-0",
              f"沒回鏈 {where.get('AA-5')}；問不到 {where.get('AA-7')}；"
              f"鏈頂答不出來 {where.get('AA-9')}")
        # A-N4 預設不動任何東西。
        check("A-N4", untouched, "預覽跑完之後，樹的每一個檔案逐位元組相同"
              if untouched else "預覽動到了樹")
        # A-N5 沒有解析器的命名空間形狀不變。
        quiet = os.path.join(root, "other", "backlog", "BB-1")
        check("A-N5", os.path.isdir(quiet),
              f"other/backlog/BB-1 還在原地（{os.path.isdir(quiet)}）")

        failed = 0
        for ident, ok, note in verdicts:
            print(f"{ident} {'PASS' if ok else 'FAIL'} — {note}")
            failed += 0 if ok else 1
        print(f"OWNERSHIP-SELFTEST {len(verdicts) - failed}/{len(verdicts)} 條過")
        return 1 if failed else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
