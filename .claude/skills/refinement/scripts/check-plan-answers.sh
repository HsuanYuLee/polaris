#!/usr/bin/env bash
# check-plan-answers.sh — 只有人回答得出來的那幾項，在凍結之前都已經有答案。
#
# 為什麼要有這一道
# ----------------
# 閘一簽的是 AC——「怎麼算成功」。它不問「什麼時候要」「為什麼要」「拿什麼測」，而那三件
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
# Usage: check-plan-answers.sh <index.md> [--require what,when,why,how]
# Exit:  0 齊備 / 2 缺項或剖析不了（訊息指名是哪一項）

set -uo pipefail

MARKER_MISSING="POLARIS_PLAN_ANSWER_MISSING"
MARKER_UNPARSEABLE="POLARIS_PLAN_BLOCK_UNPARSEABLE"

# 預設要問的四項。它們是「只有人回答得出來」的那一組，不是 5W1H 的全部——Who 與 Where
# 對同一個 repo 的每一張單答案都一樣，屬領域知識，不屬這裡。
REQUIRE="what,when,why,how"
FILE=""

usage() {
  echo "Usage: check-plan-answers.sh <index.md> [--require what,when,why,how]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require) REQUIRE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "不認得的參數：$1" >&2; usage ;;
    *) FILE="$1"; shift ;;
  esac
done

[[ -n "$FILE" ]] || usage
[[ -f "$FILE" ]] || { echo "$MARKER_UNPARSEABLE" >&2; echo "找不到 $FILE" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$FILE" "$REQUIRE" "$MARKER_MISSING" "$MARKER_UNPARSEABLE" <<'PY'
import sys

path, require_csv, marker_missing, marker_unparseable = sys.argv[1:5]
required = [k.strip() for k in require_csv.split(",") if k.strip()]
SOURCES = ("human", "environment", "inferred_confirmed")


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
           "問法在 refinement 的〈問出只有人知道的事〉：一次一題、每題附上你建議的答案、",
           "查得到的事實自己查不要拿去問人。")

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

if problems:
    refuse(marker_missing,
           f"{path} 的 plan 區塊還缺東西，凍結不放行：", *problems,
           "問法在 refinement 的〈問出只有人知道的事〉：一次一題、每題附上你建議的答案、",
           "查得到的事實自己查不要拿去問人。")

answered = [k for k in required if not plan.get(k, {}).get("not_applicable")]
skipped = [k for k in required if plan.get(k, {}).get("not_applicable")]
print(f"PLAN-ANSWERS-OK {len(answered)} 項有答案（{', '.join(answered) or '無'}）"
      f"，{len(skipped)} 項記為不適用（{', '.join(skipped) or '無'}）")
PY
