#!/usr/bin/env bash
# record-independent-oracle.sh — 把那一趟獨立量測的結果收成一份報告。
#
# **它不判定任何事，這是刻意的。** 獨立 agent 說某一條沒過，那是一份帶引用的意見，不是
# 一個 exit code：判「這張單能不能出貨」的仍然只有交付紀錄。把 LLM 的判斷接到會擋人的
# 路徑上是往下走不是往上走——EACL 2026 量到，一行「this is correct」的註解就能讓
# LLM-as-judge 的判對率動 34 個百分點。
#
# 所以這一支的離場碼說的是「收不收得成」，不是「過了沒」。
#
# Usage: record-independent-oracle.sh --issue <單的目錄> [--cost-tokens N] [--cost-seconds N]
# Exit:  0 收成了 / 2 前提不在、或兩份結果對不起來

set -euo pipefail

ISSUE="" TOKENS="" SECONDS_SPENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --cost-tokens) TOKENS="${2:-}"; shift 2 ;;
    --cost-seconds) SECONDS_SPENT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "POLARIS_INDEPENDENT_ORACLE_UNKNOWN_ARG:$1" >&2; exit 2 ;;
  esac
done

[ -n "$ISSUE" ] || { echo "POLARIS_INDEPENDENT_ORACLE_NO_ISSUE" >&2; exit 2; }
[ -d "$ISSUE" ] || { echo "POLARIS_INDEPENDENT_ORACLE_ISSUE_NOT_FOUND:$ISSUE" >&2; exit 2; }
ISSUE=$(cd "$ISSUE" && pwd)

python3 - "$ISSUE" "${TOKENS:-}" "${SECONDS_SPENT:-}" <<'PY'
import json, os, sys, datetime

issue, tokens, secs = sys.argv[1], sys.argv[2], sys.argv[3]
out = os.path.join(issue, ".spine", "independent")
p1, p2 = os.path.join(out, "phase1.json"), os.path.join(out, "phase2.json")

def die(code, *lines):
    print(code, file=sys.stderr)
    for l in lines: print("  " + l, file=sys.stderr)
    sys.exit(2)

for p, phase in ((p1, 1), (p2, 2)):
    if not os.path.exists(p):
        die(f"POLARIS_INDEPENDENT_ORACLE_PHASE{phase}_MISSING:{p}",
            f"第 {phase} 階段還沒有結果。那一趟沒跑完，就沒有東西可以收。")

def load(p):
    try:
        return json.load(open(p, encoding="utf-8"))
    except Exception as e:
        die(f"POLARIS_INDEPENDENT_ORACLE_UNREADABLE:{p}",
            f"讀不動：{e}",
            "讀不動跟「量到零條」長得不一樣，所以這裡停，不當成空的。")

a, b = load(p1), load(p2)
rows1 = a.get("assertions") or []
rows2 = b.get("per_assertion") or []
if not rows1:
    die("POLARIS_INDEPENDENT_ORACLE_PHASE1_EMPTY",
        "第一階段一條 assertion 都沒有。那不是「都過了」，是那一趟沒有量到東西。")

ids1 = [r.get("id") for r in rows1]
ids2 = [r.get("id") for r in rows2]
missing = [i for i in ids1 if i not in ids2]
extra   = [i for i in ids2 if i not in ids1]
if missing or extra:
    die("POLARIS_INDEPENDENT_ORACLE_PHASES_DISAGREE",
        f"只在第一階段出現的：{missing or '無'}",
        f"只在第二階段出現的：{extra or '無'}",
        "兩階段講的不是同一組 assertion，比對出來的差異因此不可信。")

BUCKETS = ("builder_only", "independent_only", "both")
counts = {k: [] for k in BUCKETS}
unclassified = []
for r in rows2:
    c = r.get("classification")
    (counts[c] if c in counts else unclassified).append(r.get("id"))
if unclassified:
    die("POLARIS_INDEPENDENT_ORACLE_UNCLASSIFIED",
        f"沒有分類、或分類不在三種裡的：{unclassified}",
        "三類是這份報告唯一的產出，少一條就少一塊。")

# independent_only 必須說出「漏掉這一格會讓什麼通過」——那正是這一趟存在的理由。
silent = [r.get("id") for r in rows2
          if r.get("classification") == "independent_only"
          and not (r.get("why_it_matters") or "").strip()]
if silent:
    die("POLARIS_INDEPENDENT_ORACLE_FINDING_WITHOUT_STAKES",
        f"這幾條說了「只有我量到」卻沒說漏掉它會怎樣：{silent}",
        "一條說不出後果的發現，讀的人沒有辦法決定要不要修。")

unmeasurable = [(r.get("id"), (r.get("unmeasurable_because") or "（沒說是哪一種）"))
                for r in rows1 if r.get("verdict") == "unmeasurable"]

result = {
    "schema_version": 1,
    "producer": "record-independent-oracle.sh",
    "recorded_at": datetime.datetime.now(datetime.timezone.utc)
                     .strftime("%Y-%m-%dT%H:%M:%SZ"),
    "tree": a.get("tree"),
    "assertion_count": len(rows1),
    "summary": {k: len(v) for k, v in counts.items()},
    "ids": {k: v for k, v in counts.items()},
    "unmeasurable": [{"id": i, "because": w} for i, w in unmeasurable],
    "cost": {"tokens": int(tokens) if tokens else None,
             "seconds": int(secs) if secs else None},
    "claims_nothing": ("這一趟不是 held-out 驗證，也不是第二個權威：派工的是施工方、"
                       "跑的是同一棵樹、探針由 LLM 從同一份 assertion 推。它說出的是"
                       "兩份獨立推導的 oracle 差在哪，判定仍由交付紀錄承載。"),
}
json.dump(result, open(os.path.join(out, "result.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

def bucket_lines(k, title):
    ids = counts[k]
    if not ids:
        # 空要說出來：空集合與沒跑過長得不一樣。
        return [f"### {title}：**一條都沒有**", ""]
    lines = [f"### {title}（{len(ids)} 條）", ""]
    for r in rows2:
        if r.get("classification") != k: continue
        lines.append(f"- **{r.get('id')}**")
        lines.append(f"  - 施工方量到：{r.get('builder_measures') or '（沒說）'}")
        lines.append(f"  - 獨立量到：{r.get('independent_measures') or '（沒說）'}")
        if (r.get("disagreement") or "").strip():
            lines.append(f"  - **兩邊結論不同**：{r['disagreement']}")
        if (r.get("why_it_matters") or "").strip():
            lines.append(f"  - **漏掉它會怎樣**：{r['why_it_matters']}")
    return lines + [""]

md = [
    "# 兩份獨立推導的 oracle 差在哪",
    "",
    "**這份不判定任何事。** 它是一份帶引用的意見，判「這張單能不能出貨」的仍然只有交付紀錄。",
    "",
    f"- 量的那棵樹：`{a.get('tree')}`",
    f"- assertion：{len(rows1)} 條",
    f"- 收下來的時間：{result['recorded_at']}",
]
if result["cost"]["tokens"] or result["cost"]["seconds"]:
    md.append(f"- 這一趟的成本：{result['cost']['tokens'] or '？'} token／"
              f"{result['cost']['seconds'] or '？'} 秒")
else:
    md.append("- 這一趟的成本：**沒有人記**（`--cost-tokens`／`--cost-seconds` 沒給）")
md += ["", "## 三類", ""]
md += bucket_lines("independent_only", "只有獨立量測抓到的")
md += bucket_lines("both", "兩邊都量到的")
md += bucket_lines("builder_only", "只有施工方量到的")

md += ["## 量不到的", ""]
if unmeasurable:
    md += [f"- **{i}**：{w}" for i, w in unmeasurable] + [""]
else:
    md += ["**一條都沒有**——每一條 assertion 這一趟都量得到。", ""]

md += ["## 這一趟不宣稱什麼", "", result["claims_nothing"], ""]
open(os.path.join(out, "report.md"), "w", encoding="utf-8").write("\n".join(md) + "\n")

s = result["summary"]
print(f"RECORDED: {os.path.join(out, 'report.md')}")
print(f"  只有獨立量測抓到的 {s['independent_only']} 條／兩邊都量到 {s['both']} 條／"
      f"只有施工方量到 {s['builder_only']} 條／量不到 {len(unmeasurable)} 條")
if s["independent_only"] == 0:
    print("  獨立那一趟沒有抓到施工方漏掉的東西。**這是一個結果，照實記著**——"
          "它是「這一層值不值得」要被重估的證據。")
PY
