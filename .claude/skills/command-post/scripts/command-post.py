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
import argparse, calendar, glob, json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
REGISTRY = os.path.join(HOME, ".claude", "sessions")
PROJECTS = os.path.join(HOME, ".claude", "projects")

# 「在飛的單有哪些」只有一個地方答得出來，而它不在這支 skill 裡。這一行是去問它的路徑，
# 不是一份抄過來的判定——見 `spine_rows()`。它跟其他模組常數放在一起，因為它就是一個。
SPINE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "driving-work-to-done", "scripts", "spine-loop-state.sh")


def spine_where(issue_path):
    """問權威（spine-loop-state.sh where）那張單現在的樣子。回傳 ({鍵: 值}, problem)。"""
    state = os.path.join(issue_path, ".spine", "loop-state.json")
    if not os.path.exists(SPINE):
        return None, "問不到站別：" + SPINE + " 不在"
    if not os.path.isfile(state):
        return None, "問不到站別：這張單沒有輪次狀態（" + state + "）"
    try:
        out = subprocess.run(["bash", SPINE, "where", "--state", state],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, "問不到站別：" + str(exc)
    rows = {}
    for row in out.stdout.splitlines():
        k, sep, v = row.partition("=")
        if sep and k and " " not in k:
            rows.setdefault(k, v.strip())
    if "station" not in rows:
        return None, "問不到站別：where 沒有印 station（" + (out.stderr.strip() or "無輸出") + "）"
    return rows, None


def spine_station(issue_path):
    """那張單現在在哪一站，問權威（spine-loop-state.sh where），不在這裡推（DP-865）。

    回傳 (station, problem)。站別的名字就是那一站的 skill 名；`delivered` 沒有下一站的 skill。
    """
    rows, problem = spine_where(issue_path)
    return (rows["station"], None) if rows else (None, problem)


# 改動落在哪個 repo，那個 repo 自己的規矩檔就是權威（DP-885）。領域知識是 none 的單不改程式碼，不帶。
REPO_OWN_RULES_LINE = ("改動落在的每個 repo，動手之前讀完它根目錄的 CLAUDE.md、AGENTS.md 與 .claude/rules/，"
                       "跟框架衝突以 repo 為準並回報。")


def pack_line(issue_path):
    """派工與重建指令裡講領域知識的那一句。開輪次時 --pack 只被記下，內容從來沒有被放到
    線面前（DP-880），所以派這張單的那一刻就指名它。問不到就說問不到，不擋派工。"""
    rows, problem = spine_where(issue_path) if issue_path else (None, "沒有指得到的單")
    pack = (rows or {}).get("pack", "").split()
    if not pack:
        return "這張單的領域知識問不到（" + (problem or "where 沒有印 pack") + "）。" + REPO_OWN_RULES_LINE
    if pack[0] == "none":
        return "這張單沒有領域知識，不用 invoke 任何一支。"
    if pack[0] == "unrecorded":
        return "這張單沒有記領域知識。" + REPO_OWN_RULES_LINE
    return ("這張單的領域知識是 /" + pack[0] + "：動手之前 invoke 它，改動照它做。"
            + REPO_OWN_RULES_LINE)


def held_issue(holding):
    """宣告裡「接的是什麼」指得到哪一張單：第一個問得到的單號，問 spine-loop-state.sh find。"""
    if not holding or not os.path.exists(SPINE):
        return None
    for key in re.findall(r"(?<![A-Za-z0-9])[A-Z][A-Z0-9]*-\d+(?![0-9])", holding):
        try:
            out = subprocess.run(["bash", SPINE, "find", key], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            continue
        found = out.stdout.strip().splitlines()
        if out.returncode == 0 and found and os.path.isdir(found[0]):
            return found[0]
    return None


def station_skill(station):
    """站別對到的 skill。delivered 是終點，沒有一支 skill 要從那裡開始。"""
    return None if station == "delivered" else station


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
                      f"站：{decl.get('station') or '沒宣告'}",
                      f"skills：{decl.get('skills') or '沒宣告'}",
                      f"接：{decl['holding']}",
                      f"卡：{decl['blocked_on']}", f"開單：{opened}"])


# 上一份宣告的「接」裡，一個承諾靠這三種東西才找得回來：單號、PR 號、日期（DP-888）。
HOLDING_KEY = re.compile(r"\b[A-Z][A-Z0-9]*-\d+\b|#\d+\b|\b\d{4}-\d{1,2}-\d{1,2}\b|\b\d{1,2}/\d{1,2}\b")
HOLDING_SEGMENT = re.compile(r"[、；;，,\n]")


def dropped_from_holding(previous, current):
    """上一份「接」有、這一份沒有的單號／PR 號／日期，各帶上一份裡含它的那一段原文。

    重宣告時舊的承諾會安靜地從板子上消失，而那一刻沒有人在看（DP-888）。只回字串，
    不判斷那件事是做完了還是忘了——那只有宣告的人自己知道。沒有掉的回空字串。
    """
    kept = set(HOLDING_KEY.findall(current or ""))
    items, seen = [], set()
    for seg in HOLDING_SEGMENT.split(previous or ""):
        for key in HOLDING_KEY.findall(seg):
            if key not in kept and key not in seen:
                seen.add(key)
                items.append(f"{key}（上一份：{seg.strip()}）")
    return chr(12289).join(items)


def previous_holding(session_id):
    """同一個 session 上一份宣告的「接」。讀不到（沒寫過、讀不動）就回 None，不比。"""
    try:
        with open(declaration_path(session_id), encoding="utf-8") as fh:
            decl = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None
    return decl.get("holding") if isinstance(decl, dict) else None


def write_declaration(session_id, holding, blocked_on, tickets_opened,
                      line=None, browser=None, station=None, skills=None, dropped=None):
    """這個 session 寫下自己的那一行。**只寫自己的那一份，不碰別人的。**"""
    os.makedirs(DECLARATIONS, exist_ok=True)
    path = declaration_path(session_id)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"session_id": session_id, "line": line, "browser": browser,
                   "station": station, "skills": skills,
                   "holding": holding,
                   "blocked_on": blocked_on, "tickets_opened": tickets_opened,
                   "dropped": dropped or None,
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
# 指揮官送給別的 session 的每一則本文，產出那一刻記一筆 sha256。PreToolUse hook
# `block-commander-freehand-send.sh` 拿 SendMessage 的本文來對：對不上就是手打的，擋。
# 只記雜湊不記全文——全文已經在日誌與對話裡，這裡要的只是「這一則是不是印過的」。
SENT = os.path.join(JOURNAL_DIR, "sent.jsonl")


def body_sha(text):
    """本文的指紋。去掉尾端空白再算：印出來多一個換行、送出時少一個，不該變成兩則。"""
    import hashlib
    return hashlib.sha256(text.rstrip().encode("utf-8")).hexdigest()


def record_sent(to_name, text, now=None):
    """記下這一則可以送。回傳 problem 或 None——寫不進去要失敗，不然 hook 會擋下一則合法的。"""
    try:
        os.makedirs(JOURNAL_DIR, exist_ok=True)
        with open(SENT, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": stamp(now), "to": to_name,
                                 "sha256": body_sha(text)}, ensure_ascii=False) + "\n")
        return None
    except OSError as exc:
        return f"送出紀錄寫不進去：{SENT}（{exc}）"
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
LOG_KIND = "紀錄"
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


# 「這個單號／PR／人名，日誌裡已經寫過什麼」。指揮官往上問之前、壓縮之後接手之前都要問
# 這一句，而它以前只靠記得——2026-10-16 一件三筆紀錄都寫著有線在接的事，被當成沒人顧拿去
# 問了使用者。所以它是一個命令，不是一句叮嚀。
LOOKUP_FIELDS = ("- 發生什麼：", "- 決定：", "- 在等：", "- 接：", "- 卡：")
# 一起出現的鍵：單號（`ABC-123`）與 PR 號（`#123`）。紀錄常常只寫 PR 不寫單號，
# 只查單號就撈不到那幾筆，所以命中的那幾筆裡還出現哪些，要逐個說出來。
CO_KEY = re.compile(r"(?<![A-Za-z0-9])(?:[A-Z][A-Z0-9]*-\d+|#\d+)(?![0-9])")


def key_pattern(key):
    """key 不跨數字邊界：`AB-98` 不命中 `AB-981`，`#90` 不命中 `#900`。"""
    pat = re.escape(key)
    if key[:1].isalnum():
        pat = r"(?<![A-Za-z0-9])" + pat
    if key[-1:].isdigit():
        pat += r"(?![0-9])"
    return re.compile(pat)


def journal_with_lines():
    """回傳 ([(標頭行號, [行...])...], problem)。切法跟 read_journal_entries 同一條 ENTRY_HEAD。"""
    entries, problem = read_journal_entries()
    if problem and not entries:
        return [], problem
    with open(JOURNAL, encoding="utf-8") as fh:
        text = fh.read()
    out, cur = [], None
    for no, ln in enumerate(text.splitlines(), 1):
        if ENTRY_HEAD.match(ln):
            cur = (no, [ln])
            out.append(cur)
        elif cur is not None:
            cur[1].append(ln)
    return out, None


def lookup_text(keys, since_hours=24, tail=8, now=None):
    """每個 key 一段：日誌命中、各線宣告命中、最後一句在等有沒有它、一起出現的鍵。

    唯讀。回傳 (text, problem)——日誌讀不到時 problem 不是 None，那一趟什麼都不印，
    因為「日誌裡沒有」跟「日誌讀不到」要人做的事不一樣。
    """
    now = now or time.time()
    entries, problem = journal_with_lines()
    if problem:
        return None, problem
    said, said_head = last_waiting(["\n".join(ls) for _, ls in entries])
    reg = {d.get("sessionId"): d for _, d in read_registry()[0]}
    decls = []
    try:
        names = sorted(n for n in os.listdir(DECLARATIONS) if n.endswith(".json"))
    except OSError:
        names = []
    for fn in names:
        decl, _ = read_declaration(fn[:-5])
        if decl and now - (decl.get("declared_at") or 0) <= since_hours * 3600:
            decls.append(decl)
    out = []
    for key in keys:
        pat = key_pattern(key)
        hits = [(no, ls) for no, ls in entries if any(pat.search(x) for x in ls)]
        out.append("## " + key)
        out.append("")
        if hits:
            shown = hits[-tail:]
            out.append("日誌：命中 " + str(len(hits)) + " 筆，印最近 " + str(len(shown)) + " 筆")
            for no, ls in shown:
                out.append("- L" + str(no) + " " + ls[0].lstrip("# "))
                for off, x in enumerate(ls[1:], 1):
                    if x.startswith(LOOKUP_FIELDS) or pat.search(x):
                        mark = "（命中）" if pat.search(x) else ""
                        out.append("  - L" + str(no + off) + mark + " " + x[2:][:300])
        else:
            out.append("日誌裡沒有 " + key)
        dh = []
        for decl in decls:
            text = " ".join(str(decl.get(k)) for k in ("holding", "blocked_on", "tickets_opened"))
            if pat.search(text):
                who = (reg.get(decl.get("session_id")) or {}).get("name") or decl.get("session_id")
                dh.append("- " + str(who) + "（" + str(decl.get("line") or "宣告沒說是哪條線")
                          + "，" + stamp(decl.get("declared_at")) + "）接："
                          + " ".join(str(decl.get("holding")).split()))
        out.append("宣告（" + str(since_hours) + " 小時內）："
                   + ("" if dh else "沒有一條線的宣告提到它"))
        out += dh
        if said is None:
            out.append("最後一句在等：日誌裡沒有在等的紀錄")
        elif pat.search(said):
            out.append("最後一句在等（" + said_head + "）提到它：" + said)
        else:
            out.append("最後一句在等（" + said_head + "）沒提到它")
        # 從最新那一筆往回收：最近一起出現的，最可能就是現在接著的那一個。
        co = []
        for _, ls in reversed(hits):
            for tok in CO_KEY.findall("\n".join(ls)):
                if tok not in keys and tok not in co:
                    co.append(tok)
        if co:
            top = co[:12]
            out.append("這幾筆裡一起出現、這次沒查的：" + "、".join(top)
                       + "（紀錄常常只寫其中一個，沒查的再 --lookup 一次）")
        out.append("")
    return "\n".join(out).rstrip() + "\n", None


USER_WAITING_HEAD = "｜ " + WAITING_KIND + " ｜ 使用者"
RECALL_CAP = 6000


def entry_epoch(head):
    """一筆日誌標頭的時間。讀不出來回 None。"""
    m = re.match(r"^#{2,3} (\d{4}-\d{2}-\d{2} \d{2}:\d{2})", head)
    if not m:
        return None
    try:
        return time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M"))
    except ValueError:
        return None


# 宿主包在標記裡送進來的段落：跨 session 訊息、hook 注入、IDE 選取、斜線指令的回音。使用者自己
# 打的字不會整段包在一個 `<名字 …>…</名字>` 裡，所以把這些整段拿掉之後剩下的才算。
WRAPPED = re.compile(r"<([A-Za-z][\w-]*)\b[^>]*>.*?</\1>", re.S)


def typed_by_user(row):
    """transcript 的一列是不是使用者自己打的話。是就回那段文字，不是回 None。

    不算的：不是 `type: user` 的、`isMeta`（宿主自己塞的提示）、`isCompactSummary`（壓縮摘要）、
    工具結果、整段被標記包住的（見 `WRAPPED`）、以及「[Request interrupted…」這種宿主寫的中斷
    標記。標記旁邊另外打的字照算。
    """
    if row.get("type") != "user" or row.get("isMeta") or row.get("isCompactSummary"):
        return None
    content = (row.get("message") or {}).get("content")
    if isinstance(content, str):
        parts = [content]
    elif isinstance(content, list):
        if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return None
        parts = [c.get("text") or "" for c in content if isinstance(c, dict) and c.get("type") == "text"]
    else:
        return None
    text = " ".join(" ".join(WRAPPED.sub("", p).split()) for p in parts).strip()
    if not text or text.startswith("[Request interrupted"):
        return None
    return text


def unlogged_user_rows(transcript, since, entries):
    """指揮官 transcript 裡，使用者自己打、日誌裡沒有的話。回傳 ([(epoch, 原文)], problem)。

    舊到新，只取 `since`（epoch）之後的；`since` 是 None 就取整份。「日誌裡有」的判法是
    去掉空白之後的前 20 個字出現在日誌裡：日誌引原話常常斷句或換行，整句比對會把記過的又印一次。
    代價是很短的一句（「貼了」）幾乎一定被當成記過——短到那樣的話通常不是裁決。

    日誌只收指揮官記得 `--log` 的那幾句（2026-10-27 量到當天 57 句裡 20 句不在日誌），而
    transcript 一句不漏，所以這一份補的是那個差。讀不到要說出路徑，不當成「沒有」。
    """
    if not transcript:
        return [], "沒有指名指揮官的 transcript，沒進日誌的原話讀不到"
    try:
        fh = open(transcript, encoding="utf-8", errors="ignore")
    except OSError as exc:
        return [], "指揮官的 transcript 讀不到：" + transcript + "（" + str(exc) + "）"
    logged = "".join("\n".join(entries).split())
    out, seen = [], set()
    with fh:
        for row in fh:
            if '"user"' not in row:
                continue
            try:
                d = json.loads(row)
            except ValueError:
                continue
            text = typed_by_user(d)
            if not text:
                continue
            try:
                t = calendar.timegm(time.strptime((d.get("timestamp") or "")[:19], "%Y-%m-%dT%H:%M:%S"))
            except ValueError:
                continue
            if since is not None and t < since:
                continue
            key = "".join(text.split())[:20]
            if key in logged or key in seen:
                continue
            seen.add(key)
            out.append((t, text))
    return out, None


def unlogged_user_words(transcript, since, entries):
    """`unlogged_user_rows` 排成「MM-DD HH:MM 原文」一行一句。回傳 (lines, problem)。"""
    rows, prob = unlogged_user_rows(transcript, since, entries)
    return [time.strftime("%m-%d %H:%M", time.localtime(t)) + " " + text for t, text in rows], prob


USER_WHO = "使用者"


def backfill_user_words(transcript=None):
    """把指揮官 transcript 裡沒進日誌的使用者原話補寫進日誌。回傳 (筆數, transcript, problem)。

    一句一筆「紀錄｜使用者」，標頭是那句話在 transcript 裡的時間，原話寫成「使用者原話「…」」
    ——讀日誌的每一支（派工前對一次、`--lookup`、`--prior-decisions`、壓縮後注入）認的就是這個
    寫法，所以洞補在源頭，不在每個出口各補一次。只往尾端加，不改任何既有的一筆。

    冪等靠的是 `unlogged_user_rows` 本身：寫進去的那一句，下一趟就是「日誌裡有」。
    transcript 讀不到時一筆都不寫，problem 帶著路徑。
    """
    if transcript is None:
        transcript, prob = commander_transcript()
        if prob:
            return 0, transcript, prob
    entries, _ = read_journal_entries()
    rows, prob = unlogged_user_rows(transcript, None, entries)
    if prob:
        return 0, transcript, prob
    for i, (t, text) in enumerate(rows):
        _, wprob = append_journal(LOG_KIND, USER_WHO, [
            ("發生什麼", "使用者原話「" + text + "」"),
            ("來源", "transcript " + transcript + " " + time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)))],
            now=t)
        if wprob:
            return i, transcript, wprob
    return len(rows), transcript, None


def backfill_note(n, transcript, prob):
    """補寫的結果排成一行。讀不到、補了幾句、沒有要補，三種說的話不一樣。"""
    if prob:
        return "補寫：沒進日誌的使用者原話這一趟沒補（" + prob + "）"
    if n:
        return "補寫：把 transcript 裡沒進日誌的使用者原話補了 " + str(n) + " 句進日誌（" + transcript + "）"
    return "補寫：transcript 裡使用者的話都已經在日誌裡（" + transcript + "）"


def commander_transcript():
    """最近一次宣告自己是指揮官的那個 session 的 transcript。回傳 (path, problem)。

    `--rebuild` 的時候上一任多半已經結束，登錄檔可能跟著沒了，所以查不到 cwd 就用 sessionId
    去 projects 底下找。找不到也回一個路徑，讓讀不到的那一句說得出它找的是哪裡。
    """
    best = None
    try:
        names = os.listdir(DECLARATIONS)
    except OSError:
        names = []
    for fn in names:
        if not fn.endswith(".json"):
            continue
        decl, _ = read_declaration(fn[:-5])
        if decl and decl.get("line") == COMMANDER_LINE and (
                best is None or (decl.get("declared_at") or 0) > (best.get("declared_at") or 0)):
            best = decl
    if not best or not best.get("session_id"):
        return None, "沒有任何 session 宣告過自己是指揮官（" + DECLARATIONS + "），它的 transcript 讀不到"
    sid = best["session_id"]
    for _, data in read_registry()[0]:
        if data.get("sessionId") == sid and data.get("cwd"):
            return transcript_path(data["cwd"], sid), None
    hits = glob.glob(os.path.join(PROJECTS, "*", sid + ".jsonl"))
    return (hits[0] if hits else os.path.join(PROJECTS, "*", sid + ".jsonl")), None


STANDING_TAG = re.compile(r"\[線：([^\]]+)\]")
STANDING_ARCHIVED = "封存"
TICKET_TAG = re.compile(r"^[A-Z][A-Z0-9]*-\d+$")
# 有固定名字的線；其餘宣告都算 epic 線，`[線：epic]` 對上它們。「框架」是 DP 線宣告時常用的名字。
FIXED_LINES = {"review", "站會", "dp", "框架", "指揮官"}


def standing_chunks(text):
    """standing.md 切成 [(標記集合, 原文)]：第一節之前的前言一塊，之後每個 `## ` 一塊，原文逐字保留。"""
    chunks, cur = [], []
    for ln in text.splitlines(keepends=True):
        if ln.startswith("## ") and cur:
            chunks.append(cur)
            cur = []
        cur.append(ln)
    if cur:
        chunks.append(cur)
    out = []
    for c in chunks:
        m = STANDING_TAG.search(c[0]) if c[0].startswith("## ") else None
        tags = {t.strip() for t in m.group(1).replace("，", ",").split(",") if t.strip()} if m else set()
        out.append((tags, "".join(c)))
    return out


def standing_tag_matches(tag, line, holding):
    """標記對不對得上這條線。單號標記看宣告的 line 或 holding 裡有沒有同一個單號；線名標記去掉
    「線」字與空白、不分大小寫，整名相等才算（`DP` 不對上 `DP-732`）。`epic` 對上線名不在
    FIXED_LINES 裡的每一條線。"""
    if TICKET_TAG.match(tag):
        pat = r"(?<![A-Za-z0-9])" + re.escape(tag) + r"(?![A-Za-z0-9])"
        return bool(re.search(pat, (line or "") + " " + str(holding or "")))
    norm = lambda x: re.sub(r"\s|線", "", x or "").lower()
    if norm(tag) == "epic":
        return norm(line) not in FIXED_LINES
    return norm(tag) == norm(line)


def standing_for(text, line=None, holding=None):
    """一條線要貼的常駐規矩：共用的（沒標記）加標記對上這條線的，封存的一律不帶。
    `line` 是 None 時是指揮官那份：封存以外全部。沒有任何標記時原文逐字不變。"""
    keep = []
    for tags, raw in standing_chunks(text):
        if STANDING_ARCHIVED in tags:
            continue
        if line is None or not tags or any(standing_tag_matches(t, line, holding) for t in tags):
            keep.append(raw)
    return "".join(keep).strip()


def standing_sections(text):
    """standing.md 切成 [(標題, [那一節帶「原話」的句子])]，照檔案順序。"""
    out = []
    for ln in text.splitlines():
        if ln.startswith("## "):
            out.append((ln[3:].strip(), []))
        elif out and "原話" in ln:
            out[-1][1].extend(q for _, q in quotes_in(ln))
    return out


def commander_memory(now=None, since_hours=24, cap=RECALL_CAP, transcript=None):
    """指揮官要帶著的那一份：壓縮之後的注入與 `--rebuild` 的指揮官段都用它，所以新開的指揮官
    讀到什麼，壓縮之後就拿到什麼。使用者 2026-10-27 原話：「不是說過壓縮等價新開，如果壓縮
    會掉，那代表新開也會掉，不能接受吧」。

    回傳 (full, inline, problem)。full 是全部：最後一筆使用者在等的原文、常駐規矩全文、在等
    裡每個鍵在日誌全部時間的使用者原話、`transcript` 裡使用者說過卻沒進日誌的話、從那筆在等前
    `since_hours` 小時起的決定。inline 是放得進 `cap` 字的那一份，照這個順序取：在等、常駐規矩
    每節標題與那節的使用者原話（新到舊，最多佔一半）、每個鍵的使用者原話（新到舊，互相包含的
    只留一句）、沒進日誌的原話（新到舊）、決定。放不下的說出截掉幾句、幾節、幾行。

    **不限時間的是使用者原話，不是決定。** 決定欄是指揮官自己的解讀，2026-10-21 一句
    「be2 只能新增跟查詢」被讀寬之後，帶回來的一直是那個讀寬的決定。
    """
    entries, problem = read_journal_entries()
    if problem:
        return None, None, problem
    last = None
    for e in reversed(entries):
        if USER_WAITING_HEAD in e.partition("\n")[0]:
            last = e
            break
    if last is None:
        return None, None, "日誌裡沒有任何一筆使用者在等的紀錄：" + JOURNAL
    at = entry_epoch(last.partition("\n")[0])
    decisions = []
    for e in entries:
        head, _, rest = e.partition("\n")
        t = entry_epoch(head)
        # 在等之後才做的決定一樣要帶回來，所以只有下界。
        if t is None or at is None or t < at - since_hours * 3600:
            continue
        for ln in rest.splitlines():
            if ln.startswith("- 決定："):
                decisions.append(head.lstrip("# ") + "｜" + ln[len("- 決定："):])
    decisions.reverse()
    words, wprob = unlogged_user_words(transcript, None if at is None else at - since_hours * 3600, entries)
    words_head = ("指揮官 transcript 裡使用者說過、日誌裡沒有的話（從那筆在等前 " + str(since_hours)
                  + " 小時起）：")
    words_none = wprob or "（沒有：這段時間使用者說的話都在日誌裡）"
    keys = waiting_keys(last)
    quotes = user_quotes_lines(keys)
    try:
        with open(STANDING, encoding="utf-8") as fh:
            standing = standing_for(fh.read())
    except OSError:
        standing = None
    sections = standing_sections(standing or "")
    no_standing = "（日誌目錄裡沒有常駐規矩檔：" + STANDING + "）"
    head = ["最後一筆使用者在等（原文）：", last]
    tail = ["從它前 " + str(since_hours) + " 小時起的決定（新到舊，共 " + str(len(decisions)) + " 行）："]
    full = "\n".join(head + ["", "在等裡每個鍵的使用者原話（日誌全部時間，舊到新）："] + quotes
                     + ["", words_head] + (["- " + w for w in words] or [words_none])
                     + ["", "常駐規矩（" + STANDING + " 全文）：", "", standing or no_standing, ""]
                     + tail + ["- " + d for d in decisions])
    if keys:
        lookups, lprob = lookup_text(keys, now=now)
        full += "\n\n在等裡的鍵的 --lookup：\n" + (lookups or ("--lookup 問不到：" + str(lprob)))

    inline = list(head)
    def fits(line, limit=cap):
        return len("\n".join(inline)) + len(line) + 1 <= limit
    # 常駐規矩排在原話前面，而且最多佔一半：它是每一件事都適用的規矩，被一個話多的鍵擠掉的話，
    # 壓縮之後的指揮官就不知道「線自己登入」這種早就定下的事。
    inline += ["", "常駐規矩每節（新到舊；標題＋那節的使用者原話）：" if sections else no_standing]
    half = len("\n".join(inline)) + (cap - len("\n".join(inline))) // 2
    shown = 0
    for title, qs in reversed(sections):
        line = "- " + title + "".join("「" + q[:60] + "」" for q in qs[:2])
        if not fits(line, half):
            line = "- " + title
        if not fits(line, half):
            break
        inline.append(line)
        shown += 1
    if shown < len(sections):
        inline.append("（截掉 " + str(len(sections) - shown) + " 節較舊的，在完整版裡）")
    # 每個鍵新到舊：最近的裁決最可能就是現在被問到的那一件。同一句話常常被好幾筆紀錄引用、
    # 或一筆引了另一筆的前半，所以互相包含的只留第一次出現的那一句，換一個鍵也不再印。
    inline += ["", "在等裡每個鍵的使用者原話（新到舊）："]
    cut_q, seen = 0, []
    for key, hits in user_quotes_by_key(keys)[0] or []:
        parts = []
        for h in reversed(hits):
            q = h[2]
            if any(q in o or o in q for o in seen):
                continue
            seen.append(q)
            parts.append(h[1][:16] + "「" + q[:100] + "」")
        if not parts:
            continue
        line = "- " + key + "：" + "／".join(parts)
        while not fits(line) and "／" in line:
            line, cut_q = line.rsplit("／", 1)[0], cut_q + 1
        if fits(line):
            inline.append(line)
        else:
            cut_q += len(parts)
    if not keys:
        inline.append(quotes[0])
    if cut_q:
        inline.append("（截掉 " + str(cut_q) + " 句較舊的原話，在完整版裡）")
    # 沒進日誌的話排在決定前面：決定是指揮官的解讀，這一段是它沒記下來的原文。
    inline += ["", words_head]
    shown = 0
    for w in reversed(words):
        line = "- " + (w if len(w) <= 140 else w[:140] + "…")
        if not fits(line):
            break
        inline.append(line)
        shown += 1
    if not words:
        inline.append(words_none)
    elif shown < len(words):
        inline.append("（截掉 " + str(len(words) - shown) + " 句較舊的，在完整版裡）")
    inline += [""] + tail
    shown = 0
    for d in decisions:
        if not fits("- " + d):
            break
        inline.append("- " + d)
        shown += 1
    if shown < len(decisions):
        inline.append("（還有 " + str(len(decisions) - shown) + " 行放不下，在完整版裡）")
    return full, "\n".join(inline), None


def after_compact_recall(now=None, since_hours=24, cap=RECALL_CAP, transcript=None):
    """壓縮之後要帶回來的那一份。內容是 `commander_memory`，跟 `--rebuild` 的指揮官段同一份；
    完整版落檔，注入放得下的那一份。回傳 (要注入的那一段, 完整版路徑, 問題)。"""
    path = os.path.join(JOURNAL_DIR, "after-compact", time.strftime(
        "%Y%m%d-%H%M%S", time.localtime(now or time.time())) + ".md")
    lead = ("完整版（含常駐規矩全文與每個鍵的全部原話）：" + path
            + "。現在用 Read 讀完它，再回答使用者或派工。這些是已經決定的事：不重問、不漏。")
    full, inline, problem = commander_memory(now, since_hours, cap - len(lead) - 2, transcript)
    if problem:
        return None, None, problem
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(full + "\n")
    except OSError as exc:
        return None, None, "完整版寫不進去：" + path + "（" + str(exc) + "）"
    # 路徑放第一行：注入的那一段若被宿主截斷，掉的是尾巴的決定，不是「去讀完整版」這一句。
    return lead + "\n\n" + inline, path, None


def session_name_of(session_id):
    """拿 sessionId 去登錄查名字。查不到就回 sessionId 本身——日誌裡總要有個誰。"""
    rows, _ = read_registry()
    for _, data in rows:
        if data.get("sessionId") == session_id and data.get("name"):
            return data["name"]
    return session_id


def report_to_name(from_name=None):
    """prompt 裡「回報給誰」的名字。回傳 (name, problem)。

    **它是 SendMessage 要的那個位址**，所以只認 session 登錄裡的 `name` 原字串——ListAgents
    那一列印的、SendMessage 認得的都是它。短名送不到：2026-10-12 prompt 寫「work-fa」，登錄
    裡叫「指揮官 work-fa」，收件者照抄就送不出去。

    給了 `--from` 就對登錄驗，對不上不替人換成看起來像的那一個；沒給就問跑這一趟的 session
    自己在登錄裡叫什麼。問不到說出來——猜出來的名字跟對的名字長得一樣，送出去才知道錯。
    """
    rows, prob = read_registry()
    if from_name:
        names = sorted({d["name"] for _, d in rows if d.get("name")})
        if from_name in names:
            return from_name, None
        bare = re.sub(r"\s*\[[0-9a-f]+\]$", "", from_name)
        near = [n for n in names if bare and bare in n]
        why = "--from「" + from_name + "」不是 session 登錄裡任何一個名字"
        if prob:
            why += "（" + prob + "）"
        if near:
            why += "。登錄裡含「" + bare + "」的：" + chr(12289).join(near)
        return None, why + "。--from 要給登錄裡的原字串（ListAgents 那一列的名字，不含 [ref]）。"
    if prob:
        return None, "回報給誰問不到：" + prob
    sid, why = whoami()
    if not sid:
        return None, "回報給誰問不到：找不到這個 session 自己的登錄檔（" + why + "）"
    for path, data in rows:
        if data.get("sessionId") == sid:
            if data.get("name"):
                return data["name"], None
            return None, "回報給誰問不到：登錄檔裡沒有 name：" + path
    return None, "回報給誰問不到：登錄裡沒有 sessionId " + sid + " 的檔"


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
            # 掉了的那一行不截：被截掉的正是板子上該被看見的承諾（DP-888）
            if (s.get("declaration") or {}).get("dropped"):
                lines.append(f"      掉了：{s['declaration']['dropped']}")
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


# 每一段開場 prompt 的第一行。在 VS Code 的輸入框裡，它讓新 session 一開就連上瀏覽器
# （使用者 2026-10-12：「重建 session 要加 @browser:new_tab 直接授權瀏覽器」）。終端機 CLI
# 不認得它，經 SendMessage 送到的也只是一行字——第 3 步把這兩件事說給收件者聽。
BROWSER_MENTION = "@browser:new_tab"


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
        "     預期有；沒有就把這件事當成第一個發現回報，**不自己找替代**。",
        "     預期有，是因為這則 prompt 第一行的 `" + BROWSER_MENTION + "`：它只在 VS Code 輸入框裡、",
        "     貼成新 session 的第一則時連上瀏覽器。終端機 CLI 不認得它，要用 `claude --chrome` 開；",
        "     經 SendMessage 收到時它只是一行字。",
        "  4. `SendMessage` 給 " + commander + "：「<線名> 上線，我是 <名字>，瀏覽器：有／沒有」。",
        "",
        "**指揮官失聯**（`ListAgents` 找不到 " + commander + "，或送出後 30 分鐘沒回）：讀 "
        + JOURNAL + " 的最後幾筆，然後對人說一句：",
        "「指揮官失聯，請重建指揮官：新 session 跑 /command-post，先讀 " + JOURNAL + "」。",
        "不自己當指揮官、不接別人的單、手上的單照做。",
    ])


# 日誌裡記下使用者自己說的話，寫法是「原話：「…」」或「原話「…」」，後面可以接好幾個「…」。
USER_WORDS = re.compile(r"原話[：:]?\s*((?:「[^」]+」[、，與和及\s]*)+)")


def todays_user_words(now=None):
    """今天日誌裡帶著「原話」的句子，舊到新、同一句只留第一次，全部。回傳 (lines, problem)。

    以前只留最後 10 句，放不下的安靜地不見——跟日誌漏記原話是同一種丟法（指揮官 10/21
    2026-10-28：「10 句上限就是同一種安靜的丟法」）。它只印在指揮官自己的 stderr。

    它在 `--say`／`--order` 產出那一刻印在 stderr，給寫那一則的指揮官看，不進本文。
    〈派工之前〉要新的一句話對著當天的裁決讀，而那些裁決在派工那一刻不在眼前——
    2026-10-21 一句「hotfix」在「先一起擋」之後一分鐘被單獨讀成另一個方向。
    """
    today = time.strftime("%Y-%m-%d", time.localtime(now or time.time()))
    if not os.path.exists(JOURNAL):
        return [], None
    try:
        with open(JOURNAL, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        return [], f"今天使用者說過的話問不到：{JOURNAL} 讀不到（{exc}）"
    seen, out, when = set(), [], None
    for line in text.splitlines():
        if ENTRY_HEAD.match(line):
            head = line.lstrip("#").strip()
            when = head[11:16] if head.startswith(today) else None
            continue
        if not when:
            continue
        for group in USER_WORDS.findall(line):
            for quote in re.findall(r"「([^」]+)」", group):
                if quote not in seen:
                    seen.add(quote)
                    out.append(f"  {when} {quote}")
    return out, None


def user_words_note(now=None):
    """`todays_user_words` 排成要印給指揮官的那一段。沒有、讀不到、有，三種說的話不一樣。"""
    lines, prob = todays_user_words(now)
    if prob:
        return prob
    if not lines:
        return "派工前對一次：今天日誌裡沒有帶「原話」的句子。這不代表使用者今天沒說話，只代表沒記下來。"
    return "\n".join(["派工前對一次——今天日誌裡使用者的原話（舊到新）：", *lines,
                      "這一則照上面那幾句讀得通嗎？讀出兩種方向、或多出一條裁決裡沒有的路，先問使用者。"])


# 一筆使用者的話記下來時，那句話的答案是不是早就寫在某處。值是 path:line／URL（早已在）、
# none（沒有）、n/a（不適用）。它是一個欄位，不是判定：誰標、標成什麼都是人讀過之後的事。
ANSWER_FIELD = "答案早已在"
ANNOTATE_KIND = "標註"
ANSWER_NONE, ANSWER_NA = "none", "n/a"
# 同一筆的另一格：當時有沒有讀到那條已經寫下的規矩。跟「答案早已在」交叉才分得開
# 「規矩在、沒人讀」與「讀了、沒照做」（DP-887）。同樣是人標的，不是判定。
READ_FIELD = "當時讀了沒"
READ_VALUES = ("讀到", "沒讀到", "分不出")


def journal_entries_with_lines():
    """回傳 ([(標頭行號, [行...])], problem)。行號從 1 起，跟 `sed -n` 對得上。"""
    if not os.path.exists(JOURNAL):
        return [], f"日誌還不存在：{JOURNAL}"
    try:
        with open(JOURNAL, encoding="utf-8") as fh:
            rows = fh.read().splitlines()
    except OSError as exc:
        return [], f"日誌讀不動：{JOURNAL}（{exc}）"
    entries, cur = [], None
    for no, ln in enumerate(rows, 1):
        if ENTRY_HEAD.match(ln):
            cur = (no, [ln])
            entries.append(cur)
        elif cur is not None:
            cur[1].append(ln)
    return entries, None


def is_user_entry(head):
    return "｜ 紀錄 ｜ 使用者" in head


# 「原話」後面可以先接一個括號（「使用者原話（10/21 站會後）：「…」」），引文裡可以再套引號。
QUOTE_LEAD = re.compile(r"原話(?:（[^）]*）)?[：:]?\s*(?=「)")
# 在等裡的英文人名。分不出人名與產品名，所以多抓到的那幾個只會印成「沒有原話」。
NAME_KEY = re.compile(r"(?<![A-Za-z0-9])[A-Z][a-z]{2,}(?![A-Za-z0-9])")


def quotes_in(row):
    """一行裡跟在「原話」後面的每一段「…」，回 [(「原話」在行內的位置, 引文)]。引號按層數配對。"""
    out = []
    for m in QUOTE_LEAD.finditer(row):
        i = m.end()
        while i < len(row) and row[i] == "「":
            depth, j = 0, i
            while j < len(row):
                depth += {"「": 1, "」": -1}.get(row[j], 0)
                if depth == 0:
                    break
                j += 1
            if depth:
                break
            out.append((m.start(), row[i + 1:j]))
            i = j + 1
            while i < len(row) and row[i] in "、，與和及 \t":
                i += 1
    return out


def user_quotes(rows, user_entry):
    """一筆條目裡使用者自己說的話。使用者的條目全收；別人的條目只收緊接在「使用者」之後的
    那幾段——「Billy 原話」「指揮官的決定」都不是使用者說的。"""
    out = []
    for i, r in enumerate(rows[1:], 1):
        for at, q in quotes_in(r):
            if user_entry or "使用者" in r[max(0, at - 16):at]:
                out.append((i, q))
    return out


def user_quotes_by_key(keys, before=None):
    """每個鍵在日誌全部時間裡的使用者原話，舊到新、同一句只留第一次。不限時間、不限筆數：
    被糾正的常常是很多天以前就說過的事。回 ([(鍵, [(行號, 標頭, 引文)])], problem)。"""
    entries, prob = journal_entries_with_lines()
    if prob:
        return [], prob
    out = []
    for key in keys:
        pat, seen, hits = key_pattern(key), set(), []
        for no, rows in entries:
            when = entry_epoch(rows[0])
            if before and (when is None or when >= before):
                continue
            if not any(pat.search(r) for r in rows):
                continue
            for off, q in user_quotes(rows, is_user_entry(rows[0])):
                if q not in seen:
                    seen.add(q)
                    hits.append((no + off, rows[0].lstrip("#").strip(), q))
        out.append((key, hits))
    return out, None


def user_quotes_lines(keys, before=None):
    """`user_quotes_by_key` 排成要印的那幾行。讀不到、沒有鍵、某個鍵沒有原話，各說各的話。"""
    if not keys:
        return ["這一段沒有鍵（沒有單號、PR 號或人名），所以沒有列使用者原話。"]
    groups, prob = user_quotes_by_key(keys, before=before)
    if prob:
        return ["使用者原話讀不到：" + prob]
    out = []
    for key, hits in groups:
        if not hits:
            out.append(f"- {key}：日誌裡沒有提到它的使用者原話")
            continue
        out.append(f"- {key}（{len(hits)} 句，舊到新）：")
        out += [f"  - {head[:16]} {JOURNAL}:{no}「{q}」" for no, head, q in hits]
    return out


def waiting_keys(text):
    """在等裡的鍵：單號、PR 號、英文人名，照出現順序。"""
    keys = []
    for tok in CO_KEY.findall(text) + NAME_KEY.findall(text):
        if tok not in keys:
            keys.append(tok)
    return keys


def prior_decisions_text(keys, before=None):
    """日誌裡每個鍵在 `before` 以前的全部使用者原話，逐句帶 `journal.md:行號`。

    給 `prior-decisions.py` 當一個宣告來源：沒命中就不印，讀不到就非 0 並說出來。**只給
    使用者原話**：以前也給「決定」欄，而那一欄是指揮官自己的解讀——2026-10-21 一句
    「be2 只能新增跟查詢」被讀寬，之後每一次派工印出來的是那個讀寬的決定。
    """
    groups, prob = user_quotes_by_key(keys, before=before)
    if prob:
        return [], prob
    out = []
    for key, hits in groups:
        out += [f"{JOURNAL}:{no} {head[:16]}（鍵 {key}）使用者原話「{q}」" for no, head, q in hits]
    return out, None


def answer_marks(entries, name=ANSWER_FIELD):
    """標頭行號 → 欄位 `name` 最後一次標的值。帶欄位的那一筆自己算一次，之後的標註覆蓋它。"""
    marks = {}
    for no, rows in entries:
        field = next((r.split("：", 1)[1].strip() for r in rows
                      if r.startswith(f"- {name}：")), None)
        if field is None:
            continue
        if f"｜ {ANNOTATE_KIND} ｜" in rows[0]:
            target = next((r for r in rows if r.startswith("- 標的：")), "")
            m = re.match(r"- 標的：第 (\d+) 行", target)
            if m:
                marks[int(m.group(1))] = field
        else:
            marks[no] = field
    return marks


def answer_stats_text(since, until):
    """範圍內「紀錄｜使用者」帶原話的每一筆分四類，印筆數、清單與比例。"""
    entries, prob = journal_entries_with_lines()
    if prob:
        return prob, 7
    marks = answer_marks(entries)
    read = answer_marks(entries, READ_FIELD)
    groups = {"早已在": [], "沒有": [], "不適用": [], "還沒標": []}
    cols = (*READ_VALUES, "還沒標")
    cross = {g: dict.fromkeys(cols, 0) for g in groups}
    for no, rows in entries:
        day = rows[0].lstrip("#").strip()[:10]
        if not (since <= day <= until) or not is_user_entry(rows[0]):
            continue
        if not any("原話" in r for r in rows[1:]):
            continue
        v = marks.get(no)
        g = ("還沒標" if v is None else "沒有" if v == ANSWER_NONE
             else "不適用" if v == ANSWER_NA else "早已在")
        r = read.get(no)
        cross[g][r if r in READ_VALUES else "還沒標"] += 1
        groups[g].append(f"  {JOURNAL}:{no} {rows[0].lstrip('#').strip()}"
                         + (f" → {v}" if g == "早已在" else ""))
    total = sum(len(v) for v in groups.values())
    if not total:
        return f"{since}～{until} 日誌裡沒有帶原話的「紀錄｜使用者」。", 0
    out = [f"{since}～{until} 帶原話的「紀錄｜使用者」共 {total} 筆"]
    for g, rows in groups.items():
        out.append(f"{g}：{len(rows)} 筆")
        out += rows
    known = len(groups["早已在"]) + len(groups["沒有"])
    out.append("比例（早已在÷（早已在＋沒有））：" + (
        f"{len(groups['早已在'])}/{known} = {len(groups['早已在']) / known:.0%}" if known
        else "分母是 0，還沒有任何一筆標成早已在或沒有")
        + f"；不適用 {len(groups['不適用'])}、還沒標 {len(groups['還沒標'])} 不進分母")
    out.append(f"答案早已在 × {READ_FIELD}（列 × 欄，筆數）")
    out.append("｜".join(["", *cols]))
    out += ["｜".join([g, *(str(cross[g][c]) for c in cols)]) for g in groups]
    return "\n".join(out), 0


def prior_decisions_note(text, now=None):
    """`--say` 那一刻印在 stderr 的既有決定。問不到不擋送出，說出來就好。"""
    script = os.path.join(os.path.dirname(SPINE), "prior-decisions.py")
    cmd = [sys.executable, script, "--text", text,
           "--before-epoch", str(now or time.time())]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        return f"既有決定問不到：{script}（{type(exc).__name__}）"
    return (res.stdout.rstrip() or res.stderr.rstrip()
            or f"既有決定問不到：{script} 沒有輸出（exit {res.returncode}）")


SOURCE_RULE = (
    "每一句事實標出來源：量到（附命令或截圖）、讀到（附權威檔 path:line）、推的。"
    "推的只能寫成待驗假設，不寫成狀態或規矩。"
)


def order_text(issue_path, to_name, from_name, station=None):
    """一則派工指令的全文。

    它只做兩件別的地方做不到的事：**確認那條路徑真的存在**，以及把「回報給誰」寫死在
    文字裡。指揮者手打的那一版兩件都會漏——漏掉的樣子是安靜的：一個指向不存在位置的
    成功定義，讀起來跟一份好的成功定義一模一樣。

    它**不讀那張單的內容**，也不自己判定那張單在哪一站——站別問 driving-work-to-done 的
    spine-loop-state.sh（`spine_station`），原樣寫進指令，讓收件者從那一站的 skill 開始。
    """
    if station is None:
        where = []
    elif station_skill(station):
        where = ["這張單現在在 " + station + " 站：從 /" + station_skill(station) + " 開始。", ""]
    else:
        where = ["這張單在 delivered 站，已經判過交付。要再改它，回 engineering 並重走 verify-ac。", ""]
    return "\n".join([
        BROWSER_MENTION,
        "去做 " + issue_path + "。",
        "",
        *where,
        "成功的定義在那張單自己身上：讀 " + os.path.join(issue_path, "index.md") + "。",
        "**以那份為準，不要照我這段話做**——我在這裡重講一次，就會有第二份會漂的定義。",
        pack_line(issue_path),
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
        "牽涉併、壓 tag 或上線的單，回報第一行寫每個環境的驗證格（本機／測試環境／stage／",
        "正式環境：驗了沒、證據在哪），不寫「可 review」「可併」這種結論字。",
        SOURCE_RULE,
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
        BROWSER_MENTION,
        "去看 " + issue_path + "，然後跟 " + others_text + " 互審。",
        "",
        "成功的定義在那張單自己身上：讀 " + os.path.join(issue_path, "index.md") + "。",
        "**以那份為準，不要照我這段話做**——我在這裡重講一次，就會有第二份會漂的定義。",
        pack_line(issue_path),
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
        SOURCE_RULE,
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


def epic_dir_of(issue_path):
    """這張單落在哪一張鏈頂單底下：自己或往上最遠的那一個帶 `.spine/` 的目錄。

    帶著 `.spine/` 的才是單（`driving-work-to-done`〈一張單住在哪〉），所以中間只當路徑用的
    那幾層不算。往上一張都沒有、自己也沒有 `.spine/` 的話回 None——那不是一張單。
    """
    cur = os.path.abspath(issue_path)
    top = cur if os.path.isdir(os.path.join(cur, ".spine")) else None
    while True:
        parent = os.path.dirname(cur)
        if parent == cur:
            return top
        if os.path.isdir(os.path.join(parent, ".spine")):
            top = parent
        cur = parent


def other_live_lines(epic_dir, exclude):
    """那張鏈頂單底下，`exclude` 以外還有哪幾個活著的 session 在做。回傳 (逐條, 問題)。

    兩個來源，各自說出自己是哪一個：子樹裡任何一張單的 `holders`（脊椎寫下的），以及
    活著的 session 自己的宣告裡提到那張鏈頂單的單號（還沒碰過脊椎的線只有這一格）。
    死活是這一刻量的，跟 `holders_of()` 同一個理由。
    """
    rows, problem = read_registry()
    if problem:
        return None, problem
    live = {}
    for _, row in rows:
        if not isinstance(row, dict) or not row.get("sessionId") or not row.get("name"):
            continue
        pid = row.get("pid")
        if isinstance(pid, int) and alive(pid) is False:
            continue
        if row["name"] in exclude:
            continue
        live[row["sessionId"]] = row["name"]
    found = {}
    for dirpath, dirnames, filenames in os.walk(epic_dir):
        if os.path.basename(dirpath) != ".spine" or "loop-state.json" not in filenames:
            continue
        try:
            data = json.load(open(os.path.join(dirpath, "loop-state.json"), encoding="utf-8"))
        except (OSError, ValueError):
            continue
        holders = data.get("holders") if isinstance(data, dict) else None
        for entry in holders if isinstance(holders, list) else []:
            sid = entry.get("identity") if isinstance(entry, dict) else None
            if sid in live:
                rel = os.path.relpath(os.path.dirname(dirpath), os.path.dirname(epic_dir))
                found.setdefault(live[sid], []).append("記在 " + rel + " 的 holders")
    pat = key_pattern(os.path.basename(epic_dir))
    for sid, name in live.items():
        decl, _ = read_declaration(sid)
        if not decl:
            continue
        said = "｜".join(str(decl.get(k) or "") for k in ("line", "holding"))
        if pat.search(said):
            found.setdefault(name, []).append("宣告：" + said[:80])
    return [(n, "；".join(r)) for n, r in sorted(found.items())], None


def ticket_dirs(issues_root, key):
    """單的根目錄底下，名字是 `key` 或以 `key-` 開頭、帶 `.spine/` 的目錄。"""
    found = []
    for dirpath, dirnames, _ in os.walk(issues_root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        name = os.path.basename(dirpath)
        if (name == key or name.startswith(key + "-")) and os.path.isdir(os.path.join(dirpath, ".spine")):
            found.append(dirpath)
    return found


def who_holds(issues_root, spec):
    """站會今日格的一條，現在由哪一條活著的線在做。回 (一句話, 問題)。

    `spec` 是單號，或「單號@卡號」：那一條掛在哪張卡底下，卡號一起問——子單常常沒有自己
    的目錄、也不在任何宣告裡，接著它的是那張卡的線。每個號在單樹裡的話問它的鏈頂單
    （子樹的 `holders` 加活著的宣告提到鏈頂單號，跟板子「別的線」同一個判法），再補上
    宣告直接提到這個號的線。都沒有就是「沒人接」。
    使用者 2026-10-28 原話：「為什麼現在會 寫完站會後，工作就停了，到底哪段斷掉了」。
    """
    if not os.path.isdir(issues_root):
        # 單樹不在的話只剩宣告那一半，答出來的「沒人接」可能是假的。
        return None, "單的根目錄不存在：" + issues_root
    rows, problem = read_registry()
    if problem:
        return None, problem
    found = {}

    def add(name, why):
        if why not in found.setdefault(name, []):
            found[name].append(why)

    for key in [k for k in spec.split("@") if k]:
        for d in ticket_dirs(issues_root, key):
            lines, prob = other_live_lines(epic_dir_of(d) or d, set())
            if prob:
                return None, prob
            for name, why in lines:
                add(name, why)
        pat = key_pattern(key)
        for _, row in rows:
            if not isinstance(row, dict) or not row.get("sessionId") or not row.get("name"):
                continue
            pid = row.get("pid")
            if isinstance(pid, int) and alive(pid) is False:
                continue
            decl, _ = read_declaration(row["sessionId"])
            if not decl:
                continue
            said = "｜".join(str(decl.get(k) or "") for k in ("line", "holding"))
            # 宣告一條線只算一次：鏈頂單那一趟可能已經帶過同一份宣告。
            if pat.search(said) and not any("宣告：" in w for w in found.get(row["name"], [])):
                add(row["name"], "宣告：" + said[:80])
    if not found:
        return "沒人接", None
    return "、".join(n + "（" + "；".join(w) + "）" for n, w in sorted(found.items())), None


# 派 epic 的活的 --say 固定帶這一句。使用者 2026-10-27 原話：「每張單的前因後果應該都是清楚的，
# 到底掉在哪」——一條裁決落在日誌，單上依賴它的段落沒有同一輪改，新的線照抄舊段落。
SWEEP_LINE = ("這一則若帶著裁決：落地那一輪 grep 這個 epic 單上所有引用同一件事的段落，"
              "改到一致，commit 訊息列出改了哪幾段。")


def line_refusal(to_name, epic):
    """派工之前對一次線：收件者沒宣告自己是哪條線就不派；要派的 epic 不在它宣告的
    `--line`／`--holding` 裡也不派。回一段拒絕的話，可以派就回 None。

    使用者 2026-10-27 原話：「我是不是重頭到尾都有說，一個 epic 一個 session，所以為什麼
    又在亂搞」。那天站會線被轉成另一個 epic 的線，一個沒宣告的閒置 session 被派成框架線。
    `epic` 是 None 表示這一則不派任何 epic 的活（`--say --epic none`），只查有沒有宣告。
    """
    rows, prob = read_registry()
    if prob:
        return "收件者是哪條線問不到（" + prob + "），所以不派。"
    sids = [d.get("sessionId") for _, d in rows
            if isinstance(d, dict) and d.get("name") == to_name and d.get("sessionId")
            and not (isinstance(d.get("pid"), int) and alive(d.get("pid")) is False)]
    if not sids:
        return to_name + " 不是登錄裡任何一個活著的 session，所以不派。"
    decl = next((d for d in (read_declaration(x)[0] for x in sids) if d and d.get("line")), None)
    if not decl:
        return (to_name + " 沒有宣告自己是哪條線，所以不派。要嘛叫它先跑 --declare --line，"
                "要嘛跑 --rebuild 重建一條。")
    if epic is None:
        return None
    said = "｜".join(str(decl.get(k) or "") for k in ("line", "holding"))
    if key_pattern(epic).search(said):
        return None
    return ("這條線是「" + str(decl.get("line")) + "」線，宣告裡沒有 " + epic + "。" + epic
            + " 要重建一條，跑 --rebuild；同一個 epic 已經有線的話派給那一條。")


def epic_line_warning(issue_path, to_name, from_name):
    """一個 epic 一條線：`--issue` 落在的那張鏈頂單已經有別條活線時，回一則警告。

    **警告不進指令本文**：本文是要送出去的那一份（`sent.jsonl` 記的是它的 hash），把警告
    混進去，收件者讀到的是一句寫給指揮官的話。所以它走 stderr，由 main() 印。
    """
    epic = epic_dir_of(issue_path)
    if not epic:
        return None
    lines, problem = other_live_lines(epic, {to_name, from_name})
    key = os.path.basename(epic)
    if problem:
        return "問不到這個 epic（" + key + "）有沒有別的活線：" + problem
    if not lines:
        return None
    return "\n".join(
        ["⚠ 一個 epic 一條線：" + key + " 已經有別條活線，這則派給的是 " + to_name + "。"]
        + ["  - " + n + "（" + why + "）" for n, why in lines]
        + ["  派給那一條；真的要另開一條，先跟使用者說為什麼。指令照樣產出了。"])


# 派工前對照讀的兩棵 skill 樹：這支腳本自己所在的那一棵，加上使用者家目錄那一棵。
# **不寫死任何一支 skill 的名字或觸發句**——每一行都在執行當下從那份 SKILL.md 讀。
SKILL_TREES = [os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
               os.path.join(os.path.expanduser("~"), ".claude", "skills")]
TRIGGER_WIDTH = 100


def read_skill_front(path):
    """回 (name, trigger, 讀不到什麼)。trigger 取 description 第二段，沒有第二段取第一段。"""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        return None, None, "讀不到這份檔（" + e.__class__.__name__ + "）"
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, None, "沒有 frontmatter"
    front = []
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        front.append(ln)
    name, desc = None, None
    i = 0
    while i < len(front):
        ln = front[i]
        if ln.startswith("name:"):
            name = ln[5:].strip().strip("\"'") or None
        elif ln.startswith("description:"):
            v = ln[12:].strip()
            if v in ("|", ">", "|-", ">-"):
                block = []
                i += 1
                while i < len(front) and (front[i].startswith((" ", "\t")) or not front[i].strip()):
                    block.append(front[i].strip())
                    i += 1
                desc = "\n".join(block).strip() or None
                continue
            desc = v.strip("\"'") or None
        i += 1
    if not name or not desc:
        miss = "、".join(k for k, v in (("name", name), ("description", desc)) if not v)
        return name, None, "frontmatter 沒有 " + miss
    paras = [" ".join(p.split()) for p in re.split(r"\n\s*\n", desc) if p.strip()]
    t = paras[1] if len(paras) > 1 else paras[0]
    if len(t) > TRIGGER_WIDTH:
        t = t[:TRIGGER_WIDTH] + "…"
    return name, t, None


def skill_routing_lines(trees=None):
    """派工前對照：每一份 SKILL.md 一行。讀不到的那一行或那一棵說出讀不到什麼。"""
    out, seen = [], set()
    for tree in (trees if trees is not None else SKILL_TREES):
        real = os.path.realpath(tree)
        if real in seen:
            continue
        seen.add(real)
        if not os.path.isdir(tree):
            out.append("- （" + tree + " 這棵 skill 樹不存在，這一次沒有讀到它）")
            continue
        found, walk_errs = [], []
        for root, dirs, files in os.walk(tree, onerror=walk_errs.append):
            dirs[:] = sorted(d for d in dirs if not d.startswith(".") and d != "node_modules")
            if "SKILL.md" in files:
                found.append(os.path.join(root, "SKILL.md"))
        out.append("- **" + tree + "**：" + str(len(found)) + " 份 SKILL.md")
        for e in walk_errs:
            out.append("  - （" + str(getattr(e, "filename", "") or tree) + " 讀不進去，底下的 skill 這一次沒有算到）")
        for path in found:
            name, trig, prob = read_skill_front(path)
            rel = os.path.relpath(os.path.dirname(path), tree)
            if prob:
                out.append("  - `" + (name or rel) + "`：（" + prob + "，" + rel + "/SKILL.md）")
            else:
                out.append("  - `" + name + "`：" + trig)
    return out


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
    out.append("")
    out.append("## 派工前對照（產生的，不要手改）")
    out.append("")
    out.append("派工或自己動手之前，先對這一段：這件事對得上哪一支 skill，派工句就指名它。"
               "每一行的觸發句是執行這一刻從那份 SKILL.md 的 description 讀的"
               "（第二段，沒有第二段取第一段），不是抄來的。")
    out.append("")
    out.extend(skill_routing_lines())
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

    它不送給任何人。每一段的內容來自宣告與日誌；唯一的例外是指揮官段那份「沒進日誌的原話」，
    它讀上一任指揮官的 transcript（`commander_transcript`），只讀不寫。
    """
    now = now or time.time()
    entries, jprob = read_journal_entries()
    lines, skipped = lines_to_rebuild(now, since_hours)
    try:
        with open(STANDING, encoding="utf-8") as fh:
            standing = fh.read()
    except OSError:
        standing = None
    no_standing = ("（日誌目錄裡沒有常駐規矩檔：" + STANDING + "。"
                   "這一條線要守的規矩只有下面那張單與 skill 自己帶的。）")
    fence = "````"
    out = ["# 重建 prompt（" + stamp(now) + "）", ""]
    out.append("每一段是一個新 session 的第一則訊息，整段複製貼上。")
    out.append("")

    memory, _, mprob = commander_memory(now, since_hours, transcript=commander_transcript()[0])
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
        BROWSER_MENTION,
        "你是**指揮官**。先跑 /command-post，然後照這個順序讀，前三步都不用問人：",
        "",
        "1. `python3 " + SCRIPT + " --board --issues " + issues_root + "`"
        "——它印上一任在等什麼、日誌尾端、在飛的單、這台機器上的 session。",
        "2. 日誌全文：" + JOURNAL + "（append-only，從尾端往回讀到你懂為止）。",
        "3. command-post 的 SKILL.md〈交棒〉那一節。",
        "4. 板子上在飛的每一張單、上一任在等的那句裡每一個單號與 PR，跑 `python3 " + SCRIPT
        + " --lookup <key> [<key>...]`。有命中的已經排給某條線，不是待決；壓縮摘要不是狀態，日誌才是。",
        "5. 照 command-post SKILL.md〈心跳：靠排程，不靠某個人想起來〉重排巡邏（`ScheduleWakeup` 或"
        " `CronCreate`）。上一任的排程活在它的 session 裡，隨那個 session 結束了，不會自己接上。",
        "",
        "重建時各條線的宣告：",
        "",
    ] + roster + [
        "",
        "上線之後，用 `ListAgents` 查出自己的名字，`SendMessage` 告訴每一條還活著的線：",
        "「指揮官換成 <你的名字>，回報改送這裡」。之後照 SKILL.md 做事。",
        "",
        "## 已經決定的事（跟壓縮之後注入的是同一份）",
        "",
        memory or ("日誌裡的決定帶不回來：" + str(mprob)),
    ]
    out.append(fence)
    out.append("")

    for line, decl, name, running in lines:
        # 線名常常是另一個詞的前綴（`DP` 之於 `DP-732`），所以不做子字串比對：只認宣告那一格、
        # 「X 線」這種寫法、或上一任的名字。
        marks = ("線：" + line, line + " 線", line + "線", "線＝" + line) + ((name,) if name else ())
        related = [e for e in entries if any(k in e for k in marks)][-per_line:]
        # 宣告的線名常常自己就帶「線」（「review 線」「DP 線（…）」），再接一個會印成「X 線 線」。
        label = line if "線" in line else line + " 線"
        out.append("## " + label + "（上一任 " + name + "，"
                   + {True: "還活著", False: "已經結束", None: "死活不明"}[running] + "）")
        out.append("")
        out.append(fence + "markdown")
        out += [
            BROWSER_MENTION,
            "你是 **" + label + "**，實作 session。指揮官是 " + commander + "；"
            "使用者只在指揮官那條線發號施令，你的回報送給指揮官。",
            "",
            opening_text(commander),
            "",
            "**回報**：每到一站回一則——做完哪張或卡在哪、需不需要指引、缺什麼。"
            "回報完不停下來等，繼續下一件；只有走不下去才停。",
            "",
            "## 常駐規矩",
            "",
            standing_for(standing, line, decl.get("holding")) if standing is not None else no_standing,
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
        held = held_issue(decl.get("holding"))
        if held:
            out += ["", pack_line(held)]
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
    ap.add_argument("--station", help="--declare 用：手上那張單在哪一站；接的是一張單時跟它的輪次狀態對")
    ap.add_argument("--skills", help="--declare 用：現在載著哪幾支 skill")
    ap.add_argument("--skill", help="--order 用：派的是哪一站的 skill；跟那張單的站別不同就不產出")
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
                    help="--order／--review／--rebuild 用：回報給誰，要是 session 登錄裡的原字串。"
                         "預設是跑這一趟的 session 自己在登錄裡的名字")
    ap.add_argument("--say", action="store_true",
                    help="派工與互審以外要送給某條線的話（回覆、裁決、轉達）：記進日誌與送出紀錄，"
                         "原樣印出本文。指揮官的 SendMessage 只送這三種印出來的本文。")
    ap.add_argument("--text", default=None, help="--say 用：要送的本文")
    ap.add_argument("--epic", default=None,
                    help="--say 必填：這一則派的是哪個 epic（鏈頂單號），不派 epic 的活寫 none")
    ap.add_argument("--backfill-user-words", action="store_true",
                    help="把指揮官 transcript 裡使用者自己打、日誌沒有的話補寫進日誌，一句一筆。"
                         "跑兩次不重複；--board 每輪會先跑它。")
    ap.add_argument("--board", action="store_true",
                    help="產指揮台那一頁：指揮官在等什麼、日誌尾端、在飛的單、這台機器上的 session")
    ap.add_argument("--issues", default="issues", help="--board 用：單的根目錄")
    ap.add_argument("--waiting-on", default=None,
                    help="--board／--log 用：唯一手寫的那一格——指揮官自己在等什麼。"
                         "給了就落進日誌，之後不給就讀日誌裡最後一句")
    ap.add_argument("--lookup", nargs="+", metavar="KEY", default=None,
                    help="每個單號／PR 號／人名，印日誌裡的命中、各線宣告裡的命中、最後一句在等有沒有它"
                         "（筆數照 --journal-tail，宣告照 --since-hours）。唯讀。")
    ap.add_argument("--answer-existed", default=None, metavar="WHERE",
                    help="--log／--annotate-answer 用：這句話的答案早已在哪（path:line／URL），"
                         "none＝沒有、n/a＝不適用。是人讀過之後標的，不是判定")
    ap.add_argument("--was-read", default=None, choices=READ_VALUES,
                    help="--log／--annotate-answer 用：當時有沒有讀到那條已經寫下的規矩。是人讀過之後標的，不是判定")
    ap.add_argument("--annotate-answer", type=int, default=None, metavar="LINE",
                    help="替日誌第 LINE 行開頭的那一筆補標「答案早已在」或「當時讀了沒」。另寫一筆標註，原筆不改")
    ap.add_argument("--answer-stats", action="store_true",
                    help="彙總 --since～--until 帶原話的「紀錄｜使用者」：早已在／沒有／不適用／還沒標")
    ap.add_argument("--since", default=None, help="--answer-stats 用：起日 YYYY-MM-DD")
    ap.add_argument("--until", default=None, help="--answer-stats 用：迄日 YYYY-MM-DD（含）")
    ap.add_argument("--prior-decisions", nargs="+", metavar="KEY", default=None,
                    help="每個單號／PR 號，印日誌裡最近幾筆使用者條目、決定欄與原話。"
                         "只取 PRIOR_DECISIONS_BEFORE_EPOCH（或 --now-epoch）以前的。唯讀。")
    ap.add_argument("--who-holds", nargs="+", metavar="KEY[@CARD]", default=None,
                    help="站會今日格用：每個單號（或「單號@卡號」）現在由哪一條活著的線在做，"
                         "沒有就印「沒人接」；登錄讀不到 exit 3。唯讀。")
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
    if args.who_holds:
        # 問不到不是「沒人接」：登錄讀不到時說出來、exit 3，那一條由呼叫者寫成問不到。
        for key in args.who_holds:
            said, prob = who_holds(args.issues, key)
            if prob:
                print("問不到誰在做（" + prob + "）", file=sys.stderr)
                return 3
            print(key + "：" + said)
        return 0
    if args.prior_decisions:
        before = args.now_epoch or float(os.environ.get("PRIOR_DECISIONS_BEFORE_EPOCH") or 0) or None
        lines, prob = prior_decisions_text(args.prior_decisions, before=before)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        if lines:
            print("\n".join(lines))
        return 0
    if args.answer_stats:
        if not (args.since and args.until):
            print("--answer-stats 要 --since 與 --until（YYYY-MM-DD）", file=sys.stderr)
            return 2
        text, code = answer_stats_text(args.since, args.until)
        print(text, file=sys.stderr if code else sys.stdout)
        return code
    if args.annotate_answer is not None:
        if not (args.answer_existed or args.was_read):
            print("--annotate-answer 要 --answer-existed 或 --was-read", file=sys.stderr)
            return 2
        entries, prob = journal_entries_with_lines()
        head = next((rows[0] for no, rows in entries if no == args.annotate_answer), None)
        if prob or head is None:
            print(prob or f"日誌第 {args.annotate_answer} 行不是一筆的開頭：{JOURNAL}",
                  file=sys.stderr)
            return 2
        path, prob = append_journal(ANNOTATE_KIND, args.who or COMMANDER_LINE, [
            ("標的", f"第 {args.annotate_answer} 行 {head.lstrip('#').strip()}"),
            (ANSWER_FIELD, args.answer_existed), (READ_FIELD, args.was_read)],
            now=args.now_epoch)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        print("記在 " + path)
        return 0
    if args.lookup:
        text, prob = lookup_text(args.lookup, since_hours=args.since_hours,
                                 tail=args.journal_tail, now=args.now_epoch)
        if prob:
            print(prob, file=sys.stderr)
            return 8
        print(text, end="")
        return 0
    if args.backfill_user_words:
        n, tp, prob = backfill_user_words()
        print(backfill_note(n, tp, prob), file=sys.stderr if prob else sys.stdout)
        if prob:
            return 7 if "日誌寫不進去" in prob else 3
        return 0
    if args.board:
        # 先補寫再印：板子與它尾端的原話讀的都是日誌，沒補的那幾句這一輪就看不到。
        # 補不了不擋板子——說出來，照印。
        print(backfill_note(*backfill_user_words()))
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
        said, _ = last_waiting(read_journal_entries()[0])
        keys = waiting_keys(said or "")
        print("\n## 在等裡每個鍵的使用者原話（日誌全部時間，舊到新）\n")
        print("\n".join(user_quotes_lines(keys)))
        return 0
    if args.log:
        missing = [f for f, v in (("--who", args.who), ("--what", args.what)) if not v]
        if missing:
            print("--log 要的東西沒給齊，缺：" + chr(12289).join(missing), file=sys.stderr)
            return 2
        path, prob = append_journal(LOG_KIND, args.who, [
            ("發生什麼", args.what), ("問題", args.problem), ("決定", args.decision),
            (ANSWER_FIELD, args.answer_existed), (READ_FIELD, args.was_read)],
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
        frm, why = report_to_name(args.from_name)
        if not frm:
            print(why, file=sys.stderr)
            print("每一段 prompt 都要寫出回報給誰，一段沒有收件者的 prompt 等於沒有回報要求。",
                  file=sys.stderr)
            return 4
        text = rebuild_text(frm, args.issues, since_hours=args.since_hours,
                            now=args.now_epoch)
        path, prob = save_rebuild_copy(text, now=args.now_epoch)
        print(text)
        print(prob or ("副本：" + path + "（對話裡印出來的這一份才是給人貼的）"))
        return 0
    if args.order or args.say:
        print(user_words_note(args.now_epoch), file=sys.stderr)
    if args.say and args.text:
        print(prior_decisions_note(args.text, args.now_epoch), file=sys.stderr)
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
        frm, why = report_to_name(args.from_name)
        if not frm:
            print(why, file=sys.stderr)
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
        station = None
        if args.order:
            station, prob = spine_station(args.issue)
            if prob:
                print(prob, file=sys.stderr)
                print("不知道這張單在哪一站，就不知道該叫收件者從哪一支 skill 開始——所以這裡不產出指令。",
                      file=sys.stderr)
                return 8
            if args.skill and args.skill.lstrip("/") != station_skill(station):
                print("派的 skill 是 " + args.skill + "，但這張單在 " + station + " 站（該站的 skill 是 "
                      + (station_skill(station) or "沒有——它已經判過交付了") + "）。", file=sys.stderr)
                print("兩個對不上就不產出指令。要它回某一站，先在那張單上換站。", file=sys.stderr)
                return 9
        if args.order:
            epic = epic_dir_of(args.issue)
            # 宣告裡寫的是單號，不是整個目錄名，所以比的是目錄名開頭那個單號。
            key = re.match(r"[A-Z][A-Z0-9]*-\d+", os.path.basename(epic)) if epic else None
            refusal = line_refusal(to_names[0], key.group(0) if key else
                                   (os.path.basename(epic) if epic else None))
            if refusal:
                print(refusal, file=sys.stderr)
                return 10
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
            pairs = [(me, review_order_text(args.issue, me,
                                            [n for j, n in enumerate(to_names) if j != i],
                                            args.about, frm))
                     for i, me in enumerate(to_names)]
            out = review_orders(args.issue, to_names, args.about, frm)
        else:
            pairs = [(to_names[0], order_text(args.issue, to_names[0], frm, station))]
            out = pairs[0][1]
        for to_name, text in pairs:
            prob = record_sent(to_name, text, now=args.now_epoch)
            if prob:
                print(prob, file=sys.stderr)
                return 7
        if args.order:
            print(prior_decisions_note(out, args.now_epoch), file=sys.stderr)
            warning = epic_line_warning(args.issue, to_names[0], frm)
            if warning:
                print(warning, file=sys.stderr)
        print(out)
        return 0
    if args.say:
        to_names = args.to_names or []
        if len(to_names) != 1 or not args.text:
            print("--say 要剛好一個 --to 與 --text，現在 --to 有 " + str(len(to_names))
                  + " 個、--text " + ("有" if args.text else "沒有") + "。", file=sys.stderr)
            return 2
        if not args.epic:
            print("--say 要 --epic <鏈頂單號|none>：這一則是派哪個 epic 的活，不派 epic 的活就寫 none。"
                  "判準由寫的人說出來，不從本文猜——本文裡的單號常常只是標本。", file=sys.stderr)
            return 2
        refusal = line_refusal(to_names[0], None if args.epic == "none" else args.epic)
        if refusal:
            print(refusal, file=sys.stderr)
            return 10
        frm, why = report_to_name(args.from_name)
        if not frm:
            print(why, file=sys.stderr)
            return 4
        text = args.text.rstrip()
        if args.epic != "none" and SWEEP_LINE not in text:
            text += "\n\n" + SWEEP_LINE
        _, prob = append_journal("回覆", frm, [("給", to_names[0]), ("內容", text)],
                                 now=args.now_epoch)
        prob = prob or record_sent(to_names[0], text, now=args.now_epoch)
        if prob:
            print(prob, file=sys.stderr)
            return 7
        print(text)
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
        # 接的是一張單的時候，站別由那張單的輪次狀態說（DP-865 A-P6）。自己報的跟它不同，
        # 板子上就會有兩個答案，所以不寫。
        station = args.station
        held = held_issue(args.holding)
        if held:
            actual, prob = spine_station(held)
            if actual and station and station != actual:
                print("宣告的站別是 " + station + "，但 " + held + " 的輪次狀態說是 " + actual
                      + "。兩個不同就不寫宣告。", file=sys.stderr)
                return 2
            station = actual or station
        dropped = dropped_from_holding(previous_holding(args.session_id), args.holding)
        if dropped:
            print("這次宣告掉了：" + dropped, file=sys.stderr)
        path = write_declaration(args.session_id, args.holding, args.blocked_on,
                                 args.tickets_opened, line=args.line, browser=args.browser,
                                 station=station, skills=args.skills, dropped=dropped)
        _, prob = append_journal("宣告", session_name_of(args.session_id), [
            ("線", args.line), ("瀏覽器", args.browser), ("接", args.holding),
            ("卡", args.blocked_on), ("開單", args.tickets_opened), ("掉了", dropped)],
            now=args.now_epoch)
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
