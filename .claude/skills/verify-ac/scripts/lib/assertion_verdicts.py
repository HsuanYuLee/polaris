"""逐條判定：fence 宣告了哪些 assertion，每一條的證據站不站得住。

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
2. **登錄相符**（給 `ledger_path` 才做）：證據記的命令，要等於這條 assertion 登錄過的那一條。
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
    """單裡凍結的 assertion ID，照人簽下去的順序。

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
    """登錄裡每條 assertion**現在**登錄的那一條命令。

    Args:
        ledger_path: `{issue}/.spine/measurement-ledger.json`。
    Returns:
        {assertion_id: command}，或者 `None`——**登錄檔不在跟登錄檔是空的，是兩件事**。
        前者是「這一層沒得做」，後者是「做了，而且一條都沒登錄」。回同一個空 dict 的話
        兩者在呼叫端長得一樣，而那正是「量不到被讀成通過」的形狀。
        同一條 assertion 換過命令時取最後一筆——登錄是往後追加的，最後一筆就是現在生效的。
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


def tool_specs(evidence):
    """把證據記下的工具清單還原成 `--require-tool` 認得的樣子，回一個 tuple。

    Args:
        evidence: 一份 oracle 產的證據。
    Returns:
        `("gh", "rg:--version")` 這種形狀；證據沒記過工具就是空的。

    oracle 記的是 `name` 與 `capability_probe` 兩個欄位（`run-hardened-oracle.sh` 的
    payload），而 `--require-tool` 吃的是 `name` 或 `name:<探針參數>`——同一件事的兩個
    形狀，中間差一次翻譯。**沒有這個欄位表示當初沒探過工具**，那是一個答案，不是缺料：
    DP-506 之前產生的證據全部長那樣，而它們的命令本來就只用釘死的 PATH 上那幾支。
    """
    specs = []
    for tool in evidence.get("tools") or []:
        name = tool.get("name")
        if not name:
            continue
        probe = tool.get("capability_probe")
        specs.append(f"{name}:{probe}" if probe else name)
    return tuple(specs)


def _why(done):
    """從 oracle 的兩個串流拼出「為什麼紅的」，回一行字。

    Args:
        done: `subprocess.run` 的結果。
    Returns:
        一行說明；兩個串流都空的時候回「（沒有輸出）」。

    oracle 判紅時把 marker 與說明印在 **stderr**，而在那之前它已經把命令自己的兩個串流
    原樣重播過。所以最後幾行是 oracle 說的、再前面是命令自己說的，兩邊一起才回答得了
    「哪裡紅的」。原本只讀 stdout，於是一條只往 stderr 寫的命令永遠只換得到那句
    「（沒有輸出）」——一個判紅而說不出理由的關卡，跟一個沒有理由的通過一樣不能用。
    """
    lines = [ln for ln in (done.stderr or "").splitlines() if ln.strip()]
    if not lines:
        lines = [ln for ln in (done.stdout or "").splitlines() if ln.strip()]
    return " / ".join(lines[-WHY_LINES:]) if lines else "（沒有輸出）"


# 拼失敗訊息時往回取幾行。最後兩行固定是 oracle 的 marker 與說明，再前面一行是命令
# 自己最後說的話——那一行通常才是人要看的東西（`gh: command not found`）。
WHY_LINES = 3


def _rerun(command, cwd, expect, forbid, tools, oracle, notes):
    """拿這條命令現在再跑一次，回 (state, 一句話)。

    Args:
        command: 要跑的命令；cwd: 在哪棵樹上跑（空的就用現在站的地方）。
        expect / forbid: 證據記下的正負向證據樣式，原樣交還給 oracle。
        tools: 證據記下的工具清單，原樣交還給 oracle 的 `--require-tool`。
        oracle: `run-hardened-oracle.sh` 的路徑。
        notes: 說明會被 append 進來的清單。
    Returns:
        (PASS|FAIL|UNMEASURABLE, 說明)。

    跑不起來是 UNMEASURABLE 不是 FAIL：oracle 不在、證據沒說跑的是哪一條命令，說的都是
    「這一趟沒問到」，而把問不到讀成沒過，跟把它讀成通過一樣是在編一個答案。

    工具要交還，是因為 oracle 會把 PATH 釘死成宣告的那幾個目錄，只有 `--require-tool`
    探到的才會被 symlink 進去。不交還的話，一條當初靠 `gh` 才跑得起來的命令重跑時
    exit 127，而那份證據本身是好的——這一層就從「再驗一次」變成「懲罰用過外部工具的單」。
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
    for spec in tools or ():
        argv += ["--require-tool", spec]
    if cwd:
        argv += ["--cwd", cwd]
    # 用 bytes 收再自己解碼：量測命令吐得出不是 UTF-8 的位元組（掃到二進位檔、
    # 或 shell 把多位元組字元切斷），而 text=True 會在那一刻丟 traceback ——
    # 那既不是 PASS 也不是「量不到」，是一個沒有判定的離場。
    done = subprocess.run(argv, capture_output=True)
    done = subprocess.CompletedProcess(
        done.args, done.returncode,
        done.stdout.decode("utf-8", "replace"),
        done.stderr.decode("utf-8", "replace"))
    if done.returncode == 0:
        return PASS, "重跑一次仍然是綠的"
    if done.returncode == 1:
        return FAIL, "重跑一次是紅的：" + _why(done)
    return UNMEASURABLE, "重跑量不到：" + _why(done)


def rerun_key(ev):
    """決定一趟重跑的全部東西。**這是去重的鍵，只有這一份。**

    Args:
        ev: 一份 oracle 產的證據。
    Returns:
        命令、在哪棵樹跑、要求出現什麼、要求不出現什麼、要哪些工具，五樣組成的 tuple。

    **不要把這句話簡化成「照命令去重」。** 兩條 assertion 可以跑同一條命令而各自要求不同的證據
    樣式；鍵漏掉那幾樣的話，第二條會拿到第一條的答案，而它自己的樣式從來沒有被檢查過
    ——一條沒被量到的 assertion 看起來就跟過了一樣。

    抽成一支是因為它有兩個呼叫者：跑之前數趟數的那一次，跟跑的時候。抄成兩份的話預告的
    數字會跟實際的漂開，而漂掉的那一刻預告看起來仍然很正常。
    """
    return (ev.get("command", ""),
            ev.get("measured_in") or "",
            tuple(ev.get("expect_evidence") or ()),
            tuple(ev.get("forbid_evidence") or ()),
            tool_specs(ev))



def declared_landing(index_path):
    """這張單宣告它的改動落在哪幾棵樹。問不到就回空的清單。

    問的是 `spine-loop-state.sh landing`，跟交付那一步同一個產生者——自己去讀
    `loop-state.json` 的欄位會變成第二個答案，而兩個答案會漂。

    **空的清單不等於「沒有限制」**：呼叫端拿它當「宣告過的樹有哪些」，一張問不到宣告的單
    因此走回原本那條嚴格的路（證據來自不只一棵樹就擋）。一個問不到的宣告不得比一個答得
    出來的宣告寬。
    """
    issue_dir = os.path.dirname(os.path.abspath(index_path))
    state = os.path.join(issue_dir, ".spine", "loop-state.json")
    resolver = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__))))),
        "driving-work-to-done", "scripts", "spine-loop-state.sh")
    if not (os.path.isfile(resolver) and os.path.isfile(state)):
        return []
    try:
        done = subprocess.run(["bash", resolver, "landing", "--state", state],
                              capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    if done.returncode != 0:
        return []
    out = [line.strip() for line in done.stdout.splitlines() if line.strip()]
    return [] if out == ["unlanded"] else out


def judge(index_path, evidence_dir, head=None, delta_allows=(),
          ledger_path=None, rerun=False, oracle=None):
    """逐條判定，外加幾件跨 assertion 才問得出來的事。

    Args:
        index_path: `{issue}/index.md`，assertion ID 的唯一來源。
        evidence_dir: `{issue}/.spine/evidence`。
        head: 要交付的 head；`None` 表示「由證據自己說它量的是哪一棵」。
        delta_allows: 證據量在別的 head 上時，呼叫者指名放行的路徑前綴。
        ledger_path: 給了就多做第二層（登錄相符）。
        rerun: 真就多做第三層（重跑一次）。
        oracle: `run-hardened-oracle.sh` 的路徑，只有 rerun 用得到。
    Returns:
        {"ids", "rows", "blockers", "notes", "layers", "head", "measured_in", "delta"}。
        `rows` 逐條，`blockers` 是跨 assertion 的問題（證據指向兩棵不同的樹之類），
        `layers` 說出三層各自**做成了沒有**（見 `layers_line`）。
    """
    ids = assertion_ids(index_path)
    # 做到第幾層要跟著判定一起回去，不要讓呼叫者自己算一次。呼叫者算的那一份是第二個
    # 答案：它問的是「我要求了幾層」，而這裡答的是「實際做成了幾層」——登錄檔不在的時候
    # 兩者不一樣，而那正好是唯一需要分辨的時候。
    layers = {"self_consistent": True, "registered": False, "rerun": bool(rerun)}
    report = {"ids": ids, "rows": [], "blockers": [], "notes": [], "layers": layers,
              "head": head, "measured_in": "", "delta": None,
              # 每一棵有證據的樹與它各自的 head。單樹的單只有一筆，跟 `head`／
              # `measured_in` 說的是同一件事；多樹的單只有這裡說得完。
              "heads": [],
              # 這一趟「看見」了哪幾棵樹。它記的是證據**檔案**說的，不是通過判定
              # 的那幾條說的——否則一條被判掉的 assertion 會把它的樹一起帶走，而「證據
              # 來自幾棵樹」這一項就會在輸入被清空的時候恆真（DP-611 A-N1）。
              "trees_seen": []}
    if not ids:
        report["blockers"].append(
            f"{index_path} 有 fence 但裡面一個 assertion ID 都沒有；沒有東西要證明")
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
    tree_heads = {}
    carried = {}

    def mark(aid, state, detail):
        # 第一個判定就定案：後面的檢查是加深，不是翻案。一條已經 fail 的 assertion 不會因為
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
                mark(aid, FAIL, "這條 assertion 沒有登錄過量測命令，證據指的是一條沒人簽過的命令")
                continue
            if ev.get("command") != registered[aid]:
                mark(aid, FAIL, "證據記的命令不是這條 assertion 登錄過的那一條")
                continue
        # 樹的帳記在這裡，不記在迴圈最後。下面每一個 `continue` 都會跳過迴圈尾巴，
        # 所以記在尾巴的話，「證據來自幾棵樹」問的就變成「通過判定的證據來自幾棵樹」
        # ——那一項於是在證據被判掉的時候安靜地變少，帶 `--head` 的那一趟因此看起來
        # 沒有歧義（DP-611 量到：20 PASS ＋ 2 blocker，帶了 --head 之後 11 PASS、
        # 9 FAIL、0 blocker）。走到這裡表示這份證據是 oracle 產的、命令登錄過，
        # 它說它量在哪一棵樹就是一件事實，判定結果不改變那件事實。
        if ev.get("measured_in"):
            measured_in.setdefault(ev["measured_in"], []).append(aid)
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
            if ev.get("measured_in"):
                tree_heads.setdefault(ev["measured_in"], set()).add(ev["head_sha"])

    # 呼叫者指名了差異的話，逐個去 git 驗那句話。驗過了那些 assertion 才算數——差異裡出現一個
    # 沒被指名的路徑，或者根本問不出那段差異，都退回原本的拒絕。
    for (ev_head, tree), aids in sorted(carried.items()):
        state, payload = _delta_within_allowance(
            tree, ev_head, head, delta_allows, report["notes"])
        if state == "ok":
            measured.setdefault(ev_head, []).extend(aids)
            if tree:
                tree_heads.setdefault(tree, set()).add(ev_head)
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
    # 不在的話上面記了一句話說這一層沒做）。同一條命令通常被好幾條 assertion 共用，所以去重再跑，
    # 而去重的鍵是 `rerun_key()`——它為什麼是那五樣寫在那支函式的 docstring 裡，這裡不抄
    # 第二份。
    if rerun:
        # 趟數在跑第一趟之前就說出來。這一層是唯一會真的花時間的一層，而「幾條 assertion」跟
        # 「要跑幾趟」不是同一個數字——不先說的話，看的人只能拿 assertion 數去估，然後把一趟
        # 21 分鐘的等待當成當掉。
        planned = {rerun_key(evidence[aid]) for aid in ids
                   if aid not in rows and aid in evidence}
        if planned:
            print(f"[verify-ac] 重跑這一層：{len(planned)} 個不同的量測樣式"
                  f"（{len(ids)} 條 assertion），所以要跑 {len(planned)} 趟。",
                  file=sys.stderr)
        cache = {}
        for aid in ids:
            if aid in rows or aid not in evidence:
                continue
            ev = evidence[aid]
            key = rerun_key(ev)
            if key not in cache:
                cache[key] = _rerun(*key, oracle, report["notes"])
            state, detail = cache[key]
            # 通過的那一條也要記下它憑什麼通過。以前這裡只在非 PASS 時寫，於是所有通過的
            # 斷言都掉到下面那個常數上，而一份把每一條的理由都印成同一句話的報告，說不出
            # 自己量到了什麼。
            mark(aid, state, detail)
        report["notes"].append(f"重跑了 {len(cache)} 趟（{len(ids)} 條 assertion 共用）")

    # 一張單交付到不只一個 repo 是常態（真樹上兩張，其中一張三棵），而那件事這張單自己
    # 就宣告過了。所以「證據落在幾棵樹」不是問題本身——**落在沒有宣告過的樹上**才是。
    # 宣告問不到的時候這份清單是空的，於是下面每一條比對都不成立，走回原本那條嚴格的路。
    declared = declared_landing(index_path)
    trees = [d for d in measured_in if d]
    report["trees_seen"] = sorted(trees)
    undeclared = [t for t in trees if t not in declared] if declared else trees
    # 同一棵樹上出現兩個 head 是真的歧義，宣告救不了它：那批證據量的不是同一次。
    split_tree = sorted(t for t, shas in tree_heads.items() if len(shas) > 1)
    multi_ok = bool(declared) and not undeclared and not split_tree

    # 沒有 --head 的時候，交付的 head 就是證據量到的那一棵樹。證據彼此不一致代表這幾條
    # assertion 量的不是同一棵樹——那不是「取一個」就好，取哪一個都會讓另一批證據變成沒看過的。
    # 除非那幾棵樹正是這張單宣告的落腳處：那時候「不只一個 head」是這張單本來的樣子，
    # 每一棵各記各的。
    if not head:
        if len(measured) > 1 and not multi_ok:
            report["blockers"].append("證據指向不只一棵樹，說不出要交付哪一個 head：")
            for sha, aids in sorted(measured.items()):
                report["blockers"].append(f"  {sha[:12]}: {', '.join(aids)}")
        elif measured:
            # 純量那一個取「宣告順序上第一棵有證據的樹」的 head——釋出尾段讀的是它，
            # 而順序由人寫在落腳處宣告裡，不是這裡挑的。單樹的單這個值不變。
            ordered = [t for t in declared if t in tree_heads] or sorted(tree_heads)
            head = (next(iter(tree_heads[ordered[0]])) if ordered
                    else next(iter(measured)))
    report["head"] = head
    report["heads"] = [{"tree": t, "head_sha": next(iter(tree_heads[t]))}
                       for t in ([d for d in declared if d in tree_heads]
                                 or sorted(tree_heads))]

    # 宣告過落腳處的單，證據落在宣告外的樹是紅的——那棵樹上任何無關的 commit 都會動到
    # 證據綁的 head，而這張單的產出不在那裡。以前這一條只在交付那支腳本裡，所以看報告的
    # 人看不到它。
    if declared and undeclared:
        report["blockers"].append("證據量在這張單沒有宣告的樹上：")
        for tree in sorted(undeclared):
            report["blockers"].append(f"  {tree}: {', '.join(measured_in[tree])}")
        report["blockers"].append("  這張單宣告的落腳處：" + "、".join(declared))
    if split_tree:
        report["blockers"].append("同一棵樹上的證據指向不只一個 head：")
        for tree in split_tree:
            report["blockers"].append(
                f"  {tree}: " + "、".join(sorted(s[:12] for s in tree_heads[tree])))

    # 宣告問不到的時候要說出來，不能安靜。這一項以前寫在交付那支腳本裡，所以看報告的
    # 人看不到「這一項沒有問到」——一個安靜的第三態，下一次就會被當成比過了。
    if trees and not declared:
        report["notes"].append(
            "這張單沒有宣告落腳處（或問不到），所以「證據量的樹是不是這張單宣告的那幾棵」"
            "這一項沒有被檢查；證據量在：" + "、".join(sorted(trees)))

    # 宣告了卻一條證據都沒有的那幾棵樹要被說出來。把 N 棵樹的量測全部釘在同一棵上，
    # 紀錄寫得出來而它對另外幾棵零綁定——那條路可能仍然是對的選擇，但它不能安靜
    # （DP-611 A-P6；標本是一張宣告三棵樹的單，21 條證據全記在同一棵）。
    for tree in declared:
        if tree not in tree_heads:
            report["notes"].append(
                f"這張單宣告了 {tree}，而沒有任何證據量在那裡——"
                "那棵樹上的改動沒有被任何一條 assertion 綁住")

    # 證據說得出自己是在哪一棵樹上量的，所以「那棵樹現在還在不在那個 commit」問得到它本人。
    if len(trees) > 1 and not multi_ok:
        report["blockers"].append("證據來自不只一棵樹，說不出要交付哪一個工作區：")
        for tree in sorted(trees):
            report["blockers"].append(f"  {tree}: {', '.join(measured_in[tree])}")
    elif not trees:
        # 揭露而不是放行：舊的證據沒有這個欄位，這一條就量不到。
        report["notes"].append(
            "證據沒有記下它在哪一棵樹上量的（DP-482 之前產生的），"
            "「量完之後還有沒有新 commit」這一條沒有被檢查")
    else:
        # 純量那一個給只讀得懂一棵樹的下游（釋出尾段）；`heads` 才說得完。
        report["measured_in"] = (report["heads"][0]["tree"] if report["heads"]
                                 else trees[0])
        # **每一棵各問一次。** 只問第一棵的話，另外幾棵的 head 動了看不出來——而那正是
        # 這張單要處理的那件事的另一半：紀錄綁得住的樹要真的被檢查過（DP-611）。
        for entry in (report["heads"] or [{"tree": trees[0], "head_sha": head}]):
            tree = entry["tree"]
            # 純量那一棵拿「要交付的 head」去比——`--head` 加 `--delta-allows` 的時候
            # 交付的 head 本來就走在證據前面，而那棵樹的 tip 該等於交付的那一個。其餘
            # 幾棵沒有「要交付的 head」可言，各拿自己記下的那一個。
            at = head if tree == report["measured_in"] else entry["head_sha"]
            tip = subprocess.run(["git", "-C", tree, "rev-parse", "HEAD"],
                                 capture_output=True, text=True).stdout.strip()
            if not tip:
                # 量測用的那棵樹已經不在（釋出尾段會移除 worktree）不是紅燈：這一條問的是
                # 「量完之後有沒有再 commit」，而那棵樹消失的時候這件事在這裡量不到。
                report["notes"].append(
                    f"量測用的工作區問不出 HEAD（{tree}）——"
                    "「量完之後還有沒有新 commit」這一條沒有被檢查")
            elif at and tip != at:
                shown_head, shown_tip = distinguish(at, tip)
                report["blockers"].append(
                    f"證據量的是 {shown_head}，但 {tree} 現在在 {shown_tip}——"
                    "量完之後又有 commit 落下去了")

    # 走到這裡還沒有判定的，是每一層都做完而且都成立的那些。理由要說出做完的是哪幾層
    # ——一層都沒做成的時候它不是通過，是沒有被檢查過。
    done = [name for key, name in LAYER_NAMES if report["layers"][key]]
    default = (PASS, "做完的那幾層都成立：" + "、".join(done))
    report["rows"] = [{"id": aid,
                       "state": rows.get(aid, default)[0],
                       "detail": rows.get(aid, default)[1]}
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
