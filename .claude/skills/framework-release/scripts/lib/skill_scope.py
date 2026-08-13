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

#: 沒宣告時走哪一條。跟 CLAUDE.md 與 README 說的同一個預設。
DEFAULT_SCOPE = "standalone"

#: 宣告了這幾種就不會被帶進 template repo。
NOT_TEMPLATE_FACING = frozenset({"company-only", "maintainer-only"})

_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\s*$", re.DOTALL | re.MULTILINE)
# 行首不吃空白：縮排的 scope: 是別的鍵的值，不是宣告。
_TOP_LEVEL_SCOPE = re.compile(r"^scope:[ \t]*(\S+)[ \t]*$", re.MULTILINE)


def declared_scope(skill_md):
    """讀一份 SKILL.md 宣告的通道。

    Args:
        skill_md: SKILL.md 的路徑。

    Returns:
        宣告的字串。檔案不存在、沒有 frontmatter、或 frontmatter 裡沒有頂層
        `scope:` 時回空字串——**三種都是「沒宣告」，不是某個預設值**。要預設值的
        呼叫端自己套 `DEFAULT_SCOPE`，這樣「沒宣告」與「宣告成 standalone」在
        需要分辨的地方分得出來。
    """
    path = Path(skill_md)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    matched = _FRONTMATTER.match(text)
    if not matched:
        return ""
    found = _TOP_LEVEL_SCOPE.search(matched.group(1))
    return found.group(1) if found else ""


def goes_to_template(skill_md):
    """這支 skill 會不會被帶進 template repo。

    Args:
        skill_md: SKILL.md 的路徑。

    Returns:
        True 表示會出去。沒宣告的照 `DEFAULT_SCOPE` 算，所以預設是會出去——
        這個方向是刻意的：漏宣告的後果要在同步預演的名單上看得見，不是靜默消失。
    """
    return (declared_scope(skill_md) or DEFAULT_SCOPE) not in NOT_TEMPLATE_FACING


def main(argv):
    """CLI：`skill_scope.py scope|template-facing <SKILL.md>`。

    `scope` 印出宣告（沒宣告印空行）。`template-facing` 不印東西，用離場碼回答：
    0 會出去、1 不會。bash 那一端就是靠這兩個碼問路的。
    """
    if len(argv) != 3 or argv[1] not in ("scope", "template-facing"):
        print("usage: skill_scope.py scope|template-facing <SKILL.md>", file=sys.stderr)
        return 2
    if argv[1] == "scope":
        print(declared_scope(argv[2]))
        return 0
    return 0 if goes_to_template(argv[2]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
