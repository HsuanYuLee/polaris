#!/usr/bin/env python3
"""一支 skill 走哪個通道——這裡是唯一回答這件事的地方。

以前這個問題有五份答案：同步腳本兩處、外洩掃描一處、readme-lint 一處、
gate-source-destination 一處，各自寫一條略有不同的正則去掃 SKILL.md 的原始文字。
五份會漂，而漂掉的方向不對稱：讀寬了，一支不准出去的 skill 進公開的 template repo；
讀窄了，一支該出去的靜默地不見。兩種都看 diff 看不出來。

**宣告是 frontmatter 頂層的 `scope:`，只有那裡算數。** 縮排在別的鍵底下的不算，
正文裡出現同一個字串的也不算——後者以前是真的會中的：`grep 'scope:.*maintainer-only'`
連行首錨點都沒有，一支 skill 只要在說明裡提到那個字串就會被排除在 template 之外。

不靠 PyYAML：一個「頂層鍵」在 frontmatter 裡就是行首沒有空白的那一行，用得著的部分
regex 描述得完，而多一個依賴要多一次「它在不在」的問題。
"""

import re
import sys
from pathlib import Path

#: **只有列名的才出得去。** 這是一份正向表列，不是黑名單——沒宣告、宣告了表上沒有的值、
#: 宣告的值拼錯，三種都不出去。
#:
#: 以前這裡是黑名單（`NOT_TEMPLATE_FACING = {"company-only", "maintainer-only"}`），
#: 而且沒宣告時套一個 `DEFAULT_SCOPE = "standalone"` 的預設，所以 fail-open。那個方向在
#: 只有「框架」與「公司」兩類的時候是對的：漏宣告一支公司 skill，最壞是多一份在自己的
#: template repo。**第三類出現之後它就反了**——`scope: personal` 在舊的判定下回「會出去」，
#: 而同步的目的地是一個 PUBLIC repo（2026-08-20 對合成檔實跑：`personal`、`private`、
#: 任何拼錯的值、以及完全沒宣告，四種都 exit 0）。
TEMPLATE_FACING = frozenset({"framework", "standalone"})

#: 這個工作區的追蹤範圍收得下的宣告：上面那些，加上留在本地不出去的兩種。
#: 表外的東西（個人的、拼錯的、沒宣告的）連這個 repo 的 git 都不該進。
WORKSPACE_FACING = TEMPLATE_FACING | frozenset({"company-only", "maintainer-only"})

_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\s*$", re.DOTALL | re.MULTILINE)
# 行首不吃空白：縮排的 scope: 是別的鍵的值，不是宣告。
_TOP_LEVEL_SCOPE = re.compile(r"^scope:[ \t]*(\S+)[ \t]*$", re.MULTILINE)
# rules 與 hooks 沒有 frontmatter 可以放宣告——`.claude/rules/*.md` 每次都被原樣注進
# context（多一段 YAML 就是每個 session 都在付），`.claude/hooks/*.sh` 根本不是 markdown。
# 所以它們用一行標記。名字取得夠特別，所以正文裡談到 `scope:` 不會被誤讀成宣告。
# 值之後可以接一段給人看的理由，所以只吃第一個 token。一行標記如果強迫「值就是行尾」，
# 寫下它的人就沒有地方說為什麼，而一個沒有理由的宣告下一次沒有人敢改。
_MARKER_SCOPE = re.compile(
    r"^(?:#|<!--)[ \t]*POLARIS-SCOPE:[ \t]*([A-Za-z0-9._-]+)", re.MULTILINE
)


def declared_scope(skill_md):
    """讀一份 SKILL.md 宣告的通道。

    Args:
        skill_md: SKILL.md 的路徑。

    Returns:
        宣告的字串。兩種寫法都認：frontmatter 的頂層 `scope:`（skill 用），以及
        一行 `POLARIS-SCOPE:` 標記（rules 與 hooks 用，因為它們沒有 frontmatter
        可放）。檔案不存在、兩種都找不到時回空字串——**那是「沒宣告」，不是某個預設
        值**，而沒宣告的東西哪裡都不去。
    """
    path = Path(skill_md)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    matched = _FRONTMATTER.match(text)
    if matched:
        found = _TOP_LEVEL_SCOPE.search(matched.group(1))
        if found:
            return found.group(1)
    marked = _MARKER_SCOPE.search(text)
    return marked.group(1) if marked else ""


def goes_to_template(skill_md):
    """這一份會不會被帶進 template repo。

    Args:
        skill_md: SKILL.md、rule 或 hook 的路徑。

    Returns:
        True 表示會出去，而且只有宣告落在 `TEMPLATE_FACING` 裡才會。漏宣告的
        後果從「靜靜地出去」換成「靜靜地留下」——**留下改得回來，出去改不回來**。
        看得見這件事由 `block_reason()` 負責：擋下來的每一項都要說出自己為什麼
        被擋，不是變成一個數字。
    """
    return declared_scope(skill_md) in TEMPLATE_FACING


def block_reason(skill_md):
    """說出這一份為什麼不會被帶出去；會出去的回空字串。

    Args:
        skill_md: SKILL.md、rule 或 hook 的路徑。

    Returns:
        一句話。呼叫端原樣印出來——一個被擋下來的東西只給數字的話，跟沒被擋在
        輸出上長得一樣。
    """
    scope = declared_scope(skill_md)
    if scope in TEMPLATE_FACING:
        return ""
    listed = ", ".join(sorted(TEMPLATE_FACING))
    if not scope:
        return f"沒有宣告 scope，而正向表列只收 {listed}"
    if scope in WORKSPACE_FACING:
        return f"宣告 {scope}，留在這個工作區，不進 template repo"
    return f"宣告的 {scope} 不在正向表列（{listed}）上——拼錯或不認得的一律不出去"


def main(argv):
    """CLI：`skill_scope.py scope|template-facing <SKILL.md>`。

    `scope` 印出宣告（沒宣告印空行）。`reason` 印出「為什麼不出去」（會出去的印
    空行）。`template-facing` 不印東西，用離場碼回答：0 會出去、1 不會。bash
    那一端就是靠這兩個碼問路的。
    """
    if len(argv) != 3 or argv[1] not in ("scope", "template-facing", "reason"):
        print("usage: skill_scope.py scope|template-facing|reason <SKILL.md>", file=sys.stderr)
        return 2
    if argv[1] == "scope":
        print(declared_scope(argv[2]))
        return 0
    if argv[1] == "reason":
        print(block_reason(argv[2]))
        return 0
    return 0 if goes_to_template(argv[2]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
