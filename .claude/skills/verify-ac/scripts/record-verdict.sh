#!/usr/bin/env bash
# record-verdict.sh — 對一個 head 寫下 verify-ac 的判定，一行機器讀得到（DP-993 A-P6）。
#
# 交付紀錄要等每一條都量到才寫得成，而帶著 stage、prod 才量得到的 assertion 的單，在那之前
# 一直寫不成——可是這一站該判的已經判完了。這一行說的就是那個狀態：這個 head 上，每一條不是
# 過了，就是寫明了要到哪一站才量得到、為什麼。出貨點對「開一顆 PR」「轉成 ready」讀的是這一行。
#
# 寫不成的情況說出來、回 1，不寫任何東西：有一條沒過；有一條這一站沒量、卻沒用 --not-yet 寫成
# 未到站；--not-yet 指名了一條量過而沒過的、或不存在的 assertion；--head 沒對上判定樹，或對上的不只一個 head。
#
# Usage: record-verdict.sh --issue <單的目錄> --head <sha> [--not-yet '<ID>=<哪一站>:<為什麼>']...
# --head 指名要寫哪一棵判定樹的 head；可以給前綴，至少 7 碼。
# Output: 寫成時印 `VERDICT: <單號> head <sha12> 過 n/m，未到站 k 條` 與寫進去的那一行。
# Exit:  0 寫成 / 1 寫不成（說出哪幾條；凍結塊沒過 fence 驗證也算）/ 2 參數不對
#
# 寫成之後，把這件事交給宣告了要知道的那支 skill，核心不認得任何外部系統：
#   <!-- {任意前綴}-VERDICT-RECORDED: {命令} -->
# 命令在 repo 根跑，後面接單的目錄與 head。它的離場碼不改變這一步的結果。
set -euo pipefail

PREFIX="[polaris record-verdict]"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$(cd "$ROOT_DIR/.." && pwd)"
ISSUE_DIR="" HEAD_SHA="" NOT_YET=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)   ISSUE_DIR="${2:-}"; shift 2 ;;
    --head)    HEAD_SHA="${2:-}"; shift 2 ;;
    --not-yet) NOT_YET+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done
[[ -f "$ISSUE_DIR/index.md" && -n "$HEAD_SHA" ]] || { echo "$PREFIX 要 --issue <帶 index.md 的單> 與 --head <sha>" >&2; exit 2; }
[[ ${#HEAD_SHA} -ge 7 ]] || { echo "$PREFIX --head 可以給前綴，但至少 7 碼（拿到 ${#HEAD_SHA} 碼）" >&2; exit 2; }
ISSUE_DIR="$(cd "$ISSUE_DIR" && pwd)"
# 成功的定義要是人簽過、commit 過的那一份，跟 record-delivery-intent.sh 同一道
if ! FENCE_OUT="$(bash "$ROOT_DIR/scripts/frozen-assertion-fence.sh" verify "$ISSUE_DIR/index.md" 2>&1)" \
   || grep -q '^NEW: ' <<<"$FENCE_OUT"; then
  echo "$PREFIX 寫不成判定：凍結塊沒過 fence 驗證（沒封、封了沒 commit、或封了之後被動過）。" >&2
  printf '%s\n' "$FENCE_OUT" | sed 's/^/  /' >&2
  exit 1
fi

PYTHON_OUT="$(python3 - "$ROOT_DIR" "$ISSUE_DIR" "$HEAD_SHA" "${NOT_YET[@]+"${NOT_YET[@]}"}" <<'PY'
import json, os, re, sys
from urllib.parse import quote
from datetime import datetime, timezone
sys.path.insert(0, sys.argv[1] + "/scripts/lib")
import assertion_verdicts as av

root, issue, head = sys.argv[1:4]
not_yet = {}
for spec in sys.argv[4:]:
    m = re.fullmatch(r"([A-Z][A-Z0-9]*-[A-Z]*\d+)=([^:]+):(.+)", spec.strip())
    if not m:
        print(f"--not-yet 的形狀是 '<ID>=<哪一站>:<為什麼>'（拿到 {spec!r}）", file=sys.stderr)
        sys.exit(2)
    not_yet[m.group(1)] = (m.group(2).strip(), m.group(3).strip())

index = os.path.join(issue, "index.md")
report = av.judge(index, os.path.join(issue, ".spine", "evidence"), head=None,
                  ledger_path=os.path.join(issue, ".spine", "measurement-ledger.json"))
# judge(head=None) 會依落腳處保留每棵樹的 head。呼叫者仍要指名這次寫哪一棵，
# 而判定行一律記完整 SHA，讓短 SHA 只存在於命令列介面。
heads = report["heads"]
candidates = list(heads)
single_tree_candidate = not candidates and bool(report["head"])
if single_tree_candidate:
    candidates.append({"tree": "（單樹）", "head_sha": report["head"]})
declared = av.declared_landing(index)
issue_root = os.path.dirname(os.path.abspath(index))
if not single_tree_candidate:
    for tree in declared:
        if not any(av.covering_landing(item["tree"], [tree], issue_root)
                   for item in candidates):
            candidates.append({"tree": tree, "head_sha": None})
seen_heads = set()
deduplicated = []
for item in candidates:
    if item["head_sha"] and item["head_sha"] in seen_heads:
        continue
    if item["head_sha"]:
        seen_heads.add(item["head_sha"])
    deduplicated.append(item)
candidates = deduplicated
matched = [item for item in candidates
           if item["head_sha"] and item["head_sha"].startswith(head)]
match_problems = []
if len(matched) != 1:
    match_problems.append(f"--head {head} 對不上唯一一棵判定樹；每棵樹與 head：")
    match_problems.extend(
        f"  {item['tree']}: {item['head_sha'] or '這棵沒有可判的證據'}"
        for item in candidates)
else:
    head = matched[0]["head_sha"]

# 選定要寫入的完整 head 後，才對那個 head 做最終判定。單樹沿用 judge 原有的
# 逐條 head 比對；多樹則補上沒有 measured_in 的舊證據無法歸樹時的同一道保護。
if len(matched) == 1 and not heads:
    report = av.judge(index, os.path.join(issue, ".spine", "evidence"), head=head,
                      ledger_path=os.path.join(issue, ".spine", "measurement-ledger.json"))

ids = [r["id"] for r in report["rows"]]
problems = list(match_problems)
problems.extend(f"--not-yet 指名的 {k} 不是這張單的 assertion"
                for k in not_yet if k not in ids)
passed, pending = [], []
for row in report["rows"]:
    # 未到站只給這一站還沒量過、或量了卻量不到（UNMEASURABLE）的：量過而沒過的，寫成未到站等於把一條紅改叫別的名字
    ev_path = os.path.join(issue, ".spine", "evidence", row["id"] + ".json")
    try:
        evidence = json.load(open(ev_path, encoding="utf-8")) if os.path.exists(ev_path) else {}
        ev_verdict = evidence.get("verdict")
    except (OSError, ValueError):
        evidence, ev_verdict = {}, "FAIL"
    measured = ev_verdict is not None and ev_verdict != "UNMEASURABLE"
    # 判準是 producer：宣告產生者（例如環境步驟腳本）的證據由那個產生者的規則判，逐條判定對它們不比 head，這裡也不比（DP-1023）
    if len(matched) == 1 and heads and ev_verdict == "PASS" and evidence.get("producer") == av.PRODUCER \
            and not evidence.get("measured_in") and evidence.get("head_sha") != head:
        shown_ev, shown_head = av.distinguish(str(evidence.get("head_sha") or ""), head)
        problems.append(f"{row['id']} 沒過：量在 {shown_ev}，要交付 {shown_head}（證據沒有 measured_in）")
        continue
    if row["state"] == av.PASS:
        passed.append(row["id"])
        if row["id"] in not_yet:
            problems.append(f"--not-yet 指名的 {row['id']} 已經過了，不是未到站")
    elif row["id"] in not_yet and not measured:
        pending.append(row["id"])
    elif row["id"] in not_yet:
        problems.append(f"{row['id']} 量過了而沒過，不能寫成未到站：{row['detail']}")
    elif row["state"] == av.FAIL:
        problems.append(f"{row['id']} 沒過：{row['detail']}")
    else:
        problems.append(f"{row['id']} 量不到，也沒有用 --not-yet 寫成未到站：{row['detail']}")
problems += [f"跨 assertion：{b}" for b in report["blockers"]]
# 沒有量測登錄、或證據的命令對不上登錄，一份手寫的證據就能自己指名一條一定會過的命令
# （跟 record-delivery-intent.sh 同一個拒絕）
if not report["layers"].get("registered"):
    problems.append("量測登錄那一層沒做（沒有 .spine/measurement-ledger.json，或證據的命令對不上登錄）：" + av.layers_line(report))
if problems:
    print("寫不成判定，這個 head 上還有沒判完的：", file=sys.stderr)
    for p in problems:
        print("  - " + p, file=sys.stderr)
    sys.exit(1)

at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
items = ";".join(f"{k}@{quote(not_yet[k][0], safe='')}:{quote(not_yet[k][1], safe='')}" for k in pending)
line = f"<!-- VERIFY-AC-VERDICT: head={head} pass={len(passed)}/{len(ids)} not_yet={items or '-'} at={at} -->"
body = [f"\n## verify-ac 判定（{at[:10]}，head {head[:12]}）\n", line, ""]
body.append(f"- 過：{'、'.join(passed) or '沒有'}（{len(passed)}/{len(ids)}）")
for k in pending:
    body.append(f"- 未到站：{k} 要到 {not_yet[k][0]} 才量得到。{not_yet[k][1]}")
body.append(f"- {av.layers_line(report)}")
with open(index, "a", encoding="utf-8") as fh:
    fh.write("\n".join(body) + "\n")
key = re.match(r"[A-Z][A-Z0-9]*-\d+", os.path.basename(issue))
print(f"VERDICT: {key.group(0) if key else os.path.basename(issue)} head {head[:12]} 過 {len(passed)}/{len(ids)}，未到站 {len(pending)} 條")
print(line)
PY
)" || { rc=$?; [[ -n "$PYTHON_OUT" ]] && printf '%s\n' "$PYTHON_OUT"; exit "$rc"; }
printf '%s\n' "$PYTHON_OUT"

# Python 已把縮寫正規化後的完整 SHA 寫進最後一行判定；宣告也要收到同一個完整 SHA。
RECORDED_HEAD="$(sed -nE 's/.*<!-- *VERIFY-AC-VERDICT: head=([0-9a-f]+) [^>]*-->.*/\1/p' <<<"$PYTHON_OUT" | tail -1)"
HEAD_SHA="${RECORDED_HEAD:-$HEAD_SHA}"

while IFS= read -r declared; do
  [[ -n "$declared" ]] || continue
  (cd "$SKILLS_DIR/../.." && bash -c "$declared \"\$1\" \"\$2\"" _ "$ISSUE_DIR" "$HEAD_SHA") \
    || echo "NOTE: 判定之後的宣告（${declared}）沒跑完，判定照樣寫成了。"
done < <(grep -rhoE '<!-- *[A-Za-z0-9_-]*VERDICT-RECORDED: *.+ *-->' "$SKILLS_DIR" --include=SKILL.md 2>/dev/null \
  | sed -E 's/^<!-- *[A-Za-z0-9_-]*VERDICT-RECORDED: *//; s/ *-->$//' | sort -u)
