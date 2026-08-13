#!/usr/bin/env bash
# gate-docs-collection.sh — 文件站台收進去的每一份 markdown，還帶著它的 schema 要的東西嗎。
#
# 這道閘擋的是「入口整個跑不起來，而沒有任何一步會說出來」。既有那幾道問的都是**宣告指
# 得到檔案**（`gate-dangling-declarations` 問 mise 任務與 npm script 的目標在不在、
# `gate-skill-script-references` 問腳本引用的腳本在不在），沒有一道問**這個入口跑起來會
# 怎樣**。2026-08-13 量到的：三條 viewer alias 接線全通、astro 真的起來，然後死在一份缺
# `title` 的 markdown 上，而所有的閘都是綠的。
#
# **為什麼不是在這裡跑一次 astro build。** 那要 node_modules、要好幾十秒，而且在沒裝依賴
# 的機器上它會變成一個永遠量不到的檢查——而一個永遠量不到的檢查，跟沒有那個檢查的差別只有
# 它會出現在清單上。所以這裡檢查的是擋住它的那個契約本身：集合收進去的每一份都要帶著
# schema 要的 frontmatter。純讀檔，下一份缺 title 的一樣會被抓到。
#
# **收哪些檔案不由這支腳本決定。** pattern 與排除規則從內容集合自己的設定
# （`docs-manager/src/content.config.ts`）讀出來——在這裡再抄一份清單的話，那份清單就是
# 第二個會漂的來源，而它漂掉的方向是「這裡說沒收，實際上收了」。
#
# Usage: gate-docs-collection.sh [--repo <工作區>] [--config <content.config.ts>]
#                                [--content-root <內容根>]
# Exit:  0 都帶著 / 1 有缺的 / 2 量不到（內容根不在、收到 0 份）/ 3 這棵樹沒有這個入口
#
# **3 跟 2 是兩件事。** 設定整份不在 ＝ 這棵樹根本沒有文件站台（template repo 只帶
# `.claude/` 與根目錄檔案，`docs-manager/` 不在其中），那不是「量不到」，是「沒有這個東西
# 要量」。設定在而內容根不在才是量不到——那時候有一個集合宣告在那裡，我卻看不到它收什麼。

set -uo pipefail

PREFIX="[polaris gate-docs-collection]"
REPO_PATH=""
CONFIG=""
CONTENT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)         REPO_PATH="${2:-}"; shift 2 ;;
    --config)       CONFIG="${2:-}"; shift 2 ;;
    --content-root) CONTENT_ROOT="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -n "$CONFIG" ]] || CONFIG="$REPO_PATH/docs-manager/src/content.config.ts"

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

if [[ ! -f "$CONFIG" ]]; then
  echo "$PREFIX 不適用：這棵樹沒有內容集合的設定（${CONFIG}）。"
  echo "$PREFIX 沒有那份設定就沒有「收哪些檔案」的權威，這裡不猜一份出來。"
  exit 3
fi

python3 - "$CONFIG" "$CONTENT_ROOT" "$PREFIX" <<'PY'
import fnmatch
import os
import re
import sys

config_path, content_root_arg, prefix = sys.argv[1:4]

with open(config_path, encoding="utf-8") as fh:
    config = fh.read()

# ── 從設定讀「收哪些」──────────────────────────────────────────────────────
# 剖析器故意很窄：看不懂就用量不到停下來，不要略過。略過的話一條新的排除規則會靜靜地
# 變成「沒有排除」，而這道閘就開始誣告。
base = re.search(r"base:\s*([A-Za-z_][A-Za-z0-9_]*|['\"][^'\"]+['\"])", config)
if base is None:
    print(f"{prefix} 量不到：設定裡讀不出 base。", file=sys.stderr)
    sys.exit(2)

# base 是變數時，回頭找那個變數的預設值——`process.env.X ? ... : './src/content/docs'`
# 這個形狀底下，我們要的是 else 那一邊：環境變數沒設時它就是預設的內容根。
base_value = base.group(1).strip("'\"")
if not base_value.startswith("."):
    m = re.search(re.escape(base_value) + r"\s*=[^;]*?:\s*['\"]([^'\"]+)['\"]", config, re.DOTALL)
    if m is None:
        print(f"{prefix} 量不到：base 是變數 `{base_value}`，但讀不出它的預設值。", file=sys.stderr)
        sys.exit(2)
    base_value = m.group(1)

# 陣列要用括號計數掃，不能用非貪婪的 `\[(.*?)\]`：第一條 include 自己就含著一個 `]`
# （`**/[^_]*.{...}`），非貪婪會停在那裡，於是這個陣列在剖析器眼裡是空的——而空的陣列
# 讀起來像「沒有 include」，那是一個假的量不到。
start = config.find("pattern:")
if start == -1 or config.find("[", start) == -1:
    print(f"{prefix} 量不到：設定裡讀不出 pattern。", file=sys.stderr)
    sys.exit(2)
i = config.find("[", start)
depth = 0
end = None
in_str = None
for j in range(i, len(config)):
    ch = config[j]
    if in_str:
        if ch == in_str:
            in_str = None
        continue
    if ch in "`'\"":
        in_str = ch
        continue
    if ch == "[":
        depth += 1
    elif ch == "]":
        depth -= 1
        if depth == 0:
            end = j
            break
if end is None:
    print(f"{prefix} 量不到：pattern 的陣列沒有收尾。", file=sys.stderr)
    sys.exit(2)


class _Block:
    def __init__(self, text):
        self._text = text

    def group(self, _n):
        return self._text


pattern_block = _Block(config[i + 1:end])
# 三種字串各自抓：backtick 那一條裡面含著 `'`（`${docsExtensions.join(',')}`），
# 用一個「三種引號都當結尾」的字元類會在那個單引號上斷掉，然後這條 include 就消失了。
globs = [g for group in re.findall(r"`([^`]*)`|'([^']*)'|\"([^\"]*)\"",
                                   pattern_block.group(1))
         for g in group if g]
includes = [g for g in globs if not g.startswith("!")]
excludes = [g[1:] for g in globs if g.startswith("!")]
if not includes:
    print(f"{prefix} 量不到：pattern 裡一條 include 都沒有。", file=sys.stderr)
    sys.exit(2)

# include 那一條帶著模板字串展開出來的副檔名清單（`{md,mdx,...}`）。這裡只取副檔名集合，
# 因為 `**/[^_]*.{...}` 的其餘部分（底線開頭不收）另外處理。
EXTS = re.search(r"docsExtensions\s*=\s*\[(.*?)\]", config, re.DOTALL)
if EXTS is None:
    exts = ["md", "mdx"]
else:
    exts = [e.strip().strip("'\"") for e in EXTS.group(1).split(",") if e.strip()]

content_root = content_root_arg or os.path.normpath(
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(config_path))), base_value))

if not os.path.isdir(content_root):
    print(f"{prefix} 量不到：內容根不在 {content_root}。", file=sys.stderr)
    print(f"{prefix} 那個目錄由忽略規則排除，在乾淨的 checkout 上沒有它是正常的——", file=sys.stderr)
    print(f"{prefix} 那不是「都帶著」，所以這裡不回 0。", file=sys.stderr)
    sys.exit(2)


def excluded(rel):
    """排除規則用 glob 比，比不到就是沒排除。**被排掉的要數出來**，不要靜靜消失。"""
    for pat in excludes:
        # `!**/{a,b}/**` 這種帶大括號的展開成幾條再比。
        for expanded in expand_braces(pat):
            if fnmatch.fnmatch(rel, expanded) or fnmatch.fnmatch("./" + rel, expanded):
                return True
    return False


def expand_braces(pattern):
    m = re.search(r"\{([^{}]*)\}", pattern)
    if not m:
        return [pattern]
    out = []
    for option in m.group(1).split(","):
        out += expand_braces(pattern[:m.start()] + option.strip() + pattern[m.end():])
    return out


collected = []
skipped_excluded = 0
skipped_underscore = 0
for dirpath, dirnames, filenames in os.walk(content_root):
    dirnames[:] = [d for d in dirnames if d != "node_modules"]
    for fn in filenames:
        if not any(fn.endswith("." + e) for e in exts):
            continue
        rel = os.path.relpath(os.path.join(dirpath, fn), content_root)
        if fn.startswith("_"):
            # include 那一條是 `**/[^_]*.{...}`：底線開頭的不收。
            skipped_underscore += 1
            continue
        if excluded(rel):
            skipped_excluded += 1
            continue
        collected.append((rel, os.path.join(dirpath, fn)))

if not collected:
    print(f"{prefix} 量不到：pattern 收到 0 份。0 份的 0 個缺漏，"
          f"跟「都帶著」在輸出上長得一樣。", file=sys.stderr)
    sys.exit(2)

# starlight 的 docsSchema 必填的是 title。這裡只驗它——多驗幾個欄位的話，這支腳本就變成
# 那個 schema 的第二份副本，而副本會漂。
FRONTMATTER = re.compile(r"\A---\s*\n(.*?)\n---\s*(\n|\Z)", re.DOTALL)
missing = []
for rel, path in collected:
    try:
        with open(path, encoding="utf-8") as fh:
            head = fh.read(8192)
    except (OSError, UnicodeDecodeError):
        missing.append(f"{rel}: 讀不動")
        continue
    m = FRONTMATTER.match(head)
    if m is None:
        missing.append(f"{rel}: 沒有 frontmatter（缺 title）")
        continue
    if not re.search(r"^title\s*:\s*\S", m.group(1), re.MULTILINE):
        missing.append(f"{rel}: frontmatter 在，但缺 title")

for line in sorted(missing):
    print("MISSING", line)
print(f"{prefix} DISCLOSURE 不判定的：被排除規則排掉 {skipped_excluded} 份、"
      f"底線開頭 {skipped_underscore} 份。不判定不等於沒有那些檔案。")
print(f"DOCS-COLLECTION-CHECKED root={content_root} collected={len(collected)} "
      f"missing={len(missing)}")
if missing:
    print(f"{prefix} 這幾份會讓文件站台整個建不起來（InvalidContentEntryDataError），", file=sys.stderr)
    print(f"{prefix} 而不是只有它們自己壞掉。補 frontmatter，或把它們移出內容集合。", file=sys.stderr)
    sys.exit(1)
print(f"{prefix} ✅ 收進去的 {len(collected)} 份都帶著 title。")
PY
