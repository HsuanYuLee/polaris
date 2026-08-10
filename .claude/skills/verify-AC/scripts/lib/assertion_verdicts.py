"""逐條判定：fence 宣告了哪些斷言，每一條的證據站不站得住。

**報告與交付讀的是同一段。** 在這之前這整段長在 `record-delivery-intent.sh` 的 heredoc
裡，於是「這張單過了幾條」只有在交付那條路上問得到，而且任一條不成立就整支拒絕、什麼都
不印——想知道現在到哪裡了，只能把 oracle 一條一條重跑自己拼。

判定分三種，而且三種都要說得出來：

    pass          證據站得住
    fail          證據說它沒過，或它證的不是要交付的這棵樹
    unmeasurable  問不出來（那棵樹不在了、命令跑不起來）

**量不到不是通過。** 它是第三種，不是 pass 的一個溫和版本——一個安靜的第三態下一次就會
被當成查過了。

證據的可信度分三層，由呼叫者決定要幾層：

1. **檔案自洽**（一律做）：來源欄位、判定、綁的 head。
2. **登錄相符**（給 `ledger_path` 才做）：證據記的命令，要等於這條斷言登錄過的那一條。
   少了這一層，一份手寫的證據可以指名一條「一定會過」的命令。
3. **重跑一次**（給 `rerun=True` 才做）：拿登錄的那條命令現在再跑一次，要還是綠的。
   這一層是唯一擋得住「內容自洽但不是這一套產生的證據」的東西——前兩層讀的都是檔案，
   而檔案是誰寫的它自己說了算。

**擋不住什麼要說出來**：一個能在同一棵樹上執行任意命令的施工端，可以讓命令本身變成一條
永遠會過的命令。擋那件事的不是這裡，是登錄那一層要求換命令必須帶「實作之前紅過」的證據，
而登錄本身住在 git 歷史裡。三層疊起來仍然不是證明，是把偽造的成本從「寫一個 JSON」提高
到「改一條登錄過的命令，而那個改動會出現在 diff 裡」。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

PRODUCER = "run-hardened-oracle.sh"

PASS = "pass"
FAIL = "fail"
UNMEASURABLE = "unmeasurable"


def assertion_ids(index_path):
    """單裡凍結的斷言 ID，照人簽下去的順序。

    Args:
        index_path: `{issue}/index.md`。
    Returns:
        去重後的 ID 列表；沒有 fence 或 fence 裡沒有 ID 時回空的。

    比對的樣式容得下有沒有粗體：只認粗體那一種的話，有人拿掉星號就會靜靜地找不到——
    而在這裡找不到任何東西，讀起來像「沒有東西要證明」。
    """
    body = open(index_path, encoding="utf-8").read()
    fences = re.findall(
        r"<!-- POLARIS-FROZEN-[A-Z]+-BEGIN -->(.*?)<!-- POLARIS-FROZEN-[A-Z]+-END -->",
        body, re.S)
    return list(dict.fromkeys(re.findall(
        r"^[ \t]*[-*][ \t]*\**([A-Z]+-[PN]\d+)\b", "\n".join(fences), re.M)))


def distinguish(a, b):
    """把兩個要被說成不同的 sha 變成兩個看得出不同的字串。

    Args:
        a, b: 兩個 sha。長度不保證一樣——證據裡存過縮寫。
    Returns:
        (a_shown, b_shown)。其中一個是另一個的前綴時兩邊都印全長：那種情況沒有任何
        寬度能讓它們長得不一樣，而截斷會印出兩個一模一樣的字串，然後說它們不同。
        2026-08-09 真的印過那一行，讀的人照著建議重跑了一次本來就正確的量測。
    """
    if a.startswith(b) or b.startswith(a):
        return a, b
    width = 12
    while a[:width] == b[:width] and width < max(len(a), len(b)):
        width += 4
    return a[:width], b[:width]


def _sees_both(repo, frm, to):
    """這棵樹的物件庫裡有沒有同時有這兩個 commit。"""
    if not repo or not os.path.isdir(repo):
        return False
    return all(
        subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{sha}^{{commit}}"],
                       capture_output=True, text=True).returncode == 0
        for sha in (frm, to))


def _candidate_repos(measuring_tree):
    """可能答得出「這兩個 commit 之間差了什麼」的那幾棵樹，量測用的排第一。"""
    out = []
    for repo in (measuring_tree, os.getcwd()):
        if repo and repo not in out:
            out.append(repo)
    return out


def _delta_within_allowance(measuring_tree, frm, to, delta_allows, notes):
    """呼叫者指名的那段差異是不是真的只碰了它指名的路徑。

    Args:
        measuring_tree: 證據記下的量測工作區。它只是**第一個候選**，不是唯一答案——
            兩個 commit 之間的差異是物件庫的性質，不是工作目錄的性質，所以任何一棵
            看得到那兩個 commit 的樹都會給出同一個答案。釋出尾段的前一步剛好會移除
            量測用的 worktree，把問題綁在它身上等於讓這道判定對每一張在 worktree
            開工的單永遠不成立。
        frm: 證據量到的 head；to: 要交付的 head。
        delta_allows: 呼叫者指名放行的路徑前綴。
        notes: 說明會被 append 進來的清單。
    Returns:
        ("ok", 碰到的路徑) / ("outside", 沒被指名的那幾條) / ("unmeasurable", 一句原因)。
    """
    tried = _candidate_repos(measuring_tree)
    repo = next((r for r in tried if _sees_both(r, frm, to)), None)
    if repo is None:
        # 問不到不得放行，而且要說出試過哪幾棵——一句「量不到」沒有指名的話，
        # 下一個人沒有辦法知道要去哪裡找那兩個 commit。
        listed = "、".join(repr(r) for r in tried) or "（一個候選都沒有）"
        return UNMEASURABLE, (
            f"沒有任何一棵樹同時看得到 {frm[:12]} 與 {to[:12]}；試過：{listed}")
    diff = subprocess.run(["git", "-C", repo, "diff", "--name-only", frm, to],
                          capture_output=True, text=True)
    if diff.returncode != 0:
        return UNMEASURABLE, f"{repo} 的 git diff 問不出來：{diff.stderr.strip()}"
    notes.append("那段差異問的是 " + repo + (
        "" if repo == measuring_tree
        else f"（證據量在 {measuring_tree!r}，那棵已經不在或看不到那兩個 commit）"))
    paths = [p for p in diff.stdout.splitlines() if p]
    outside = [p for p in paths
               if not any(p == a or p.startswith(a.rstrip("/") + "/") for a in delta_allows)]
    if outside:
        return "outside", outside
    return "ok", paths


def registered_commands(ledger_path):
    """登錄裡每條斷言**現在**登錄的那一條命令。

    Args:
        ledger_path: `{issue}/.spine/measurement-ledger.json`。
    Returns:
        {assertion_id: command}，或者 `None`——**登錄檔不在跟登錄檔是空的，是兩件事**。
        前者是「這一層沒得做」，後者是「做了，而且一條都沒登錄」。回同一個空 dict 的話
        兩者在呼叫端長得一樣，而那正是「量不到被讀成通過」的形狀。
        同一條斷言換過命令時取最後一筆——登錄是往後追加的，最後一筆就是現在生效的。
    """
    if not ledger_path or not os.path.exists(ledger_path):
        return None
    try:
        entries = json.load(open(ledger_path, encoding="utf-8")).get("entries", [])
    except (OSError, ValueError):
        return None
    out = {}
    for entry in entries:
        if entry.get("assertion_id") and entry.get("new_command"):
            out[entry["assertion_id"]] = entry["new_command"]
    return out


def _rerun(command, cwd, expect, forbid, oracle, notes):
    """拿這條命令現在再跑一次，回 (state, 一句話)。

    Args:
        command: 要跑的命令；cwd: 在哪棵樹上跑（空的就用現在站的地方）。
        expect / forbid: 證據記下的正負向證據樣式，原樣交還給 oracle。
        oracle: `run-hardened-oracle.sh` 的路徑。
        notes: 說明會被 append 進來的清單。
    Returns:
        (PASS|FAIL|UNMEASURABLE, 說明)。

    跑不起來是 UNMEASURABLE 不是 FAIL：oracle 不在、證據沒說跑的是哪一條命令，說的都是
    「這一趟沒問到」，而把問不到讀成沒過，跟把它讀成通過一樣是在編一個答案。
    """
    if not oracle or not os.path.exists(oracle):
        return UNMEASURABLE, f"重跑不了：找不到 {oracle or 'run-hardened-oracle.sh'}"
    if not command:
        return UNMEASURABLE, "重跑不了：證據沒說它跑的是哪一條命令"
    if cwd and not os.path.isdir(cwd):
        # 量測用的樹不在了不是紅燈，也不是「這一層做不成」：釋出尾段的前一步就是移除
        # 那個 worktree，所以每一張在 worktree 開工的單走到這裡都會撞上。退回現在站的
        # 地方重跑，並且說出來——一個安靜的退路下一次會被當成原本就在那棵樹上跑的。
        notes.append(f"重跑退回現在站的地方：量測用的工作區 {cwd} 已經不在")
        cwd = ""
    argv = ["bash", oracle, "--command", command]
    for pattern in expect or []:
        argv += ["--expect-evidence", pattern]
    for pattern in forbid or []:
        argv += ["--forbid-evidence", pattern]
    if cwd:
        argv += ["--cwd", cwd]
    done = subprocess.run(argv, capture_output=True, text=True)
    if done.returncode == 0:
        return PASS, "重跑一次仍然是綠的"
    if done.returncode == 1:
        return FAIL, "重跑一次是紅的：" + (done.stdout.strip().splitlines() or ["（沒有輸出）"])[-1]
    return UNMEASURABLE, "重跑量不到：" + (done.stderr.strip().splitlines() or ["（沒有輸出）"])[-1]


def judge(index_path, evidence_dir, head=None, delta_allows=(),
          ledger_path=None, rerun=False, oracle=None):
    """逐條判定，外加幾件跨斷言才問得出來的事。

    Args:
        index_path: `{issue}/index.md`，斷言 ID 的唯一來源。
        evidence_dir: `{issue}/.spine/evidence`。
        head: 要交付的 head；`None` 表示「由證據自己說它量的是哪一棵」。
        delta_allows: 證據量在別的 head 上時，呼叫者指名放行的路徑前綴。
        ledger_path: 給了就多做第二層（登錄相符）。
        rerun: 真就多做第三層（重跑一次）。
        oracle: `run-hardened-oracle.sh` 的路徑，只有 rerun 用得到。
    Returns:
        {"ids", "rows", "blockers", "notes", "layers", "head", "measured_in", "delta"}。
        `rows` 逐條，`blockers` 是跨斷言的問題（證據指向兩棵不同的樹之類），
        `layers` 說出三層各自**做成了沒有**（見 `layers_line`）。
    """
    ids = assertion_ids(index_path)
    # 做到第幾層要跟著判定一起回去，不要讓呼叫者自己算一次。呼叫者算的那一份是第二個
    # 答案：它問的是「我要求了幾層」，而這裡答的是「實際做成了幾層」——登錄檔不在的時候
    # 兩者不一樣，而那正好是唯一需要分辨的時候。
    layers = {"self_consistent": True, "registered": False, "rerun": bool(rerun)}
    report = {"ids": ids, "rows": [], "blockers": [], "notes": [], "layers": layers,
              "head": head, "measured_in": "", "delta": None}
    if not ids:
        report["blockers"].append(
            f"{index_path} 有 fence 但裡面一個斷言 ID 都沒有；沒有東西要證明")
        return report

    registered = registered_commands(ledger_path) if ledger_path else None
    layers["registered"] = registered is not None
    if ledger_path and registered is None:
        report["notes"].append(
            f"讀不到量測登錄（{ledger_path}），「證據記的命令是登錄過的那一條」沒有被檢查")
    rows = {}
    evidence = {}
    measured = {}
    measured_in = {}
    carried = {}

    def mark(aid, state, detail):
        # 第一個判定就定案：後面的檢查是加深，不是翻案。一條已經 fail 的斷言不會因為
        # 重跑綠了就變成 pass——那份證據本身還是不成立的。
        rows.setdefault(aid, (state, detail))

    for aid in ids:
        path = os.path.join(evidence_dir, f"{aid}.json")
        if not os.path.exists(path):
            mark(aid, FAIL, f"沒有證據（{path}）")
            continue
        try:
            ev = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            mark(aid, UNMEASURABLE, f"證據讀不出來（{exc}）")
            continue
        evidence[aid] = ev
        if ev.get("producer") != PRODUCER:
            mark(aid, FAIL, f"產生者是 {ev.get('producer')!r}，不是 {PRODUCER}")
            continue
        if registered is not None:
            # 登錄檔在，就每一條都要在裡面。「沒登錄過」不能當成豁免——那正好是一份手寫
            # 證據會長的樣子：它指名一條沒有人簽過的命令，而舊的寫法對這種情況不判任何話。
            if aid not in registered:
                mark(aid, FAIL, "這條斷言沒有登錄過量測命令，證據指的是一條沒人簽過的命令")
                continue
            if ev.get("command") != registered[aid]:
                mark(aid, FAIL, "證據記的命令不是這條斷言登錄過的那一條")
                continue
        if ev.get("verdict") != "PASS":
            mark(aid, FAIL, f"判定是 {ev.get('verdict')!r}，不是 PASS")
            continue
        if not ev.get("head_sha"):
            mark(aid, UNMEASURABLE, "證據沒說它量的是哪一個 head")
            continue
        if head and ev["head_sha"] != head and not delta_allows:
            shown_ev, shown_head = distinguish(str(ev["head_sha"]), head)
            mark(aid, FAIL, f"量在 {shown_ev}，要交付 {shown_head}")
            continue
        if head and ev["head_sha"] != head:
            carried.setdefault((ev["head_sha"], ev.get("measured_in") or ""), []).append(aid)
        else:
            measured.setdefault(ev["head_sha"], []).append(aid)
        measured_in.setdefault(ev.get("measured_in") or "", []).append(aid)

    # 呼叫者指名了差異的話，逐個去 git 驗那句話。驗過了那些斷言才算數——差異裡出現一個
    # 沒被指名的路徑，或者根本問不出那段差異，都退回原本的拒絕。
    for (ev_head, tree), aids in sorted(carried.items()):
        state, payload = _delta_within_allowance(
            tree, ev_head, head, delta_allows, report["notes"])
        if state == "ok":
            measured.setdefault(ev_head, []).extend(aids)
            report["delta"] = {"from": ev_head, "to": head, "paths": payload,
                               "declared_allowed": list(delta_allows)}
        elif state == "outside":
            for aid in aids:
                mark(aid, FAIL, f"量在 {ev_head[:12]}，而中間那段差異碰到了沒被指名的檔案："
                                + "、".join(payload))
        else:
            for aid in aids:
                mark(aid, UNMEASURABLE, f"量在 {ev_head[:12]}，而這段差異量不到——{payload}")

    # 第三層。跑的是證據記的那條命令——走到這裡它已經被上面驗過等於登錄的那一條（登錄檔
    # 不在的話上面記了一句話說這一層沒做）。同一條命令通常被好幾條斷言共用，所以照
    # (命令, 樹) 去重再跑：一張八條斷言三條命令的單，重跑三次不是八次。
    if rerun:
        cache = {}
        for aid in ids:
            if aid in rows or aid not in evidence:
                continue
            ev = evidence[aid]
            key = (ev.get("command", ""), ev.get("measured_in") or "")
            if key not in cache:
                cache[key] = _rerun(key[0], key[1], ev.get("expect_evidence"),
                                    ev.get("forbid_evidence"), oracle, report["notes"])
            state, detail = cache[key]
            if state != PASS:
                mark(aid, state, detail)
        report["notes"].append(f"重跑了 {len(cache)} 條不同的命令（{len(ids)} 條斷言共用）")

    # 沒有 --head 的時候，交付的 head 就是證據量到的那一棵樹。證據彼此不一致代表這幾條
    # 斷言量的不是同一棵樹——那不是「取一個」就好，取哪一個都會讓另一批證據變成沒看過的。
    if not head:
        if len(measured) > 1:
            report["blockers"].append("證據指向不只一棵樹，說不出要交付哪一個 head：")
            for sha, aids in sorted(measured.items()):
                report["blockers"].append(f"  {sha[:12]}: {', '.join(aids)}")
        elif measured:
            head = next(iter(measured))
    report["head"] = head

    # 證據說得出自己是在哪一棵樹上量的，所以「那棵樹現在還在不在那個 commit」問得到它本人。
    trees = [d for d in measured_in if d]
    if len(trees) > 1:
        report["blockers"].append("證據來自不只一棵樹，說不出要交付哪一個工作區：")
        for tree in sorted(trees):
            report["blockers"].append(f"  {tree}: {', '.join(measured_in[tree])}")
    elif not trees:
        # 揭露而不是放行：舊的證據沒有這個欄位，這一條就量不到。
        report["notes"].append(
            "證據沒有記下它在哪一棵樹上量的（DP-482 之前產生的），"
            "「量完之後還有沒有新 commit」這一條沒有被檢查")
    else:
        report["measured_in"] = trees[0]
        tip = subprocess.run(["git", "-C", trees[0], "rev-parse", "HEAD"],
                             capture_output=True, text=True).stdout.strip()
        if not tip:
            # 量測用的那棵樹已經不在（釋出尾段會移除 worktree）不是紅燈：這一條問的是
            # 「量完之後有沒有再 commit」，而那棵樹消失的時候這件事在這裡量不到。
            report["notes"].append(
                f"量測用的工作區問不出 HEAD（{trees[0]}）——"
                "「量完之後還有沒有新 commit」這一條沒有被檢查")
        elif head and tip != head:
            shown_head, shown_tip = distinguish(head, tip)
            report["blockers"].append(
                f"證據量的是 {shown_head}，但 {trees[0]} 現在在 {shown_tip}——"
                "量完之後又有 commit 落下去了")

    report["rows"] = [{"id": aid,
                       "state": rows.get(aid, (PASS, "證據站得住"))[0],
                       "detail": rows.get(aid, (PASS, "證據站得住"))[1]}
                      for aid in ids]
    return report


LAYER_NAMES = (("self_consistent", "檔案自洽"),
               ("registered", "登錄相符"),
               ("rerun", "重跑一次"))


def layers_line(report):
    """做成了哪幾層，一行。沒做成的也說出來——一份沒說自己做到第幾層的報告，讀起來永遠
    像做滿了。"""
    done = [name for key, name in LAYER_NAMES if report["layers"][key]]
    missing = [name for key, name in LAYER_NAMES if not report["layers"][key]]
    return "LAYERS: " + "、".join(done) + (
        f"（沒做：{'、'.join(missing)}）" if missing else "")


def counts(report):
    """{pass: n, fail: n, unmeasurable: n}。三種都在，包含 0——一個不出現的類別讀起來
    像它不存在。"""
    out = {PASS: 0, FAIL: 0, UNMEASURABLE: 0}
    for row in report["rows"]:
        out[row["state"]] += 1
    return out


def render(report, stream=sys.stdout):
    """把判定印成人讀的形狀。回 exit code：0 全過 / 1 有沒過的 / 2 有量不到的。

    量不到的優先權高於沒過：一張「三條紅、一條問不到」的單，真正該先處理的是那個問不到
    ——沒過至少是一個答案。
    """
    icon = {PASS: "PASS", FAIL: "FAIL", UNMEASURABLE: "????"}
    for row in report["rows"]:
        print(f"  {icon[row['state']]}  {row['id']}  {row['detail']}", file=stream)
    tally = counts(report)
    print(f"ASSERTIONS: {len(report['rows'])} 條——過 {tally[PASS]}、"
          f"沒過 {tally[FAIL]}、量不到 {tally[UNMEASURABLE]}", file=stream)
    if report["head"]:
        print(f"  head {report['head'][:12]}"
              + (f"  量在 {report['measured_in']}" if report["measured_in"] else ""),
              file=stream)
    for note in report["notes"]:
        print(f"  NOTE: {note}", file=stream)
    for blocker in report["blockers"]:
        print(f"  BLOCKER: {blocker}", file=stream)
    if report["blockers"] or tally[UNMEASURABLE]:
        return 2
    return 1 if tally[FAIL] else 0
