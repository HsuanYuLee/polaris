#!/usr/bin/env python3
"""一支 skill 需要哪些外部工具——這裡是唯一回答這件事的地方。

**宣告寫在需要它的那一支 skill 自己的 frontmatter 裡。** 以前寫在
`lib/tool-attribution.sh` 一個 `case` 裡，而那支 lib 住在 `framework-release` 底下：一支
`scope: standalone` 的 skill 被單獨帶到 claude.ai 或 Cowork 時，帶走的東西裡完全沒有
「我需要 gh」——而那些環境沒有這個 repo 的任何一個檔案。

宣告長這樣，`tools:` 是 frontmatter 的頂層鍵，跟 `scope:` 同一層：

```yaml
tools:
  - name: gh
    provision: manual
    why: 開 PR、讀 review
    fix: 裝 GitHub CLI 並完成 gh auth login
```

`provision` 只有兩個值，而它們的分界是**這個環境有沒有辦法自己把它裝起來**：

- `framework`——裝得起來（root mise 或 toolchain package）。缺了的修法是跑 bootstrap，
  所以不必每支都重寫一次 `fix`。**選填的 `install` 說出是哪一步會裝它**：不填的話用「跟工具
  同名的那個安裝項」，而名字對不上的時候必須填——`rg` 的 mise 鍵是
  `aqua:BurntSushi/ripgrep`、`npx` 根本沒有自己的安裝項（跟著 `node` 來）。這個對照以前不
  存在於任何地方，靠的是有人記得。四種寫法：`mise:<鍵>`、`pnpm:<目錄>`、`uv`、`with:<工具>`。
- `manual`——裝不起來，要人。三類會落在這裡：**要憑證才算數的**（`gh` 裝得了二進位檔、
  登不了入）、**本身就是宿主環境的**（docker daemon）、**別的 repo 擁有的**。這一類
  `fix` 是必填：一個說不出修法的「要人補」跟沒有宣告一樣沒用。

`probe` 是選填：不給的話，「在不在」用「PATH 上有沒有這個命令」問。**不是每一個相依都是
一個命令**——PyYAML 是一個函式庫，`command -v PyYAML` 永遠答不出來，而答不出來會被讀成
不在。這種就自己帶一條問法（`python3 -c "import yaml"`），回 0 就算在。

讀的人拿到的是聚合過的清單，所以「這台機器缺什麼」問一次就有答案，不必逐支翻。
"""

import os
import re
import sys

#: `provision` 的值域。多一種就要多一種處置，所以它不該悄悄變寬。
PROVISIONS = ("framework", "manual")

#: `provision: framework` 缺了的時候的修法。宣告端不必每支重寫一次。
FRAMEWORK_FIX = "mise run bootstrap"

_FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\s*$", re.DOTALL | re.MULTILINE)
# 頂層鍵：行首沒有空白。縮排在別的鍵底下的不算宣告（跟 skill_scope.py 同一條規矩）。
_TOOLS_BLOCK = re.compile(r"^tools:[ \t]*\n((?:[ \t]+.*\n?|\n)*)", re.MULTILINE)
_ENTRY = re.compile(r"^[ \t]*-[ \t]+name:[ \t]*(\S+)[ \t]*$")
_FIELD = re.compile(r"^[ \t]+([a-z_]+):[ \t]*(.*?)[ \t]*$")


def _unquote(value):
    """去掉整個值外面那一對引號，只在頭尾成對的時候。

    `.strip('"')` 會把 `python3 -c "import yaml"` 尾巴那個引號也吃掉，而剩下的那條命令
    看起來仍然像一條命令——跑起來才會壞，而且壞的方式是「這個工具不在」。
    """
    value = value.strip()
    for quote in ('"', "'"):
        if len(value) >= 2 and value[0] == quote and value[-1] == quote:
            return value[1:-1]
    return value


def _frontmatter(path):
    """一份 SKILL.md 的 frontmatter 原文，沒有就回空字串。"""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
    except OSError:
        return ""
    matched = _FRONTMATTER.match(text)
    return matched.group(1) if matched else ""


def declared_tools(skill_md):
    """一支 skill 宣告它需要的工具。

    Args:
        skill_md: SKILL.md 的路徑。

    Returns:
        一串 dict，每個有 `name`、`provision`、`why`、`fix`、`probe`、`install`。沒有 `tools:` 就回空串列
        ——**那是「這支不需要任何外部工具」，不是「還沒填」**。兩者在這裡分不出來是刻意的：
        分得出來就要有第三種處置，而一支 skill 說不出自己要什麼的時候，能做的事跟不需要
        任何東西是一樣的。
    """
    block = _TOOLS_BLOCK.search(_frontmatter(skill_md))
    if not block:
        return []
    entries = []
    for line in block.group(1).split("\n"):
        head = _ENTRY.match(line)
        if head:
            entries.append({"name": head.group(1), "provision": "", "why": "",
                            "fix": "", "probe": "", "install": ""})
            continue
        field = _FIELD.match(line)
        if field and entries and field.group(1) in ("provision", "why", "fix", "probe",
                                                    "install"):
            entries[-1][field.group(1)] = _unquote(field.group(2))
    for entry in entries:
        if entry["provision"] == "framework" and not entry["fix"]:
            entry["fix"] = FRAMEWORK_FIX
    return entries


def skill_md_paths(skills_root):
    """`{skills_root}` 底下每一支 skill 的 SKILL.md。

    符號連結跳過——公司 skill 靠 depth-one 符號連結才被執行期註冊，跟著走會把同一支
    數兩次。
    """
    found = []
    try:
        names = sorted(os.listdir(skills_root))
    except OSError:
        return found
    for name in names:
        path = os.path.join(skills_root, name)
        if os.path.islink(path) or not os.path.isdir(path):
            continue
        direct = os.path.join(path, "SKILL.md")
        if os.path.isfile(direct):
            found.append(direct)
            continue
        for sub in sorted(os.listdir(path)):
            nested = os.path.join(path, sub, "SKILL.md")
            if os.path.isfile(nested):
                found.append(nested)
    return found


def aggregate(skills_root):
    """整棵樹宣告的工具，一個工具一筆，記下是哪幾支要它。

    Returns:
        dict：工具名 → {`provision`, `fix`, `probe`, `install`, `wanted_by`: [skill 名]}。同一個工具被兩支
        宣告成不同的 `provision` 時，**保留較嚴的那一個**（`manual`）並把兩邊都記進
        `wanted_by`——寬鬆的那一份會讓檢查說「這裡裝得起來」，而它裝不起來。
    """
    merged = {}
    for path in skill_md_paths(skills_root):
        skill = os.path.basename(os.path.dirname(path))
        for entry in declared_tools(path):
            slot = merged.setdefault(entry["name"], {
                "provision": entry["provision"], "fix": entry["fix"],
                "probe": entry["probe"], "install": entry["install"], "wanted_by": []})
            slot["wanted_by"].append(skill)
            slot["probe"] = slot["probe"] or entry["probe"]
            slot["install"] = slot["install"] or entry["install"]
            if entry["provision"] == "manual":
                slot["provision"] = "manual"
                slot["fix"] = entry["fix"] or slot["fix"]
    return merged


def main(argv):
    """CLI：`skill_tools.py list <skills_root>` 印聚合清單，一行一個工具。

    每行是 tab 分隔的 `name`、`provision`、`fix`、`probe`、`install`、`wanted_by`（逗號相連），
    給 bash 讀。
    空欄位印 `-` 而不是留空：tab 是 IFS 的空白字元，連續兩個會被 `read` 收成一個分隔符，
    於是一個空欄位會把它後面那一欄整個吃掉——而那個錯讀起來像宣告本身有問題。
    宣告不合法時（`provision` 不在值域裡、`manual` 沒給 `fix`）以離場碼 1 指名它——
    **那不是「沒宣告」，是宣告錯了，兩者要分得出來。**
    """
    if len(argv) != 3 or argv[1] != "list":
        print("usage: skill_tools.py list <skills_root>", file=sys.stderr)
        return 2
    merged = aggregate(argv[2])
    if not merged:
        print("SKILL-TOOLS 一個宣告都沒讀到", file=sys.stderr)
        return 2
    bad = []
    for name, slot in sorted(merged.items()):
        if slot["provision"] not in PROVISIONS:
            bad.append(f"{name}: provision={slot['provision'] or '(空)'} 不在 {PROVISIONS}")
        elif slot["provision"] == "manual" and not slot["fix"]:
            bad.append(f"{name}: provision=manual 但沒有 fix")
        print("\t".join([name, slot["provision"], slot["fix"] or "-",
                          slot["probe"] or "-", slot["install"] or "-",
                          ",".join(slot["wanted_by"])]))
    for line in bad:
        print(f"SKILL-TOOLS 宣告不合法：{line}", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
