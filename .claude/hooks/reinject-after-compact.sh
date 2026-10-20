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

printf '%s' "$(cat)" | python3 -c '
import json, os, sys
skill_md = sys.argv[1]
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
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                         "additionalContext": "\n\n".join(parts)}},
                 ensure_ascii=False))
' "$skill_md"
