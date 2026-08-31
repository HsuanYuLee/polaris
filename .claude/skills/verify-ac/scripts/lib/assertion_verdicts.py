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
import shutil
import subprocess
import sys
import tempfile

PRODUCER = "run-hardened-oracle.sh"

PASS = "pass"
FAIL = "fail"
UNMEASURABLE = "unmeasurable"


#: 一條 bullet 抽得出來的 assertion 編號。編號後面允許接字尾（`A-P1b`）——`\w*` 是貪婪的，
#: 最長匹配保證它停在第一個非詞字元上，所以 `A-P1 一般` 抽到的仍然是 `A-P1`。
#: 以前這裡是 `\d+\b`：`1` 與 `b` 之間沒有詞邊界，於是 `A-P1b` 整條抓不到——不是判成
#: 量不到，是不存在。fence 宣告十條而報告印九條，三層全綠（DP-617 撞到，DP-618 修）。
BULLET_ID = re.compile(r"^[ \t]*[-*][ \t]*\**([A-Z]+-[PN]\d+\w*)", re.M)

#: 一條看起來要當 assertion、但編號抽不出來的 bullet。範圍刻意窄到「開頭就是
#: `{字母}-{P 或 N}`」：真樹上 201 份 fence 裡不成 ID 的 bullet 有 81 筆，全部是寫成粗體
#: bullet 的小標與續行（`**正向表列**` 之類），沒有一筆長成這個樣子。放寬到「所有抽不出
#: 編號的 bullet」的話，這條指名會變成每張單都有的雜訊，然後被學會跳過。
BULLET_LOOKS_LIKE_ID = re.compile(r"^[ \t]*[-*][ \t]*\**([A-Z]+-[PN])", re.M)


def fence_text(index_path):
    """單裡所有凍結塊的內文接起來。

    Args:
        index_path: `{issue}/index.md`。
    Returns:
        每個 fence 的內文以換行接起來的一整段；沒有 fence 時回空字串。
    """
    body = open(index_path, encoding="utf-8").read()
    return "\n".join(re.findall(
        r"<!-- POLARIS-FROZEN-[A-Z]+-BEGIN -->(.*?)<!-- POLARIS-FROZEN-[A-Z]+-END -->",
        body, re.S))


def assertion_ids(index_path):
    """單裡凍結的 assertion ID，照人簽下去的順序。

    Args:
        index_path: `{issue}/index.md`。
    Returns:
        去重後的 ID 列表；沒有 fence 或 fence 裡沒有 ID 時回空的。

    比對的樣式容得下有沒有粗體：只認粗體那一種的話，有人拿掉星號就會靜靜地找不到——
    而在這裡找不到任何東西，讀起來像「沒有東西要證明」。

    抽不出編號的那幾條由 `unrecognized_assertion_bullets()` 說出來，不在這裡默默消失。
    """
    return list(dict.fromkeys(BULLET_ID.findall(fence_text(index_path))))


def unrecognized_assertion_bullets(index_path):
    """fence 裡看起來要當 assertion、卻抽不出編號的那幾條。

    Args:
        index_path: `{issue}/index.md`。
    Returns:
        那幾條 bullet 的原文（去掉前後空白）；沒有就回空的。

    **這個清單非空就是一個要擋人的問題，不是一句提醒。** 一條抽不出編號的 assertion 不會
    變成「量不到」——它會從逐條清單、從交付紀錄要檢查的那組 ID 裡一起消失，而少掉一條的
    報告跟做滿的報告長得一模一樣。
    """
    out = []
    for line in fence_text(index_path).splitlines():
        if BULLET_LOOKS_LIKE_ID.match(line) and not BULLET_ID.match(line):
            out.append(line.strip())
    return out


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


# 一個 token 要長成什麼樣才算「一條路徑」。放寬一點會把 grep 的樣式當成路徑，收緊一點會漏掉
# `bash issues/x/probe.sh` 這種相對寫法——所以兩條都算：明確的路徑開頭，或者帶著副檔名。
_PATHISH_PREFIX = ("/", "./", "../", "~/")
_PATHISH_SUFFIX = (".sh", ".py", ".json", ".md", ".mjs", ".js", ".ts", ".txt", ".yaml", ".yml")

# 會被交一個檔案去跑的那幾個。它們後面第一個像路徑的 token，就是「這條命令要跑的東西」。
_INTERPRETERS = ("bash", "sh", "zsh", "python3", "python", "node")


def _pathish(token):
    """這個 token 看起來是不是一條路徑。Args: token。Returns: bool。"""
    if "/" not in token or token.startswith("-"):
        return False
    return token.startswith(_PATHISH_PREFIX) or token.endswith(_PATHISH_SUFFIX)


def _without_substitutions(command):
    """把 `$(…)` 與反引號那幾段整段換成一個 `$`，剩下的才拿去找路徑。

    Args:
        command: 命令字串。
    Returns:
        同一條命令，命令替換的那幾段各換成一個 `$`。

    換成 `$` 而不是拿掉，是為了讓它黏在後面那一段上：`"$(… find X)/probes/probe.sh"`
    變成 `$/probes/probe.sh`，帶著 `$` 的 token 上面那一層本來就會跳過。換成空白的話
    後半會自己成為一個 token，看起來就是一條不存在的絕對路徑——那正好是要放行的寫法。
    """
    out = []
    i = 0
    depth = 0
    while i < len(command):
        ch = command[i]
        if depth == 0 and command.startswith("$(", i):
            depth = 1
            i += 2
            continue
        if depth:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    out.append("$")
            i += 1
            continue
        if ch == "`":
            end = command.find("`", i + 1)
            if end < 0:
                break
            out.append("$")
            i = end + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def unstartable_path(command, cwd):
    """這條命令要跑的那個檔案現在還在不在。

    Args:
        command: 登錄下來的那條命令，原樣。
        cwd: 重跑時站的地方；空的就用現在站的地方。
    Returns:
        那個檔案的路徑（原樣），如果它不存在；否則 None。

    **只看第一個簡單命令要跑的那個檔案，不看命令裡所有路徑。** 看全部的話，一條在斷言
    「某個東西不該存在」的量測會被這一層從紅降成量不到——那是拿一句安慰換掉一個真的判定。
    要跑的那個檔案不在，才是「這條登錄下來的命令已經指不到東西了」。

    帶著還沒展開的 `$(…)`、反引號、別的變數或萬用字元的一律不算：那些正是「執行當下才問
    位置」的寫法，它們現在長什麼樣要跑過才知道。`$HOME` 例外，它展開得出來，而且它就是
    今天放行、明天作廢的那一種。
    """
    home = os.path.expanduser("~")
    head = re.split(r"[|;&\n]", _without_substitutions(command or ""), 1)[0]
    tokens = [t for t in re.findall(r"""[^\s"'`|;&<>]+""", head)]
    # 前面那幾個 VAR=value 是環境設定，不是要跑的東西。
    while tokens and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
        tokens.pop(0)
    if not tokens:
        return None
    if os.path.basename(tokens[0]) in _INTERPRETERS:
        target = next((t for t in tokens[1:] if _pathish(t)), None)
    else:
        target = tokens[0] if _pathish(tokens[0]) else None
    if not target:
        return None
    resolved = target.replace("${HOME}", home).replace("$HOME", home)
    if "$" in resolved or "*" in resolved or "?" in resolved:
        return None
    if resolved.startswith("~/"):
        resolved = home + resolved[1:]
    if not os.path.isabs(resolved):
        resolved = os.path.join(cwd or os.getcwd(), resolved)
    return None if os.path.exists(resolved) else target


def _rerun_group(command, cwd, tools, members, oracle, notes):
    """把這一組跑一趟，組裡每一條 assertion 在同一份輸出上各自判。

    Args:
        command: 要跑的命令；cwd: 在哪棵樹上跑（空的就用現在站的地方）。
        tools: 證據記下的工具清單，原樣交還給 oracle 的 `--require-tool`。
        members: `[(assertion id, expect, forbid)]`——決定「在那份輸出裡找什麼」的那幾樣。
        oracle: `run-hardened-oracle.sh` 的路徑。
        notes: 說明會被 append 進來的清單。
    Returns:
        `{assertion id: (PASS|FAIL|UNMEASURABLE, 說明)}`，組裡每一條都有自己的一筆。

    **一組一趟，不是一條一趟。** 分開兩條 assertion 的只有正負向樣式，而樣式不必重新
    執行一次命令才問得出來——`run-hardened-oracle.sh --assertion` 本來就是在同一份輸出
    上逐條判、逐條寫。把樣式放進「要跑幾趟」的鍵裡，換到的不是嚴謹，是同一條命令被跑 N 次。

    **而且那樣換到的答案可能是假的。** 一條命令的輸出在兩趟之間變了的時候，兩條互斥的
    assertion 會各自看到對自己有利的那一趟，於是同時綠——它們判的根本不是同一份輸出。
    同一趟裡矛盾看得見：一條綠、另一條紅。所以這件事表面上是省時間，實際上是把一個
    會靜靜給出假綠的地方修成會紅。

    跑不起來是 UNMEASURABLE 不是 FAIL：oracle 不在、證據沒說跑的是哪一條命令，說的都是
    「這一趟沒問到」，而把問不到讀成沒過，跟把它讀成通過一樣是在編一個答案。

    工具要交還，是因為 oracle 會把 PATH 釘死成宣告的那幾個目錄，只有 `--require-tool`
    探到的才會被 symlink 進去。不交還的話，一條當初靠 `gh` 才跑得起來的命令重跑時
    exit 127，而那份證據本身是好的——這一層就從「再驗一次」變成「懲罰用過外部工具的單」。
    """
    def everyone(state, detail):
        return {aid: (state, detail) for aid, _, _ in members}

    if not oracle or not os.path.exists(oracle):
        return everyone(UNMEASURABLE, f"重跑不了：找不到 {oracle or 'run-hardened-oracle.sh'}")
    if not command:
        return everyone(UNMEASURABLE, "重跑不了：證據沒說它跑的是哪一條命令")
    if cwd and not os.path.isdir(cwd):
        # 量測用的樹不在了不是紅燈，也不是「這一層做不成」：釋出尾段的前一步就是移除
        # 那個 worktree，所以每一張在 worktree 開工的單走到這裡都會撞上。退回現在站的
        # 地方重跑，並且說出來——一個安靜的退路下一次會被當成原本就在那棵樹上跑的。
        notes.append(f"重跑退回現在站的地方：量測用的工作區 {cwd} 已經不在")
        cwd = ""

    # 每一組要有自己的輸出路徑，這是 oracle 的要求，也是這件事的重點：一組一份判定。
    # 寫進暫存目錄，因為這一層是「再驗一次」——它不得覆蓋單自己那幾份被判定過的證據。
    workdir = tempfile.mkdtemp(prefix="verify-ac-rerun-")
    try:
        argv = ["bash", oracle, "--command", command]
        outs = {}
        for aid, expect, forbid in members:
            outs[aid] = os.path.join(workdir, aid.replace("/", "_") + ".json")
            argv += ["--assertion", aid]
            for pattern in expect or ():
                argv += ["--expect-evidence", pattern]
            for pattern in forbid or ():
                argv += ["--forbid-evidence", pattern]
            argv += ["--evidence-out", outs[aid]]
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
        return {aid: _one_group_verdict(outs[aid], command, cwd, done)
                for aid, _, _ in members}
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def _why_group(payload, done):
    """從這一組自己的證據拼出「為什麼紅的」，回一行字。

    Args:
        payload: 那一組的證據內容；done: 整趟執行的結果，證據拼不出東西時的退路。
    Returns:
        一行說明。

    **要帶著命令自己說的那句話**，不能只有 oracle 的判定。`command exited 127` 說得出
    它紅了，說不出 `gh: command not found`——而後者才是人要看的東西。一個判紅而說不出
    理由的關卡，跟一個沒有理由的通過一樣不能用。

    **不從整趟的 stderr 上刮**：一趟裡好幾組，oracle 把每一組的 marker 都印在後面，
    所以最後那幾行是別條 assertion 的話。命令自己的兩個串流原樣記在每一組的證據裡，
    那才是這一組該讀的地方。
    """
    parts = []
    stream = payload.get("stderr") or ""
    lines = [ln for ln in stream.splitlines() if ln.strip()]
    if not lines:
        lines = [ln for ln in (payload.get("stdout") or "").splitlines() if ln.strip()]
    parts += lines[-(WHY_LINES - 2):] if lines else []
    parts += [x for x in (payload.get("marker"), payload.get("detail")) if x]
    return " / ".join(parts) if parts else _why(done)


def _one_group_verdict(out_path, command, cwd, done):
    """把 oracle 為某一條 assertion 寫下的那份判定，翻成這一層的三種結果。

    Args:
        out_path: 那一組的證據路徑；command / cwd: 這一趟跑的東西，只用來解釋失敗。
        done: 整趟執行的結果，用來在證據不存在時說出為什麼。
    Returns:
        (PASS|FAIL|UNMEASURABLE, 說明)。

    **三種結果的意思一個字都不改**，只是問的對象從離場碼換成那一組自己的判定：
    oracle 的 `FAIL` 是命令自己紅了（重跑一次是紅的），`NOT_PASS` 是命令綠了卻沒有它
    要求的證據（重跑量不到）。離場碼答不了這件事——一趟裡好幾組，而它只有一個。

    **證據不在是第三種**，不是其中一種的溫和版本：oracle 在跑起來之前就死了（工具探不到、
    參數不合法），那一趟沒有任何一組被判過。
    """
    try:
        with open(out_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError):
        return UNMEASURABLE, "重跑量不到（這一趟沒有留下判定）：" + _why(done)

    verdict = payload.get("verdict")
    detail = _why_group(payload, done)
    if verdict == "PASS":
        return PASS, "重跑一次仍然是綠的"
    # 非零有兩種來源，而它們要的下一步不一樣：「這一趟量到了，是紅的」「這一趟沒問到」，
    # 都假設那條命令還跑得起來。而一張單交付之後會被重算搬走，於是登錄下來的那條命令要跑
    # 的檔案根本不在了——那既不是紅也不是沒問到，是這份證據再也重跑不了（DP-595）。
    # 它以前分別落進上面那兩句話：直譯器開不到檔回 2、oracle 把它翻成 FAIL 回 1，
    # 所以讀起來是「重跑一次是紅的」——一張好好的單看起來像交付壞了。
    gone = unstartable_path(command, cwd)
    if gone:
        return UNMEASURABLE, (
            f"重跑指向一個不存在的位置：這條命令要跑的 {gone} 現在找不到。"
            "這不是「量到了是紅的」，也不是「這一趟沒問到」——是這條登錄下來的命令本身"
            "已經指不到東西了（單的位置會被重算，改成執行當下用 spine-loop-state.sh find 問）。"
            + detail)
    if verdict == "FAIL":
        return FAIL, "重跑一次是紅的：" + detail
    return UNMEASURABLE, "重跑量不到：" + detail


def rerun_exec_key(ev):
    """決定「要跑幾趟」的鍵：命令、在哪棵樹跑、要哪些工具。**只有這一份。**

    Args:
        ev: 一份 oracle 產的證據。
    Returns:
        三樣組成的 tuple，正好是 `_rerun_group` 前三個參數。

    **正負向樣式刻意不在鍵裡。** 它們決定的是「在那份輸出裡找什麼」，不是「跑什麼」——
    同一條命令的同一份輸出，好幾條 assertion 各自拿自己的樣式去判就好。以前把樣式也
    算進鍵裡，於是十條共用同一支 selftest 的 assertion 要跑十趟同一件事。

    這不是把樣式放掉：`_rerun_group` 拿著組裡每一條自己的樣式，逐條判、逐條回報。少了
    那一步才是「第二條拿到第一條的答案」——一條沒被量到的 assertion 看起來就跟過了一樣。

    抽成一支是因為它有兩個呼叫者：跑之前數趟數的那一次，跟跑的時候。抄成兩份的話預告的
    數字會跟實際的漂開，而漂掉的那一刻預告看起來仍然很正常。
    """
    return (ev.get("command", ""),
            ev.get("measured_in") or "",
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
    # 抽不出編號的那幾條先說出來，而且在「一個 ID 都沒有」之前說：整份 fence 的編號全部
    # 打錯的時候，兩件事同時成立，而只印後面那一句的話，讀的人會去找一個根本不存在的 fence。
    for bullet in unrecognized_assertion_bullets(index_path):
        report["blockers"].append(
            f"{index_path} 的 fence 裡有一條看起來要當 assertion、卻抽不出編號的："
            f"{bullet} —— 它不在下面任何一條裡，也不會被交付紀錄檢查")
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
    # 不在的話上面記了一句話說這一層沒做）。同一條命令通常被好幾條 assertion 共用，**而它
    # 們共用的是同一趟執行，不是同一個判定**：分組的鍵是 `rerun_exec_key()`（跑什麼），
    # 每一條自己的正負向樣式跟著它進那一組，在同一份輸出上各自判。為什麼樣式不在鍵裡，
    # 寫在那支函式的 docstring 裡，這裡不抄第二份。
    if rerun:
        # 分組只算一次，預告與實際讀的是同一份。以前是「跑之前算一次、跑的時候用另一個
        # 快取再算一次」——兩個算式一致的時候沒有人看得出來它們是兩份，而漂開的那一刻
        # 預告仍然看起來很正常。
        groups = {}
        for aid in ids:
            if aid in rows or aid not in evidence:
                continue
            ev = evidence[aid]
            groups.setdefault(rerun_exec_key(ev), []).append(
                (aid, tuple(ev.get("expect_evidence") or ()),
                 tuple(ev.get("forbid_evidence") or ())))
        # 趟數在跑第一趟之前就說出來。這一層是唯一會真的花時間的一層，而「幾條 assertion」跟
        # 「要跑幾趟」不是同一個數字——不先說的話，看的人只能拿 assertion 數去估，然後把一趟
        # 21 分鐘的等待當成當掉。
        graded = sum(len(m) for m in groups.values())
        if groups:
            print(f"[verify-ac] 重跑這一層：{graded} 條 assertion 分成 "
                  f"{len(groups)} 組不同的量測命令（這張單共 {len(ids)} 條 assertion），"
                  f"所以要跑 {len(groups)} 趟；每一趟裡每一條各自判自己的樣式。",
                  file=sys.stderr)
        for key, members in groups.items():
            verdicts = _rerun_group(*key, members, oracle, report["notes"])
            for aid, _expect, _forbid in members:
                state, detail = verdicts[aid]
                # 通過的那一條也要記下它憑什麼通過。以前這裡只在非 PASS 時寫，於是所有通過的
                # 斷言都掉到下面那個常數上，而一份把每一條的理由都印成同一句話的報告，說不出
                # 自己量到了什麼。
                mark(aid, state, detail)
        report["notes"].append(
            f"重跑了 {len(groups)} 趟，{graded} 條 assertion 各自判過自己的樣式")

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
