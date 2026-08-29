#!/usr/bin/env python3
"""「問不到」與「答不出來」是兩件事——六條 assertion 各量一次。見同名 .sh 的檔頭。"""

import importlib.util
import json
import os
import shutil
import stat
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib", "place_issues_by_state.py")
spec = importlib.util.spec_from_file_location("placer", LIB)
placer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(placer)

# 一支照要求收場的解析器。五種離場方式各一個——**離場碼與有沒有印東西是兩個維度**，
# 而上一版正是拿其中一個去猜另一個。
STUB = """#!/usr/bin/env bash
case "$1" in
  CANNOT-ASK)   echo '連不上 JIRA' >&2; exit 2 ;;
  NO-ANSWER)    echo '對照表沒有涵蓋狀態 `discuss`' >&2; exit 1 ;;
  NO-ANSWER-MUTE) exit 1 ;;
  SILENT)       exit 0 ;;
  GOOD)         echo '{"slot": "backlog", "mine": true}' ; exit 0 ;;
esac
exit 1
"""


def ask(root, name):
    """問一次那支 stub，回 (slot, basis, why)。"""
    placer._RESOLVER_CACHE.clear()
    slot, basis, detail = placer.slot_from_resolver(
        f"bash {os.path.join(root, 'stub.sh')}", name)
    return slot, basis, (detail or {}).get("why", "")


def main() -> int:
    root = tempfile.mkdtemp(prefix="resolver-exits-")
    try:
        path = os.path.join(root, "stub.sh")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(STUB)
        os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)

        cannot = ask(root, "CANNOT-ASK")
        no_answer = ask(root, "NO-ANSWER")
        mute = ask(root, "NO-ANSWER-MUTE")
        silent = ask(root, "SILENT")
        good = ask(root, "GOOD")
        verdicts = []

        # A-P1 答不出來的那一種不以「這次沒問到」開頭。帶說明與不帶說明各一次——不帶說明
        # 的那一種以前會退回同一句話，而它正是最容易被漏掉的那個形狀。
        ok = (not no_answer[2].startswith("這次沒問到")
              and "discuss" in no_answer[2]
              and not mute[2].startswith("這次沒問到"))
        verdicts.append(("A-P1", ok,
                         f"帶說明時說「{no_answer[2][:34]}」；不帶說明時說「{mute[2][:34]}」"))

        # A-P2 問不到的那一種照舊。
        ok = cannot[2].startswith("這次沒問到") and "連不上" in cannot[2]
        verdicts.append(("A-P2", ok, f"說「{cannot[2][:40]}」"))

        # A-P3 兩種落在不同的依據上。
        ok = (cannot[1] != no_answer[1]
              and cannot[1] == "resolver-unreachable"
              and no_answer[1] == mute[1] == "resolver-no-answer")
        verdicts.append(("A-P3", ok,
                         f"問不到={cannot[1]}／答不出來={no_answer[1]}（不帶說明也是 {mute[1]}）"))

        # A-N1 說法分開不等於歸位。四種答不出來的全部還在「等人歸位」那一格。
        stuck = {cannot[0], no_answer[0], mute[0], silent[0]}
        verdicts.append(("A-N1", stuck == {placer.TRIAGE},
                         f"四種答不出來的落在 {sorted(stuck)}"))

        # A-N2 回 0 卻什麼都沒印不算一個答案，而且不被說成「這次沒問到」。
        ok = (silent[0] == placer.TRIAGE
              and not silent[2].startswith("這次沒問到")
              and "什麼都沒印" in silent[2])
        verdicts.append(("A-N2", ok, f"說「{silent[2][:40]}」，依據={silent[1]}"))

        # A-N3 答得出來的單行為不變。
        ok = good[0] == "backlog" and good[1] == "resolver"
        verdicts.append(("A-N3", ok, f"slot={good[0]} basis={good[1]}"))

        for name, ok, note in verdicts:
            print(f"{name} {'PASS' if ok else 'FAIL'} — {note}")
        passed = sum(1 for _, ok, _ in verdicts if ok)
        print(f"RESOLVER-EXIT-CODES-SELFTEST {passed}/{len(verdicts)} 條過")
        return 0 if passed == len(verdicts) else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
