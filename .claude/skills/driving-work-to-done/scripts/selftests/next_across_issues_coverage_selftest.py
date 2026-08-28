#!/usr/bin/env python3
"""`next --across-issues` 涵蓋整棵樹的六條斷言，一條一條量。見同名 .sh 的檔頭。"""

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
LIB = os.path.join(SCRIPTS, "lib", "place_issues_by_state.py")
NEXT = os.path.join(SCRIPTS, "spine-loop-state.sh")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 九張單，蓋掉一張單身上「狀態在哪」的每一種答案。最後一張是 A-N2 的那一張：它住在一個
# 終局的資料夾裡，而它自己記下的推導結果說它還在中間態——兩份不一致的時候，誰說了算。
#
#   單     住在哪                        身上有什麼                     該落進哪一個數字
FIXTURE = [
    ("S-1", "ns/backlog/S-1",            "spine-open-sealed",           "live"),
    ("S-2", "ns/backlog/S-2",            "spine-open-unsealed",         "live"),
    ("S-3", "ns/released/2026-01-02/S-3", "spine-converged",            "settled"),
    ("S-4", "ns/backlog/S-4",            "spine-broken",                "unreadable"),
    ("R-1", "ns/in-review/R-1",          "placement:in-review",         "elsewhere"),
    ("R-2", "ns/triage/R-2",             "placement:triage",            "elsewhere"),
    ("R-3", "ns/released/2026-01-02/R-3", "placement:released",         "settled_elsewhere"),
    ("U-1", "ns/backlog/U-1",            "nothing",                     "unplaced"),
    ("M-1", "ns/released/2026-01-02/M-1", "placement:in-progress",      "elsewhere"),
]
EXPECT = {"live": 2, "settled": 1, "unreadable": 1,
          "elsewhere": 3, "settled_elsewhere": 1, "unplaced": 1}


def build(root):
    for name, where, shape, _ in FIXTURE:
        ticket = os.path.join(root, *where.split("/"))
        spine = os.path.join(ticket, ".spine")
        os.makedirs(spine, exist_ok=True)
        sealed = shape == "spine-open-sealed"
        with open(os.path.join(ticket, "index.md"), "w", encoding="utf-8") as h:
            h.write("---\ntitle: \"%s\"\n" % name)
            if sealed:
                h.write("assertions_hash:\n  A: sha256:0\n")
            h.write("---\n\n# %s\n" % name)
        if shape.startswith("spine"):
            if shape == "spine-broken":
                # 有檔但讀不動。這一格本來就在，量它是為了證明新的三格沒有把它吃掉。
                body = "{ 這不是 JSON"
            else:
                body = json.dumps({
                    "schema_version": 2, "producer": "fixture", "max_rounds": 3,
                    "rounds": [], "stops": [], "stop": None,
                    "station": "delivered" if shape == "spine-converged" else "engineering",
                    "status": "converged" if shape == "spine-converged" else "open",
                }, ensure_ascii=False)
            with open(os.path.join(spine, "loop-state.json"), "w", encoding="utf-8") as h:
                h.write(body)
        if shape.startswith("placement:"):
            with open(os.path.join(spine, "placement.json"), "w", encoding="utf-8") as h:
                json.dump({"schema_version": 1, "producer": "fixture",
                           "slot": shape.split(":", 1)[1], "basis": "resolver"},
                          h, ensure_ascii=False)


def run(root):
    out = subprocess.run(["bash", NEXT, "next", "--across-issues", root],
                         capture_output=True, text=True)
    return out.stdout


def numbers(text):
    """把輸出裡那幾個具名的數字讀回來。讀不到的回 None，不回 0——量不到與量到 0 是兩件事。"""
    got = {}
    for line in text.splitlines():
        if line.startswith("counted: "):
            for pair in line[len("counted: "):].split():
                key, _, value = pair.partition("=")
                got[key] = int(value)
        if line.startswith("tree: "):
            got["tree_line"] = line
        if line.startswith("elsewhere: "):
            got["elsewhere_line"] = line
        if line.startswith("unplaced: "):
            got["unplaced_line"] = line
    return got


def main():
    root = tempfile.mkdtemp(prefix="next-coverage-")
    try:
        build(root)
        text = run(root)
        got = numbers(text)
        total = len(placer.tickets(root))
        line = got.get("tree_line", "")
        verdicts = []

        # A-P1 加起來等於整棵樹。每一個加數都從**那一行自己**讀回來，分母跟位置重算對。
        # 第一版是拿測試自己的期望值相加，於是「那一行少報一格」與「整種形狀被丟掉」兩種
        # 注入它都沒紅——它證明的是測試跟自己一致，不是那一行說了實話。
        declared = None
        if line.startswith("tree: "):
            digits = "".join(c for c in line[len("tree: "):].partition(" 張＝")[0] if c.isdigit())
            declared = int(digits) if digits else None
        addends = {key: expected_from_line(line, key) for key in EXPECT}
        summed = sum(v for v in addends.values() if v is not None)
        ok = (declared == total == len(FIXTURE)
              and None not in addends.values()
              and summed == declared
              and addends == EXPECT)
        verdicts.append(("A-P1", ok, f"重算認得 {total} 張，那一行宣告 {declared} 張，"
                                     f"加數 {addends} 加起來 {summed}"))

        # A-P2 狀態在別處的有自己的數字，而且說得出逐張看哪裡。
        el = got.get("elsewhere_line", "")
        ok = (f"{EXPECT['elsewhere'] + EXPECT['settled_elsewhere']} 張" in el
              and os.path.join(root, "OPEN.md") in el)
        verdicts.append(("A-P2", ok, el or "沒有 elsewhere 那一行"))

        # A-P3 五種形狀各至少一張，五張都被某一個數字涵蓋。
        shapes = {
            "走過主流程的": ("live", EXPECT["live"]),
            "狀態由外部推導的": ("elsewhere", EXPECT["elsewhere"]),
            "問不到而落 triage 的": ("elsewhere", EXPECT["elsewhere"]),
            "還沒開輪次的種子": ("live", EXPECT["live"]),
            "輪次檔讀不動的": ("unreadable", EXPECT["unreadable"]),
        }
        covered = [s for s, (key, want) in shapes.items()
                   if (got.get(key) if key in got else expected_from_line(line, key)) == want]
        ok = len(covered) == len(shapes) and "seed:ns/backlog/S-2" in text
        verdicts.append(("A-P3", ok, f"{len(covered)}/{len(shapes)} 種形狀落進具名的數字，"
                                     f"種子那一張{'有' if 'seed:' in text else '沒有'}逐張列出來"))

        # A-N1 不複製第二份逐張清單。
        leaked = [name for name, where, shape, bucket in FIXTURE
                  if bucket in ("elsewhere", "settled_elsewhere", "unplaced")
                  and any(l.startswith(("next:", "blocked:", "seed:")) and where in l
                          for l in text.splitlines())]
        verdicts.append(("A-N1", not leaked,
                         f"逐張印出來的裡面{'有' if leaked else '沒有'}狀態在別處的單"
                         + (f"：{leaked}" if leaked else "")))

        # A-N2 不從資料夾名推狀態。M-1 住在 released/ 底下，它自己記的是 in-progress。
        ok = (expected_from_line(line, "elsewhere") == EXPECT["elsewhere"]
              and expected_from_line(line, "settled_elsewhere") == EXPECT["settled_elsewhere"])
        verdicts.append(("A-N2", ok,
                         f"住在 released/ 而自己記 in-progress 的那一張，算進"
                         f"{'中間態' if ok else '有結論那一格'}"))

        # A-N3 什麼都問不到的有自己的數字，而且被說出來。
        up = got.get("unplaced_line", "")
        ok = f"{EXPECT['unplaced']} 張" in up and expected_from_line(line, "unplaced") == EXPECT["unplaced"]
        verdicts.append(("A-N3", ok, up or "沒有 unplaced 那一行"))

        for name, ok, note in verdicts:
            print(f"{name} {'PASS' if ok else 'FAIL'} — {note}")
        passed = sum(1 for _, ok, _ in verdicts if ok)
        print(f"NEXT-COVERAGE-SELFTEST {passed}/{len(verdicts)} 條過")
        if passed != len(verdicts):
            print(text)
        return 0 if passed == len(verdicts) else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


LABELS = {"live": "live", "settled": "settled", "unreadable": "讀不動",
          "elsewhere": "狀態在別處", "settled_elsewhere": "狀態在別處而且已經有結論",
          "unplaced": "兩層都問不到"}


def expected_from_line(line, key):
    """從 `tree:` 那一行把某一格的數字讀回來。讀不到回 None——量不到不是 0。

    刻意從**那一行**讀，不從 counted 讀：`tree:` 是宣告等式的那一行，而這幾條斷言問的
    正是那個等式成不成立。從別的地方讀出一個對的數字，證明不了那一行說了實話。
    """
    label = LABELS[key]
    body = line.partition("＝")[2]
    for chunk in body.replace("（", "＋（").split("＋"):
        chunk = chunk.strip()
        if chunk.startswith(label + " "):
            rest = chunk[len(label) + 1:]
            digits = "".join(c for c in rest if c.isdigit())
            return int(digits) if digits else None
    return None


if __name__ == "__main__":
    raise SystemExit(main())
