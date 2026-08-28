#!/usr/bin/env python3
"""這台機器上有哪些 session、各自閒置多久、各自在做什麼。

**只讀。** 不對任何 session 送訊息、不送訊號、不寫任何不屬於這支 skill 的檔案。
「在做什麼」一律是那個 session 自己留下的話，不從名字、路徑或進程資訊推一句——推出來的
那一句看起來跟讀到的一模一樣，而它會在最需要真話的時候是錯的。

問不到的留在地圖上並指名問不到的是哪一份，不從清單上消失、也不填一個猜的。
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


def last_words(path):
    """那個 session 最後說的話，以及它是什麼時候說的。

    回傳 (text, epoch, problem)。problem 不是 None 的時候 text 一定是 None——
    「讀不到」與「它沒說話」是兩件事，不可以長成同一個值。
    """
    if not os.path.exists(path):
        return None, None, f"transcript 不存在：{path}"
    try:
        text, stamp = None, None
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get("type") != "assistant":
                    continue
                content = (row.get("message") or {}).get("content")
                chunks = []
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            chunks.append(c.get("text") or "")
                elif isinstance(content, str):
                    chunks.append(content)
                joined = " ".join(x.strip() for x in chunks if x and x.strip())
                if joined:
                    text, stamp = joined, row.get("timestamp")
        if text is None:
            return None, None, f"transcript 在，但裡面沒有它說過的話：{path}"
        epoch = None
        if stamp:
            try:
                import datetime
                epoch = datetime.datetime.fromisoformat(
                    stamp.replace("Z", "+00:00")).timestamp()
            except ValueError:
                epoch = None
        if epoch is None:
            epoch = os.path.getmtime(path)
        return text, epoch, None
    except OSError as exc:
        return None, None, f"transcript 讀不動：{path}（{exc}）"


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
        if cwd and sid:
            text, epoch, prob = last_words(transcript_path(cwd, sid))
            row["doing"], row["problem"] = text, prob
            if epoch:
                row["idle_seconds"] = max(0, int(now - epoch))
        else:
            row["problem"] = "登錄裡缺 cwd 或 sessionId，找不到它說過的話"
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
            lines.append(f"      它自己說：{t[:110]}{'…' if len(t) > 110 else ''}")
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
    args = ap.parse_args()
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
