#!/usr/bin/env bash
# Purpose: 這支 skill 底下的每一個檔案、每一個對外旗標，要嘛有現在的呼叫者，要嘛有寫下來
#          的理由。兩者都沒有的就是死的，而死的東西會被下一個人當成還在用的。
# Inputs:  這支 skill 自己的目錄；反向對照組用的 fixture 在 mktemp 底下。
# Outputs: PASS 當沒有呼叫者又沒有理由的檔案／旗標被指名判紅、宣告過理由的不判紅，
#          而這支 skill 現在的狀態是綠的。
#
# 為什麼判準是「這支 skill 自己」而不是整個 repo：它是可攜的，會被單獨下載到只有它自己
# 的環境裡。一個只在這個 repo 裡有呼叫者的東西，到了那裡就是死的。
#
# selftest 本身沒有具名的呼叫者，那是對的——釋出尾段的跑測器用
# `find -name '*-selftest.sh'` 找它們，那個慣例就是它們的呼叫者。豁免逐條數出來，
# 因為一個安靜的豁免下一次會被當成檢查過了。

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok  $*"; PASS=$((PASS + 1)); }

# Description: 對一個 skill 目錄跑一次孤兒盤點。輸出放進 OUT，exit code 放進 RC。
# Args: $1 = skill 目錄
audit() {
  RC=0
  OUT="$(python3 - "$1" <<'PY'
import os
import re
import sys

skill = os.path.abspath(sys.argv[1])

# 誰提到誰。整支 skill 的文字讀一次就好——這棵樹很小，而分開讀會讓「有沒有人用」這個
# 問題在不同地方有不同答案。
corpus = {}
for dirpath, dirnames, filenames in os.walk(skill):
    dirnames[:] = [d for d in dirnames if d != "__pycache__"]
    for name in filenames:
        path = os.path.join(dirpath, name)
        try:
            corpus[path] = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            corpus[path] = ""

# 一個名字只出現在註解裡不算它存在——這跟 gate-prose-matches-behaviour 是同一句話。
LINE_COMMENT = re.compile(r"^[ \t]*#.*$", re.M)
# 寫下來的理由長這樣，而且一定要有理由：一個沒有理由的豁免跟刪掉它的差別只有磁碟空間。
NO_CALLER = re.compile(r"^[ \t]*#[ \t]*NO-CALLER:[ \t]*(\S+)[ \t]*(?:—|--)[ \t]*(\S.*?)[ \t]*$", re.M)

orphans = []
exempt_selftests = 0
declared = 0

scripts = os.path.join(skill, "scripts")
for dirpath, dirnames, filenames in os.walk(scripts):
    dirnames[:] = [d for d in dirnames if d != "__pycache__"]
    for name in sorted(filenames):
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, skill)
        if name.endswith("-selftest.sh"):
            exempt_selftests += 1
            continue
        if not any(name in text for other, text in corpus.items() if other != path):
            orphans.append(f"{rel}：沒有任何一個檔案提到它")

# 對外旗標。只看直接住在 scripts/ 底下的 .sh——那些是這支 skill 的介面；lib/ 底下的是
# 內部實作，它的介面是函式，不是命令列。
for name in sorted(os.listdir(scripts)):
    path = os.path.join(scripts, name)
    if not os.path.isfile(path) or not name.endswith(".sh"):
        continue
    text = corpus[path]
    reasons = {flag: why for flag, why in NO_CALLER.findall(text)}
    body = LINE_COMMENT.sub("", text)
    for flag in sorted(set(re.findall(r"^\s*(--[a-z][a-z0-9-]*)\)", body, re.M))):
        if any(flag in other_text and name in other_text
               for other, other_text in corpus.items() if other != path):
            continue
        if flag in reasons:
            declared += 1
            continue
        orphans.append(f"{name} {flag}：沒有呼叫者，也沒有寫下理由")

print(f"盤點 {len(corpus)} 個檔：豁免 {exempt_selftests} 支 selftest"
      f"（跑測器用 find 找它們）、{declared} 個旗標有寫下來的理由。")
for line in orphans:
    print(f"  ORPHAN {line}")
sys.exit(1 if orphans else 0)
PY
)" || RC=$?
}

echo "no-orphans selftest"

# 反向對照組一：沒有呼叫者的檔案。先證明它紅得起來，再拿它去量真的那棵樹。
mkdir -p "$WORK/red/scripts"
printf '# demo\n\n跑 `scripts/used.sh`。\n' > "$WORK/red/SKILL.md"
printf '#!/usr/bin/env bash\ncase "$1" in\n  --issue) shift 2 ;;\nesac\n' > "$WORK/red/scripts/used.sh"
printf '#!/usr/bin/env bash\necho nobody calls me\n' > "$WORK/red/scripts/orphan.sh"
audit "$WORK/red"
[[ "$RC" -eq 1 ]] || fail "沒有呼叫者的檔案應該判紅；拿到 ${RC}：$OUT"
grep -q 'ORPHAN scripts/orphan.sh' <<<"$OUT" || fail "沒說出是哪一個檔案：$OUT"
ok "沒有呼叫者的檔案會紅，而且說得出是哪一個"

# 反向對照組二：沒有呼叫者的旗標。`--issue` 有人用（SKILL.md 沒寫，但這裡故意只留一個）。
rm "$WORK/red/scripts/orphan.sh"
printf '#!/usr/bin/env bash\ncase "$1" in\n  --issue) shift 2 ;;\n  --nobody-uses-this) shift ;;\nesac\n' \
  > "$WORK/red/scripts/used.sh"
printf '# demo\n\n跑 `scripts/used.sh --issue x`。\n' > "$WORK/red/SKILL.md"
audit "$WORK/red"
[[ "$RC" -eq 1 ]] || fail "沒有呼叫者的旗標應該判紅；拿到 ${RC}：$OUT"
grep -q -- 'ORPHAN used.sh --nobody-uses-this' <<<"$OUT" || fail "沒說出是哪一個旗標：$OUT"
ok "沒有呼叫者的旗標會紅，而且說得出是哪一個"

# 寫下來的理由是唯一的出路，而且理由要真的寫出來——只有標記沒有句子不算。
printf '#!/usr/bin/env bash\n# NO-CALLER: --nobody-uses-this — 保留給下游，這棵樹上沒有呼叫者\ncase "$1" in\n  --issue) shift 2 ;;\n  --nobody-uses-this) shift ;;\nesac\n' \
  > "$WORK/red/scripts/used.sh"
audit "$WORK/red"
[[ "$RC" -eq 0 ]] || fail "寫下理由之後應該是綠的；拿到 ${RC}：$OUT"
grep -q '1 個旗標有寫下來的理由' <<<"$OUT" || fail "寫下來的理由要被數出來：$OUT"
ok "寫下理由的旗標不判紅，而且理由的數量被印出來"

printf '#!/usr/bin/env bash\n# NO-CALLER: --nobody-uses-this\ncase "$1" in\n  --issue) shift 2 ;;\n  --nobody-uses-this) shift ;;\nesac\n' \
  > "$WORK/red/scripts/used.sh"
audit "$WORK/red"
[[ "$RC" -eq 1 ]] || fail "沒有理由的標記不該買到豁免；拿到 ${RC}：$OUT"
ok "只有標記沒有理由不算寫下來"

# 真的那棵樹。上面三條證明這支量得到東西，這一條才有意義。
audit "$SKILL_DIR"
[[ "$RC" -eq 0 ]] || fail "這支 skill 有沒有呼叫者也沒有理由的東西：$OUT"
grep -q '豁免 .* 支 selftest' <<<"$OUT" || fail "豁免要被數出來：$OUT"
ok "verify-ac 自己現在沒有孤兒（$(printf '%s' "$OUT" | head -1)）"

echo "PASS: no-orphans（$PASS 項）"
