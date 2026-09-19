#!/usr/bin/env python3
"""這台機器上有哪些 session、各自閒置多久、各自在做什麼；以及指揮官日誌。

不對任何 session 送訊息、不送訊號。寫的只有兩樣：每個 session 自己的宣告，以及登錄旁邊
那份 append-only 的指揮官日誌（宣告、派工、`--log`、`--waiting-on` 各落一筆）。

「在做什麼」讀的是**那個 session 自己寫下的宣告**（`--declare` 寫、這裡讀），不是它
transcript 裡最後一則說的話。兩個理由，第二個才是真正的那一個：

1. 最後一則話是「它剛好講到哪」，不是「它在做什麼」。
2. **讀不完。** 這台機器上 8 個活著的 session，transcript 合計 220.5 MB（最大一份
   92.4 MB／45,135 筆），約 5,780 萬 token——一個 200k 視窗的 289 倍。指揮者累積每個
   worker 的完整 context 這條路在四個 worker 就走不通，何況八個。所以指揮讀的是索引，
   要細節去問那一個 session。

閒置多久仍然由 transcript 的 mtime 算——那是一次 stat，不讀內容。

問不到的留在地圖上並指名問不到的是哪一份，不從清單上消失、也不填一個猜的。而「從來沒
寫過宣告」「宣告讀不動」「宣告在而缺欄位」是三件事，長成三句不同的話。
"""
import argparse, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
REGISTRY = os.path.join(HOME, ".claude", "sessions")
PROJECTS = os.path.join(HOME, ".claude", "projects")

# 「在飛的單有哪些」只有一個地方答得出來，而它不在這支 skill 裡。這一行是去問它的路徑，
# 不是一份抄過來的判定——見 `spine_rows()`。它跟其他模組常數放在一起，因為它就是一個。
SPINE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "driving-work-to-done", "scripts", "spine-loop-state.sh")


def transcript_path(cwd, session_id):
    """cwd 換成 projects 底下的目錄名。

    `/` 與 `.` **都**要換成 `-`。只換 `/` 的話，任何帶點的路徑（`hsuanyu.lee` 這種家目錄）
    全部對不到——那不是少幾筆，是整台機器一筆都對不到，而輸出看起來只是「大家都讀不到」。
    """
    slug = cwd.replace("/", "-").replace(".", "-")
    return os.path.join(PROJECTS, slug, f"{session_id}.jsonl")


DECLARATIONS = os.path.join(REGISTRY, "declarations")
DECL_FIELDS = ("holding", "blocked_on", "tickets_opened")


def declaration_path(session_id):
    """一個 session 的宣告住哪。

    放在登錄目錄底下的子目錄，不跟 `{pid}.json` 並排——`read_registry()` 收的是
    `*.json`，並排的話每一份宣告都會被當成一筆壞掉的登錄列出來。
    """
    return os.path.join(DECLARATIONS, f"{session_id}.json")


def read_declaration(session_id):
    """那個 session 自己寫下的宣告。

    回傳 (decl, problem)。problem 不是 None 的時候 decl 一定是 None——三種讀不到各說
    各的話，因為它們要人做的事不一樣：沒寫過要去叫它寫，讀不動要去看那個檔，缺欄位是
    它寫了但沒寫全。
    """
    path = declaration_path(session_id)
    if not os.path.exists(path):
        return None, f"這個 session 從來沒寫過宣告（要它跑 --declare）：{path}"
    try:
        with open(path, encoding="utf-8") as fh:
            decl = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        return None, f"宣告讀不動：{path}（{exc}）"
    if not isinstance(decl, dict):
        return None, f"宣告不是一個物件：{path}"
    missing = [k for k in DECL_FIELDS if not decl.get(k)]
    if missing:
        return None, f"宣告缺欄位（{chr(12289).join(missing)}）：{path}"
    return decl, None


def declaration_line(decl):
    """把宣告排成一行給人讀。結構的那一份仍然在 `declaration` 鍵裡。

    「哪條線」與「瀏覽器」是後來才加的兩格。舊的宣告沒有它們，**照樣讀得出來**，但那一格
    說出是缺——不印空白，空白跟「這個 session 沒有線」長得一模一樣。
    """
    opened = decl.get("tickets_opened")
    if isinstance(opened, list):
        opened = chr(12289).join(str(x) for x in opened) or "無"
    return "｜".join([f"線：{decl.get('line') or '（宣告沒說——舊宣告缺 line）'}",
                      f"瀏覽器：{decl.get('browser') or '（宣告沒說——舊宣告缺 browser）'}",
                      f"接：{decl['holding']}",
                      f"卡：{decl['blocked_on']}", f"開單：{opened}"])


def write_declaration(session_id, holding, blocked_on, tickets_opened,
                      line=None, browser=None):
    """這個 session 寫下自己的那一行。**只寫自己的那一份，不碰別人的。**"""
    os.makedirs(DECLARATIONS, exist_ok=True)
    path = declaration_path(session_id)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"session_id": session_id, "line": line, "browser": browser,
                   "holding": holding,
                   "blocked_on": blocked_on, "tickets_opened": tickets_opened,
                   "declared_at": time.time()}, fh, ensure_ascii=False, indent=2)
    return path


# ── 指揮官日誌 ────────────────────────────────────────────────────────────────
#
# **它是事件流，不是交接文件。** 每一筆由發生那件事的命令在那一刻寫下（宣告、派工、
# 記一則回報、指揮官換了在等的東西），交棒時沒有人需要坐下來寫一份。〈交棒不新增任何
# 要人維護的狀態〉禁止的是後者：交棒那一刻才手寫的文件會跟實際狀態漂開。
#
# 住在登錄旁邊，不住在任何一個 workspace 裡：它講的是這台機器上的 session，而各條線的
# cwd 不一定在同一個 workspace。`COMMAND_POST_DIR` 只給量測換一個地方寫。
JOURNAL_DIR = os.environ.get("COMMAND_POST_DIR") or os.path.join(REGISTRY, "command-post")
JOURNAL = os.path.join(JOURNAL_DIR, "journal.md")
# 指揮官自己放的常駐規矩。**skill 不帶任何一家公司的規矩**——那些只在這份檔裡，
# `--rebuild` 原樣貼上。
STANDING = os.path.join(JOURNAL_DIR, "standing.md")
SCRIPT = os.path.abspath(__file__)

JOURNAL_HEADER = """# 指揮官工作日誌（command-post journal）

給**下一個指揮官**讀，也給**指揮官失聯時的實作 session** 讀。append-only：每一筆由發生
那件事的命令在那一刻寫下——宣告、派工、回報、指揮官在等什麼。不改舊的，只往下加；要補一
句就用 `--log`。

接手順序：跑 `--board`（它印這份的尾端與上一任在等什麼），再讀 command-post 的 SKILL.md。
重建各條線的開場 prompt：`--rebuild`。

---
"""

# 一筆的開頭。`## ` 與 `### ` 都算，手寫的那幾節（`## 日期 ｜ 誰`）也就一起被切成筆。
ENTRY_HEAD = re.compile(r"^#{2,3} \d{4}-\d{2}-\d{2} \d{2}:\d{2}")


def stamp(now=None):
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(now or time.time()))


def append_journal(kind, who, fields, now=None):
    """往日誌尾端加一筆。回傳 (path, problem)。

    **寫不進去不得安靜地當作寫了**——呼叫者拿到 problem 就要失敗並說出路徑。
    """
    try:
        os.makedirs(JOURNAL_DIR, exist_ok=True)
        fresh = not os.path.exists(JOURNAL) or os.path.getsize(JOURNAL) == 0
        body = ["", f"### {stamp(now)} ｜ {kind} ｜ {who}"]
        body += [f"- {k}：{v}" for k, v in fields if v]
        with open(JOURNAL, "a", encoding="utf-8") as fh:
            if fresh:
                fh.write(JOURNAL_HEADER)
            fh.write("\n".join(body) + "\n")
        return JOURNAL, None
    except OSError as exc:
        return JOURNAL, f"日誌寫不進去：{JOURNAL}（{exc}）"


def read_journal_entries():
    """回傳 (entries, problem)。三種讀不到各說各的話：不存在、是空的、讀不動。"""
    if not os.path.exists(JOURNAL):
        return [], f"日誌還不存在：{JOURNAL}（第一次宣告、派工或 --log 會建立它）"
    try:
        with open(JOURNAL, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        return [], f"日誌讀不動：{JOURNAL}（{exc}）"
    entries, cur = [], None
    for ln in text.splitlines():
        if ENTRY_HEAD.match(ln):
            if cur:
                entries.append("\n".join(cur).rstrip())
            cur = [ln]
        elif cur is not None:
            cur.append(ln)
    if cur:
        entries.append("\n".join(cur).rstrip())
    if not entries:
        return [], f"日誌在，但一筆紀錄都沒有：{JOURNAL}"
    return entries, None


WAITING_KIND = "在等"
COMMANDER_LINE = "指揮官"


def last_waiting(entries):
    """最後一句「指揮官在等什麼」。回傳 (那一句, 那一筆的標頭) 或 (None, None)。"""
    for e in reversed(entries):
        head, _, rest = e.partition("\n")
        if f"｜ {WAITING_KIND} ｜" in head:
            for ln in rest.splitlines():
                if ln.startswith("- 在等："):
                    return ln[len("- 在等："):], head.lstrip("# ")
    return None, None


def session_name_of(session_id):
    """拿 sessionId 去登錄查名字。查不到就回 sessionId 本身——日誌裡總要有個誰。"""
    rows, _ = read_registry()
    for _, data in rows:
        if data.get("sessionId") == session_id and data.get("name"):
            return data["name"]
    return session_id


def idle_seconds_of(path, now):
    """閒置多久。**stat，不讀內容**——這一支不打開 transcript。

    回傳 (seconds, problem)。檔案不在的時候不猜一個 0：猜出來的 0 會讓那一列看起來
    像剛動過，而剛動過正好是「不要關它」的理由。
    """
    if not os.path.exists(path):
        return None, f"算不出閒置多久，transcript 不存在：{path}"
    try:
        return max(0, int(now - os.path.getmtime(path))), None
    except OSError as exc:
        return None, f"算不出閒置多久：{path}（{exc}）"


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True          # 存在，只是不是我的
    except (OverflowError, ValueError):
        return False


MAX_ANCESTRY_HOPS = 24


def whoami(start_pid=None):
    """跑這一趟的是哪一個 session——**推出來的，不是任何人宣告的**。

    往上走進程祖先，每一跳去 `~/.claude/sessions/{pid}.json` 找。找到就是它：那份登錄檔
    是 Claude Code 自己寫的，`pid` 就是檔名。實測兩跳就中（呼叫者的 shell → session 本身）。

    **這件事不靠宣告**，所以覆蓋率不是「記得寫的那幾個」而是「凡是走過流程的都有」——
    這台機器上 8 個 session 只有 1 份自願宣告，量過。

    回傳 (sessionId, 為什麼推不出來)。推不出來一定有一句話：一個空字串會跟「沒有人接」
    長得一模一樣，而它們要人做的事不同。
    """
    pid = start_pid if start_pid is not None else os.getpid()
    seen = []
    for _ in range(MAX_ANCESTRY_HOPS):
        path = os.path.join(REGISTRY, f"{pid}.json")
        if os.path.exists(path):
            try:
                data = json.load(open(path, encoding="utf-8"))
            except (OSError, ValueError) as exc:
                return None, f"pid {pid} 的登錄檔讀不動：{path}（{exc}）"
            sid = data.get("sessionId")
            if not sid:
                return None, f"pid {pid} 的登錄檔裡沒有 sessionId：{path}"
            return sid, None
        seen.append(pid)
        try:
            out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                                 capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError) as exc:
            return None, ("問不到祖先（走過 "
                          + "→".join(str(x) for x in seen) + f"）：{exc}")
        try:
            parent = int(out.stdout.strip())
        except ValueError:
            return None, ("走到頭了，沿路沒有一個 pid 有登錄檔（走過 "
                          + "→".join(str(x) for x in seen) + "）")
        if parent <= 1 or parent == pid:
            return None, ("走到 pid " + str(parent) + " 還沒找到登錄檔（走過 "
                          + "→".join(str(x) for x in seen) + "）")
        pid = parent
    return None, (f"走了 {MAX_ANCESTRY_HOPS} 跳還沒找到登錄檔（走過 "
                  + "→".join(str(x) for x in seen) + "）")


def read_registry():
    """回傳 (rows, problem)。登錄本身讀不到是一種狀態，不是空清單。"""
    if not os.path.isdir(REGISTRY):
        return [], f"session 登錄目錄不存在：{REGISTRY}"
    try:
        names = sorted(n for n in os.listdir(REGISTRY) if n.endswith(".json"))
    except OSError as exc:
        return [], f"session 登錄目錄讀不動：{REGISTRY}（{exc}）"
    rows = []
    for name in names:
        path = os.path.join(REGISTRY, name)
        try:
            with open(path, encoding="utf-8") as fh:
                rows.append((path, json.load(fh)))
        except (OSError, json.JSONDecodeError) as exc:
            rows.append((path, {"__unreadable__": f"{exc}"}))
    return rows, None


def build(now=None):
    now = now or time.time()
    rows, problem = read_registry()
    out = {"generated_at": now, "registry": REGISTRY,
           "registry_problem": problem, "sessions": [], "not_this_machine": []}
    this_domain = "darwin" if sys.platform == "darwin" else sys.platform
    for path, data in rows:
        if "__unreadable__" in data:
            out["sessions"].append({
                "name": None, "pid": None, "source": path,
                "missing": ["這份登錄檔讀不動"],
                "problem": f"登錄檔讀不動：{path}（{data['__unreadable__']}）",
                "doing": None, "idle_seconds": None, "local": None,
                # running 要有，即使是 None：human() 每一列都讀它，少一個鍵就是整支炸掉，
                # 而炸掉的那一刻剛好是登錄裡有一份壞檔的時候。
                "running": None})
            continue
        pid, sid = data.get("pid"), data.get("sessionId")
        cwd, nm = data.get("cwd"), data.get("name")
        missing = [k for k, v in (("name", nm), ("pid", pid),
                                  ("sessionId", sid), ("cwd", cwd)) if not v]
        domain = data.get("pidDomain") or this_domain
        is_local = (domain == this_domain)
        row = {"name": nm, "pid": pid, "cwd": cwd, "session_id": sid,
               "source": path, "kind": data.get("kind"),
               "socket": data.get("messagingSocketPath"),
               "pid_domain": domain, "local": is_local,
               "missing": missing, "problem": None,
               "doing": None, "idle_seconds": None, "running": None}
        if not is_local:
            # 不在這台機器上、也答不了話。它留在輸出裡，但它永遠不是「該關掉」的候選——
            # 這裡關不掉它，而把它列成候選等於教人去做一件做不到的事。
            out["not_this_machine"].append(row)
            continue
        row["running"] = alive(pid) if isinstance(pid, int) else None
        row["declaration"] = None
        if sid:
            decl, prob = read_declaration(sid)
            row["declaration"], row["problem"] = decl, prob
            if decl:
                row["doing"] = declaration_line(decl)
        else:
            row["problem"] = "登錄裡缺 sessionId，找不到它的宣告"
        if cwd and sid:
            idle, idle_prob = idle_seconds_of(transcript_path(cwd, sid), now)
            row["idle_seconds"] = idle
            if idle_prob:
                row["idle_problem"] = idle_prob
        out["sessions"].append(row)
    return out


def human(m):
    def dur(s):
        if s is None:
            return "?"
        if s < 3600:
            return f"{s // 60} 分"
        if s < 86400:
            return f"{s // 3600} 小時"
        return f"{s // 86400} 天 {(s % 86400) // 3600} 小時"
    lines = []
    if m["registry_problem"]:
        lines.append(f"問不到：{m['registry_problem']}")
        lines.append("這不是「沒有 session」——是這份登錄本身讀不到。")
        return "\n".join(lines)
    lines.append(f"這台機器上的 session（{len(m['sessions'])} 個）")
    for s in m["sessions"]:
        who = s["name"] or "（沒有名字）"
        pid = s["pid"] if s["pid"] is not None else "?"
        alive_s = {True: "活著", False: "已經結束", None: "?"}[s["running"]]
        lines.append(f"  {who}  pid={pid}  {alive_s}  閒置 {dur(s['idle_seconds'])}")
        if s["missing"]:
            lines.append(f"      這一列缺：{'、'.join(s['missing'])}")
        if s["problem"]:
            lines.append(f"      讀不到它在做什麼——{s['problem']}")
        elif s["doing"]:
            t = " ".join(s["doing"].split())
            lines.append(f"      它自己宣告：{t[:160]}{'…' if len(t) > 160 else ''}")
    if m["not_this_machine"]:
        lines.append("")
        lines.append(f"不在這台機器上（{len(m['not_this_machine'])} 個）"
                     "——這裡關不掉它們，所以它們不是「該關掉」的候選：")
        for s in m["not_this_machine"]:
            lines.append(f"  {s['name'] or '（沒有名字）'}  pidDomain={s['pid_domain']}")
    return "\n".join(lines)


DONE_WORDS = ("做完", "已完成", "完成了", "沒有進行中", "shipped", "已釋出")


def closable(m, idle_threshold=3600):
    """哪些**可以**關掉，每一項帶著憑什麼這樣認為。

    **這裡只出建議，執行關閉的是人。** 這支 skill 不送訊號、不 kill——關掉一個 session 會
    丟掉它還沒寫進磁碟的工作，而那件事沒有復原鍵。

    不在這台機器上的永遠不是候選：這裡關不掉它們，列進來等於教人去做一件做不到的事。
    """
    out = []
    for s in m["sessions"]:
        if s.get("running") is False:
            out.append((s, ["這個進程已經結束了，登錄檔還留著"]))
            continue
        why = []
        idle = s.get("idle_seconds")
        if idle is not None and idle >= idle_threshold:
            why.append(f"閒置 {idle // 3600} 小時 {(idle % 3600) // 60} 分")
        doing = s.get("doing") or ""
        if doing and any(w in doing for w in DONE_WORDS):
            why.append("它最後說的話是「做完了」那一類")
        if s.get("problem"):
            why.append(f"讀不到它在做什麼——{s['problem']}")
        if why:
            out.append((s, why))
    return out


def closable_text(m, idle_threshold=3600):
    rows = closable(m, idle_threshold)
    lines = ["可以考慮關掉的（建議，不是動作——**執行關閉的是人**）："]
    if not rows:
        lines.append("  沒有。每一個都在這台機器上、活著、而且剛動過。")
    for s, why in rows:
        lines.append(f"  {s['name'] or '（沒有名字）'}  pid={s['pid']}")
        for w in why:
            lines.append(f"      憑什麼：{w}")
    if m["not_this_machine"]:
        lines.append(f"  （{len(m['not_this_machine'])} 個不在這台機器上的沒有列進候選"
                     "——這裡關不掉它們。）")
    return "\n".join(lines)


def opening_text(commander):
    """每一則派工、互審、重建 prompt 開頭都一樣的那一段：開場四步與失聯協定。

    **路徑與名字都是實際值**。佔位字留給收件者自己填的話，它會照抄一個佔位字，或挑一個
    看起來比較順的——兩者都是安靜的。腳本寫成絕對路徑，因為收件者的 cwd 不一定在這個
    workspace 裡。
    """
    return "\n".join([
        "**建立那一刻做四件事，做完才開工：**",
        "  1. `ListAgents` 查出自己的名字。",
        "  2. 宣告自己（之後狀態變了再跑一次）：",
        "       CP=" + SCRIPT,
        "       python3 $CP --declare --session-id \"$(python3 $CP --whoami)\" \\",
        "         --line '<你是哪條線>' --browser '<有／沒有>' \\",
        "         --holding '<你接的是什麼>' --blocked-on '<沒卡就寫沒有>'",
        "     板子只讀這份宣告。沒宣告的話你那一列是空的，而它跟「沒人接」長得一模一樣。",
        "  3. 用 `ToolSearch` 查有沒有瀏覽器工具（例如查 `chrome navigate screenshot`）。",
        "     沒有就等指揮官轉達授權，**不自己找替代**。",
        "  4. `SendMessage` 給 " + commander + "：「<線名> 上線，我是 <名字>，瀏覽器：有／沒有」。",
        "",
        "**指揮官失聯**（`ListAgents` 找不到 " + commander + "，或送出後 30 分鐘沒回）：讀 "
        + JOURNAL + " 的最後幾筆，然後對人說一句：",
        "「指揮官失聯，請重建指揮官：新 session 跑 /command-post，先讀 " + JOURNAL + "」。",
        "不自己當指揮官、不接別人的單、手上的單照做。",
    ])


def order_text(issue_path, to_name, from_name):
    """一則派工指令的全文。

    它只做兩件別的地方做不到的事：**確認那條路徑真的存在**，以及把「回報給誰」寫死在
    文字裡。指揮者手打的那一版兩件都會漏——漏掉的樣子是安靜的：一個指向不存在位置的
    成功定義，讀起來跟一份好的成功定義一模一樣。

    它**不讀那張單的內容，也不讀它的輪次狀態**。這一支不判定任何工作在哪一站——那在
    driving-work-to-done，只在那裡。這裡只確認路徑在。
    """
    return "\n".join([
        "去做 " + issue_path + "。",
        "",
        "成功的定義在那張單自己身上：讀 " + os.path.join(issue_path, "index.md") + "。",
        "**以那份為準，不要照我這段話做**——我在這裡重講一次，就會有第二份會漂的定義。",
        "",
        opening_text(from_name),
        "",
        "做完，或撞到四種停點的任何一種（assertion_wrong／surfaced_concern／",
        "unconverged_cap／unauthorized_action），SendMessage 回 " + from_name + "。",
        "判準是一句話：**你接下來需不需要有人告訴你做什麼。**",
        "",
        "回報只要三樣：",
        "  1. 做完哪一張，或卡在哪一張。",
        "  2. 需不需要指引。",
        "  3. 需要的話，缺的是什麼。",
        "逐條判定不用講——它們留在那張單的 .spine/ 裡，要細節的人自己去讀。",
        "",
        "**回報不等於停下來等。** 送完那一則就自己抽下一張繼續。只有兩種情況才停著等：",
        "板子答不出下一步，或你自己走不下去。**輪次邊界不是停點。**",
        "",
        "（這則指令由 command-post 產出，收件者是 " + to_name + "）",
    ])


def review_order_text(issue_path, me, others, about, from_name):
    """一則互審指令的全文，寫給 `me` 那一個。

    它跟一對一的派工差三樣，而那三樣正是「互審」與「兩則獨立的派工」的差別：**對方是誰**、
    **要對對方的什麼下判斷**、**兩邊不同意的時候結果回到哪裡**。少了任何一樣，收到的人
    會各自做各自的，然後各自回報一份沒有對照過的結論。

    它仍然不重講那份成功定義，只給路徑——理由跟 `order_text` 是同一個。
    """
    others_text = chr(12289).join(others)
    return "\n".join([
        "去看 " + issue_path + "，然後跟 " + others_text + " 互審。",
        "",
        "成功的定義在那張單自己身上：讀 " + os.path.join(issue_path, "index.md") + "。",
        "**以那份為準，不要照我這段話做**——我在這裡重講一次，就會有第二份會漂的定義。",
        "",
        opening_text(from_name),
        "",
        "**要互相下判斷的是**：" + about,
        "",
        "怎麼互審：",
        "  1. 先自己做出結論，帶證據。",
        "  2. 把結論送給 " + others_text + "，並且去看它們的。",
        "  3. 對它們的結論逐條說「同意」或「不同意，因為……」，不同意要帶得出證據。",
        "  4. 收斂不了就把**兩邊各自的結論與各自的證據**一起送回 " + from_name + "，",
        "     不要挑一個送。指揮官要的是分歧本身，不是一個被抹平的答案。",
        "",
        "做完，或撞到四種停點的任何一種（assertion_wrong／surfaced_concern／",
        "unconverged_cap／unauthorized_action），SendMessage 回 " + from_name + "。",
        "判準是一句話：**你接下來需不需要有人告訴你做什麼。**",
        "",
        "回報只要三樣：",
        "  1. 你的結論，以及跟對方收斂到哪裡（同意了、還是分歧還在）。",
        "  2. 需不需要指引。",
        "  3. 需要的話，缺的是什麼。",
        "逐條判定不用講——它們留在那張單的 .spine/ 裡，要細節的人自己去讀。",
        "",
        "**回報不等於停下來等。** 送完那一則就自己抽下一張繼續。只有兩種情況才停著等：",
        "板子答不出下一步，或你自己走不下去。**輪次邊界不是停點。**",
        "",
        "（這則互審指令由 command-post 產出，收件者是 " + me + "；"
        "同一批還送給了 " + others_text + "）",
    ])


def review_orders(issue_path, to_names, about, from_name):
    """一批互審指令：一個收件者一則，每一則指名它自己與其餘的人。

    **不產一則群發的**。一則沒有指名收件者的指令，每一個收到的人都會以為對方會做。
    """
    blocks = []
    for i, me in enumerate(to_names):
        others = [n for j, n in enumerate(to_names) if j != i]
        blocks.append("── 給 " + me + " ──")
        blocks.append(review_order_text(issue_path, me, others, about, from_name))
        blocks.append("")
    return "\n".join(blocks).rstrip("\n")


def recent_tool_failures(cwd, session_id, tail_bytes=512 * 1024):
    """這個 session 最近**連續**失敗了幾次工具呼叫。

    為什麼是連續而不是總數：總數會隨 session 變長而單調上升，於是它對「現在還穩不穩」
    永遠給同一個方向的答案。連續失敗會被任何一次成功歸零，所以它量得到的是當下。

    **只讀尾巴。** 整份 transcript 這台機器上最大一份 92 MB，為了一個訊號讀完它，這支
    就變成它自己要避免的那件事。

    回傳 (連續失敗次數, 這個視窗裡看到幾筆工具結果, 問題)。三個值都要，因為
    **「看了 26 筆、沒有一筆失敗」與「這個視窗裡一筆工具結果都沒有」是兩件事**——後者
    答不出這個問題，而它們都會是 0。
    """
    path = transcript_path(cwd, session_id)
    if not os.path.exists(path):
        return None, None, "transcript 不在：" + path
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            if size > tail_bytes:
                fh.seek(size - tail_bytes)
            raw = fh.read()
    except OSError as exc:
        return None, None, "transcript 讀不動：" + str(exc)
    lines = raw.decode("utf-8", "replace").split("\n")
    if size > tail_bytes:
        # 第一行多半是從中間切開的，丟掉。留著只會多一個解析失敗。
        lines = lines[1:]
    results = []
    for line in lines:
        if '"tool_result"' not in line:
            continue
        try:
            data = json.loads(line)
        except ValueError:
            continue
        content = (data.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                results.append(bool(block.get("is_error")))
    streak = 0
    for failed in reversed(results):
        if not failed:
            break
        streak += 1
    return streak, len(results), None


def compaction_count(cwd, session_id):
    """這個 session 的 transcript 被壓縮過幾次。

    數的是 `isCompactSummary`——每一次壓縮在 transcript 裡留下一筆。**只回數字，不回
    任何據此得出的建議**：壓縮間隔量過是平的（1099／1248／1268／1149／1543／1270／1231／
    1111／1122），沒有加速的特徵，所以「什麼時候該換一個 session」偵測不出來。發明一個
    門檻只會讓一個猜測看起來像一個量測。

    回傳 (次數, 問題)。讀不到就回 (None, 為什麼)——空白不得長得跟 0 一樣。
    """
    path = transcript_path(cwd, session_id)
    if not os.path.exists(path):
        return None, "transcript 不在：" + path
    n = 0
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                # 整份 18 MB、14,000 筆，所以先用字串排除掉絕大多數再解析。
                if "isCompactSummary" not in line:
                    continue
                try:
                    if json.loads(line).get("isCompactSummary"):
                        n += 1
                except ValueError:
                    continue
    except OSError as exc:
        return None, "transcript 讀不動：" + str(exc)
    return n, None


def spine_rows(issues_root):
    """在飛的單有哪些——問脊椎自己，不自己算。

    回傳 (逐行的清單, 問題)。這一支**不推導任何一張單走到哪**：那個答案只有一個地方
    產得出來，而它就在 `driving-work-to-done`。這裡做的是把它印出來的那幾行重新排版。
    抄一份判定進來就是第二個權威，而兩個權威遲早會給出不同的答案。
    """
    if not os.path.exists(SPINE):
        return None, "問不到：" + SPINE + " 不在（這份文件因此沒有在飛的單那一段）"
    try:
        out = subprocess.run(["bash", SPINE, "next", "--across-issues", issues_root],
                             capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, "問不到：" + str(exc)
    lines = [ln for ln in out.stdout.splitlines() if ln.strip()]
    if not lines:
        return None, "問到了，但它一行都沒印（exit " + str(out.returncode) + "）"
    return lines, None


def holders_of(issues_root, ticket_path):
    """一張單現在被誰接著——**讀脊椎寫下的那一格，加上執行當下量到的死活**。

    回傳一句話，給板子第五欄用。五種答案長成五句不同的話，因為它們要人做的事不同：

    | 讀到什麼 | 印什麼 | 人要做什麼 |
    |---|---|---|
    | `holders` 有活著的對象 | 那幾個的名字 | 去問他 |
    | `holders` 是空的／沒有這個欄位 | 沒有人接 | 去找人接 |
    | 狀態檔讀不到、登錄讀不到 | 這一次問不到 | 去看那份檔案 |
    | 有紀錄，而登錄裡找不到那個對象 | 紀錄在、人不在 | 這張單其實沒人在做 |
    | 紀錄自己寫著推不出來 | 推不出來是誰（理由） | 去看為什麼推不出來 |

    **死活是這一刻量的，不是紀錄裡寫的。** 一份紀錄只證明「當時它動過這張單」；那個
    session 還在不在，只有現在去問登錄才知道。
    """
    state = os.path.join(issues_root, ticket_path, ".spine", "loop-state.json")
    if not os.path.exists(state):
        return "這一次問不到（沒有輪次狀態檔：" + state + "）"
    try:
        data = json.load(open(state, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return "這一次問不到（輪次狀態檔讀不動：" + str(exc) + "）"
    if not isinstance(data, dict):
        return "這一次問不到（輪次狀態檔不是一個物件）"
    holders = data.get("holders")
    if not isinstance(holders, list) or not holders:
        return "沒有人接"

    rows, problem = read_registry()
    if problem:
        return "這一次問不到（" + problem + "）"
    live = {}
    for _, row in rows:
        if isinstance(row, dict) and row.get("sessionId"):
            live[row["sessionId"]] = row

    said = []
    for entry in holders:
        if not isinstance(entry, dict):
            continue
        who = entry.get("identity")
        if not who:
            said.append("推不出來是誰（" + str(entry.get("why") or "沒有記下理由") + "）")
            continue
        row = live.get(who)
        if row is None:
            said.append("紀錄在、人不在（" + who[:8] + "…）")
            continue
        name = row.get("name") or "（沒有名字）"
        pid = row.get("pid")
        running = alive(pid) if isinstance(pid, int) else None
        if running is False:
            said.append("紀錄在、人不在（" + name + " 已經結束）")
        else:
            said.append(name)
    if not said:
        return "沒有人接"
    # 不收斂成一個。同一張單被一個以上的對象接著，正是要被看見的東西。
    return "、".join(said)


def board_text(m, issues_root, waiting_on, session_id=None, idle_threshold=3600,
               journal_tail=8):
    """指揮官每一輪重讀的那一頁。

    **產生的部分不手寫**（先例是 `OPEN.md`，它自己的表頭就寫著下一次重算會整份重寫），
    **成功條件只指過去、不抄**（唯一權威是那張單的 fence），**手寫的只有一格**——指揮官
    自己在等什麼。那一格是板子答不出來的唯一一樣東西。

    它的主要用途不是交接，是**每一輪重讀**：把目標重寫到 context 尾端，避開 lost-in-the-
    middle。交接是副作用。
    """
    out = ["# 指揮台", ""]

    entries, jprob = read_journal_entries()
    out.append("## 我在等什麼（唯一手寫的一格）")
    out.append("")
    if waiting_on:
        out.append(waiting_on)
    else:
        # 沒給就讀日誌裡最後一句。**這一格以前是交棒時唯一會遺失的東西**，所以它不能只活在
        # 一次命令列參數裡——給過一次，下一個指揮官不給也讀得回來。
        said, head = last_waiting(entries)
        if said:
            out.append(said)
            out.append("")
            out.append("（這一句是從日誌讀來的，寫在「" + head + "」。這一次沒有給 --waiting-on。）")
        elif jprob:
            out.append("（沒有給 --waiting-on，日誌也讀不到——" + jprob + "）")
        else:
            out.append("（沒有給 --waiting-on，日誌裡也沒有紀錄。指揮官從來沒說過在等什麼，"
                       "或者說過而沒有落進日誌。）")
    out.append("")

    out.append("## 日誌尾端（最後 " + str(journal_tail) + " 筆，全文在 " + JOURNAL + "）")
    out.append("")
    if jprob:
        out.append(jprob)
    else:
        for e in entries[-journal_tail:]:
            out.append(e)
            out.append("")

    if not session_id:
        answer = "？次（推不出這一趟是哪一個 session，這一次問不到）"
    else:
        # **cwd 要拿那個 session 自己登錄的那一個，不是呼叫者現在站的地方。** transcript
        # 的目錄名是從 session 開場時的 cwd 算出來的；從一個 worktree 裡跑這支的話，
        # 用 os.getcwd() 解出來的是一條不存在的路徑，而輸出只說「transcript 不在」。
        home = None
        for row in m["sessions"]:
            if row.get("session_id") == session_id:
                home = row.get("cwd")
                break
        n, why = compaction_count(home or os.getcwd(), session_id)
        answer = str(n) + " 次" if why is None else "？次（" + why + "）"
    out.append("這個 session 壓縮過 " + answer + "（數的是 transcript 裡的 "
               + "isCompactSummary）。")

    # 第二個訊號。**兩個都只印，不判定**——理由跟壓縮次數是同一個：偵測不出那一刻的
    # 東西配上一個門檻，只會讓一個猜測看起來像一個量測。
    if not session_id:
        fail_line = "連續失敗的工具呼叫：？（推不出這一趟是哪一個 session，這一次問不到）"
    else:
        streak, seen, why2 = recent_tool_failures(home or os.getcwd(), session_id)
        if why2:
            fail_line = "連續失敗的工具呼叫：？（" + why2 + "）"
        elif seen == 0:
            fail_line = ("連續失敗的工具呼叫：這一次答不出來"
                         "（transcript 尾端 512 KB 裡一筆工具結果都沒有，"
                         "所以 0 在這裡不代表沒有失敗）")
        else:
            fail_line = ("連續失敗的工具呼叫：" + str(streak)
                         + "（看的是 transcript 尾端 512 KB 裡的 " + str(seen)
                         + " 筆工具結果，從最新的往回數到第一次成功為止）")
    out.append(fail_line)
    out.append("**這兩個訊號只印，不判斷該不該換一個。** 壓縮間隔量過是平的、"
               "連續失敗沒有量過門檻，兩者都偵測不出「開始不穩」那一刻，"
               "所以判斷留給人。要換的時候照〈交棒〉那一節走。")
    out.append("")

    out.append("## 在飛的單（產生的，不要手改）")
    out.append("")
    rows, why = spine_rows(issues_root)
    if why:
        out.append(why)
    else:
        # `next:` 那一行是脊椎的建議，它指的那一張同時也會出現在下面的清單裡。兩者
        # 印成兩列的話，同一張單在板子上出現兩次，而讀的人分不出那是兩張還是一張。
        table, notes, suggested = [], [], None
        listed = set()
        for ln in rows:
            kind, _, rest = ln.partition(":")
            path = rest.split()[0] if rest.split() else rest
            if kind == "next":
                notes.append("脊椎建議的下一張：`" + path + "`")
                # 它同時也是一張在飛的單，所以它要有自己的一列。**只當成一句話的那一版，
                # 一張正在施工、正被人接著的單在這張表上根本沒有列**——而那正好是第五欄
                # 最該印出東西的那一種。下面用路徑去重，所以它跟 seed／stop 重疊時不會
                # 出現兩次。
                suggested = path
            elif kind in ("stop", "seed"):
                listed.add(path)
                table.append("| `" + path + "` | " + kind + " | `"
                             + os.path.join(issues_root, path, "index.md") + "` | "
                             + holders_of(issues_root, path) + " |")
            else:
                notes.append(ln)
        if suggested and suggested not in listed:
            table.insert(0, "| `" + suggested + "` | next | `"
                         + os.path.join(issues_root, suggested, "index.md") + "` | "
                         + holders_of(issues_root, suggested) + " |")
        for n in notes[:1]:
            out.append(n)
            out.append("")
        out.append("| 單 | 這一行是哪一種 | 成功條件在哪 | 誰在做 |")
        out.append("|---|---|---|---|")
        out.extend(table)
        out.append("")
        for n in notes[1:]:
            out.append(n)
        out.append("")
        out.append("「誰在做」那一欄是產生的：值來自那張單的 `.spine/loop-state.json` 裡"
                   "`init`／`advance`／`record` 寫下的 `holders[]`，加上**執行這一刻**去 session "
                   "登錄量到的死活。答不出來的時候它說出是哪一種答不出來——沒有人接、這一次"
                   "問不到、紀錄在而人不在、推不出來是誰——四句不同的話，不合併成空白。")
        if all("沒有人接" in row.rsplit("|", 2)[-2].strip() for row in table) and table:
            out.append("")
            out.append("**這一欄整欄是「沒有人接」，而那是真話，不是壞掉。** `holders[]` 是 "
                       "DP-622 才加的欄位——在它存在之前走過流程的單，沒有任何一趟寫得下"
                       "那個值。等這幾張單各自再被 `init`／`advance`／`record` 碰一次，"
                       "那一格才會有東西。")
        out.append("")
        out.append("「成功條件在哪」那一欄是**路徑**，不是內容。抄進來就是第二份會漂的定義，"
                   "而漂的是最不能漂的那一份。")
    out.append("")

    out.append("## 這台機器上的 session（產生的，不要手改）")
    out.append("")
    out.append(human(m))
    return "\n".join(out)


def lines_to_rebuild(now, since_hours):
    """哪幾條線要各印一段：有宣告 `line` 的、在 since_hours 之內宣告過的，同一條線取最新的那份。

    **只讀宣告，不從名字或 cwd 推線名。** 沒宣告過線的 session 不會出現在這裡——那一段
    答不出它是哪條線，印一段猜的比不印糟。它們在板子上照樣看得到。
    """
    by_line, skipped = {}, []
    try:
        names = sorted(os.listdir(DECLARATIONS))
    except OSError:
        names = []
    reg = {d.get("sessionId"): d for _, d in read_registry()[0]}
    for fn in names:
        if not fn.endswith(".json"):
            continue
        decl, prob = read_declaration(fn[:-5])
        if not decl:
            continue
        at = decl.get("declared_at") or 0
        if now - at > since_hours * 3600:
            continue
        if decl.get("line") == COMMANDER_LINE:
            # 指揮官自己的那一段另外印，不當成一條實作線。
            continue
        if not decl.get("line"):
            skipped.append(reg.get(decl.get("session_id"), {}).get("name") or fn[:-5])
            continue
        cur = by_line.get(decl["line"])
        if not cur or at > (cur.get("declared_at") or 0):
            by_line[decl["line"]] = decl
    out = []
    for line, decl in sorted(by_line.items()):
        data = reg.get(decl.get("session_id")) or {}
        pid = data.get("pid")
        running = alive(pid) if isinstance(pid, int) else None
        out.append((line, decl, data.get("name") or decl.get("session_id"), running))
    return out, skipped


def rebuild_text(commander, issues_root, since_hours=24, now=None, per_line=6):
    """重建時要貼給新 session 的全部 prompt。

    使用者 2026-09-19 的原話：「直接給我 prompt，不要用文件給，用 md 給，我要能直接複製
    貼上」。所以**全文印在輸出裡**，每一段一個可以整段複製的 markdown 區塊；檔案只是副本。

    它不送給任何人，也不讀任何 transcript——每一段的內容只來自宣告與日誌。
    """
    now = now or time.time()
    entries, jprob = read_journal_entries()
    lines, skipped = lines_to_rebuild(now, since_hours)
    try:
        with open(STANDING, encoding="utf-8") as fh:
            standing = fh.read().strip()
    except OSError:
        standing = None
    standing_block = standing or ("（日誌目錄裡沒有常駐規矩檔：" + STANDING + "。"
                                  "這一條線要守的規矩只有下面那張單與 skill 自己帶的。）")
    fence = "````"
    out = ["# 重建 prompt（" + stamp(now) + "）", ""]
    out.append("每一段是一個新 session 的第一則訊息，整段複製貼上。")
    out.append("")

    said, head = last_waiting(entries)
    roster = ["| 線 | 上一任 | 還活著 | 接的是什麼 | 卡在哪 |", "|---|---|---|---|---|"]
    for line, decl, name, running in lines:
        roster.append("| " + " | ".join([
            line, name, {True: "是", False: "否", None: "?"}[running],
            " ".join(str(decl.get("holding")).split()),
            " ".join(str(decl.get("blocked_on")).split())]) + " |")
    out.append("## 指揮官")
    out.append("")
    out.append(fence + "markdown")
    out += [
        "你是**指揮官**。先跑 /command-post，然後照這個順序讀，前三步都不用問人：",
        "",
        "1. `python3 " + SCRIPT + " --board --issues " + issues_root + "`"
        "——它印上一任在等什麼、日誌尾端、在飛的單、這台機器上的 session。",
        "2. 日誌全文：" + JOURNAL + "（append-only，從尾端往回讀到你懂為止）。",
        "3. command-post 的 SKILL.md〈交棒〉那一節。",
        "",
        "上一任在等的（" + (head or "日誌裡沒有紀錄") + "）：" + (said or "沒有紀錄"),
        "",
        "重建時各條線的宣告：",
        "",
    ] + roster + [
        "",
        "上線之後，用 `ListAgents` 查出自己的名字，`SendMessage` 告訴每一條還活著的線：",
        "「指揮官換成 <你的名字>，回報改送這裡」。之後照 SKILL.md 做事。",
        "",
        "## 常駐規矩",
        "",
        standing_block,
    ]
    out.append(fence)
    out.append("")

    for line, decl, name, running in lines:
        # 線名常常是另一個詞的前綴（`DP` 之於 `DP-732`），所以不做子字串比對：只認宣告那一格、
        # 「X 線」這種寫法、或上一任的名字。
        marks = ("線：" + line, line + " 線", line + "線", "線＝" + line) + ((name,) if name else ())
        related = [e for e in entries if any(k in e for k in marks)][-per_line:]
        out.append("## " + line + " 線（上一任 " + name + "，"
                   + {True: "還活著", False: "已經結束", None: "死活不明"}[running] + "）")
        out.append("")
        out.append(fence + "markdown")
        out += [
            "你是 **" + line + " 線**，實作 session。指揮官是 " + commander + "；"
            "使用者只在指揮官那條線發號施令，你的回報送給指揮官。",
            "",
            opening_text(commander),
            "",
            "**回報**：每到一站回一則——做完哪張或卡在哪、需不需要指引、缺什麼。"
            "回報完不停下來等，繼續下一件；只有走不下去才停。",
            "",
            "## 常駐規矩",
            "",
            standing_block,
            "",
            "## 你的工作",
            "",
            "上一任最後的宣告（" + stamp(decl.get("declared_at")) + "）：",
            "- 接：" + " ".join(str(decl.get("holding")).split()),
            "- 卡：" + " ".join(str(decl.get("blocked_on")).split()),
            "- 開單：" + str(decl.get("tickets_opened")),
            "",
            "日誌裡跟這條線有關的最近幾筆：",
            "",
        ]
        out += ([e + "\n" for e in related] if related
                else ["（日誌裡沒有提到「" + line + "」或「" + name + "」的紀錄）", ""])
        out += ["從那張單自己的 index.md 與 .spine/ 接手；不確定在哪一站就問 driving-work-to-done。"]
        out.append(fence)
        out.append("")

    if not lines:
        out.append("（" + str(since_hours) + " 小時內沒有任何宣告說出自己是哪條線，"
                   "所以沒有線的段落可以印。各條線要先用 --declare --line 宣告。）")
    if skipped:
        out.append("沒印段落的 session（宣告裡沒說是哪條線）：" + "、".join(skipped))
    if jprob:
        out.append("日誌：" + jprob)
    return "\n".join(out).rstrip() + "\n"


def save_rebuild_copy(text, now=None):
    """副本。**檔案不是給人讀的那一份**——對話裡印出來的才是。回傳 (path, problem)。"""
    now = now or time.time()
    d = os.path.join(JOURNAL_DIR, "prompts", time.strftime("%Y-%m-%d", time.localtime(now)))
    path = os.path.join(d, "rebuild-" + time.strftime("%H%M%S", time.localtime(now)) + ".md")
    try:
        os.makedirs(d, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path, None
    except OSError as exc:
        return path, "副本寫不進去：" + path + "（" + str(exc) + "）"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true", help="輸出機器讀的那一份")
    ap.add_argument("--closable", action="store_true",
                    help="哪些可以關掉，帶著憑什麼這樣認為。只出建議，不關任何東西。")
    ap.add_argument("--idle-threshold", type=int, default=3600,
                    help="閒置多久算「可以考慮關掉」，單位是秒")
    ap.add_argument("--now-epoch", type=float, default=None,
                    help="把「現在」固定成這個時間，讓輸出可以被重現")
    ap.add_argument("--declare", action="store_true",
                    help="寫下這個 session 自己的那一行。只寫自己的，不碰別人的。")
    ap.add_argument("--session-id", help="--declare 用：這個 session 的 sessionId")
    ap.add_argument("--holding", help="--declare 用：接的是什麼")
    ap.add_argument("--blocked-on", help="--declare 用：現在卡在哪；沒卡就寫「沒有」")
    ap.add_argument("--tickets-opened", default="無",
                    help="--declare 用：開了哪幾張單給誰")
    ap.add_argument("--line", help="--declare 用：你是哪條線")
    ap.add_argument("--browser", help="--declare 用：有沒有瀏覽器工具（有／沒有）")
    ap.add_argument("--log", action="store_true",
                    help="往指揮官日誌記一筆（收到回報、做了裁決時）。append-only。")
    ap.add_argument("--who", help="--log 用：這一筆是誰的事")
    ap.add_argument("--what", help="--log 用：發生什麼")
    ap.add_argument("--problem", help="--log 用：碰到的問題（可以沒有）")
    ap.add_argument("--decision", help="--log 用：決定了什麼（可以沒有）")
    ap.add_argument("--rebuild", action="store_true",
                    help="把重建指揮官與每一條線的開場 prompt 印成可整段複製的 markdown，"
                         "副本存進日誌目錄。不送給任何人。")
    ap.add_argument("--since-hours", type=float, default=24,
                    help="--rebuild 用：多久之內宣告過的線才印段落")
    ap.add_argument("--journal-tail", type=int, default=8,
                    help="--board 用：印日誌最後幾筆")
    ap.add_argument("--order", action="store_true",
                    help="產一則派工指令的全文。只印出來，不送給任何人。")
    ap.add_argument("--issue", help="--order 用：那張單的路徑")
    ap.add_argument("--to", dest="to_names", action="append", default=None,
                    help="要它去做的那個 session。--order 收剛好一個；"
                         "--review 給幾次就是幾個人互審")
    ap.add_argument("--review", action="store_true",
                    help="產一批互審指令：一個收件者一則，每一則指名它自己與其餘的人。"
                         "只印出來，不送給任何人。")
    ap.add_argument("--about", default=None,
                    help="--review 用：要互相下判斷的是什麼")
    ap.add_argument("--from", dest="from_name", default=None,
                    help="--order 用：回報給誰。預設是這個 session 自己的名字（$CLAUDE_SESSION_NAME）")
    ap.add_argument("--board", action="store_true",
                    help="產指揮台那一頁：指揮官在等什麼、日誌尾端、在飛的單、這台機器上的 session")
    ap.add_argument("--issues", default="issues", help="--board 用：單的根目錄")
    ap.add_argument("--waiting-on", default=None,
                    help="--board／--log 用：唯一手寫的那一格——指揮官自己在等什麼。"
                         "給了就落進日誌，之後不給就讀日誌裡最後一句")
    ap.add_argument("--whoami", action="store_true",
                    help="印出跑這一趟的那個 session 的 sessionId。推出來的，不靠任何宣告。")
    args = ap.parse_args()
    if args.whoami:
        # 脊椎宣告掃到的就是這個模式。**印一行，非 0 就是這一次推不出來**——理由走 stderr，
        # 因為呼叫者把 stdout 原樣當成身分記下來，一句解釋混進去就變成一個假的身分。
        sid, why = whoami()
        if why:
            print(why, file=sys.stderr)
            return 2
        print(sid)
        return 0
    if args.board:
        # 環境變數優先，推導是後備。以前只讀環境變數，而它在這裡從來沒有被設過——於是
        # 「壓縮過幾次」每一次都印「這一次問不到」，那是同一個缺口的第二個出口。
        sid = os.environ.get("CLAUDE_SESSION_ID")
        if not sid:
            sid, _ = whoami()
        if args.waiting_on:
            # 給了就落進日誌，交棒時才讀得回來。跟上一句一字不差就不再寫——板子每一輪都
            # 重讀，每一輪都寫一次的話，日誌尾端會被同一句洗掉。
            said, _ = last_waiting(read_journal_entries()[0])
            if said != args.waiting_on:
                who = args.from_name or os.environ.get("CLAUDE_SESSION_NAME") \
                    or (session_name_of(sid) if sid else "指揮官")
                _, prob = append_journal(WAITING_KIND, who, [("在等", args.waiting_on)],
                                         now=args.now_epoch)
                if prob:
                    print(prob, file=sys.stderr)
                    return 7
        print(board_text(build(now=args.now_epoch), args.issues, args.waiting_on,
                         session_id=sid,
                         idle_threshold=args.idle_threshold,
                         journal_tail=args.journal_tail))
        return 0
    if args.log:
        missing = [f for f, v in (("--who", args.who), ("--what", args.what)) if not v]
        if missing:
            print("--log 要的東西沒給齊，缺：" + chr(12289).join(missing), file=sys.stderr)
            return 2
        path, prob = append_journal("紀錄", args.who, [
            ("發生什麼", args.what), ("問題", args.problem), ("決定", args.decision)],
            now=args.now_epoch)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        if args.waiting_on:
            _, prob = append_journal(WAITING_KIND, args.who, [("在等", args.waiting_on)],
                                     now=args.now_epoch)
            if prob:
                print(prob, file=sys.stderr)
                return 7
        print("記在 " + path)
        return 0
    if args.rebuild:
        frm = args.from_name or os.environ.get("CLAUDE_SESSION_NAME", "")
        if not frm:
            print("指揮官是誰答不出來：--from 沒給，環境裡也沒有 CLAUDE_SESSION_NAME。",
                  file=sys.stderr)
            print("每一段 prompt 都要寫出回報給誰，一段沒有收件者的 prompt 等於沒有回報要求。",
                  file=sys.stderr)
            return 4
        text = rebuild_text(frm, args.issues, since_hours=args.since_hours,
                            now=args.now_epoch)
        path, prob = save_rebuild_copy(text, now=args.now_epoch)
        print(text)
        print(prob or ("副本：" + path + "（對話裡印出來的這一份才是給人貼的）"))
        return 0
    if args.order or args.review:
        which = "--review" if args.review else "--order"
        to_names = args.to_names or []
        missing = [f for f, v in (("--issue", args.issue),
                                  ("--to", to_names)) if not v]
        if args.review and not args.about:
            missing.append("--about")
        if missing:
            print(which + " 要的東西沒給齊，缺："
                  + chr(12289).join(missing), file=sys.stderr)
            if "--about" in missing:
                print("互審少了「要對對方的什麼下判斷」，收到的人會各自做各自的"
                      "——那跟兩則獨立的派工沒有差別。", file=sys.stderr)
            return 2
        if not os.path.isdir(args.issue):
            print("這條路徑不在：" + args.issue, file=sys.stderr)
            print("成功的定義指向一個不存在的位置，跟沒有成功定義一樣——所以這裡不產出指令。",
                  file=sys.stderr)
            return 3
        frm = args.from_name or os.environ.get("CLAUDE_SESSION_NAME", "")
        if not frm:
            print("回報給誰答不出來：--from 沒給，環境裡也沒有 CLAUDE_SESSION_NAME。",
                  file=sys.stderr)
            print("一則沒有收件者的回報要求，等於沒有回報要求。", file=sys.stderr)
            return 4
        # 人數與模式對不上的兩種，各自說各自的話。**不要安靜地產出一則看起來像的東西**：
        # 一個人的「互審」讀起來跟互審一模一樣，而收到的人沒有對象可以互審。
        if args.review and len(to_names) < 2:
            print("互審至少要兩個收件者，現在只有 " + str(len(to_names))
                  + " 個：" + chr(12289).join(to_names), file=sys.stderr)
            print("一個人審不了「互相」。要派給一個人就用 --order。", file=sys.stderr)
            return 5
        if args.order and len(to_names) > 1:
            print("--order 是一對一，收剛好一個 --to，現在有 " + str(len(to_names))
                  + " 個：" + chr(12289).join(to_names), file=sys.stderr)
            print("要它們互相審對方的結論就用 --review（它會一人產一則，"
                  "並且說出對方是誰）。", file=sys.stderr)
            return 6
        # 產出那一刻落一筆。**產出不等於送出**——送出仍然是 SendMessage，所以這一筆寫的是
        # 「產出了給誰的指令」，不是「送出了」。
        _, prob = append_journal("互審" if args.review else "派工", frm, [
            ("單", args.issue), ("給", chr(12289).join(to_names)),
            ("要互相下判斷的是", args.about if args.review else None),
            ("註", "這一筆記的是產出指令；送出另由 SendMessage")], now=args.now_epoch)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        if args.review:
            print(review_orders(args.issue, to_names, args.about, frm))
        else:
            print(order_text(args.issue, to_names[0], frm))
        return 0
    if args.declare:
        missing = [f for f, v in (("--session-id", args.session_id),
                                  ("--line", args.line), ("--browser", args.browser),
                                  ("--holding", args.holding),
                                  ("--blocked-on", args.blocked_on)) if not v]
        if missing:
            print("宣告要五樣都給，缺：" + chr(12289).join(missing), file=sys.stderr)
            if "--line" in missing:
                print("沒說是哪條線的話，接手的指揮官看得到有這個 session，看不出它是哪一條。",
                      file=sys.stderr)
            return 2
        path = write_declaration(args.session_id, args.holding, args.blocked_on,
                                 args.tickets_opened, line=args.line, browser=args.browser)
        _, prob = append_journal("宣告", session_name_of(args.session_id), [
            ("線", args.line), ("瀏覽器", args.browser), ("接", args.holding),
            ("卡", args.blocked_on), ("開單", args.tickets_opened)], now=args.now_epoch)
        print("宣告寫在 " + path)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        return 0
    m = build(now=args.now_epoch)
    if args.closable:
        m["closable"] = [{"name": s["name"], "pid": s["pid"], "why": why}
                         for s, why in closable(m, args.idle_threshold)]
        print(json.dumps(m, ensure_ascii=False, indent=2) if args.json
              else closable_text(m, args.idle_threshold))
        return 0
    print(json.dumps(m, ensure_ascii=False, indent=2) if args.json else human(m))
    return 0


if __name__ == "__main__":
    sys.exit(main())
