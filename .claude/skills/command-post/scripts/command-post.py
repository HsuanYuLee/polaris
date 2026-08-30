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
import argparse, json, os, sys, time

HOME = os.path.expanduser("~")
REGISTRY = os.path.join(HOME, ".claude", "sessions")
PROJECTS = os.path.join(HOME, ".claude", "projects")


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
    args = ap.parse_args()
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
