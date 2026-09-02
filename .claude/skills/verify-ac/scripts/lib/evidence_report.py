"""把已經判定過的東西排版成一份交得出去的報告。

**唯讀。** 這裡不重做判定——逐條判定住在 `assertion_verdicts.py`，報告與交付讀的是同一份。
抄成兩份的話，「報告說過了」與「交付說不行」會同時是對的，而沒有人有辦法說出哪一份錯。

產兩個檔案，因為讀的人有兩種：

- `report.md` —— 人看的。
- `manifest.json` —— 機器讀的：逐條的判定、綁的 head、量測命令、以及要跟著一起送出去的
  檔案清單。發佈那一層拿它去決定要送什麼，不需要認得這裡的任何一個資料結構。

**這一支不判定成敗，也不因為有東西沒過就不產出。** 最想看報告的那一刻，正是有東西沒過的
那一刻——而舊的做法是任一條不成立就整支拒絕、什麼都不印。
"""

import json
import os

import assertion_verdicts as av

SCHEMA_VERSION = 1

# 判定在報告與清單裡各自長什麼樣。清單用大寫的字串，因為它是給別人讀的介面；報告用中文，
# 因為它是給人讀的。兩邊都從同一個 state 來，不各自算一次。
_MANIFEST_VERDICT = {av.PASS: "PASS", av.FAIL: "FAIL", av.UNMEASURABLE: "UNMEASURABLE"}
_REPORT_VERDICT = {av.PASS: "過", av.FAIL: "沒過", av.UNMEASURABLE: "量不到"}

# 附件放這裡：報告要帶截圖之類的東西時，施工的人把它們放進這個目錄，清單就會帶上。
# 不設定、不宣告——一個目錄的存在與否就是答案。
ATTACHMENTS_SUBDIR = ".spine/attachments"


def namespace_of(issue_dir, issues_root=None):
    """這張單屬於哪個命名空間。

    從路徑推：`{單的根目錄}/{命名空間}/{狀態}/{單}`。這跟 `place_issues_by_state.py` 是同一個
    做法——命名空間本來就是目錄結構決定的，它跟「這張單走到哪一站」不一樣（那個不從路徑推，
    從 `loop-state.json` 讀）。

    Args:
        issue_dir: 這張單的目錄。
        issues_root: 單的根目錄；`None` 表示往上找名為 `issues` 的那一層。
    Returns:
        命名空間字串；推不出來時回 `""`（呼叫者要說出來，不要猜一個）。
    """
    parts = os.path.normpath(os.path.abspath(issue_dir)).split(os.sep)
    root_name = os.path.basename(os.path.normpath(issues_root)) if issues_root else "issues"
    for i in range(len(parts) - 1, 0, -1):
        if parts[i - 1] == root_name and i < len(parts):
            return parts[i]
    return ""


def collect_files(issue_dir, ids):
    """要跟著報告一起送出去的檔案。

    兩種：每條 assertion 的證據 JSON，以及 `.spine/attachments/` 底下的東西（截圖之類）。
    回的是相對於 `issue_dir` 的路徑——絕對路徑只在產生它的那台機器上有意義。
    """
    files = []
    for aid in ids:
        rel = os.path.join(".spine", "evidence", f"{aid}.json")
        if os.path.isfile(os.path.join(issue_dir, rel)):
            files.append(rel)
    attach_dir = os.path.join(issue_dir, ATTACHMENTS_SUBDIR)
    if os.path.isdir(attach_dir):
        for dirpath, _, filenames in sorted(os.walk(attach_dir)):
            for name in sorted(filenames):
                full = os.path.join(dirpath, name)
                files.append(os.path.relpath(full, issue_dir))
    return files


def build(report, issue_dir, ledger_path=None, issues_root=None):
    """把 `assertion_verdicts.judge()` 的結果變成一份清單。"""
    # `registered_commands` 回 None 表示登錄檔不在，回 {} 表示在但一條都沒登錄——兩件事。
    # 在這裡把它們壓成同一個空 dict 的話，清單上就分不出「這一層沒得做」與「做了而且是空的」，
    # 而那正是「量不到被讀成沒問題」的形狀。所以它變成清單上的一格。
    commands = av.registered_commands(ledger_path) if ledger_path else None
    ledger_state = "absent" if commands is None else "present"
    commands = commands or {}
    assertions = []
    for row in report["rows"]:
        aid = row["id"]
        evidence_rel = os.path.join(".spine", "evidence", f"{aid}.json")
        assertions.append({
            "id": aid,
            "verdict": _MANIFEST_VERDICT[row["state"]],
            "detail": row["detail"],
            "command": commands.get(aid),
            "evidence_file": evidence_rel
            if os.path.isfile(os.path.join(issue_dir, evidence_rel)) else None,
        })
    tally = av.counts(report)
    return {
        "schema_version": SCHEMA_VERSION,
        "issue": os.path.basename(os.path.normpath(issue_dir)),
        # 絕對路徑，因為 `files` 是相對於它的——而發佈那一層只拿得到報告與清單兩個路徑，
        # 沒有這一格它解不開那些檔案在哪。它只在產出它的那台機器上有意義，這是刻意的。
        "issue_dir": os.path.abspath(issue_dir),
        "namespace": namespace_of(issue_dir, issues_root),
        "head": report["head"],
        "measured_in": report["measured_in"],
        "layers": report["layers"],
        "measurement_ledger": ledger_state,
        "counts": {
            "pass": tally[av.PASS],
            "fail": tally[av.FAIL],
            "unmeasurable": tally[av.UNMEASURABLE],
        },
        "assertions": assertions,
        "files": collect_files(issue_dir, report["ids"]),
        "notes": list(report["notes"]),
        "blockers": list(report["blockers"]),
    }


def render_markdown(manifest):
    """人看的那一份。三種判定各自看得出來，不只印過了幾條。"""
    counts = manifest["counts"]
    lines = [
        f"# 判定報告：{manifest['issue']}",
        "",
        f"- assertion {len(manifest['assertions'])} 條——"
        f"過 {counts['pass']}、沒過 {counts['fail']}、量不到 {counts['unmeasurable']}",
    ]
    if manifest["head"]:
        # 只印工作區的名字，不印完整路徑。這份 report.md 會被當成附件送出去（見
        # 各命名空間宣告的 evidence publisher），而一台機器的目錄配置送出去收不回來，
        # 它說的又只是「這台機器上的哪裡」——要回答的問題是「量在哪一棵樹」，名字就夠。
        tree = os.path.basename(os.path.normpath(manifest["measured_in"])) \
            if manifest["measured_in"] else ""
        lines.append(f"- 量在 head `{manifest['head'][:12]}`"
                     + (f"（{tree}）" if tree else ""))
    layers = manifest["layers"]
    done = [name for name, label in (
        ("self_consistent", "檔案自洽"), ("registered", "登錄相符"), ("rerun", "重跑一次"),
    ) if layers.get(name)]
    lines.append("- 做到這幾層："
                 + ("、".join(l for n, l in (
                     ("self_consistent", "檔案自洽"), ("registered", "登錄相符"),
                     ("rerun", "重跑一次")) if layers.get(n)) if done else "（一層都沒做成）"))
    if manifest.get("measurement_ledger") == "absent":
        lines.append("- 量測登錄不在——所以下面沒有任何一條說得出它是拿什麼量的")
    lines += ["", "| assertion | 判定 | 依據 |", "|---|---|---|"]
    for a in manifest["assertions"]:
        detail = a["detail"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| `{a['id']}` | {_REPORT_VERDICT_FROM_MANIFEST[a['verdict']]} | {detail} |")

    if manifest["files"]:
        lines += ["", "## 跟著一起送出去的檔案", ""]
        lines += [f"- `{f}`" for f in manifest["files"]]

    # 量測命令要看得到：一份說不出「拿什麼量的」的報告，讀的人核對不了。
    commands = [(a["id"], a["command"]) for a in manifest["assertions"] if a["command"]]
    if commands:
        lines += ["", "## 量測命令", "", "```"]
        lines += [f"{aid}  {cmd}" for aid, cmd in commands]
        lines.append("```")

    for label, items in (("NOTE", manifest["notes"]), ("BLOCKER", manifest["blockers"])):
        for item in items:
            lines.append(f"\n> **{label}**：{item}")
    return "\n".join(lines) + "\n"


_REPORT_VERDICT_FROM_MANIFEST = {
    "PASS": _REPORT_VERDICT[av.PASS],
    "FAIL": _REPORT_VERDICT[av.FAIL],
    "UNMEASURABLE": _REPORT_VERDICT[av.UNMEASURABLE],
}


def write(manifest, out_dir):
    """寫出兩個檔案，回它們的路徑。"""
    os.makedirs(out_dir, exist_ok=True)
    manifest_path = os.path.join(out_dir, "manifest.json")
    report_path = os.path.join(out_dir, "report.md")
    with open(manifest_path, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")
    with open(report_path, "w", encoding="utf-8") as fh:
        fh.write(render_markdown(manifest))
    return report_path, manifest_path
