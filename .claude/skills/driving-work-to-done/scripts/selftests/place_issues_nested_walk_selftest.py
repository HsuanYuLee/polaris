#!/usr/bin/env python3
"""埋在「不是單」的目錄底下的單也要被找到——五條 assertion 各量一次。見同名 .sh 的檔頭。"""

import contextlib
import importlib.util
import io
import os
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib", "place_issues_by_state.py")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 單號 → (格子, 鏈)。`MID` 在樹裡只是一個目錄——沒有推導結果、沒有正文，只有一個子單。
# 它是 `move()` 建目的地時順手造出來的那種層，而真樹上有 19 張孫單卡在它後面。
FAKE = {
    "P-1": ("backlog", []),
    "G-1": ("backlog", ["P-1", "MID"]),      # 埋一層：P-1/MID/G-1
    "G-2": ("backlog", ["P-1", "MID", "D2"]),  # 埋兩層：P-1/MID/D2/G-2
    "MID": ("backlog", ["P-1"]),
}
# 樹裡一開始長這樣。BARE 那兩層底下沒有 .spine/、沒有 index.md。
LAYOUT = {
    "P-1": "ns/backlog/P-1",
    "G-1": "ns/backlog/P-1/MID/G-1",
    "G-2": "ns/backlog/P-1/MID/D2/G-2",
}
# 舊層留在單裡的工作目錄。它有正文、沒有推導結果——穿得過去，但不是一張單。
LEGACY = "ns/backlog/P-1/tasks/T1"


def fake_resolver(command, ticket_name):
    row = FAKE.get(ticket_name)
    if row is None:
        return placer.TRIAGE, "resolver-unreachable", {"why": "這次沒問到"}
    slot, chain = row
    detail = {"mine": True, "upstream": {"標題": f"{ticket_name} 的標題", "上游狀態": slot}}
    if chain:
        detail["chain"] = list(chain)
    return slot, "resolver", detail


def build(root):
    for name, where in LAYOUT.items():
        path = os.path.join(root, *where.split("/"))
        os.makedirs(os.path.join(path, ".spine"), exist_ok=True)
        with open(os.path.join(path, ".spine", "placement.json"), "w", encoding="utf-8") as h:
            h.write('{"schema_version": 1, "producer": "fixture"}\n')
        with open(os.path.join(path, "index.md"), "w", encoding="utf-8") as h:
            h.write(f"# {name}\n")
    legacy = os.path.join(root, *LEGACY.split("/"))
    os.makedirs(legacy, exist_ok=True)
    with open(os.path.join(legacy, "index.md"), "w", encoding="utf-8") as h:
        h.write("# 舊層的一個 task\n")


def main() -> int:
    root = tempfile.mkdtemp(prefix="nested-walk-")
    try:
        build(root)
        names = [os.path.relpath(d, root) for _, d in placer.tickets(root)]
        verdicts = []

        # A-P1 埋一層與埋兩層的單都被找到。
        one, two = LAYOUT["G-1"], LAYOUT["G-2"]
        ok = one in names and two in names
        verdicts.append(("A-P1", ok,
                         f"埋一層的 {'有' if one in names else '沒有'}被找到，"
                         f"埋兩層的 {'有' if two in names else '沒有'}被找到"))

        # A-N1 舊層的工作目錄不是單。它有正文、沒有推導結果，而現在會被穿過去。
        leaked = [n for n in names if "tasks" in n.split(os.sep) or n.endswith("T1")]
        verdicts.append(("A-N1", not leaked,
                         f"清單裡{'有' if leaked else '沒有'}舊層的工作目錄"
                         + (f"：{leaked}" if leaked else "")))

        # A-N2 同一張單不出現兩次。
        dupes = sorted({n for n in names if names.count(n) > 1})
        verdicts.append(("A-N2", not dupes,
                         f"{len(names)} 個路徑，重複 {len(dupes)} 個"
                         + (f"：{dupes}" if dupes else "")))

        # A-P2／A-N3 要看整趟推導的結果，不只看清單。解析器換成假的，不連任何外部系統。
        placer._RESOLVER_CACHE.clear()
        real_resolver, real_declared = placer.slot_from_resolver, placer.declared_resolvers
        placer.slot_from_resolver = fake_resolver
        placer.declared_resolvers = lambda *a, **k: {"ns": "fake"}
        try:
            rows, _abstained = placer.survey(root)
        finally:
            placer.slot_from_resolver = real_resolver
            placer.declared_resolvers = real_declared
        by_name = {r["name"]: r for r in rows}

        # A-P2 鏈上那個只當路徑用的號被補成一張單。
        mid = by_name.get("MID")
        verdicts.append(("A-P2", mid is not None and mid["target"].endswith("MID"),
                         f"MID {'被補出來了，落在 ' + mid['target'] if mid else '沒有被補出來'}"))

        # A-N3 舊層的工作目錄不會變成某一張單的母單。
        bad = [f"{r['name']} → {r['target']}" for r in rows
               if "tasks" in r["target"].split(os.sep) or "/T1/" in r["target"]]
        verdicts.append(("A-N3", not bad,
                         f"{len(rows)} 張單的目的地裡{'有' if bad else '沒有'}穿過舊層工作目錄的"
                         + (f"：{bad}" if bad else "")))

        for name, ok, note in verdicts:
            print(f"{name} {'PASS' if ok else 'FAIL'} — {note}")
        passed = sum(1 for _, ok, _ in verdicts if ok)
        print(f"NESTED-WALK-SELFTEST {passed}/{len(verdicts)} 條過")
        return 0 if passed == len(verdicts) else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
