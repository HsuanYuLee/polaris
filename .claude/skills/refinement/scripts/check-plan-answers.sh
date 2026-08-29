#!/usr/bin/env bash
# check-plan-answers.sh — 只有人回答得出來的那幾項，在凍結之前都已經有答案。
#
# 為什麼要有這一道
# ----------------
# 第一關簽的是 AC——「怎麼算成功」。它不問「什麼時候要」「為什麼要」「拿什麼測」，而那三件
# 事同樣只有人知道，而且它們會決定 AC 本身寫得對不對。
#
# 沒被問的那一刻，LLM 不會停下來，它會**自己填一個**。這比空著糟：空著看得出來，填過的看
# 不出來。而判定那一站只驗實作有沒有達成那份 AC——AC 若照著一個編出來的意圖寫，整條流程會
# 全綠地交付錯的東西。
#
# 空著與「不適用」是兩件事
# ------------------------
# 這是這支腳本唯一在防的形狀。一個沒填的欄位跟一個「這張單不需要它」的決定，在檔案裡必須
# 長得不一樣，否則第二種會被第一種吸收，然後沒有人知道哪些是真的被想過的。
#
# 剖析器故意很窄
# --------------
# 這裡不拉 YAML 套件：這支 skill 要能被複製到 claude.ai 與 Cowork，那裡不保證有。窄的代價
# 是看不懂的寫法要**拒絕**而不是略過——略過的話，一個縮排打錯的 plan 區塊會靜默地變成
# 「沒有 plan 區塊」，而那正是這道檢查要抓的東西。
#
# 環境是列出來的，不是寫在句子裡
# ------------------------------
# 「拿什麼測」的答案裡通常含著「要起哪些東西」，但一句自由文字沒有任何東西讀得懂。所以
# `how` 要多帶一個 `environments`：列出來之後，「哪個環境還沒有人會起」就算得出來，而那
# 正是「該生一份領域知識了」的訊號——**在凍結之前就算得出來**，那時候計劃還改得動。
#
# 字面值 `none` 表示這件工作不需要起任何環境。那是一個寫下來的答案，不是欄位不見；跟
# `not_applicable` 與空著的關係是同一條分界。
#
# Usage: check-plan-answers.sh <index.md> [--require what,when,why,how] [--skills <dir>]
# Exit:  0 齊備 / 2 缺項、剖析不了、或有環境沒人會起（訊息指名是哪一個）

set -uo pipefail

MARKER_MISSING="POLARIS_PLAN_ANSWER_MISSING"
MARKER_UNPARSEABLE="POLARIS_PLAN_BLOCK_UNPARSEABLE"
MARKER_NO_ENV="POLARIS_PLAN_ENVIRONMENT_UNCLAIMED"

# 領域知識住的地方。發現面掃它底下每一份 SKILL.md 找環境宣告——跟核心解 pack 是同一棵樹，
# 所以換一個 workspace 不用改這裡。
SKILLS_DIR=""

# 預設要問的四項。它們是「只有人回答得出來」的那一組，不是 5W1H 的全部——Who 與 Where
# 對同一個 repo 的每一張單答案都一樣，屬領域知識，不屬這裡。
REQUIRE="what,when,why,how"
FILE=""

usage() {
  echo "Usage: check-plan-answers.sh <index.md> [--require what,when,why,how] [--skills <dir>]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require) REQUIRE="${2:-}"; shift 2 ;;
    --skills)  SKILLS_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "不認得的參數：$1" >&2; usage ;;
    *) FILE="$1"; shift ;;
  esac
done

# 往上兩層是 skill 根目錄（這支住在 {skill}/scripts/ 底下）。不寫死 repo 路徑：這一組
# 要能被整包複製到別的地方，而那裡的 repo 根目錄叫什麼不知道。
[[ -n "$SKILLS_DIR" ]] || SKILLS_DIR="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"

[[ -n "$FILE" ]] || usage
[[ -f "$FILE" ]] || { echo "$MARKER_UNPARSEABLE" >&2; echo "找不到 $FILE" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$FILE" "$REQUIRE" "$MARKER_MISSING" "$MARKER_UNPARSEABLE" "$MARKER_NO_ENV" "$SKILLS_DIR" <<'PY'
import glob
import os
import re
import sys

path, require_csv, marker_missing, marker_unparseable = sys.argv[1:5]
marker_no_env, skills_dir = sys.argv[5], sys.argv[6]
required = [k.strip() for k in require_csv.split(",") if k.strip()]
SOURCES = ("human", "environment", "inferred_confirmed")
# 「拿什麼測」是唯一帶得出環境的那一項。哪一項帶它寫在這裡而不是散在各處，因為它是一個
# 會被兩個地方讀到的決定：這支腳本，以及第一關的散文。
ENV_CARRIER = "how"
NO_ENVIRONMENT = "none"


def refuse(marker, *lines):
    print(marker, file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    sys.exit(2)


with open(path, encoding="utf-8") as handle:
    text = handle.read()

if not text.startswith("---\n"):
    refuse(marker_unparseable, f"{path} 沒有 frontmatter，讀不出 plan 區塊")
end = text.find("\n---", 3)
if end == -1:
    refuse(marker_unparseable, f"{path} 的 frontmatter 沒有收尾")
front = text[4:end].splitlines()

# 只認一種形狀：
#   plan:
#     <key>:
#       <field>: <value>
# 認不出來的行在 plan 區塊裡就是拒絕。略過會讓一個縮排打錯的區塊變成「沒有區塊」。
plan, current, in_plan, bad = {}, None, False, []
for lineno, raw in enumerate(front, start=2):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    indent = len(raw) - len(raw.lstrip())
    if indent == 0:
        in_plan = raw.startswith("plan:")
        current = None
        continue
    if not in_plan:
        continue
    stripped = raw.strip()
    if indent == 2 and stripped.endswith(":"):
        current = stripped[:-1].strip()
        plan[current] = {}
    elif indent == 4 and ":" in stripped and current is not None:
        field, _, value = stripped.partition(":")
        plan[current][field.strip()] = value.strip().strip('"').strip("'")
    else:
        bad.append(f"  第 {lineno} 行讀不懂：{raw.rstrip()}")

if bad:
    refuse(marker_unparseable,
           f"{path} 的 plan 區塊有讀不懂的行。認得的形狀只有一種：",
           "  plan:", "    <項目>:", "      answer: \"…\"", "      source: human",
           *bad)

if not plan:
    refuse(marker_missing,
           f"{path} 沒有 plan 區塊——只有人回答得出來的那幾項都還沒被問。",
           f"要問的是：{', '.join(required)}。",
           "每一項要嘛帶 answer + source，要嘛帶 not_applicable 加理由。",
           "做法在 refinement 的〈交一份草案，不交一串問題〉：整張讀完、每一格都先填、",
           "標好那一格是誰給的，然後讓人在草案上改。查得到的事實自己查，不要做成問題。")

problems = []
for key in required:
    entry = plan.get(key)
    if entry is None:
        problems.append(f"  {key}: 沒有這一項")
        continue
    na = entry.get("not_applicable", "")
    answer = entry.get("answer", "")
    source = entry.get("source", "")
    if na:
        continue
    if "not_applicable" in entry and not na:
        # 空的 not_applicable 是「我標了但沒說為什麼」，那跟沒標一樣。
        problems.append(f"  {key}: 標成 not_applicable 但沒有說為什麼")
        continue
    if not answer:
        problems.append(f"  {key}: 空著。沒有答案就要明講 not_applicable 並說為什麼——"
                        "空著與不適用是兩件事")
        continue
    if source not in SOURCES:
        problems.append(f"  {key}: 有答案但 source 是「{source or '空的'}」，"
                        f"要是 {'/'.join(SOURCES)} 其中之一——"
                        "一個不說出是誰給的答案，事後分不出它是人決定的還是編的")
        continue
    if key == ENV_CARRIER and "environments" not in entry:
        problems.append(f"  {key}: 沒有 environments。要起哪些環境寫在句子裡沒有人讀得懂，"
                        f"列出來才算得出「哪個還沒有人會起」。真的不需要就寫 "
                        f"environments: {NO_ENVIRONMENT}——那是一個答案，不是欄位不見")

if problems:
    refuse(marker_missing,
           f"{path} 的 plan 區塊還缺東西，凍結不放行：", *problems,
           "做法在 refinement 的〈交一份草案，不交一串問題〉：整張讀完、每一格都先填、",
           "標好那一格是誰給的，然後讓人在草案上改。查得到的事實自己查，不要做成問題。")

# 環境對得上人。列出來的每一個，都要有某一份領域知識宣告它會起它——找不到的那個就是
# 該生出來的那一份，而這件事在 assertion 被凍結之前就說得出來。
raw = (plan.get(ENV_CARRIER) or {}).get("environments", "")
wanted = [e.strip() for e in raw.strip().strip("[]").split(",") if e.strip()]
if wanted == [NO_ENVIRONMENT]:
    wanted = []

claimed = {}
for doc in sorted(glob.glob(os.path.join(skills_dir, "*", "SKILL.md"))):
    try:
        text = open(doc, encoding="utf-8").read()
    except OSError:
        continue
    # 宣告行的形狀跟開工條件、工作區身分同一種：前綴由那份知識自己定，這裡只認中段的
    # ENVIRONMENT-{名}。核心與這支腳本都不認得任何一個環境的名字。
    for name in re.findall(r"<!--\s*[A-Za-z0-9_-]*ENVIRONMENT-([A-Za-z0-9_.-]+):", text):
        claimed.setdefault(name, os.path.basename(os.path.dirname(doc)))

orphans = [e for e in wanted if e not in claimed]
if orphans:
    refuse(marker_no_env,
           f"{path} 列了 {len(wanted)} 個環境，其中 {len(orphans)} 個沒有任何一份領域知識會起：",
           *[f"  {e}" for e in orphans],
           "這就是「該沉澱一份領域知識了」的訊號。做法：開一份 skill，在它的 SKILL.md 裡",
           "宣告一行 `<!-- {前綴}-ENVIRONMENT-{環境名}: {起它的命令} -->`，命令要真的跑得起來。",
           "現在就做，比簽完 assertion 之後才發現便宜——那時候計劃還改得動。",
           f"（已經有人會起的：{', '.join(f'{k}→{v}' for k, v in sorted(claimed.items())) or '無'}）")

answered = [k for k in required if not plan.get(k, {}).get("not_applicable")]
skipped = [k for k in required if plan.get(k, {}).get("not_applicable")]
env_note = (f"，{len(wanted)} 個環境都有人會起（{', '.join(wanted)}）" if wanted
            else "，不需要起任何環境" if raw.strip() == NO_ENVIRONMENT else "")
print(f"PLAN-ANSWERS-OK {len(answered)} 項有答案（{', '.join(answered) or '無'}）"
      f"，{len(skipped)} 項記為不適用（{', '.join(skipped) or '無'}）{env_note}")
PY
