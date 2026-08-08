#!/usr/bin/env bash
# Purpose: 該壓版的時候版號真的動了。對不起來就非 0 並說出往下走的路；不印一行附註
#          然後讓釋出繼續。
# Inputs:  --pending <n>    壓版**之前**待處理的 changeset 份數
#          --before <版號>  壓版之前
#          --after  <版號>  壓版之後
# Outputs: 一行結論到 stdout；不一致時錯誤說明到 stderr。
#          exit 0 一致 / 1 宣告了卻沒動 / 2 用法錯
#
# 為什麼獨立成一支
# ----------------
# 這個判斷原本內嵌在 spine-release.sh 的 version 步驟裡，而那一步只在 execute 模式跑——
# 要碰 remote、要碰 template checkout。於是它從來沒有被任何測試碰過，而 DP-464 出貨時它
# 真的錯了：沒有 changeset → release-version.sh no-op → 印一行 `no pending changeset` →
# 繼續跑 → template repo 收到新 code 卻標著舊版號。
#
# 一個只能在不可重播的路徑上被驗證的判斷，等於沒有被驗證。拆出來之後它是純函數：
# 三個字串進，一個判定出。
#
# 宣告源是 .changeset/，不是交付紀錄（DP-467 H-P3）
# ------------------------------------------------
# 這支原本讀交付紀錄裡的 version_bump——而那個欄位住在可攜層，逼每一個採用者學一套
# 只有這條釋出尾段在用的詞彙。現在版號的宣告源就是壓版那一步真的會讀的東西：
# release-version.sh 讀 .changeset/*.md，所以「這次該不該壓」問它們就好，中間不經過
# 任何人轉述。少一次轉述就少一個對不上的機會，而 DP-464 的錯就發生在轉述那一段。
#
# 份數要在壓版**之前**數：changeset CLI 會把用掉的那些刪掉，之後再數永遠是 0。
set -euo pipefail

PREFIX="[polaris version-bump]"
PENDING=""
BEFORE=""
AFTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pending) PENDING="${2:-}"; shift 2 ;;
    --before) BEFORE="${2:-}"; shift 2 ;;
    --after) AFTER="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$BEFORE" && -n "$AFTER" ]] || { echo "$PREFIX --before 與 --after 都要給" >&2; exit 2; }
[[ "$PENDING" =~ ^[0-9]+$ ]] || { echo "$PREFIX --pending 要是一個非負整數（拿到 '${PENDING}'）" >&2; exit 2; }

MOVED=false
[[ "$BEFORE" != "$AFTER" ]] && MOVED=true

if [[ "$PENDING" -gt 0 && "$MOVED" == false ]]; then
  cat >&2 <<EOF
$PREFIX POLARIS_SPINE_RELEASE_VERSION_UNBUMPED
壓版之前有 ${PENDING} 份 changeset，但版號停在 ${AFTER} 沒有動。

有東西要壓卻沒壓動，代表 release-version.sh 那一步沒有真的走完——不是 changeset 的
frontmatter 不合法，就是它整支 no-op 了。往下走之前先讓那一步自己說出為什麼：

  bash .claude/skills/framework-release/scripts/release-version.sh --repo <repo>

不提供繞過。帶著新 code 用舊版號出貨，是讓收到它的人拿不出辦法分辨手上是哪一版。
EOF
  exit 1
fi

if [[ "$PENDING" -eq 0 && "$MOVED" == true ]]; then
  # 這一向不擋。一份 changeset 都沒有而版號動了，代表壓版那一步從別的地方拿到了輸入
  # ——那是 DP-334 的多 DP 堆疊問題，release-version.sh 自己有閘在管，這裡重複擋一次
  # 只會讓同一件事有兩個說法。說出來就好。
  echo "$PREFIX 注意：一份 changeset 都沒有，但版號 ${BEFORE} -> ${AFTER} 動了。"
  exit 0
fi

if [[ "$MOVED" == true ]]; then
  echo "$PREFIX 一致：${PENDING} 份 changeset，版號 ${BEFORE} -> ${AFTER}。"
else
  echo "$PREFIX 一致：沒有 changeset 要壓，版號停在 ${AFTER}。"
fi
