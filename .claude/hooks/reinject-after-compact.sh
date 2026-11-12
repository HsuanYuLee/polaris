#!/usr/bin/env bash
# reinject-after-compact.sh — SessionStart hook（source = compact）：壓縮之後指回手上的 skill。
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
#   1. 不是指揮官的 session：transcript 裡 invoke 過哪幾支 skill，以及要照某一支的某一節做時
#      才 invoke 那支。不要求全部重新 invoke：每次 invoke 把正文再載一次，之後每一趟都帶著
#      （2026-11-12 量到壓縮後 8 趟內 11 次，DP-1052）。
#   2. 宣告以「指揮官」開頭的 session（含「指揮官（投資線）」這種帶括號的）：command-post SKILL.md 硬規則那一節的原文（兩個
#      COMMANDER-HARD-RULES 標記之間），加上 command-post.py after_compact_recall() 寫出的
#      日誌完整版的檔案路徑一行。內容在檔案裡，不注入；它跟 --rebuild 的指揮官段是同一份。
#      2026-10-21 指揮官壓縮後把前一天已決定的三件重問或漏掉，所以那份檔案照樣每次寫。
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
sid = data.get("session_id") or ""
decl = os.path.join(os.path.expanduser("~"), ".claude", "sessions", "declarations", sid + ".json")
try:
    line = json.load(open(decl, encoding="utf-8")).get("line")
except (OSError, ValueError):
    line = None
if isinstance(line, str) and line.startswith("指揮官"):
    try:
        text = open(skill_md, encoding="utf-8").read()
        a = text.index("<!-- COMMANDER-HARD-RULES-BEGIN -->")
        b = text.index("<!-- COMMANDER-HARD-RULES-END -->")
        rules = text[a + len("<!-- COMMANDER-HARD-RULES-BEGIN -->"):b].strip()
        parts.append(rules or "command-post 的硬規則那一節是空的（" + skill_md + "）。先 invoke command-post。")
    except (OSError, ValueError) as exc:
        parts.append("command-post 的硬規則讀不到（" + skill_md + "：" + str(exc)
                     + "）。先 invoke command-post。")
    try:
        spec = importlib.util.spec_from_file_location("command_post", command_post)
        cp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cp)
        _, path, problem = cp.after_compact_recall(transcript=tp or None)
    except Exception as exc:
        path, problem = None, command_post + " 載不起來（" + str(exc) + "）"
    if problem:
        parts.append("日誌的完整版寫不出來：" + problem
                     + "。先跑 command-post.py --board 與手上每張單的 --lookup。")
    else:
        parts.append("日誌裡已經決定的事，完整版在 " + path + "，回答或派工之前讀它。")
elif skills:
    parts.append("[compact 之後] 這個 session 壓縮前用過：" + "、".join(skills)
                 + "。要照某一支的某一節做時，才 invoke 那支 skill 讀那一節；摘要裡的流程不是權威。")
else:
    parts.append("[compact 之後] 手上的工作要照某一支 skill 做時，先 invoke 它讀那一節。")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": "\n\n".join(parts)}},
                 ensure_ascii=False))
' "$skill_md" "$command_post"
