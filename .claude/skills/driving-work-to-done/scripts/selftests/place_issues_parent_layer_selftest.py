#!/usr/bin/env python3
"""母單層的九條斷言，一條一條量。見同名 .sh 的檔頭。"""

import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib", "place_issues_by_state.py")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 假的單樹：一個命名空間、一個注入進去的解析器。真的解析器要連外部系統，而這九條斷言
# 問的是核心怎麼擺，不是外部系統怎麼答。
FAKE = {
    # 單號:        (格,            母單,    母單標題)
    "AA-1":        ("in-progress", None,    None),      # 自己是母單，也是一張單
    "AA-2":        ("in-progress", "AA-1",  "母單一號"),  # 跟母單同格
    "AA-3":        ("backlog",     "AA-1",  "母單一號"),  # 跟母單不同格
    "AA-4":        ("done",        "ZZ-9",  "沒人認領的母單"),  # 母單自己不在樹裡
    "AA-5":        ("backlog",     None,    None),      # 沒有母單
    "AA-6":        ("released",    "AA-1",  "母單一號"),  # 日期層＋母單層
    "AA-7":        ("triage",      None,    None),      # 問不到的
}
RELEASED_ON = "2026-01-02"


def fake_resolver(command, ticket_name):
    """注入用。回傳與 `slot_from_resolver` 同形狀的三元組。"""
    row = FAKE.get(ticket_name)
    if row is None:
        return placer.TRIAGE, "resolver-unreachable", {"why": "這次沒問到"}
    slot, parent, title = row
    detail = {"mine": True}
    if parent:
        detail["parent"] = parent
        detail["parent_title"] = title
    if slot == placer.RELEASED:
        detail["released_on"] = RELEASED_ON
    return slot, "resolver", detail


def build_tree(root, with_parents):
    """把每一張單都放在它自己的格底下、不分母單層——重算要從這裡開始。"""
    for name, (slot, _, _) in FAKE.items():
        parts = [root, "ns", slot]
        if slot == placer.RELEASED:
            parts.append(RELEASED_ON)
        parts.append(name)
        path = os.path.join(*parts)
        os.makedirs(os.path.join(path, ".spine"), exist_ok=True)
        with open(os.path.join(path, "index.md"), "w", encoding="utf-8") as handle:
            handle.write(f"# {name}\n")


def run(root):
    placer._RESOLVER_CACHE.clear()
    placer._TOUCHED_CACHE.clear()
    original = placer.slot_from_resolver
    placer.slot_from_resolver = fake_resolver
    try:
        rows, abstained = placer.survey(root, resolvers={"ns": "fake"})
        for row in rows:
            if row["from_dir"] != row["to_dir"]:
                placer.move(row["from_dir"], row["to_dir"])
            # 推導結果要寫回單身上——A-N3 問的正是「格從那一份讀得到」，所以這裡跟
            # 真的重算一樣寫，不只搬。
            placer.write_placement(row["to_dir"], row["slot"], row["basis"],
                                   row["detail"])
        placer.prune_empty(root)
        placer._RESOLVER_CACHE.clear()
        placer._TOUCHED_CACHE.clear()
        after, _ = placer.survey(root, resolvers={"ns": "fake"})
    finally:
        placer.slot_from_resolver = original
    return rows, after, abstained


def rel(root, row):
    return row["current"].replace(os.sep, "/")


def main() -> int:
    root = tempfile.mkdtemp(prefix="parent-layer-")
    try:
        build_tree(root, True)
        before, after, abstained = run(root)
        where = {r["name"]: rel(root, r) for r in after}
        verdicts = []

        def check(ident, ok, note):
            verdicts.append((ident, ok, note))

        # A-P1 歸屬在路徑上：不開檔案就讀得出它屬於誰。
        check("A-P1", where.get("AA-2") == "ns/in-progress/_AA-1-母單一號/AA-2",
              f"AA-2 → {where.get('AA-2')}")
        # A-P2 母單自己不在樹裡，那一層照樣長出來。
        check("A-P2", where.get("AA-4") == "ns/done/_ZZ-9-沒人認領的母單/AA-4",
              f"AA-4（母單 ZZ-9 不在樹裡）→ {where.get('AA-4')}")
        # A-P3 分層不改任何一張單的格：母單在 in-progress，子單留在 backlog。
        check("A-P3",
              where.get("AA-1") == "ns/in-progress/AA-1"
              and where.get("AA-3") == "ns/backlog/_AA-1-母單一號/AA-3",
              f"AA-1 → {where.get('AA-1')}；AA-3 → {where.get('AA-3')}")
        # A-P4 一張單同時是母單也是子單時兩件事都成立。
        check("A-P4",
              where.get("AA-1") == "ns/in-progress/AA-1"
              and where.get("AA-2", "").startswith("ns/in-progress/_AA-1-"),
              f"AA-1 有自己的格且底下掛著 AA-2：{where.get('AA-1')} / {where.get('AA-2')}")
        # A-P5 問不到母單的照樣被放好，不落 triage 也不停掉。
        check("A-P5", where.get("AA-5") == "ns/backlog/AA-5",
              f"AA-5（解析器沒回母單）→ {where.get('AA-5')}")
        # A-N1 沒有一張單因為多一層而從判定裡消失。
        #
        # **數量相等不算數。** 母單層自己也是一個目錄——一個把它誤判成單的實作，數出來的
        # 總數可以剛好不變（實測：把子單整批弄丟的那個注入，總數仍然是 7）。所以這裡比的
        # 是名字的集合，不是長度。
        names_before = {r["name"] for r in before}
        names_after = {r["name"] for r in after}
        expected = set(FAKE)
        check("A-N1", names_before == expected and names_after == expected,
              f"重算前 {sorted(names_before)}、重算後 {sorted(names_after)}，"
              f"樹裡共 {sorted(expected)}")
        # A-N2 沒有母單的單不多一層。
        check("A-N2",
              where.get("AA-5") == "ns/backlog/AA-5"
              and where.get("AA-7") == "ns/triage/AA-7",
              f"AA-5 → {where.get('AA-5')}；AA-7 → {where.get('AA-7')}")
        # A-N3 母單層不是第二個狀態權威：格仍然只從 placement.json 讀得到。
        recorded = placer.read_json(os.path.join(
            root, "ns", "backlog", "_AA-1-母單一號", "AA-3", ".spine", "placement.json"))
        check("A-N3", (recorded or {}).get("slot") == "backlog",
              f"AA-3 的 placement.json 記的格是 {(recorded or {}).get('slot')}"
              "（路徑上的母單層不參與這個答案）")
        # A-N4 既有的日期層不受影響。
        check("A-N4", where.get("AA-6") == f"ns/released/{RELEASED_ON}/_AA-1-母單一號/AA-6",
              f"AA-6 → {where.get('AA-6')}")

        failed = 0
        for ident, ok, note in verdicts:
            print(f"{ident} {'PASS' if ok else 'FAIL'} — {note}")
            failed += 0 if ok else 1
        print(f"PARENT-LAYER-SELFTEST {len(verdicts) - failed}/{len(verdicts)} 條過")
        return 1 if failed else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
