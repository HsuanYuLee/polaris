#!/usr/bin/env bash
# Purpose: 把已經判定過的證據排版成一份**交得出去**的東西：一份人看的報告、一份機器讀的
#          清單。判定的價值在於別人能核對，而 report-assertions.sh 只印到終端——沒有檔案
#          可以交給下一層。
#
# Inputs:  --issue <單的目錄>       必要
#          --out <目錄>             預設 {單}/.spine/report
#          --head <sha>             要交付的 head（預設由證據自己說它量的是哪一棵）
#          --delta-allows <path>    可重複。證據量在別的 head 上時，指名放行的路徑前綴——
#                                   它驗證呼叫者的主張（那段差異真的只碰了這幾條），不代它宣告。
#                                   兩支姊妹腳本（report-assertions、record-delivery-intent）
#                                   本來就認得它，判定那一層也早就實作了；缺的只有這裡的傳遞。
#          --publish                產完之後交給宣告了這個命名空間的那個命令
#          --namespace <名>         覆寫命名空間（預設從單的目錄樹的目錄結構推）
# Outputs: <out>/report.md 與 <out>/manifest.json；路徑印在 stdout
# Exit:    0 產得出來（不論 assertion 過了幾條）/ 2 前置條件不到 / 4 產得出來但沒有人說要送去哪
#
# **它唯讀，而且不判定成敗。** 它讀的是已經被 oracle 判定過的東西，只是把它排版：不寫輪次
# 狀態、不寫交付紀錄、不碰證據檔案，也**不成為第二條可以宣稱 PASS 的路徑**。判「這張單能不
# 能出貨」的仍然只有交付紀錄。
#
# **有東西沒過照樣產得出來**，這是刻意的：最想看報告的那一刻，正是有東西沒過的那一刻。所以
# 離場碼說的是「產不產得出來」，不是「過了沒」——把兩者混在同一個數字上，讀的人就得先猜它
# 在講哪一件事。
#
# **發佈不是關卡。** `--publish` 送不出去的時候它吵、它留下訊息，但一條 assertion 的判定不會因此改變
# ——判定由 oracle 決定，發佈是那個判定的投影。
#
# 排版那一段住在 `lib/evidence_report.py`，逐條判定住在 `lib/assertion_verdicts.py`——後者
# 與交付那條路共用同一份，這裡不重做一次判定。

set -euo pipefail

PREFIX="[polaris evidence-report]"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUE_DIR=""
OUT_DIR=""
HEAD_SHA=""
NAMESPACE=""
PUBLISH=0
DELTA_ALLOWS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)     ISSUE_DIR="${2:-}"; shift 2 ;;
    --out)       OUT_DIR="${2:-}"; shift 2 ;;
    --head)      HEAD_SHA="${2:-}"; shift 2 ;;
    --delta-allows) DELTA_ALLOWS+=("${2:-}"); shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --publish)   PUBLISH=1; shift ;;
    -h|--help)   sed -n '6,12p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ISSUE_DIR" ]]; then
  echo "$PREFIX 要指名一張單：--issue <目錄>" >&2
  exit 2
fi
INDEX="$ISSUE_DIR/index.md"
if [[ ! -f "$INDEX" ]]; then
  echo "$PREFIX 量不到：$INDEX 不在。" >&2
  exit 2
fi
[[ -n "$OUT_DIR" ]] || OUT_DIR="$ISSUE_DIR/.spine/report"

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

if [[ ${#DELTA_ALLOWS[@]} -gt 0 && -z "$HEAD_SHA" ]]; then
  echo "$PREFIX --delta-allows 只有在同時指名 --head 的時候才有意義：它描述的是「證據量到的 head 與要交付的那個 head 之間差了什麼」，沒有後者就沒有那段差異。" >&2
  exit 2
fi

paths="$(python3 - "$ROOT_DIR" "$INDEX" "$ISSUE_DIR" "$HEAD_SHA" "$OUT_DIR" ${DELTA_ALLOWS+"${DELTA_ALLOWS[@]}"} <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/lib")
import assertion_verdicts as av
import evidence_report as er

root, index, issue, head, out_dir = sys.argv[1:6]
delta_allows = sys.argv[6:]

# 三層裡的前兩層，跟交付那條路讀同一份判定程式。不重跑（第三層）——重跑是交付那條路的事，
# 而這一支要在「有東西沒過」的時候也產得出來，跑一趟不會綠的量測只是讓它變慢。
report = av.judge(
    index, issue + "/.spine/evidence",
    head=head or None,
    delta_allows=delta_allows,
    ledger_path=issue + "/.spine/measurement-ledger.json",
)
manifest = er.build(report, issue, ledger_path=issue + "/.spine/measurement-ledger.json")
report_path, manifest_path = er.write(manifest, out_dir)
print(report_path)
print(manifest_path)
print(manifest["namespace"])
PY
)"

REPORT_PATH="$(printf '%s\n' "$paths" | sed -n '1p')"
MANIFEST_PATH="$(printf '%s\n' "$paths" | sed -n '2p')"
DERIVED_NAMESPACE="$(printf '%s\n' "$paths" | sed -n '3p')"
[[ -n "$NAMESPACE" ]] || NAMESPACE="$DERIVED_NAMESPACE"

echo "$REPORT_PATH"
echo "$MANIFEST_PATH"

[[ "$PUBLISH" == "1" ]] || exit 0

if [[ -z "$NAMESPACE" ]]; then
  echo "$PREFIX 推不出這張單屬於哪個命名空間，所以問不到要送去哪。報告留在本機：$REPORT_PATH" >&2
  echo "$PREFIX 修法：用 --namespace 指名。" >&2
  exit 4
fi

# 發佈失敗不改變任何一條判定——上面那兩個檔案已經寫好了，這裡只是把它們交出去。
# 離場碼要在自己那一行接住：寫成 `if 命令; then …; fi` 再讀 `$?`，讀到的是 `if` 的結果，
# 而那永遠是 0——訊息會說「離場碼 0」然後宣稱失敗，讀的人兩句話都不能信。
set +e
"$ROOT_DIR/scripts/resolve-evidence-publish.sh" publish \
  --namespace "$NAMESPACE" --report "$REPORT_PATH" --manifest "$MANIFEST_PATH"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || exit 0
echo "$PREFIX 沒送出去（命名空間「${NAMESPACE}」，離場碼 ${rc}）。判定不受影響，報告留在本機：$REPORT_PATH" >&2
exit 4
