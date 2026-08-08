#!/usr/bin/env bash
# gate-skill-knowledge-locality.sh — 一支 skill 需要的知識，住不住在它自己身上。
#
# 為什麼這件事要有閘：skill 目錄是唯一會被帶到 claude.ai 與 Cowork 的東西。一支 skill 到了
# 那裡，它引用的那些工作區底下的路徑不存在；在原機器上那條路徑跑得動，所以沒有人
# 發現。2026-08-07 rex 撞到的就是這個——web-dev-env 的五行環境宣告在他機器上全部非 0，
# 在寫下它們的人的機器上全部 exit 0，差別只有本機有沒有一個沒版控的目錄。
#
# 一筆往外的引用有兩種，這道閘要求說出是哪一種：
#
#   動手對象  skill 操作的東西——被改的 repo、被寫出去的產出、被查詢的服務。它本來就在
#             外面，這是對的。
#   知識      skill 據以判斷「怎麼做」的東西。它必須住在 skill 自己的目錄裡。
#
# 分類寫在既有的宣告源上，不另開第二份：
#
#   <!-- PROSE-EXTERNAL-PATHS: {路徑前綴} — 動手對象：{理由} -->
#   <!-- PROSE-EXTERNAL-PATHS: {路徑前綴} — 知識：{理由} -->
#
# gate-prose-matches-behaviour 讀同一行的「路徑 + 理由」，這裡多讀理由開頭那個詞。兩個
# 消費者、一個宣告源——抄成兩份的話，兩邊會各自漂，而漂掉的那一刻沒有人在看。
#
# Usage: gate-skill-knowledge-locality.sh [--repo <工作區>] [--skills <skill 目錄>]
# Exit:  0 每一筆都分類過而且沒有知識住在外面 / 1 有未分類或有知識住在外面 / 2 量不到

set -uo pipefail

PREFIX="[polaris gate-skill-knowledge-locality]"
REPO_PATH=""
SKILLS_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    # 掃哪些 skill、跟「那條路徑在不在版控裡」是兩個問題，在 worktree 裡答案來自兩棵樹：
    # worktree 帶著要驗的 skill，但那些被 ignore 的目錄（公司的 checkout、站台的 repo）只在
    # 主 checkout。不分開的話，在 worktree 跑會全綠——而那個綠只代表那棵樹裡什麼都沒有。
    --skills) SKILLS_PATH="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -n "$SKILLS_PATH" ]] || SKILLS_PATH="$REPO_PATH/.claude/skills"

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

python3 - "$REPO_PATH" "$PREFIX" "$SKILLS_PATH" <<'PY'
import os
import re
import subprocess
import sys

repo, prefix, skills_root = sys.argv[1:4]
if not os.path.isdir(skills_root):
    print(f"{prefix} 量不到：{skills_root} 不存在。", file=sys.stderr)
    sys.exit(2)

# 管轄範圍要確定性地畫出來，不能靠「看起來像路徑」——`base/head`、`read/write`、
# `merged/open/closed` 都長得像路徑而且都不是。所以第一段必須是**這個工作區真正的頂層
# 項目**；解不到頂層項目的字串不在管轄內，數量會被印出來（一個安靜的第三態下一次就會
# 被當成檢查過了）。
REFERENCE = re.compile(r"(?<![\w./-])([\w.-]+/[\w./-]+)")
DECLARATION = re.compile(
    r"<!--\s*PROSE-EXTERNAL-PATHS:\s*(\S+)\s*(?:—|--)\s*([^>]*?)\s*-->")
KNOWLEDGE = "知識"
TARGET = "動手對象"
# 這幾個開頭不是往外，是這個 repo 自己的東西或相對路徑。
INTERNAL_PREFIXES = (".claude/", "_template/", "issues/", "./", "../",
                     # 裝出來的東西不是知識也不是動手對象，它由 package manager 決定。
                     "node_modules/", ".codex/", ".polaris/")


def local_only(path: str) -> bool:
    """本機有、但版控裡沒有——「我這台跑得動、別人跑不動」就是這個形狀。

    本機根本不存在的路徑不算：那要嘛是散文在講另一個 repo 的樹（搬進來的 handbook 滿是
    `tests/...`、`tools/...`），要嘛是一個斷掉的指標，而斷指標有 gate-prose-matches-behaviour
    在管。一件事只讓一道閘管，兩道會各自漂。
    """
    if not os.path.exists(os.path.join(repo, path)):
        return False
    return subprocess.run(["git", "-C", repo, "check-ignore", "-q", path],
                          capture_output=True).returncode == 0


def skill_of(file_path: str) -> str:
    """這個檔案屬於哪一支 skill。公司 skill 多包一層，那一層也算 skill 的一部分。

    分界看的是哪一層帶著 SKILL.md，不是那一層叫什麼名字——寫死一個公司名，換一家公司
    就會把它整批 skill 併成同一支來判。
    """
    rel = os.path.relpath(file_path, skills_root).split(os.sep)
    if len(rel) > 2 and os.path.isfile(
            os.path.join(skills_root, rel[0], rel[1], "SKILL.md")):
        return "/".join(rel[:2])
    return rel[0]


TOP_LEVEL = {name for name in os.listdir(repo) if not name.startswith(".git")}

skills: dict[str, dict] = {}
out_of_jurisdiction = 0
for root, dirs, files in os.walk(skills_root):
    for name in files:
        path = os.path.join(root, name)
        # 裝進來的相依不是這支 skill 寫的東西，掃它等於在掃 npm 的 registry。
        if "node_modules" in path.split(os.sep):
            continue
        skill = skill_of(path)
        entry = skills.setdefault(skill, {"declarations": [], "references": {}})
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        for m in DECLARATION.finditer(text):
            entry["declarations"].append((m.group(1), m.group(2)))
        for m in set(REFERENCE.findall(text)):
            if m.startswith(INTERNAL_PREFIXES):
                continue
            if m.split("/", 1)[0] not in TOP_LEVEL:
                out_of_jurisdiction += 1
                continue
            if not local_only(m):
                out_of_jurisdiction += 1
                continue
            entry["references"].setdefault(m, set()).add(
                os.path.relpath(path, repo))

unclassified: list[str] = []
knowledge_outside: list[str] = []
classified = 0
for skill in sorted(skills):
    for ref, sources in sorted(skills[skill]["references"].items()):
        kind = None
        for declared_prefix, reason in skills[skill]["declarations"]:
            if not ref.startswith(declared_prefix.rstrip("/")):
                continue
            if reason.startswith(KNOWLEDGE):
                kind = KNOWLEDGE
            elif reason.startswith(TARGET):
                kind = TARGET
            break
        where = "、".join(sorted(sources)[:2])
        if kind is None:
            unclassified.append(f"  {skill}: `{ref}` ← {where}")
        elif kind == KNOWLEDGE:
            knowledge_outside.append(f"  {skill}: `{ref}` ← {where}")
        else:
            classified += 1

total_refs = sum(len(s["references"]) for s in skills.values())
print(f"{prefix} 掃過 {len(skills)} 支 skill，找到 {total_refs} 筆指向版控之外的引用："
      f"分類成動手對象 {classified} 筆、知識 {len(knowledge_outside)} 筆、"
      f"沒有分類 {len(unclassified)} 筆"
      f"（另有 {out_of_jurisdiction} 個字串不在管轄內：第一段不是工作區頂層項目，或本機根本沒有那個東西——斷指標由 gate-prose-matches-behaviour 管）。")

if unclassified:
    print(f"{prefix} 沒有分類的 {len(unclassified)} 筆——一筆沒有說法的往外引用，"
          f"跟一筆說錯了的在出事的時候長得一樣：")
    print("\n".join(unclassified))
if knowledge_outside:
    print(f"{prefix} 被分類成知識、卻住在 skill 目錄外的 {len(knowledge_outside)} 筆——"
          f"這支 skill 被帶到 claude.ai 或 Cowork 就會少掉這些：")
    print("\n".join(knowledge_outside))

if unclassified or knowledge_outside:
    print(f"{prefix} 修法：知識搬進那支 skill 自己的目錄；真的是動手對象的，"
          f"在那支 skill 裡加一行 "
          f"<!-- PROSE-EXTERNAL-PATHS: {{路徑前綴}} — 動手對象：{{理由}} -->")
    sys.exit(1)

print(f"{prefix} ✅ 每一筆往外的引用都分類過，沒有知識住在 skill 目錄外。")
PY
