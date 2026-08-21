#!/usr/bin/env python3
"""搬動順序與「沒搬成」的五條斷言，一條一條量。見同名 .sh 的檔頭。"""

import contextlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib", "place_issues_by_state.py")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 第一棵樹重現的是真的那一次：母單與子單的**來源一樣深**，而目的地一個在另一個底下。
# 來源的深度回答不了「誰先搬」，所以那一版把順序交給了清單的排列。
#
# 單號:  (自己的格,  到鏈頂為止那幾層,  一開始住在哪——相對於樹根)
ORDER_TREE = {
    "P-1": ("backlog",   [],              "ns/backlog/P-1"),
    "C-1": ("in-review", ["P-1"],         "ns/in-review/_P-1-母單的標題/C-1"),
    "G-1": ("backlog",   ["P-1", "C-1"],  "ns/backlog/_C-1-子單的標題/G-1"),
}
# 第二棵樹本來就帶著兩個同號的目錄——那是「排完順序還是撞到」的那一種。它是一個真的 git
# repo，因為那一條要問的正是「兩邊各自上次動過是什麼時候」，而那個答案在 git 裡。
DOUBLE = ("ns/backlog/D-1", "ns/in-review/D-1")
OLD_DAY, NEW_DAY = "2026-01-02", "2026-06-15"


def fake_resolver(command, ticket_name):
    if ticket_name == "D-1":
        slot, chain = "backlog", []
    else:
        row = ORDER_TREE.get(ticket_name)
        if row is None:
            return placer.TRIAGE, "resolver-unreachable", {"why": "這次沒問到"}
        slot, chain = row[0], row[1]
    detail = {"mine": True, "upstream": {"標題": f"{ticket_name} 的標題", "上游狀態": slot}}
    if chain:
        detail["chain"] = list(chain)
    return slot, "resolver", detail


def put(root, relative, body):
    path = os.path.join(root, *relative.split("/"))
    os.makedirs(os.path.join(path, ".spine"), exist_ok=True)
    with open(os.path.join(path, ".spine", "placement.json"), "w", encoding="utf-8") as h:
        h.write('{"schema_version": 1, "producer": "fixture"}\n')
    with open(os.path.join(path, "index.md"), "w", encoding="utf-8") as h:
        h.write(body)
    return path


def git(root, *args, day=None):
    env = dict(os.environ)
    env.update({"GIT_AUTHOR_NAME": "fixture", "GIT_AUTHOR_EMAIL": "f@x",
                "GIT_COMMITTER_NAME": "fixture", "GIT_COMMITTER_EMAIL": "f@x"})
    if day:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"{day}T12:00:00+00:00"
    subprocess.run(["git", "-C", root, *args], env=env, check=True,
                   capture_output=True, text=True)


def build_order_tree(root):
    for name, (_slot, _chain, where) in ORDER_TREE.items():
        put(root, where, f"# {name}\n\n這一段是人寫的，重算不得碰它。\n")


def build_double_tree(root):
    """兩個同號的目錄，一個在舊的 commit 上，一個在新的 commit 上被改過。"""
    for i, where in enumerate(DOUBLE):
        put(root, where, f"# D-1 第 {i + 1} 份\n\n這一段是人寫的。\n")
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "第一版", day=OLD_DAY)
    later = os.path.join(root, *DOUBLE[1].split("/"), "index.md")
    with open(later, "a", encoding="utf-8") as handle:
        handle.write("\n後來又補了一段。\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "改了 in-review 那一份", day=NEW_DAY)


def run(root, order=None):
    """真的跑一次 `--execute`，回它印出來的東西。搬動的順序記進 `order`。"""
    placer._RESOLVER_CACHE.clear()
    placer._TOUCHED_CACHE.clear()
    real_resolver, real_move = placer.slot_from_resolver, placer.move
    real_declared = placer.declared_resolvers
    placer.slot_from_resolver = fake_resolver
    placer.declared_resolvers = lambda *a, **k: {"ns": "fake"}

    def watched_move(source, target):
        if order is not None:
            order.append(os.path.basename(target))
        return real_move(source, target)

    placer.move = watched_move
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            placer.main(["--issues", root, "--execute"])
    finally:
        placer.slot_from_resolver = real_resolver
        placer.declared_resolvers = real_declared
        placer.move = real_move
    return out.getvalue()


def where_is(root, name):
    """這個單號在樹裡對到幾個目錄，各在哪。"""
    found = []
    for dirpath, dirnames, _files in os.walk(root):
        if ".git" in dirpath.split(os.sep):
            continue
        for d in dirnames:
            if d == name:
                found.append(os.path.relpath(os.path.join(dirpath, d), root)
                             .replace(os.sep, "/"))
    return sorted(found)


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def main() -> int:
    one = tempfile.mkdtemp(prefix="move-order-")
    two = tempfile.mkdtemp(prefix="move-double-")
    try:
        build_order_tree(one)
        build_double_tree(two)
        before = {p: read(os.path.join(two, *p.split("/"), "index.md")) for p in DOUBLE}

        order = []
        run(one, order)
        report = run(two)

        verdicts = []

        def check(ident, ok, note):
            verdicts.append((ident, ok, note))

        # A-P1 母單先搬：C-1 的搬動排在 G-1 之前。判準是目的地的深度，不是來源的。
        # **兩者的來源一樣深**，所以照來源排的那一版在這裡沒有順序可言。
        at_c = order.index("C-1") if "C-1" in order else -1
        at_g = order.index("G-1") if "G-1" in order else -1
        check("A-P1", at_c >= 0 and at_g >= 0 and at_c < at_g,
              f"真的搬動的順序：{order}（C-1 在第 {at_c}、G-1 在第 {at_g}）")

        # A-P2 重算不製造重複：這一棵樹一開始沒有同號重複，重算之後也不該有。
        # **這一條問的不是集合**——兩個目錄同一個號的時候，「有哪些單號」一張都沒少。
        doubled = {n: w for n, w in ((n, where_is(one, n)) for n in ORDER_TREE)
                   if len(w) != 1}
        check("A-P2", not doubled, f"對到不只一個目錄的單號：{doubled or '沒有'}")

        # A-P3 沒搬成要說出來，而且說得出哪一份比較新。
        block = report.split("沒搬成", 1)[1] if "沒搬成" in report else ""
        named = "ns/in-review/D-1" in block and "ns/backlog/D-1" in block
        dated = NEW_DAY in block and OLD_DAY in block
        check("A-P3", named and dated,
              f"報告指名了撞到的那一張（{named}）、印出兩邊上次動過（{dated}："
              f"新的 {NEW_DAY}／舊的 {OLD_DAY}）")

        # A-N1 四個數字自洽：打算搬的 ＝ 真的搬了 ＋ 跟著母單走 ＋ 沒搬成 ＋ 來源不見了。
        got = re.search(r"打算搬 (\d+) 張＝真的搬了 (\d+) 張＋跟著母單一起走 (\d+) 張"
                        r"＋撞到已經存在的目的地沒搬成 (\d+) 張＋來源不見了 (\d+) 張", report)
        nums = [int(x) for x in got.groups()] if got else []
        check("A-N1", bool(nums) and nums[0] == sum(nums[1:]),
              (f"打算 {nums[0]} ＝ {nums[1]}＋{nums[2]}＋{nums[3]}＋{nums[4]}"
               f"（{sum(nums[1:])}）" if nums else "報告裡找不到那四個數字"))

        # A-N2 撞到的東西不被覆蓋也不被刪：兩個目錄都還在，兩份人寫的內容都還讀得到。
        # **不問「逐位元組不變」**——重算本來就會重寫每一張單的上層資訊區塊。
        after = {p: read(os.path.join(two, *p.split("/"), "index.md")) for p in DOUBLE}
        alive = [p for p in DOUBLE if os.path.isdir(os.path.join(two, *p.split("/")))]
        kept = [p for p in DOUBLE if "這一段是人寫的。" in after[p]
                and before[p].splitlines()[0] in after[p]]
        check("A-N2", len(alive) == 2 and len(kept) == 2,
              f"兩個目錄都還在（{len(alive)}/2）、兩份人寫的內容都還讀得到（{len(kept)}/2）")

        failed = 0
        for ident, ok, note in verdicts:
            print(f"{ident} {'PASS' if ok else 'FAIL'} — {note}")
            failed += 0 if ok else 1
        print(f"MOVE-ORDER-SELFTEST {len(verdicts) - failed}/{len(verdicts)} 條過")
        return 1 if failed else 0
    finally:
        shutil.rmtree(one, ignore_errors=True)
        shutil.rmtree(two, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
