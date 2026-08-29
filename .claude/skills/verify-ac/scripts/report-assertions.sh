#!/usr/bin/env bash
# report-assertions.sh — 這張單的 assertion，過哪些、沒過哪些、哪些量不到。
#
# **唯讀。** 它不寫任何檔案，也不產生任何下游可以拿去當證據的東西——判「這張單能不能
# 出貨」的仍然只有交付紀錄（`record-delivery-intent.sh` 寫的那一份）。有兩個地方能宣稱
# PASS 的話，它們遲早會給出不同的答案。
#
# 為什麼需要它：逐條判定的邏輯本來只長在交付那條路上，而交付**任一條不成立就整支拒絕、
# 什麼都不印**。想知道「現在八條裡過了幾條」只能把 oracle 一條一條重跑自己拼——DP-471
# 那一輪就是這樣做的。判定的那一段現在住在 `lib/assertion_verdicts.py`，兩邊共用。
#
# Usage: report-assertions.sh --issue <單的目錄>
#          [--head <sha>]            要交付的 head（預設由證據自己說它量的是哪一棵）
#          [--delta-allows <path>]…  證據量在別的 head 上時，放行的路徑前綴
#          [--rerun]                 多做一層：拿登錄的命令現在再跑一次
# Exit:  0 全部過 / 1 有沒過的 / 2 有量不到的、或有跨 assertion 的問題
#
# NO-CALLER: --delta-allows — 這棵樹上沒有人給過值。留著是因為交付那條路認得它：證據量在
# 壓版之前的 head 上時，兩邊要對同一份證據給出同一個答案，而少了這個旗標，報告會把交付
# 記得下來的那張單說成紅的。一個跟權威路徑答案不同的報告，比沒有報告糟。

set -euo pipefail

PREFIX="[polaris report-assertions]"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUE_DIR=""
HEAD_SHA=""
RERUN=0
DELTA_ALLOWS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)        ISSUE_DIR="${2:-}"; shift 2 ;;
    --head)         HEAD_SHA="${2:-}"; shift 2 ;;
    --delta-allows) DELTA_ALLOWS+=("${2:-}"); shift 2 ;;
    --rerun)        RERUN=1; shift ;;
    -h|--help)      sed -n '16,21p' "$0"; exit 0 ;;
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

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

python3 - "$ROOT_DIR" "$INDEX" "$ISSUE_DIR" "$HEAD_SHA" "$RERUN" \
  "${DELTA_ALLOWS[@]+${DELTA_ALLOWS[@]}}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/lib")
import assertion_verdicts as av

root, index, issue, head, rerun = sys.argv[1:6]
delta_allows = sys.argv[6:]

report = av.judge(
    index, issue + "/.spine/evidence",
    head=head or None,
    delta_allows=delta_allows,
    ledger_path=issue + "/.spine/measurement-ledger.json",
    rerun=rerun == "1",
    oracle=root + "/scripts/run-hardened-oracle.sh",
)
print(av.layers_line(report))
sys.exit(av.render(report))
PY
