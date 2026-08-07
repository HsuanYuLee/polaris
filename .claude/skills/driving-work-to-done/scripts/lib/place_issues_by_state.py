#!/usr/bin/env python3
"""把每一張單放到它的狀態說的那一格，並把推導結果寫回單自己身上。

位置是狀態的投影，不是第二個權威。以前投影只有兩格（活躍區／`archive/`），答得了「做完了
沒」，答不了「在哪一站」。這支把解析度提高到六格，權威沒有換人。

    backlog/            立案了，還沒開工
    in-progress/        兩個閘之間
    in-review/          送審中（只有會動到 code 的單走得到）
    done/               我這邊做完了，還沒上線
    released/{日期}/    真的出去了，日期就是那天
    triage/             推導不出來——在等人歸位

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

# 六格。順序有意義：報告按這個順序印，而它就是一張單往前走的順序。
BACKLOG, IN_PROGRESS, IN_REVIEW, DONE, RELEASED, TRIAGE = (
    "backlog", "in-progress", "in-review", "done", "released", "triage")
SLOTS = (BACKLOG, IN_PROGRESS, IN_REVIEW, DONE, RELEASED, TRIAGE)

# 轉場期還會遇到的舊格子。它不是一個狀態，是上一版投影留下的形狀。
LEGACY_SLOT = "archive"

# 會動到 code 的工作才走得到 in-review。這個訊號已經記在單的狀態裡（開輪次時決定的領域），
# 不需要另外標一次。
CODE_PACK = "swe-knowledge"

PLACEMENT_SCHEMA = 1

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


def tickets(issues_root: str) -> list[tuple[str, str]]:
    """每一張單：回 (命名空間, 單的絕對路徑)。

    什麼算一張單：命名空間底下，**不是格子名**的那一層目錄。格子名這支自己認得（六格加上
    轉場期的 `archive`），`released/` 底下還多一層日期。這是唯一知道版面長怎樣的地方——
    其餘每一個消費端都改成問狀態檔，不再各自猜路徑。
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
                continue
            for inner in sorted(os.listdir(path)):
                inner_path = os.path.join(path, inner)
                if inner.startswith(".") or not os.path.isdir(inner_path):
                    continue
                if name != RELEASED:
                    found.append((namespace, inner_path))
                    continue
                # released/ 底下多一層日期。
                for leaf in sorted(os.listdir(inner_path)):
                    leaf_path = os.path.join(inner_path, leaf)
                    if not leaf.startswith(".") and os.path.isdir(leaf_path):
                        found.append((namespace, leaf_path))
    return found


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
                         f"格子名 `{slot}`——六格是 {'／'.join(SLOTS)}")
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
    live = [r for r in rows if r["slot"] != RELEASED]
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
        if slot == RELEASED:
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
                owner = f"不是（{detail['assignee']}）" if detail.get("assignee") else "不是"
            else:
                owner = "不知道"
            lines.append(f"| `{row['namespace']}/{row['name']}` | {slot} | "
                         f"{row['basis']} | {when} | {owner} |")

    counts = {slot: sum(1 for r in live if r["slot"] == slot)
              for slot in SLOTS if slot != RELEASED}
    lines += ["", f"共 {len(live)} 張："
              + "、".join(f"{slot} {n}" for slot, n in counts.items()), ""]

    path = os.path.join(issues_root, OPEN_INDEX)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return path


def target_dir(issues_root: str, namespace: str, ticket_dir: str,
               slot: str, detail: dict) -> str:
    """這張單該住哪。`released/` 底下多一層釋出日。"""
    name = os.path.basename(ticket_dir)
    parts = [issues_root, namespace, slot]
    if slot == RELEASED:
        parts.append(detail["released_on"])
    parts.append(name)
    return os.path.join(*parts)


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


def survey(issues_root: str, resolvers: dict[str, str] | None = None) -> list[dict]:
    """每一張單現在在哪、該在哪、依據是什麼。不動任何東西。

    兩層：走過脊椎的單看它自己的狀態檔，這一層不需要問任何人。沒有狀態檔的才往下問那個
    命名空間宣告出來的解析器。順序不能反——脊椎的答案是本地的、確定的，讓一次網路往返有
    機會覆蓋它，等於把權威交給一個會逾時的東西（S-N3）。

    **兩層都問不到的不參與判定**，回在第二個清單裡。理由是量出來的：`framework/archive/`
    底下有 460 個舊層搬進來的目錄，它們在脊椎存在之前就結束了，沒有狀態檔也沒有人能問。
    把它們掃進 `triage/`，那一格會裝 467 張，而 `triage/` 存在的意義是「機器問過了，答不
    出來，等人歸位」——一個沒人看得完的抽屜等於沒有這一格。留在原地、把數量印出來，是
    `document-flow.md` 本來就寫下的規矩。
    """
    if resolvers is None:
        resolvers = declared_resolvers()
    rows, abstained = [], []
    for namespace, ticket_dir in tickets(issues_root):
        derived = slot_from_spine(ticket_dir)
        if derived is None:
            command = resolvers.get(namespace)
            if not command:
                abstained.append({"namespace": namespace,
                                  "name": os.path.basename(ticket_dir),
                                  "current": os.path.relpath(ticket_dir, issues_root)})
                continue
            slot, basis, detail = slot_from_resolver(command,
                                                     os.path.basename(ticket_dir))
        else:
            slot, basis, detail = derived
        # 解析器問得到 JIRA 上次動的時間，那比 git 準——一張掛在 Code Review 兩個月的單，
        # 本機那個目錄可能昨天才被 commit 碰過。問不到的才退回 git。
        detail.setdefault("updated", last_touched(
            issues_root, os.path.relpath(ticket_dir, issues_root),
            os.path.basename(ticket_dir)))
        destination = target_dir(issues_root, namespace, ticket_dir, slot, detail)
        rows.append({
            "namespace": namespace,
            "name": os.path.basename(ticket_dir),
            "current": os.path.relpath(ticket_dir, issues_root),
            "target": os.path.relpath(destination, issues_root),
            "slot": slot,
            "basis": basis,
            "detail": detail,
            "from_dir": ticket_dir,
            "to_dir": destination,
        })
    return rows, abstained


def render(rows: list[dict], abstained: list[dict], moved: int, mode: str) -> str:
    """報告。每一格都有數字——包括 0，一個安靜的空格子跟一個沒被檢查的格子長得一樣。"""
    lines = []
    counts = {slot: sum(1 for r in rows if r["slot"] == slot) for slot in SLOTS}
    lines.append("PLACE-ISSUES-BY-STATE " + "／".join(
        f"{slot} {counts[slot]}" for slot in SLOTS) + f"（共 {len(rows)} 張）")

    off = [r for r in rows if r["current"] != r["target"]]
    if mode.startswith("execute"):
        # 「原本就在對的位置」要從搬之前那次調查算。搬完再算的話它等於總數，於是報告會同時
        # 說「搬了 7 張」與「原本就有 7 張在對的位置」。
        lines.append(f"搬了 {moved} 張，原本就在對的位置的 {len(rows) - moved} 張")
    else:
        lines.append(f"位置與狀態對不上的 {len(off)} 張，對得上的 {len(rows) - len(off)} 張"
                     + ("（--check，不動任何東西）" if mode == "check"
                        else "（預覽，不動任何東西；要真的搬加 --execute）"))
    for row in off[:40]:
        lines.append(f"  {row['current']} → {row['target']}"
                     f"（依據 {row['basis']}）")
    if len(off) > 40:
        lines.append(f"  …還有 {len(off) - 40} 張")

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

    moved = 0
    if args.execute:
        for row in rows:
            if row["current"] == row["target"]:
                continue
            move(row["from_dir"], row["to_dir"])
            moved += 1
        prune_empty(issues_root)
        rows, abstained = survey(issues_root, resolvers)

        # placement.json 只在真的重算的時候寫。預覽與 --check 說好了不動任何東西，而一份
        # 被預覽寫出來的推導結果，會讓下一個讀它的程式以為那次搬家發生過。
        for row in rows:
            write_placement(row["to_dir"], row["slot"], row["basis"], row["detail"])
        # 清單只在問過解析器的那種執行裡重寫。spine-only 看不到靠解析器回答的那些命名空間，
        # 讓它重寫等於每記一輪就把清單上的那些單全部刪掉一次。
        if not args.spine_only:
            index = write_index(issues_root, rows)
            print(f"非釋出清單：{os.path.relpath(index, issues_root)}")

    mode = "check" if args.check else ("execute" if args.execute else "preview")
    if args.spine_only:
        mode += "+spine-only"
    print(render(rows, abstained, moved, mode))
    if args.check and any(r["current"] != r["target"] for r in rows):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
