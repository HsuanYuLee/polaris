#!/usr/bin/env bash
# Purpose: 找出「往別人看得到的地方送出文字之前要先過哪一道檢查」，答案由別人宣告，
#          不由這裡寫死。這一層知道的只有一件事：**送出去之前要先落地成檔案、要先過檢查**。
#          那道檢查叫什麼、住在哪支 skill、怎麼呼叫，換一個環境就換一個答案。
#
# Inputs:  --skills-root <目錄>   預設從自己的位置往上推到 skills 根
# Outputs: 找到的話 stdout 印一行命令；找不到的話 stderr 說出來
# Exit:    0 有人宣告 / 3 沒有人宣告（**這不是壞掉**，見下）/ 2 參數或環境不對
#
# 宣告長這樣，掃的是所有 skill 的 SKILL.md：
#
#     <!-- {任意前綴}-EXTERNAL-WRITE-GATE: {命令} -->
#
# **沒有人宣告不等於可以直接送。** 這一支被單獨匯進一個沒有那道檢查的環境時，離場碼 3 的
# 意思是「這裡沒有那一層，落地成檔案這件事你自己要做」——不是「不用檢查了」。把它做成
# 離場碼 0 的那一版，會讓一個沒有檢查的環境跟一個檢查全過的環境印出同一句話。
#
# 為什麼不寫死路徑：這支 skill 目前指不到自己目錄以外的任何東西，而那是刻意的——它會被
# 單獨匯進別人的環境。寫一行 `.claude/skills/{某支}/scripts/{某支}.sh` 進來，在那些環境裡
# 是一個安靜讀不到的路徑，不會有人報錯。

set -euo pipefail

PREFIX="[swe-external-write-gate]"
SKILLS_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skills-root) SKILLS_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$SKILLS_ROOT" ]] || SKILLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -d "$SKILLS_ROOT" ]]; then
  echo "$PREFIX 量不到：$SKILLS_ROOT 不是一個目錄。" >&2
  exit 2
fi

# BSD 的 sed 沒有 lazy quantifier，而宣告行的尾巴是 `-->`——貪婪的比對會把它吃進命令裡。
# 所以這一行用 python3 解，跟樹上其他讀宣告的地方同一個做法。
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

found="$(python3 - "$SKILLS_ROOT" <<'PY'
import os
import re
import sys

root = sys.argv[1]
pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]*EXTERNAL-WRITE-GATE:\s*(.+?)\s*-->")
seen = set()
out = []
for dirpath, dirnames, filenames in os.walk(root):
    # `_template/` 講的是別人將來的 repo，它的宣告不是這個環境的答案。
    dirnames[:] = sorted(d for d in dirnames if d != "_template")
    if "SKILL.md" not in filenames:
        continue
    path = os.path.join(dirpath, "SKILL.md")
    real = os.path.realpath(path)
    if real in seen:
        continue
    seen.add(real)
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    for command in pattern.findall(text):
        out.append(f"{command}\t{os.path.relpath(path, root)}")
print("\n".join(out))
PY
)"

if [[ -z "$found" ]]; then
  echo "$PREFIX 沒有人宣告對外寫入的檢查。送出去之前仍然要先把文字落地成一個檔案。" >&2
  echo "$PREFIX 認領它的那支 skill 在自己的 SKILL.md 放一行：" >&2
  echo "$PREFIX   <!-- {前綴}-EXTERNAL-WRITE-GATE: {檢查文字的命令} -->" >&2
  exit 3
fi

count="$(printf '%s\n' "$found" | grep -c '')"
if [[ "$count" -gt 1 ]]; then
  # 兩個答案不比一個答案好。指名是哪幾份，讓人拆掉多的那一份。
  echo "$PREFIX ${count} 個地方宣告了對外寫入的檢查，說不出該用哪一個：" >&2
  printf '%s\n' "$found" | while IFS=$'\t' read -r cmd src; do
    echo "$PREFIX   ${src}: ${cmd}" >&2
  done
  exit 2
fi

printf '%s\n' "${found%%$'\t'*}"
