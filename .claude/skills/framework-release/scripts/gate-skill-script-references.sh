#!/usr/bin/env bash
# Purpose: 每支 skill 底下的腳本，指向自己同目錄（或 lib/、env/、selftests/）的檔案時，
#          那個檔案要真的在。腳本搬家會把這種寫死的相對路徑一個一個變成執行期才炸的洞。
# Inputs:  --repo <path>（預設從自己的位置往上找 git 根）
# Outputs: 每個對不上的引用印一行；有任何一個就 exit 1。
#
# 為什麼需要這道閘：shellcheck 不解析變數路徑，per-skill selftest 只跑得到自己那支的
# happy path。DP-462 把共用的 scripts/ 拆進各 skill 之後，三個不同的斷點都是在**釋出
# 執行到一半**才炸出來的——`gates/gate-spine-delivery.sh`、`gate-pr-language.sh` 整支不見、
# `lib/tool-resolution.sh` 沒跟著搬。那時候版號已經壓下去了。

set -euo pipefail

PREFIX="[polaris gate-skill-script-references]"
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi

python3 - "$REPO_ROOT" "$PREFIX" <<'PY'
import os
import re
import subprocess
import sys

repo_root, prefix = sys.argv[1], sys.argv[2]

# 只看「從腳本自己的位置算起」的引用。指向 repo 根或別的 skill 的引用不在這裡管——
# 那些變數的值不是自明的，猜錯會製造假紅。
SELF_DIR_VARS = r"SCRIPT_DIR|SCRIPTS|HERE|LIB_DIR|SKILLS_DIR"
REF = re.compile(
    rf"\$\{{?(?:{SELF_DIR_VARS})\}}?/((?:lib/|env/|selftests/|gates/)?[\w.-]+\.(?:sh|py|mjs))"
)
CODE_SUFFIXES = (".sh", ".py", ".mjs")
HEREDOC_OPEN = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")


def strip_heredocs(text):
    """把 heredoc 的內容拿掉。

    heredoc 裡的東西是要寫到別的地方去的資料，不是這個檔自己的引用——selftest 的
    fixture 就長這樣，不排掉的話這道閘會擋下自己的 selftest。

    Args: text = 原始檔案內容
    Returns: 移除所有 heredoc body 之後的內容（行數不保留）
    """
    out, delimiter = [], None
    for line in text.split("\n"):
        if delimiter is None:
            match = HEREDOC_OPEN.search(line)
            out.append(line)
            if match:
                delimiter = match.group(1)
        elif line.strip() == delimiter:
            delimiter = None
    return "\n".join(out)

listed = subprocess.run(
    ["git", "-C", repo_root, "ls-files", ".claude/skills"],
    capture_output=True, text=True, check=True,
).stdout.split()

problems = []
scanned = 0
for rel in listed:
    if not rel.endswith(CODE_SUFFIXES):
        continue
    path = os.path.join(repo_root, rel)
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    scanned += 1
    here = os.path.dirname(path)
    for match in REF.finditer(strip_heredocs(text)):
        target = match.group(1)
        if not os.path.exists(os.path.join(here, target)):
            problems.append(f"  {rel} -> {target}")

if problems:
    print(f"{prefix} 引用指向不存在的檔案：", file=sys.stderr)
    print("\n".join(sorted(set(problems))), file=sys.stderr)
    print(f"{prefix} ❌ {len(set(problems))} 個斷掉的引用（掃了 {scanned} 個檔）", file=sys.stderr)
    raise SystemExit(1)

print(f"{prefix} ✅ {scanned} 個檔的同目錄引用都對得上。")
PY
