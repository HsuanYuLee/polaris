#!/usr/bin/env bash
# reinject-after-compact.sh — SessionStart hook（source = compact）：壓縮之後把手上的 skill 叫回來。
#
# 為什麼是 hook
# -------------
# 官方文件：compact 之後每支已載入的 skill 只留前 5,000 tokens、全部合計 25,000。超過的部分
# 不在 context 裡，模型照摘要與臨時規矩重新發明流程。2026-10-19 指揮官壓縮後沒有再讀
# command-post，跳過 driving-work-to-done、自創報告結構，規矩寫進自己的筆記而不是指回 skill。
#
# 做什麼
# ------
# 只在 source 是 compact 時輸出 additionalContext：
#   1. 這個 session 的 transcript 裡 invoke 過哪幾支 skill，要求現在逐支重新 invoke。
#   2. 這個 session 宣告自己是指揮官的話，附上 command-post SKILL.md 硬規則那一節的原文
#      （兩個 COMMANDER-HARD-RULES 標記之間），不是另一份抄本。
#   3. 指揮官的話，再附上 command-post.py 的 commander_memory()：最後一筆使用者在等的原文、
#      在等裡每個鍵在日誌全部時間的使用者原話、常駐規矩每節標題與原話、24 小時內的決定，
#      放不下的落檔並給路徑。它跟 --rebuild 的指揮官段是同一份，這裡不另外解析日誌。2026-10-21 指揮官壓縮後把前一天
#      已決定的三件重問或漏掉；SKILL.md 寫著壓縮後先跑 --lookup，沒有東西逼它跑。
# 其他來源（startup、resume、clear）什麼都不輸出。
#
# 擋不到什麼，明講
# ----------------
# 這是注入，不是強制：模型讀到了仍然可以不叫。強制的那一半在 block-commander-freehand-send.sh。
# Codex 沒有 SessionStart(compact) 這個事件。
#
# POLARIS-SCOPE: universal
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_md="${here}/../skills/command-post/SKILL.md"
command_post="${here}/../skills/command-post/scripts/command-post.py"

printf '%s' "$(cat)" | python3 -c '
import importlib.util, json, os, sys
skill_md, command_post = sys.argv[1], sys.argv[2]
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
if data.get("source") != "compact":
    sys.exit(0)
skills = []
tp = data.get("transcript_path") or ""
try:
    for row in open(tp, encoding="utf-8", errors="ignore"):
        if "\"Skill\"" not in row:
            continue
        try:
            d = json.loads(row)
        except ValueError:
            continue
        content = (d.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for c in content:
            if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Skill":
                name = (c.get("input") or {}).get("skill")
                if name and name not in skills:
                    skills.append(name)
except OSError:
    pass
parts = []
if skills:
    parts.append("[compact 之後] 這個 session 壓縮前用過這幾支 skill："
                 + "、".join(skills) + "。壓縮後它們只剩前段，現在逐支重新 invoke（Skill 工具），"
                 "再繼續手上的事。摘要裡的流程不是權威，skill 才是。")
else:
    parts.append("[compact 之後] transcript 裡讀不到這個 session 用過哪支 skill。"
                 "手上的工作對得上哪支 skill，就先 invoke 它再繼續。")
sid = data.get("session_id") or ""
decl = os.path.join(os.path.expanduser("~"), ".claude", "sessions", "declarations", sid + ".json")
try:
    line = json.load(open(decl, encoding="utf-8")).get("line")
except (OSError, ValueError):
    line = None
if line == "指揮官":
    try:
        text = open(skill_md, encoding="utf-8").read()
        a = text.index("<!-- COMMANDER-HARD-RULES-BEGIN -->")
        b = text.index("<!-- COMMANDER-HARD-RULES-END -->")
        parts.append("你是指揮官。command-post 的硬規則（原文）：\n" + text[a + len("<!-- COMMANDER-HARD-RULES-BEGIN -->"):b].strip())
    except (OSError, ValueError) as exc:
        parts.append("你是指揮官，但 command-post 的硬規則讀不到（" + skill_md + "：" + str(exc)
                     + "）。先 invoke command-post。")
    try:
        spec = importlib.util.spec_from_file_location("command_post", command_post)
        cp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cp)
        # 宿主對 additionalContext 的上限是 10,000 字元，超過就整段換成檔案路徑加前 2,000 字
        # 預覽（code.claude.com/docs/en/hooks〈JSON output〉）。所以決定那一段只拿剩下的額度。
        budget = 9800 - len("\n\n".join(parts)) - len("[compact 之後] 日誌裡已經決定的事（摘要會漏，這一份不會）：\n") - 4
        inline, _, problem = cp.after_compact_recall(cap=max(budget, 1500))
    except Exception as exc:
        inline, problem = None, command_post + " 載不起來（" + str(exc) + "）"
    if problem:
        parts.append("[compact 之後] 日誌裡的決定帶不回來：" + problem
                     + "。先跑 command-post.py --board 與手上每張單的 --lookup，再回答使用者。")
    else:
        parts.append("[compact 之後] 日誌裡已經決定的事（摘要會漏，這一份不會）：\n" + inline)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": "\n\n".join(parts)}},
                 ensure_ascii=False))
' "$skill_md" "$command_post"
