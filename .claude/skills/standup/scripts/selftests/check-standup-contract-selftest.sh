#!/usr/bin/env bash
# check-standup-contract-selftest.sh — 餵紅 check-standup-contract.sh。
#
# 一支自己剛寫的檢查第一次就綠是可疑訊號，通常代表規則太窄。這支對每一個契約點做兩種
# 破壞，量它真的會紅：
#
#   1. 拔掉錨 —— 契約點整段被後續改寫刪掉的那一種。
#   2. 留著錨、掏空內容 —— 契約被稀釋成一句沒有內容的話的那一種。只驗第 1 種的話，
#      「刪散文留註解」會靜靜地過。
#
# 另外驗兩種「量不到」要用 exit 2 而不是 0：散文檔不在、一個錨都沒有。一個掃到 0 個目標的
# 負向檢查，在輸出上跟「掃過了，沒問題」長得一模一樣。
#
# Usage: check-standup-contract-selftest.sh
# Exit:  0 全部如預期 / 1 有一種破壞沒被抓到

set -euo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
CHECKER="$SCRIPTS_DIR/check-standup-contract.sh"

PREFIX="[selftest check-standup-contract]"
PASS=0
FAIL=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 每個契約點：錨名 → 住在哪個檔
ANCHORS=(
  "evidence-window:references/standup-data-collection-flow.md"
  "comments-are-collected:references/standup-data-collection-flow.md"
  "newest-wins:references/standup-data-collection-flow.md"
  "ydy-includes-pr:references/standup-data-collection-flow.md"
  "status-is-not-intent:references/standup-data-collection-flow.md"
  "bos-admission:references/standup-planning-flow.md"
  "terse-output:references/standup-template.md"
  "evidence-exempt:references/standup-template.md"
  "drift-surfaced:references/standup-format-publish-flow.md"
  "drift-needs-consent:references/standup-format-publish-flow.md"
  "unmeasurable-is-not-silent:references/standup-data-collection-flow.md"
)

# 不變量：舊的結構被順手改掉的那一種。每一項給一個「刪掉它」的注入。
# 格式：住在哪個檔:要刪掉的字串
INVARIANT_KILLS=(
  "references/standup-format-publish-flow.md:BOS – Blockers or Struggles"
  "references/standup-format-publish-flow.md:YDY 與 TDT 都依 team 分組"
  "references/standup-format-publish-flow.md:[KEY title](URL)"
  "references/standup-planning-flow.md:使用者在對話中的口述 blockers"
  "references/standup-planning-flow.md:不擴張"
)

# fresh_copy <dest> —— 把真的散文複製一份出來動手腳，不碰原樹。
fresh_copy() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest/references"
  cp "$SKILL_DIR"/references/standup-data-collection-flow.md \
     "$SKILL_DIR"/references/standup-planning-flow.md \
     "$SKILL_DIR"/references/standup-template.md \
     "$SKILL_DIR"/references/standup-format-publish-flow.md \
     "$dest/references/"
}

# expect <想要的 exit code> <說明> -- <命令...>
expect() {
  local want="$1" what="$2"; shift 3
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "$PREFIX 沒抓到：$what（想要 exit $want，實際 $got）" >&2
  fi
}

# ── 0. 真樹要是綠的。它紅了的話下面每一條紅都沒有意義 ────────────────────────
expect 0 "真樹綠" -- bash "$CHECKER" --skill-dir "$SKILL_DIR"

# ── 1+2. 逐個契約點：拔錨、掏空 ──────────────────────────────────────────────
for entry in "${ANCHORS[@]}"; do
  name="${entry%%:*}"
  rel="${entry#*:}"

  # 1. 拔掉錨
  d="$WORK/drop-$name"
  fresh_copy "$d"
  python3 - "$d/$rel" "$name" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    re.sub(r"<!--\s*STANDUP-CONTRACT:\s*" + re.escape(name) + r"\s*-->\n?", "", src)
)
PY
  expect 1 "拔掉錨 $name" -- bash "$CHECKER" --skill-dir "$d"

  # 2. 留著錨，把它底下那一段換成一句沒有內容的話
  d="$WORK/gut-$name"
  fresh_copy "$d"
  python3 - "$d/$rel" "$name" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
anchor = re.compile(r"<!--\s*STANDUP-CONTRACT:\s*([a-z0-9-]+)\s*-->")
hit = next(m for m in anchor.finditer(src) if m.group(1) == name)
nxt = anchor.search(src, hit.end())
end = nxt.start() if nxt else len(src)
open(path, "w", encoding="utf-8").write(
    src[:hit.end()] + "\n\n這一段照規矩辦。\n\n" + src[end:]
)
PY
  # ${name} 要帶大括號：後面接的是全形括號，bash 在這個 locale 下會把它的第一個 byte
  # 讀進變數名，於是 `$name（` 變成一個 unbound variable。
  expect 1 "掏空 ${name}（錨還在）" -- bash "$CHECKER" --skill-dir "$d"
done

# ── 2b. 不變量：把既有結構刪掉，要紅 ─────────────────────────────────────────
inv_n=0
for entry in "${INVARIANT_KILLS[@]}"; do
  rel="${entry%%:*}"
  needle="${entry#*:}"
  inv_n=$((inv_n + 1))
  d="$WORK/inv-$inv_n"
  fresh_copy "$d"
  python3 - "$d/$rel" "$needle" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
if needle not in src:
    raise SystemExit(f"注入本身沒生效：{needle!r} 不在 {path}")
open(path, "w", encoding="utf-8").write(src.replace(needle, "（刪掉了）"))
PY
  expect 1 "刪掉既有結構：${needle}" -- bash "$CHECKER" --skill-dir "$d"
done

# ── 3. 量不到要用 2，不是 0 ──────────────────────────────────────────────────
d="$WORK/nodir"
expect 2 "skill 目錄不在" -- bash "$CHECKER" --skill-dir "$d"

d="$WORK/nofile"
fresh_copy "$d"
rm "$d/references/standup-template.md"
expect 2 "散文檔不在" -- bash "$CHECKER" --skill-dir "$d"

d="$WORK/noanchor"
fresh_copy "$d"
python3 - "$d" <<'PY'
import os, re, sys
root = sys.argv[1]
anchor = re.compile(r"<!--\s*STANDUP-CONTRACT:[^>]*-->\n?")
for name in os.listdir(os.path.join(root, "references")):
    p = os.path.join(root, "references", name)
    src = open(p, encoding="utf-8").read()
    open(p, "w", encoding="utf-8").write(anchor.sub("", src))
PY
expect 2 "一個錨都沒有（不得判綠）" -- bash "$CHECKER" --skill-dir "$d"

echo "$PREFIX PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" == 0 ]]
