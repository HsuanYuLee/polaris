#!/usr/bin/env python3
"""把每一張單放到它的狀態說的那一格，並把推導結果寫回單自己身上。

位置是狀態的投影，不是第二個權威。以前投影只有兩格（活躍區／`archive/`），答得了「做完了
沒」，答不了「在哪一站」。這支把解析度提高到七格，權威沒有換人。

    backlog/            立案了，還沒開工
    in-progress/        兩個閘之間
    in-review/          送審中（只有會動到 code 的單走得到）
    done/               我這邊做完了，還沒上線
    released/{日期}/    真的出去了，日期就是那天
    closed/{日期}/      不再執行——放棄、被取代、需求消失，日期就是決定的那天
    triage/             推導不出來——在等人歸位

`closed` 與 `done` 的差別是「不做了」與「做完了」，兩者都停止打轉但結論相反。合成一格的話
那個差別就只剩在 JSON 裡，而翻資料夾的人看到的是一堆看起來都做完了的單。

**推導出來的東西要寫回單身上**（`.spine/placement.json`），不是只反映在路徑上。理由是別的
程式要問「這張單收斂了沒」時，唯一能問的東西不該是它的路徑：memory 的退休判定以前就是看
`archive/` 這個位置，而那條路徑一旦多一層資料夾就會靜靜地失效。位置給人看，`placement.json`
給程式讀，兩者同一次推導產出，所以不會有第二個答案。

停滯不進位置。一張掛在 in-review 兩個月的單，`in-review/` 是**正確的**位置——「這樣算不算
太久」由看的人決定，不由門檻代決。那件事屬於索引，不屬於這裡。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from datetime import datetime, timezone

# 七格。順序有意義：報告按這個順序印，而它就是一張單往前走的順序。`closed` 是唯一一個
# 不在那條路上的——它是岔出去的終點，給「不再執行」用，而那跟「做完了」是兩件事。
BACKLOG, IN_PROGRESS, IN_REVIEW, DONE, RELEASED, CLOSED, TRIAGE = (
    "backlog", "in-progress", "in-review", "done", "released", "closed", "triage")
SLOTS = (BACKLOG, IN_PROGRESS, IN_REVIEW, DONE, RELEASED, CLOSED, TRIAGE)

# 有結論的兩格。它們不進「還沒出去的單」那份清單——不是因為它們不重要，是因為那份清單
# 問的是「還有什麼在中間態打轉」，而這兩格都已經停止打轉了。
SETTLED_SLOTS = (RELEASED, CLOSED)

# 這兩格底下多一層日期。終局要知道時間——一張單走到終點卻說不出是哪天走到的，那份清單
# 只能照名字翻。
DATED_SLOTS = (RELEASED, CLOSED)

# 日期查不到時 `closed/` 底下的那一層。`released/` 沒有這一格：一張單算不算釋出過看的是
# 它自己的釋出紀錄，而那份紀錄本來就帶著日期。「不做了」不一樣——理由知道、日期不知道
# 是舊層真實的狀態，而把記帳當天填進去會讓那個空白看不出來。
UNDATED = "undated"

# 轉場期還會遇到的舊格子。它不是一個狀態，是上一版投影留下的形狀。
LEGACY_SLOT = "archive"

# 舊形狀留下來的群組層。**只認得、不再產生**：它們是 DP-551 那一版的疤，重算會把底下的
# 單搬到它們該去的地方，空掉之後 `prune_empty` 自己收掉。認得它是為了在轉場期間不掉單。
LEGACY_PARENT_PREFIX = "_"

# 上游快照寫在單的 `index.md` 裡，夾在這兩行之間。**只有這中間會被重寫**——一張自己的單
# 裡面寫的東西是人寫的，重算不得碰它。
UPSTREAM_BEGIN = "<!-- POLARIS-UPSTREAM-BEGIN -->"
UPSTREAM_END = "<!-- POLARIS-UPSTREAM-END -->"

# 會動到 code 的工作才走得到 in-review。這個訊號已經記在單的狀態裡（開輪次時決定的領域），
# 不需要另外標一次。
CODE_PACK = "swe-knowledge"

PLACEMENT_SCHEMA = 1

# 不參與判定的目錄少到這個數以內就逐個指名。上限存在的理由跟印數量一樣：
# 幾百筆逐個印出來等於沒印，而幾筆只給總數等於沒說。
ABSTAINED_NAME_THRESHOLD = 20

# 沒走過脊椎的單，狀態在別的地方——JIRA、某張看板、某個試算表。**核心不認得那些東西**，
# 它只認得一行宣告：某個命名空間由哪一條命令回答「這張單在哪一格」。形狀跟 `refinement`
# 的 `ENVIRONMENT-{名}` 是同一套，理由也一樣——核心去讀，不自己抄一份。
#
#     <!-- {任意前綴}-ISSUE-STATE-{命名空間}: {命令} -->
#
# 命令拿到單名，印一行 JSON：`slot` 必有，`released` 另帶 `released_on`，其餘欄位原樣帶進
# `placement.json` 與非釋出清單（`updated`、`mine` 就是那份清單要的）。它 exit 非 0 就是這次
# 沒問到，那張單落 triage 並被指名——不沿用上一次的答案，也不讓整支停掉（S-N3）。
RESOLVER_DECLARATION = re.compile(
    r"<!--\s*[A-Za-z0-9_-]*ISSUE-STATE-([A-Za-z0-9_.-]+):\s*(.+?)\s*-->")

RESOLVER_TIMEOUT_SECONDS = 30

# 解析器的離場碼分兩種，報告上也要是兩種：2 ＝ 這次沒問到（下一次可能問得到），
# 1 ＝ 問到了但對照不到（對照表不夠用）。
RESOLVER_COULD_NOT_ASK = 2

MARKER_UNKNOWN_SLOT = "POLARIS_ISSUE_STATE_SLOT_UNKNOWN"

# `git log --format=%cs` 印出來的那一行長這樣。
DATE_LINE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# 一次執行 ＝ 一個時間點的快照。見 `slot_from_resolver`。
_RESOLVER_CACHE: dict[tuple[str, str], tuple[str, str, dict]] = {}
_TOUCHED_CACHE: dict[str, str | None] = {}


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: str) -> dict | None:
    """讀得出來就回 dict，讀不出來回 None。壞掉的檔案不當成空的——空的會安靜地通過。"""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def namespaces(issues_root: str) -> list[str]:
    """`issues/` 底下每一個命名空間。名字不影響任何判定，這裡只是列出來。"""
    if not os.path.isdir(issues_root):
        return []
    return sorted(name for name in os.listdir(issues_root)
                  if not name.startswith(".")
                  and os.path.isdir(os.path.join(issues_root, name)))


def chain_of(detail: dict) -> list[str]:
    """這張單掛在哪幾張單底下——鏈頂在前，直接母單在後。沒有母單就回空的。

    鏈由那個命名空間的解析器回答，核心不認得任何一個外部系統的欄位名，也不認得「Epic」
    這個詞：它只把這串名字原樣接成路徑上的幾層。解析器不回這一項的單就住在格子底下，
    重算不因此停掉——一個問不到的歸屬不得讓一張問得到狀態的單失去位置。
    """
    chain = detail.get("chain") or []
    if isinstance(chain, str):
        chain = [chain]
    return [str(k).strip() for k in chain if str(k).strip()]


def tickets(issues_root: str) -> list[tuple[str, str]]:
    """每一張單：回 (命名空間, 單的絕對路徑)。

    命名空間底下，**不是格子名**的那一層目錄就是單。格底下還可能有兩種不是單的層：

        released/{日期}/{單}            日期層——`released/` 與 `closed/` 專用
        {格}/_{母單}-{標題}/{單}         舊的群組層——只認得，不再產生

    而**單底下也可以有單**（`{格}/{母單}/{子單}/{孫單}`），那是這棵樹的主軸：位置說的是
    歸屬。單底下哪些目錄才是單，判準寫在 `_walk_ticket`——不是「每一個」。

    用深度猜的話，還沒分日期的那些會被當成日期層，而它們底下沒有單，於是整批安靜地從總數
    裡消失——實測一次弄丟 100 張。所以這裡逐層說出自己在看哪一種層。
    """
    found = []
    for namespace in namespaces(issues_root):
        base = os.path.join(issues_root, namespace)
        for name in sorted(os.listdir(base)):
            path = os.path.join(base, name)
            if name.startswith(".") or not os.path.isdir(path):
                continue
            if name not in SLOTS and name != LEGACY_SLOT:
                found.append((namespace, path))
                _walk_ticket(namespace, path, found)
                continue
            _walk_slot(namespace, path, found, dated=name in DATED_SLOTS)
    return found


def _walk_slot(namespace: str, path: str, found: list, dated: bool) -> None:
    """一格底下逐個看。`dated` 表示這一格還可能有日期層——走過一次就沒有了。"""
    for name in sorted(os.listdir(path)):
        inner = os.path.join(path, name)
        if name.startswith(".") or not os.path.isdir(inner):
            continue
        if name.startswith(LEGACY_PARENT_PREFIX):
            _walk_slot(namespace, inner, found, dated=False)
            continue
        if dated and not os.path.isdir(os.path.join(inner, ".spine")):
            _walk_slot(namespace, inner, found, dated=False)
            continue
        found.append((namespace, inner))
        _walk_ticket(namespace, inner, found)


def _walk_ticket(namespace: str, ticket_dir: str, found: list) -> None:
    """一張單底下**帶著 `.spine/` 的**那些目錄是另一張單。其餘的不是，穿過去也不看。

    這裡不能寫成「單底下的每一個目錄都是另一張單」。真實的樹上不成立：舊層在單裡放過
    `tasks/`、`T1/`、`evidence/`、`scripts/`、`migrations/` 這些目錄，實測 259 個。把它們
    當成單的那一版，會替每一個算出一個 `{命名空間}/triage/tasks` 之類的目的地——一個不是
    單號的層，而且好幾張單的 `T1` 全部指向同一個地方。

    判準跟 A-P5 問的是同一件事（「有 `.spine/` 的單」），而且它不需要認得任何外部系統的
    命名慣例：樹裡的巢狀只由重算自己造出來，而它造的時候一定會把推導結果寫回那張單的
    `.spine/`。轉場期還會撞到舊的群組層，那一種穿過去。
    """
    for name in sorted(os.listdir(ticket_dir)):
        inner = os.path.join(ticket_dir, name)
        if name.startswith(".") or not os.path.isdir(inner):
            continue
        if name.startswith(LEGACY_PARENT_PREFIX):
            _walk_slot(namespace, inner, found, dated=False)
            continue
        if not os.path.isdir(os.path.join(inner, ".spine")):
            continue
        found.append((namespace, inner))
        _walk_ticket(namespace, inner, found)


def release_record(ticket_dir: str) -> dict | None:
    """這張單真的出去過沒有。回釋出紀錄，沒有就回 None。

    **交付紀錄不算釋出紀錄。** `delivery.json` 是第二個閘在釋出**之前**寫的交付意向，它的
    `judged_at` 是判定日不是釋出日。拿它當釋出日會讓一張還沒上線的單落進 `released/`。
    """
    return read_json(os.path.join(ticket_dir, ".spine", "release.json"))


def pack_of(state: dict) -> str | None:
    """這張單開輪次時記下的領域。

    它住在 `knowledge_pack.pack`，不是 top-level `pack`——這支第一版讀錯了地方，而儀器的
    fixture 自己寫了一個扁平的 `pack` 欄位，於是那個錯誤在假資料上永遠是綠的。真實的單
    一份都沒有 top-level `pack`。
    """
    return (state.get("knowledge_pack") or {}).get("pack")


def last_touched(issues_root: str, relative: str, name: str) -> str | None:
    """這張單上次**被動過**是哪一天——問 `issues` 自己的 git 歷史。

    狀態檔裡的時間戳都不能用：`rounds` 根本沒有時間戳，而 `landings` 每跑一次 `where` 就
    多一筆，所以它記的是「上次有人問這張單在哪」。實測 DP-440 最後一輪落在 2026-08-01，
    landings 卻寫著今天——照那個算，每一張老單都會顯示 0 天前。

    目錄的 mtime 同樣不行：搬一次家就推到今天。commit 才是工作真的發生過的痕跡。

    **只看活文件，不看整個目錄。** `.spine/` 是流程自己的簿記——補一次落腳處、記一次輪次
    狀態都會產生 commit，而那不是有人在做這張單。實測 DP-440：整個目錄的最後一筆是今天
    （一個只改 `.spine/` 的記帳 commit），`index.md` 是 08-04。後者才是答案。

    答案照單名記住。搬完之後要再調查一次，那時候舊路徑已經不在了，git 會回空的——而
    「0 天前」與「不知道」在這份清單上是兩件不同的事。
    """
    if name in _TOUCHED_CACHE:
        return _TOUCHED_CACHE[name]
    answer = None
    try:
        result = subprocess.run(
            # --follow：單會換格子，換格子就是 rename。不跟著走的話，每一次搬家都會把
            # 所有單的「上次動過」清成「不知道」——它們的歷史還在，只是掛在舊路徑上。
            # --numstat：純改名是 `0  0`。搬家本身也是一個 commit，算進去的話每一次重算
            # 都會把所有單刷成「今天動過」，而「兩個月沒動的 code review」就永遠浮不出來。
            ["git", "-C", issues_root, "log", "--follow", "--format=%cs", "--numstat",
             "--", os.path.join(relative, "index.md")],
            capture_output=True, text=True, timeout=RESOLVER_TIMEOUT_SECONDS)
        if result.returncode == 0:
            answer = first_commit_that_changed_lines(result.stdout)
    except (OSError, subprocess.SubprocessError):
        answer = None
    _TOUCHED_CACHE[name] = answer
    return answer


def touched_at(issues_root: str, relative: str) -> str | None:
    """**這個路徑**上的活文件，上次真的被改過是哪一天。問不到回 None。

    不走 `last_touched`：那一支照**單名**記住答案，而這裡問的正好是同一個單號的兩個不同
    路徑——共用一份按名字記的快取，兩邊會拿到同一個日期，而那個日期正是要拿來分辨它們的。

    「不知道」與「今天」是兩件事。問不到就回 None，讓報告寫「不知道」——把記帳那天填進去
    的話，一個看得出來的空白會變成一個看不出來的謊。
    """
    try:
        result = subprocess.run(
            ["git", "-C", issues_root, "log", "--follow", "--format=%cs", "--numstat",
             "--", os.path.join(relative, "index.md")],
            capture_output=True, text=True, timeout=RESOLVER_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return first_commit_that_changed_lines(result.stdout)


def first_commit_that_changed_lines(log: str) -> str | None:
    """`git log --format=%cs --numstat` 的輸出裡，第一個真的改過行數的 commit 的日期。

    不能用 `--diff-filter=M` 代替：搬家與修改落在同一個 commit 時，git 把那個路徑歸類成
    R（改名），`M` 就漏掉它，於是「上次動過」變成「不知道」。而記一輪就會觸發重算，那個
    組合在真實情況下很常見。行數騙不了人——純改名是 0 0。
    """
    date = None
    for line in log.splitlines():
        line = line.strip()
        if not line:
            continue
        if DATE_LINE.match(line):
            date = line
            continue
        parts = line.split("\t")
        if len(parts) >= 2 and date:
            added, deleted = parts[0], parts[1]
            # 二進位檔是 `-  -`，那也是一次真的改動。
            if added != "0" or deleted != "0":
                return date
    return None


def slot_from_spine(ticket_dir: str) -> tuple[str, str, dict] | None:
    """走過脊椎的單：狀態檔就是權威。回 (格子, 依據, 細節)，沒有狀態檔回 None。"""
    state = read_json(os.path.join(ticket_dir, ".spine", "loop-state.json"))
    if state is None:
        return None

    if state.get("status") == "closed":
        # 「不再執行」不是「做完了」。兩者都停止打轉，但一張被放棄或被取代的單，下一個
        # 讀到它的人需要知道是哪一種——擠進 done 的話那個差別就只剩在 JSON 裡。
        return CLOSED, "loop-state", {"why": state.get("closed_reason") or "不再執行",
                                      # 終局要知道時間。查不到就明講 undated——那不是一個
                                      # 日期，而把記帳當天填進去會讓一個查得到的空白變成
                                      # 一個查不出來的謊。
                                      "closed_on": state.get("closed_on") or UNDATED,
                                      "mine": True}

    if state.get("status") == "converged":
        release = release_record(ticket_dir)
        if release and release.get("released_on"):
            return RELEASED, "loop-state+release", {"released_on": release["released_on"],
                                                    "version": release.get("version"),
                                                    "mine": True}
        return DONE, "loop-state", {"why": "收斂了，但單身上沒有釋出紀錄",
                                    "mine": True}

    station = state.get("station") or "engineering"
    if station == "refinement" or not (state.get("rounds") or []):
        return BACKLOG, "loop-state", {"station": station, "mine": True}
    if station == "verify-ac" and pack_of(state) == CODE_PACK:
        return IN_REVIEW, "loop-state", {"station": station, "mine": True}
    if station == "verify-ac":
        # 不會動到 code 的工作沒有 review 這一站——它從 engineering 直接走到判定。
        return IN_PROGRESS, "loop-state", {
            "station": station, "mine": True,
            "why": f"pack 不是 {CODE_PACK}，沒有 review 這一格"}
    return IN_PROGRESS, "loop-state", {"station": station, "mine": True}


def skills_root() -> str:
    """`.claude/skills/`。錨在這支腳本自己的位置——它住在 `{skills}/{skill}/scripts/lib/`。

    不用 git 求根：worktree 裡 `issues/` 根本不存在，而這支要掃的是 skill，不是單。
    """
    here = os.path.abspath(__file__)
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(here))))


def declared_resolvers(root: str | None = None) -> dict[str, str]:
    """掃所有 SKILL.md，回 {命名空間: 命令}。核心不認得任何一個命名空間的名字。"""
    root = root or skills_root()
    found: dict[str, str] = {}
    if not os.path.isdir(root):
        return found
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        if "SKILL.md" not in filenames:
            continue
        try:
            with open(os.path.join(dirpath, "SKILL.md"), encoding="utf-8") as handle:
                text = handle.read()
        except OSError:
            continue
        for namespace, command in RESOLVER_DECLARATION.findall(text):
            found.setdefault(namespace, command)
    return found


def slot_from_resolver(command: str, ticket_name: str) -> tuple[str, str, dict]:
    """問那條宣告出來的命令。回 (格子, 依據, 細節)——問不到就是 triage，不是猜一格。

    命令自己說不出答案（exit 非 0）與問不到（跑不起來、逾時）在報告上長得不一樣，但兩者
    都落 triage：一個推導不出來的狀態不得被寫成一個看起來像推導出來的位置。

    同一次執行裡問過的不再問第二次。這不只是省一趟網路——搬完之後要再調查一次才印得出
    「搬了幾張」，而如果第二次問到的答案跟第一次不一樣，報告就會跟磁碟上真正發生的事矛盾。
    一次重算是一個時間點的快照。
    """
    key = (command, ticket_name)
    if key not in _RESOLVER_CACHE:
        _RESOLVER_CACHE[key] = _ask_resolver(command, ticket_name)
    return _RESOLVER_CACHE[key]


def _ask_resolver(command: str, ticket_name: str) -> tuple[str, str, dict]:
    # 宣告出來的命令寫的是 repo 相對路徑（`.claude/skills/…`），跟這個 repo 每一份散文裡的
    # 命令同一個形狀。所以它從 repo 根跑，不從呼叫者剛好站的地方跑——後者會讓同一張單在
    # 不同的 cwd 得到不同的答案。
    repo_root = os.path.dirname(os.path.dirname(skills_root()))
    try:
        result = subprocess.run(command.split() + [ticket_name],
                                capture_output=True, text=True, cwd=repo_root,
                                timeout=RESOLVER_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError) as error:
        return TRIAGE, "resolver-unreachable", {
            "why": f"這次沒問到（{type(error).__name__}）——不沿用上一次的答案"}

    answer = (result.stdout or "").strip().splitlines()
    reason = (result.stderr or "").strip().splitlines()
    note = reason[-1][:160] if reason else ""
    if result.returncode != 0 or not answer:
        # exit 2 與 exit 1 是兩件事，報告上也必須是兩件事：「這次沒問到」的下一次可能問得到，
        # 「問到了但對照不到」是對照表不夠用。第一版把兩者都寫成同一句，於是一個連不上的
        # 早上跟一張表漏了一列，在報告上長得一模一樣。
        if result.returncode == RESOLVER_COULD_NOT_ASK or not answer:
            return TRIAGE, "resolver-unreachable", {
                "why": f"這次沒問到——{note}" if note else "這次沒問到，而且解析器沒說為什麼"}
        return TRIAGE, "resolver-no-answer", {
            "why": note or f"解析器說不出這張單在哪一格（exit {result.returncode}）"}

    try:
        detail = json.loads(answer[-1])
        slot = detail.pop("slot")
    except (ValueError, KeyError, TypeError):
        return TRIAGE, "resolver-unparseable", {
            "why": f"解析器印的不是一個帶 slot 的 JSON 物件：{answer[-1][:120]}"}

    if slot not in SLOTS:
        # S-P6：對照到不存在的格子名是紅的，不是「就當它 triage」。一個會被靜默吞掉的
        # 錯誤格子名，等於對照表想寫什麼都可以。
        raise ValueError(f"{MARKER_UNKNOWN_SLOT}\n{ticket_name} 的解析器回了一個不存在的"
                         f"格子名 `{slot}`——格子只有這些：{'／'.join(SLOTS)}")
    if note:
        detail["why"] = note
    if slot == RELEASED and not detail.get("released_on"):
        return TRIAGE, "resolver-no-date", {
            "why": f"解析器說它 released，但沒說是哪一天（{answer[-1][:120]}）"}
    return slot, "resolver", detail


def placement_path(ticket_dir: str) -> str:
    return os.path.join(ticket_dir, ".spine", "placement.json")


def write_placement(ticket_dir: str, slot: str, basis: str, detail: dict) -> None:
    """把推導結果寫回單身上。程式讀這個，不讀路徑。"""
    record = {
        "schema_version": PLACEMENT_SCHEMA,
        "producer": "place-issues-by-state.sh",
        "slot": slot,
        "basis": basis,
        "derived_at": _now(),
    }
    record.update({k: v for k, v in detail.items() if v is not None})
    path = placement_path(ticket_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(record, handle, ensure_ascii=False, indent=1)
        handle.write("\n")


OPEN_INDEX = "OPEN.md"


def days_since(day: str | None, today: str) -> int | None:
    """`day` 到今天幾天。算不出來回 None——「不知道」與「0 天」不是同一件事。"""
    if not day:
        return None
    try:
        then = datetime.strptime(day, "%Y-%m-%d")
        now = datetime.strptime(today, "%Y-%m-%d")
    except ValueError:
        return None
    return (now - then).days


def write_index(issues_root: str, rows: list[dict]) -> str:
    """所有不在 `released/` 的單，一份看得懂的清單（S-P7）。

    **停滯只出現在這裡，不出現在位置上。** 一張掛在 in-review 兩個月的單，`in-review/` 是
    正確的位置——這份清單的工作是讓那件事被看見，不是替人決定它該搬走（S-N4）。所以這裡
    印天數，不排序成「逾期區」，也不改任何一張單的格子。
    """
    today = _now()[:10]
    live = [r for r in rows if r["slot"] not in SETTLED_SLOTS]
    lines = [
        "# 還沒出去的單",
        "",
        f"`place-issues-by-state.sh` 每次重算產出，{today} 更新。**不要手改**——下一次重算"
        "會整份重寫。",
        "",
        "「上次動過」是給人看的訊號，不是門檻：它不影響任何一張單落在哪一格。",
        "",
        "| 單 | 格子 | 依據 | 上次動過 | 自己的單 |",
        "|---|---|---|---|---|",
    ]
    for slot in SLOTS:
        if slot in SETTLED_SLOTS:
            continue
        for row in sorted((r for r in live if r["slot"] == slot),
                          key=lambda r: (r["namespace"], r["name"])):
            detail = row["detail"]
            stale = days_since(detail.get("updated"), today)
            when = f"{stale} 天前" if stale is not None else "不知道"
            mine = detail.get("mine")
            if mine:
                owner = "是"
            elif mine is False:
                owner = f"不是（{detail['owner']}）" if detail.get("owner") else "不是"
            else:
                owner = "不知道"
            lines.append(f"| `{row['namespace']}/{row['name']}` | {slot} | "
                         f"{row['basis']} | {when} | {owner} |")

    counts = {slot: sum(1 for r in live if r["slot"] == slot)
              for slot in SLOTS if slot not in SETTLED_SLOTS}
    lines += ["", f"共 {len(live)} 張："
              + "、".join(f"{slot} {n}" for slot, n in counts.items()), ""]

    path = os.path.join(issues_root, OPEN_INDEX)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return path


def target_dir(issues_root: str, namespace: str, name: str,
               slot: str, detail: dict, chain: list[str] | None = None) -> str:
    """這張單該住哪。

    `{命名空間}/{格}/[{日期}/]{鏈頂}/…/{直接母單}/{它自己}`。**格與日期說的是鏈頂那張單**
    ——同一個母單底下的子單狀態各不相同是常態，讓每一張各自搬家的話那個母單就被切成好幾
    塊，而它正是人拿來理解工作的單位。子單自己的狀態沒有消失，它在 `placement.json` 與
    人看的那份清單上。

    呼叫端算好鏈頂的格與日期之後把 `slot`／`detail` 換成鏈頂那張的；`chain` 是這張單到
    鏈頂之間的那幾層。兩者都沒有給的時候，它就是自己的鏈頂。
    """
    parts = [issues_root, namespace, slot]
    if slot == RELEASED:
        parts.append(detail["released_on"])
    elif slot == CLOSED:
        parts.append(detail.get("closed_on") or UNDATED)
    parts.extend(chain if chain is not None else chain_of(detail))
    parts.append(name)
    return os.path.join(*parts)


def write_upstream(ticket_dir: str, detail: dict) -> None:
    """把上游的樣子寫進這張單的 `index.md`，夾在兩行標記之間。

    **只有標記之間會被重寫。** 一張自己的單裡面是人寫的東西，重算碰它就不是重算了。檔案
    還不存在（母單被重算長出來的那一種）就只有這一塊。

    鍵是解析器給的標籤，核心原樣印——它不知道哪一個是標題、哪一個是狀態，也不該知道。
    """
    upstream = detail.get("upstream") or {}
    text = (detail.get("upstream_text") or "").strip()
    if not upstream and not text:
        return
    block = [UPSTREAM_BEGIN, ""]
    for label, value in upstream.items():
        block.append(f"- **{label}**：{value}")
    if text:
        block += ["", "> 上游描述的快照。改了就是這個檔案的一次改動——", "",
                  "\n".join(f"> {line}" if line.strip() else ">"
                             for line in text.splitlines())]
    block += ["", UPSTREAM_END]
    rendered = "\n".join(block)

    path = os.path.join(ticket_dir, "index.md")
    try:
        with open(path, encoding="utf-8") as handle:
            body = handle.read()
    except OSError:
        body = ""
    if UPSTREAM_BEGIN in body and UPSTREAM_END in body:
        head = body[:body.index(UPSTREAM_BEGIN)]
        tail = body[body.index(UPSTREAM_END) + len(UPSTREAM_END):]
        body = head + rendered + tail
    else:
        title = f"# {os.path.basename(ticket_dir)}\n\n"
        body = (title + rendered + "\n") if not body else (rendered + "\n\n" + body)
    os.makedirs(ticket_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(body)


def move(ticket_dir: str, destination: str) -> None:
    """搬。目的地已經有東西就不動——覆蓋掉的是別人的單，那不是搬家是刪除。"""
    if os.path.exists(destination):
        raise FileExistsError(destination)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.move(ticket_dir, destination)


def prune_empty(issues_root: str) -> None:
    """搬完之後留下的空格子清掉，但六格本身留著——一個空的 `in-review/` 是一個答案。"""
    for namespace in namespaces(issues_root):
        base = os.path.join(issues_root, namespace)
        for dirpath, dirnames, filenames in os.walk(base, topdown=False):
            if dirpath == base or filenames or dirnames:
                continue
            relative = os.path.relpath(dirpath, base)
            if relative in SLOTS:
                continue
            os.rmdir(dirpath)


def _resolve(issues_root: str, namespace: str, ticket_dir: str, name: str,
             resolvers: dict[str, str]) -> tuple[str, str, dict] | None:
    """一張單的 (格子, 依據, 細節)。兩層都問不到就回 None。

    兩層：走過脊椎的單看它自己的狀態檔，這一層不需要問任何人。沒有狀態檔的才往下問那個
    命名空間宣告出來的解析器。順序不能反——脊椎的答案是本地的、確定的，讓一次網路往返有
    機會覆蓋它，等於把權威交給一個會逾時的東西（S-N3）。
    """
    derived = slot_from_spine(ticket_dir) if ticket_dir else None
    if derived is None:
        command = resolvers.get(namespace)
        if not command:
            return None
        slot, basis, detail = slot_from_resolver(command, name)
    else:
        slot, basis, detail = derived
    if ticket_dir:
        # 解析器問得到上游上次動的時間，那比 git 準——一張掛在 Code Review 兩個月的單，
        # 本機那個目錄可能昨天才被 commit 碰過。問不到的才退回 git。
        detail.setdefault("updated", last_touched(
            issues_root, os.path.relpath(ticket_dir, issues_root), name))
    return slot, basis, detail


def survey(issues_root: str, resolvers: dict[str, str] | None = None) -> tuple[list, list]:
    """每一張單現在在哪、該在哪、依據是什麼。不動任何東西。

    **兩層都問不到的不參與判定**，回在第二個清單裡。理由是量出來的：`framework/archive/`
    底下有 460 個舊層搬進來的目錄，它們在脊椎存在之前就結束了，沒有狀態檔也沒有人能問。
    把它們掃進 `triage/`，那一格會裝 467 張，而 `triage/` 存在的意義是「機器問過了，答不
    出來，等人歸位」——一個沒人看得完的抽屜等於沒有這一格。留在原地、把數量印出來，是
    `document-flow.md` 本來就寫下的規矩。

    鏈上出現、但樹裡還沒有目錄的那些單號會被補成一張單（`create`）。**那一條直接回答
    「上游不屬於我，我還是要讀得到上層資訊」**：一個只當路徑用、沒有內容的母單層，翻樹的
    人在它身上讀不到任何東西。
    """
    if resolvers is None:
        resolvers = declared_resolvers()
    entries, abstained = [], []
    known: dict[tuple[str, str], int] = {}
    for namespace, ticket_dir in tickets(issues_root):
        name = os.path.basename(ticket_dir)
        got = _resolve(issues_root, namespace, ticket_dir, name, resolvers)
        if got is None:
            abstained.append({"namespace": namespace, "name": name,
                              "current": os.path.relpath(ticket_dir, issues_root)})
            continue
        slot, basis, detail = got
        known[(namespace, name)] = len(entries)
        entries.append({"namespace": namespace, "name": name, "slot": slot,
                        "basis": basis, "detail": detail, "from_dir": ticket_dir})

    # 鏈上出現但樹裡沒有的，補。往上補出來的那一張自己也可能有母單，所以是一個佇列。
    queue, referred_by = [], {}
    for entry in list(entries):
        for key in chain_of(entry["detail"]):
            referred_by.setdefault((entry["namespace"], key), entry["name"])
            queue.append((entry["namespace"], key))
    while queue:
        namespace, key = queue.pop(0)
        if (namespace, key) in known:
            continue
        got = _resolve(issues_root, namespace, "", key, resolvers)
        if got is None:
            continue  # 沒有解析器就問不到這個號，不猜一張單出來
        slot, basis, detail = got
        known[(namespace, key)] = len(entries)
        entries.append({"namespace": namespace, "name": key, "slot": slot,
                        "basis": basis, "detail": detail, "from_dir": None})
        for k in chain_of(detail):
            referred_by.setdefault((namespace, k), key)
            queue.append((namespace, k))

    # **母單問不到，不得讓底下那張問得到的單失去位置。** 它照樣要有一格（不然子單沒有地方
    # 可以住），那一格取自引用它的那張單——不是 `triage/`。丟進 triage 的話，一次問不到會把
    # 整條鏈拖進那個抽屜，而抽屜的意義是「機器問過了，答不出來，等人歸位」，不是「它底下
    # 問得到的單也一起等」。沒有任何人引用的那些才屬於那裡，它們不進這一輪。
    #
    # **這一輪對樹裡的每一張單做，不只對剛補出來的那幾張。** 補出來的那一張，下一次重算就
    # 是樹裡的一個目錄了——它走的是上面第一段那條路，不是佇列那條。只在補的時候處理，等於
    # 這條規則只成立一次，第二次重算就把整條鏈拖回 triage/。
    #
    # 判準是 `basis`，不是格子名：解析器答得出「這張就是 triage」時那是一個答案，不是一次
    # 問不到。失敗的那幾種 basis 都帶 `resolver-` 前綴，成功的那一種是光的 `resolver`。
    for _ in range(len(entries) + 1):
        adopted = False
        for entry in entries:
            if entry["slot"] != TRIAGE or not entry["basis"].startswith("resolver-"):
                continue
            referrer = referred_by.get((entry["namespace"], entry["name"]), "")
            at = known.get((entry["namespace"], referrer))
            if at is None or entries[at]["slot"] == TRIAGE:
                continue
            entry["slot"] = entries[at]["slot"]
            entry["basis"] = "chain-head-unresolved"
            entry["detail"] = dict(entry["detail"])
            entry["detail"].pop("chain", None)
            entry["detail"]["why"] = (entry["detail"].get("why") or "這次沒問到") + \
                f"——所以它跟著 {entries[at]['name']} 擺在 {entry['slot']}"
            adopted = True
        if not adopted:
            break

    # 格與日期取鏈頂那張的。鏈頂問不到的話（解析器沒回它）就用自己的，不讓一張單因為它的
    # 母單問不到而失去位置。
    rows = []
    for entry in entries:
        chain = chain_of(entry["detail"])
        head = entry
        if chain:
            at = known.get((entry["namespace"], chain[0]))
            if at is not None:
                head = entries[at]
        destination = target_dir(issues_root, entry["namespace"],
                                 entry["name"], head["slot"], head["detail"], chain)
        rows.append({
            "namespace": entry["namespace"],
            "name": entry["name"],
            "current": (os.path.relpath(entry["from_dir"], issues_root)
                        if entry["from_dir"] else None),
            "target": os.path.relpath(destination, issues_root),
            "slot": entry["slot"],
            "head_slot": head["slot"],
            "chain": chain,
            "basis": entry["basis"],
            "detail": entry["detail"],
            "from_dir": entry["from_dir"],
            "to_dir": destination,
        })
    return rows, abstained


def render(rows: list[dict], abstained: list[dict], moved: int, mode: str,
           planned: int = 0, skipped: list[dict] | None = None,
           carried: int = 0, vanished: list[dict] | None = None) -> str:
    """報告。每一格都有數字——包括 0，一個安靜的空格子跟一個沒被檢查的格子長得一樣。

    真的搬過的那一種要三個數字：**打算搬幾張、真的搬了幾張、撞到東西沒搬成幾張**。少了
    第三個，被跳過的那些會被「原本就在對的位置」吸收——2026-08-21 那一次寫的是「搬了 0 張，
    原本就在對的位置的 710 張」，緊接著逐行列出 24 張位置不對的單。兩個數字互相矛盾，而讀
    的人只會看第一行。
    """
    lines = []
    counts = {slot: sum(1 for r in rows if r["slot"] == slot) for slot in SLOTS}
    lines.append("PLACE-ISSUES-BY-STATE " + "／".join(
        f"{slot} {counts[slot]}" for slot in SLOTS) + f"（共 {len(rows)} 張）")

    created = [r for r in rows if r["current"] is None]
    off = [r for r in rows if r["current"] is not None and r["current"] != r["target"]]
    if mode.startswith("execute"):
        # 「原本就在對的位置」要從搬之前那次調查算。搬完再算的話它等於總數，於是報告會同時
        # 說「搬了 7 張」與「原本就有 7 張在對的位置」。
        stuck, gone = skipped or [], vanished or []
        lines.append(f"打算搬 {planned} 張＝真的搬了 {moved} 張"
                     f"＋跟著母單一起走 {carried} 張"
                     f"＋撞到已經存在的目的地沒搬成 {len(stuck)} 張"
                     f"＋來源不見了 {len(gone)} 張；"
                     f"原本就在對的位置的 {len(rows) - planned} 張")
        if gone:
            lines.append(f"來源不見了的 {len(gone)} 張：")
            for row in gone[:40]:
                lines.append(f"  {row['from']} ↛ {row['to']}")
        if stuck:
            # **沒搬成不得只是一個數字。** 撞到的那個位置多半是一個空殼，而那張單的內容還
            # 留在舊路徑上——同一個單號在樹裡出現兩次，沒有東西會喊。
            lines.append(f"沒搬成的 {len(stuck)} 張，逐張說出撞到什麼、哪一份比較新：")
            for row in stuck[:40]:
                here = row.get("from_touched") or "不知道"
                there = row.get("to_touched") or "不知道"
                lines.append(f"  {row['from']} ↛ {row['to']}（那個位置已經有東西了）")
                lines.append(f"    上次動過：這一份 {here}／那一份 {there}"
                             "——哪一份留下來由人決定")
            if len(stuck) > 40:
                lines.append(f"  …還有 {len(stuck) - 40} 張")
    else:
        lines.append(f"位置與狀態對不上的 {len(off)} 張，對得上的 {len(rows) - len(off)} 張"
                     + ("（--check，不動任何東西）" if mode == "check"
                        else "（預覽，不動任何東西；要真的搬加 --execute）"))
    for row in off[:40]:
        lines.append(f"  {row['current']} → {row['target']}"
                     f"（依據 {row['basis']}）")
    if len(off) > 40:
        lines.append(f"  …還有 {len(off) - 40} 張")

    if created:
        # 鏈上出現、樹裡還沒有的母單。**不印出來的話它們會安靜地長出來**，而那正是
        # 「上游不屬於我」的那幾張——最需要有人看一眼的就是它們。
        lines.append(f"鏈上出現、樹裡還沒有的母單 {len(created)} 張"
                     + ("（會補出來）" if mode.startswith("execute") else "（要補出來）") + "：")
        for row in created[:40]:
            lines.append(f"  {row['target']}")
        if len(created) > 40:
            lines.append(f"  …還有 {len(created) - 40} 張")

    deep = [r for r in rows if r["chain"]]
    if deep:
        depths: dict[int, int] = {}
        for row in deep:
            depths[len(row["chain"])] = depths.get(len(row["chain"]), 0) + 1
        lines.append("掛在母單底下的 " + str(len(deep)) + " 張，鏈長分佈："
                     + "、".join(f"{d} 層 {n} 張" for d, n in sorted(depths.items())))

    triaged = [r for r in rows if r["slot"] == TRIAGE]
    lines.append(f"落 {TRIAGE}/ 的 {len(triaged)} 張，逐張說出為什麼：")
    for row in triaged[:40]:
        lines.append(f"  {row['namespace']}/{row['name']}："
                     f"{row['detail'].get('why', row['basis'])}")
    if len(triaged) > 40:
        lines.append(f"  …還有 {len(triaged) - 40} 張")

    # 不參與判定的第三態。它安靜的話，下一個看報告的人會以為那幾百個目錄都被檢查過了。
    if abstained:
        by_namespace: dict[str, int] = {}
        for row in abstained:
            by_namespace[row["namespace"]] = by_namespace.get(row["namespace"], 0) + 1
        why = ("這次沒問任何解析器（--spine-only）" if mode.endswith("spine-only")
               else "命名空間也沒有宣告解析器")
        lines.append(f"沒有狀態檔、{why}的 {len(abstained)} 個目錄留在原地，不參與判定："
                     + "、".join(f"{ns} {n}" for ns, n in sorted(by_namespace.items())))
        # 少到看得完的時候逐個指名。數量本來就是為了不讓幾百個目錄被當成檢查過了；
        # 但一個只有三筆的總數同樣看不出是哪三筆，而那三筆是真的可以被處理掉的。
        if len(abstained) <= ABSTAINED_NAME_THRESHOLD:
            for row in sorted(abstained, key=lambda r: (r["namespace"], r["name"])):
                # 印它真正在哪，不只印它叫什麼。單名前面那一層正是「它為什麼沒被判定」
                # 的答案（多半是 archive/），而拿掉那一層之後兩者長得一模一樣。
                lines.append(f"  {row['current']}")
    return "\n".join(lines)


def main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="把每一張單放到它的狀態說的那一格；預設只看不動。")
    parser.add_argument("--issues", required=True, help="issues 根目錄")
    parser.add_argument("--check", action="store_true",
                        help="只報位置與狀態的落差，有落差就 exit 1")
    parser.add_argument("--execute", action="store_true", help="真的搬")
    parser.add_argument("--spine-only", action="store_true",
                        help="不問任何解析器。記一輪之後自動跑的就是這個模式——"
                             "剛動過的是一張走脊椎的單，它的答案在本機，不需要一趟網路。")
    args = parser.parse_args(argv)

    issues_root = os.path.abspath(args.issues.rstrip("/"))
    if not os.path.isdir(issues_root):
        print(f"POLARIS_ISSUES_ROOT_MISSING\nissues 目錄不存在：{issues_root}")
        return 2
    # 傳進一個「底下直接有格子」的根，等於把某一個命名空間當成整棵樹。上一版就這樣把 103 個
    # 目錄搬進 archive/archive/。錯的根要在動任何東西之前擋下來，不是靠呼叫端記得傳對。
    if any(os.path.isdir(os.path.join(issues_root, slot)) for slot in SLOTS):
        print(f"POLARIS_ISSUES_ROOT_IS_A_NAMESPACE\n{issues_root} 底下直接有格子——"
              "這代表傳進來的是某一個命名空間，不是整棵樹。再往上一層。")
        return 2

    resolvers = {} if args.spine_only else declared_resolvers()
    try:
        rows, abstained = survey(issues_root, resolvers)
    except ValueError as error:
        # 對照到不存在的格子名（S-P6）。這是紅的，不是一張落 triage 的單——對照表寫錯什麼
        # 都靜默通過的話，它就不是宣告源了。
        print(error)
        return 2
    if not rows and not abstained:
        print("POLARIS_ISSUES_TREE_EMPTY\n一張單都沒有掃到——這不是「全部都在對的位置」")
        return 2

    moved, planned, carried = 0, 0, 0
    skipped: list[dict] = []
    vanished: list[dict] = []
    if args.execute:
        # 一、鏈上出現、樹裡還沒有的母單，先長出來。它們是別人的落腳處，晚一步的話那些
        #     子單就沒有地方可以搬。
        for row in rows:
            if row["current"] is None:
                os.makedirs(row["to_dir"], exist_ok=True)

        # 二、搬。**母單先搬，而且要記得它搬去哪**——一張單搬走的時候底下的子單跟著一起
        #     走，於是那些子單記著的來源路徑當場失效。重新調查一次可以修好，但那是七百次
        #     子行程，所以這裡自己把路徑改寫過來。
        remap: list[tuple[str, str]] = []

        def current_path(path: str) -> str:
            for old_dir, new_dir in remap:
                if path == old_dir or path.startswith(old_dir + os.sep):
                    return new_dir + path[len(old_dir):]
            return path

        # **排序用目的地的深度，不用來源的。** 來源的深度回答不了「誰要先搬」：一張單與它
        # 的子單可以來自同樣深的兩個地方，而目的地一個在另一個底下。深度相同就沒有順序，
        # 交給清單的排列——子單先搬的話，`move()` 會把母單的目的地當成路徑造出來，輪到母單
        # 自己的時候那個路徑已經存在，於是它的搬動被跳過，內容永遠留在舊路徑上。
        #
        # 實測：2026-08-21 對真實單樹跑一次遷移，遷移前 0 組同號重複，遷移後 12 組。
        movable = [r for r in rows if r["from_dir"] and r["current"] != r["target"]]
        planned = len(movable)
        for row in sorted(movable, key=lambda r: r["to_dir"].count(os.sep)):
            source = current_path(row["from_dir"])
            if source == row["to_dir"]:
                # 母單搬走的時候它整個目錄一起走，底下的子單已經到位了。**這不是「沒搬」，
                # 也不是「原本就在對的位置」**——它本來不在，是這一次被帶過去的。
                carried += 1
                continue
            if not os.path.isdir(source):
                # 來源不見了。正常不會發生（remap 就是為了這件事），發生了要有人看見。
                vanished.append({"from": row["current"], "to": row["target"],
                                 "name": row["name"]})
                continue
            if os.path.exists(row["to_dir"]):
                # 已經有東西了：覆蓋掉的是別人的單，那不是搬家是刪除。**但也不得安靜地
                # 跳過**——排完順序還撞到，代表樹裡本來就有兩個同號的目錄，那要有人看見。
                # **「哪一份是權威」只有一個線索機械答得出來：兩邊各自上次動過。** 重算
                # 不替人決定留哪一份——它答得出「哪一邊比較新」，答不出「哪一邊是對的」。
                skipped.append({
                    "from": row["current"], "to": row["target"], "name": row["name"],
                    "from_touched": touched_at(issues_root, row["current"]),
                    "to_touched": touched_at(issues_root, row["target"]),
                })
                continue
            move(source, row["to_dir"])
            remap.append((source, row["to_dir"]))
            moved += 1
        prune_empty(issues_root)
        rows, abstained = survey(issues_root, resolvers)

        # placement.json 只在真的重算的時候寫。預覽與 --check 說好了不動任何東西，而一份
        # 被預覽寫出來的推導結果，會讓下一個讀它的程式以為那次搬家發生過。
        for row in rows:
            write_placement(row["to_dir"], row["slot"], row["basis"], row["detail"])
            write_upstream(row["to_dir"], row["detail"])
        # 清單只在問過解析器的那種執行裡重寫。spine-only 看不到靠解析器回答的那些命名空間，
        # 讓它重寫等於每記一輪就把清單上的那些單全部刪掉一次。
        if not args.spine_only:
            index = write_index(issues_root, rows)
            print(f"非釋出清單：{os.path.relpath(index, issues_root)}")

    mode = "check" if args.check else ("execute" if args.execute else "preview")
    if args.spine_only:
        mode += "+spine-only"
    print(render(rows, abstained, moved, mode, planned, skipped, carried, vanished))
    if args.check and any(r["current"] is None or r["current"] != r["target"]
                          for r in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
