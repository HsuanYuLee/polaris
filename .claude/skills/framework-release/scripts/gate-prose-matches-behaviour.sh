#!/usr/bin/env bash
# gate-prose-matches-behaviour.sh — 散文裡指名的東西，要真的在。
#
# 擋三種形狀，都是「讀的人照做、然後自己撞上」的那一類：
#
#   1. 指向不存在的檔案。`engineering/SKILL.md` 與 `verify-ac/SKILL.md` 開頭各有一句
#      「前置必讀：.claude/skills/references/spine-*.md」，那兩個檔在 DP-462 搬家時就沒了，
#      而那兩行一路活到 4.1.0。每一個讀 SKILL.md 的人第一行就被指去一個空位。
#   2. 指名不存在的子命令。散文寫 `spine-loop-state.sh where`，而那支腳本的 case 裡沒有
#      `where`——執行才炸，而且炸在流程中間。
#   3. 指名不存在的旗標。散文寫 `--source`，腳本認的是 `--issue`。這個真的發生過：三站
#      改名之後，judge/work 兩支 SKILL.md 裡整批 `--source` 全部對不上。
#
# 為什麼要一道閘而不是靠讀：這三種都不會在寫的當下錯，它們是**搬家之後**才錯的，而搬家的
# 人不會回頭讀每一支 SKILL.md。gate-skill-script-references.sh 管的是腳本引用腳本；這一支管
# 的是散文引用行為，兩者不重疊。
#
# Usage: gate-prose-matches-behaviour.sh [--repo <path>]
# Exit:  0 全部對得上 / 1 有對不上的

set -euo pipefail

PREFIX="[polaris gate-prose-matches-behaviour]"
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$REPO_ROOT" "$PREFIX" <<'PY'
import os
import re
import sys

repo_root, prefix = sys.argv[1], sys.argv[2]
skills_root = os.path.join(repo_root, ".claude", "skills")

# 只看 fenced bash block 與 inline code 裡的東西。散文行文提到一個名字不算指名——
# 「像 spine-loop-state 那種狀態機」不是叫人去跑它。
FENCE = re.compile(r"^```(?:bash|sh)\s*$")
FENCE_END = re.compile(r"^```\s*$")
# `bash <path>` 起頭的一行命令，後面可能接子命令與旗標。續行的反斜線要接起來。
INVOCATION = re.compile(r"\bbash\s+(?P<path>[\w./-]+\.sh)(?P<rest>[^\n]*)")
# 行文裡的「前置必讀：`x/y.md`」這類指路。副檔名限定成文件，免得把命令當路徑。
#
# 一定要有 `/`：一個光禿禿的 `shared-defaults.md` 解不出唯一位置，把它當指路只會製造
# 一堆猜的紅。這是刻意讓出去的精度——沒有目錄的檔名不在這道閘的管轄內，而不是被判成綠。
# 讓出去多少，跑完會印出來。
DOC_POINTER = re.compile(r"`([\w.-]+(?:/[\w.-]+)+\.(?:md|json|yaml|yml))`")
BARE_DOC = re.compile(r"`([\w.-]+\.(?:md|json|yaml|yml))`")
SUBCOMMAND = re.compile(r"^\s+([a-z][a-z0-9-]*)\b")
FLAG = re.compile(r"(--[a-z][a-z0-9-]*)")
# 散文的第二種寫法：`$SKILL_DIR/scripts/x.sh`。這一整類原本一個都沒被檢查——
# gate-skill-script-references 只看腳本引用腳本，看不到 SKILL.md 怎麼寫。
SKILL_DIR_REF = re.compile(
    r"\$\{?(?:SKILL_DIR|SKILLS_DIR|SKILL_ROOT)\}?/((?:scripts/|references/|env/)?[\w.-]+\.(?:sh|py|mjs|md|json|yaml|yml))"
)

problems = []
# 不被判定的第三態要有數字。一個安靜的豁免，下一次就會有人以為那些也被檢查過了。
unjudged = set()


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def script_vocabulary(script_path):
    """腳本認得的子命令與旗標。

    子命令從結尾那個 dispatch case 讀，旗標從所有 case 分支讀——兩者都是 `x|y)` 的形狀，
    分不開也不需要分開：一個名字只要出現在任何一個 case 標籤裡，這支腳本就處理得動它。
    """
    text = read(script_path)
    words = set()
    for label in re.findall(r"^\s*([\w|:*.-]+)\)", text, re.MULTILINE):
        for part in label.split("|"):
            part = part.strip()
            if part and part not in ("*", "esac"):
                words.add(part)
    words.update(re.findall(r"--[a-z][a-z0-9-]*", text))
    return words


def resolve(doc_path, quoted):
    """把散文裡的路徑解成磁碟位置。

    兩種寫法都收：從 repo 根寫起的（`.claude/skills/x/scripts/y.sh`），以及相對於這份
    文件自己的。先試 repo 根，因為這個 repo 的 SKILL.md 幾乎都那樣寫。
    """
    from_root = os.path.join(repo_root, quoted)
    if os.path.exists(from_root):
        return from_root
    from_doc = os.path.join(os.path.dirname(doc_path), quoted)
    if os.path.exists(from_doc):
        return from_doc
    return None


for dirpath, dirnames, filenames in os.walk(skills_root):
    dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
    for name in filenames:
        if name != "SKILL.md":
            continue
        doc = os.path.join(dirpath, name)
        rel_doc = os.path.relpath(doc, repo_root)
        text = read(doc)

        # 1. 指路到不存在的文件。
        for quoted in DOC_POINTER.findall(text):
            # 佔位符不是指路：`{issue}/index.md` 是一個要被代換的樣板。
            if "{" in quoted or quoted.startswith("<"):
                continue
            if resolve(doc, quoted) is None:
                problems.append(f"{rel_doc}: 指向不存在的 `{quoted}`")

        for quoted in BARE_DOC.findall(text):
            if "/" in quoted or "{" in quoted:
                continue
            unjudged.add(f"{rel_doc}: `{quoted}`")

        # 1b. `$SKILL_DIR/...`。變數的值是自明的：SKILL.md 自己那一支 skill 的目錄。
        for tail in SKILL_DIR_REF.findall(text):
            if not os.path.exists(os.path.join(dirpath, tail)):
                problems.append(f"{rel_doc}: 指向不存在的 `$SKILL_DIR/{tail}`")

        # 2 與 3. 命令、子命令、旗標。續行接起來再看。
        joined = re.sub(r"\\\n\s*", " ", text)
        for match in INVOCATION.finditer(joined):
            quoted = match.group("path")
            if "{" in quoted:
                continue
            script = resolve(doc, quoted)
            if script is None:
                problems.append(f"{rel_doc}: 指向不存在的腳本 `{quoted}`")
                continue
            vocabulary = script_vocabulary(script)
            rest = match.group("rest")
            sub = SUBCOMMAND.match(rest)
            if sub and sub.group(1) not in vocabulary:
                problems.append(
                    f"{rel_doc}: `{os.path.basename(quoted)} {sub.group(1)}` "
                    f"——那支腳本沒有這個子命令"
                )
            for flag in FLAG.findall(rest):
                if flag not in vocabulary:
                    problems.append(
                        f"{rel_doc}: `{os.path.basename(quoted)} {flag}` "
                        f"——那支腳本不認得這個旗標"
                    )

if unjudged:
    print(f"{prefix} 沒有目錄的檔名 {len(unjudged)} 個，不在管轄內（解不出唯一位置）：",
          file=sys.stderr)
    for item in sorted(unjudged):
        print(f"{prefix}   {item}", file=sys.stderr)

if problems:
    for problem in sorted(set(problems)):
        print(f"{prefix} {problem}", file=sys.stderr)
    print(f"{prefix} {len(set(problems))} 處散文與實際行為對不上。", file=sys.stderr)
    print(f"{prefix} 文字有問題就改文字；只有在描述是對的而行為錯了的時候才改腳本。",
          file=sys.stderr)
    sys.exit(1)

print("PROSE-MATCHES-BEHAVIOUR 掃過的 SKILL.md 裡，指名的檔案、子命令與旗標都對得上"
      f"（另有 {len(unjudged)} 個沒有目錄的檔名不在管轄內）。")
PY
