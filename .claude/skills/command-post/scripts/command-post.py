#!/usr/bin/env python3
"""這台機器上有哪些 session、各自閒置多久、各自在做什麼。

**只讀。** 不對任何 session 送訊息、不送訊號、不寫任何不屬於這支 skill 的檔案。

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
import argparse, json, os, subprocess, sys, time

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
    """把宣告排成一行給人讀。結構的那一份仍然在 `declaration` 鍵裡。"""
    opened = decl.get("tickets_opened")
    if isinstance(opened, list):
        opened = chr(12289).join(str(x) for x in opened) or "無"
    return "｜".join([f"接：{decl['holding']}",
                      f"卡：{decl['blocked_on']}", f"開單：{opened}"])


def write_declaration(session_id, holding, blocked_on, tickets_opened):
    """這個 session 寫下自己的那一行。**只寫自己的那一份，不碰別人的。**"""
    os.makedirs(DECLARATIONS, exist_ok=True)
    path = declaration_path(session_id)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"session_id": session_id, "holding": holding,
                   "blocked_on": blocked_on, "tickets_opened": tickets_opened,
                   "declared_at": time.time()}, fh, ensure_ascii=False, indent=2)
    return path


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


def board_text(m, issues_root, waiting_on, session_id=None, idle_threshold=3600):
    """指揮官每一輪重讀的那一頁。

    **產生的部分不手寫**（先例是 `OPEN.md`，它自己的表頭就寫著下一次重算會整份重寫），
    **成功條件只指過去、不抄**（唯一權威是那張單的 fence），**手寫的只有一格**——指揮官
    自己在等什麼。那一格是板子答不出來的唯一一樣東西。

    它的主要用途不是交接，是**每一輪重讀**：把目標重寫到 context 尾端，避開 lost-in-the-
    middle。交接是副作用。
    """
    out = ["# 指揮台", ""]

    out.append("## 我在等什麼（唯一手寫的一格）")
    out.append("")
    out.append(waiting_on or "（沒有給 --waiting-on。這一格空著，"
                             "而它是這份文件裡唯一一樣板子答不出來的東西。）")
    out.append("")

    if not session_id:
        answer = "？次（環境裡沒有 CLAUDE_SESSION_ID，這一次問不到）"
    else:
        n, why = compaction_count(os.getcwd(), session_id)
        answer = str(n) + " 次" if why is None else "？次（" + why + "）"
    out.append("這個 session 壓縮過 " + answer
               + "。**這裡不判斷該不該換一個**——壓縮間隔量過是平的，"
                 "偵測不出「開始過度壓縮」那一刻，所以判斷留給人。")
    out.append("")

    out.append("## 在飛的單（產生的，不要手改）")
    out.append("")
    rows, why = spine_rows(issues_root)
    if why:
        out.append(why)
    else:
        # `next:` 那一行是脊椎的建議，它指的那一張同時也會出現在下面的清單裡。兩者
        # 印成兩列的話，同一張單在板子上出現兩次，而讀的人分不出那是兩張還是一張。
        table, notes = [], []
        for ln in rows:
            kind, _, rest = ln.partition(":")
            path = rest.split()[0] if rest.split() else rest
            if kind == "next":
                notes.append("脊椎建議的下一張：`" + path + "`")
            elif kind in ("stop", "seed"):
                table.append("| `" + path + "` | " + kind + " | `"
                             + os.path.join(issues_root, path, "index.md") + "` | |")
            else:
                notes.append(ln)
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
        out.append("「誰在做」整欄是空的，**而它是空的有原因**：輪次狀態檔沒有任何欄位記"
                   "「哪個 session 在做這一張」（DP-622）。一個看得出來的空白比一個手寫的猜測好。")
        out.append("")
        out.append("「成功條件在哪」那一欄是**路徑**，不是內容。抄進來就是第二份會漂的定義，"
                   "而漂的是最不能漂的那一份。")
    out.append("")

    out.append("## 這台機器上的 session（產生的，不要手改）")
    out.append("")
    out.append(human(m))
    return "\n".join(out)


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
    ap.add_argument("--order", action="store_true",
                    help="產一則派工指令的全文。只印出來，不送給任何人。")
    ap.add_argument("--issue", help="--order 用：那張單的路徑")
    ap.add_argument("--to", dest="to_name", help="--order 用：要它去做的那個 session")
    ap.add_argument("--from", dest="from_name", default=None,
                    help="--order 用：回報給誰。預設是這個 session 自己的名字（$CLAUDE_SESSION_NAME）")
    ap.add_argument("--board", action="store_true",
                    help="產指揮台那一頁：在飛的單、這台機器上的 session、以及唯一手寫的那一格")
    ap.add_argument("--issues", default="issues", help="--board 用：單的根目錄")
    ap.add_argument("--waiting-on", default=None,
                    help="--board 用：唯一手寫的那一格——指揮官自己在等什麼、剛決定了什麼")
    args = ap.parse_args()
    if args.board:
        print(board_text(build(now=args.now_epoch), args.issues, args.waiting_on,
                         session_id=os.environ.get("CLAUDE_SESSION_ID"),
                         idle_threshold=args.idle_threshold))
        return 0
    if args.order:
        missing = [f for f, v in (("--issue", args.issue),
                                  ("--to", args.to_name)) if not v]
        if missing:
            print("派工要兩樣都給，缺：" + chr(12289).join(missing), file=sys.stderr)
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
        print(order_text(args.issue, args.to_name, frm))
        return 0
    if args.declare:
        missing = [f for f, v in (("--session-id", args.session_id),
                                  ("--holding", args.holding),
                                  ("--blocked-on", args.blocked_on)) if not v]
        if missing:
            print("宣告要三樣都給，缺：" + chr(12289).join(missing), file=sys.stderr)
            return 2
        print("宣告寫在 " + write_declaration(
            args.session_id, args.holding, args.blocked_on, args.tickets_opened))
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
