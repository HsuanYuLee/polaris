#!/usr/bin/env bash
# Purpose: 收斂完的 issue 換到自己命名空間的 archive/ 底下，還沒收斂的留在命名空間根。
#          位置是輪次狀態的投影，不是第二個權威——所以這支同時提供 --check，讓「位置說的」
#          與「狀態說的」對得起來。
# Inputs:  --issues <path>（issues 根目錄，預設從自己的位置往上找 workspace 的 issues/）
#          --check（只報不動，有落差就 exit 1）
# Outputs: 每個要動的印一行；--check 模式下有落差就 exit 1。不參與判定的也印出數量。
#
# 版面是 issues/{命名空間}/{單號} 與 issues/{命名空間}/archive/{單號}。命名空間叫什麼**不影響
# 任何判定**——這支只是逐個走過去，不從名字推導行為。用名字判斷身分是 DP-463 的 D-N2 禁止的
# 形狀，換成單也一樣。
#
# 唯一的權威是 `{issue}/.spine/loop-state.json` 的 `status`：`converged` 才叫完成。位置只是
# 把那件事投影成「列出還沒完成的工作」時看得見的形狀。兩者可以不一致的唯一情況是有人手動搬過，
# --check 就是為了讓那件事被看見而不是被猜。
#
# 不用交付紀錄當權威——實測 DP-440 有 delivery.json（某一輪確實出過貨）但 status 仍是 open、
# 三輪未收斂。「出過貨」與「這張單完成了」是兩個問題，拿前者回答後者會把還在做的單掃進 archive。
#
# 沒有輪次狀態的目錄（舊層搬進來的知識、還沒開輪次的種子）不參與位置判定——它們的位置不是
# 任何狀態的投影，所以沒有可以對不上的東西。但**數量一定要印出來**：一個不被判定的第三態
# 如果安靜，下一次就會有人以為那幾百個目錄都被檢查過了。

set -euo pipefail

PREFIX="[polaris archive-delivered-issues]"
ISSUES_ROOT=""
MODE="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues) ISSUES_ROOT="${2:-}"; shift 2 ;;
    --check) MODE="check"; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$ISSUES_ROOT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ISSUES_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)/issues"
fi

if [[ ! -d "$ISSUES_ROOT" ]]; then
  echo "$PREFIX issues 目錄不存在：$ISSUES_ROOT" >&2
  exit 2
fi

# 命名空間叫什麼都不影響判定——只有這一個名字例外，因為它是這支腳本自己的目的地。
# 傳進一個「底下直接有 archive/ 的」根，等於把某一個命名空間當成整棵樹：archive 會被當成
# 一個命名空間，它底下每一張已歸檔的單都會再被搬進 archive/archive/。這不是假設，
# 2026-08-03 就這樣搬了 103 個檔案。錯的根要在動任何東西之前擋下來，不是靠呼叫端記得傳對。
if [[ -d "$ISSUES_ROOT/archive" ]]; then
  echo "$PREFIX 這不是 issues 根：$ISSUES_ROOT 底下直接有 archive/" >&2
  echo "$PREFIX 這個形狀代表傳進來的是某一個命名空間，不是整棵樹。再往上一層。" >&2
  exit 2
fi

# 有輪次狀態的才進得了判定；那份檔案就是「這張單完成了沒有」的答案所在。
# 回 none 的分兩種、都不參與：舊層搬進來的知識，以及還沒開輪次的種子。
state_of() {
  local state="$1/.spine/loop-state.json"
  [[ -f "$state" ]] || { echo "none"; return; }
  python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status') or 'unknown')" "$state"
}

mismatches=0
unmanaged_active=0
unmanaged_archive=0
moves=()

for ns_dir in "$ISSUES_ROOT"/*/; do
  [[ -d "$ns_dir" ]] || continue
  ns="$(basename "$ns_dir")"

  for dir in "$ns_dir"*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ "$name" == "archive" ]] && continue
    case "$(state_of "$dir")" in
      converged) moves+=("$ns/$name|$ns/archive/$name"); mismatches=$((mismatches + 1)) ;;
      none)      unmanaged_active=$((unmanaged_active + 1)) ;;
    esac
  done

  [[ -d "$ns_dir/archive" ]] || continue
  for dir in "$ns_dir"archive/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    case "$(state_of "$dir")" in
      converged) ;;
      none)      unmanaged_archive=$((unmanaged_archive + 1)) ;;
      *)         moves+=("$ns/archive/$name|$ns/$name"); mismatches=$((mismatches + 1)) ;;
    esac
  done
done

disclosure="不參與判定：活躍 $unmanaged_active 個、archive $unmanaged_archive 個（沒有輪次狀態）"

if [[ "$mismatches" -eq 0 ]]; then
  echo "$PREFIX ✅ ARCHIVE-IN-SYNC 位置與輪次狀態一致。$disclosure"
  exit 0
fi

if [[ "$MODE" == "check" ]]; then
  echo "$PREFIX 位置與輪次狀態對不上：" >&2
  for entry in "${moves[@]}"; do
    from="${entry%%|*}"; to="${entry##*|}"
    if [[ "$to" == */archive/* ]]; then
      echo "  $from 已經收斂，卻還在活躍區" >&2
    else
      echo "  $from 還沒收斂，卻在 archive 裡" >&2
    fi
  done
  echo "$PREFIX ❌ $mismatches 個位置不一致。$disclosure" >&2
  exit 1
fi

for entry in "${moves[@]}"; do
  from_rel="${entry%%|*}"; to_rel="${entry##*|}"
  mkdir -p "$(dirname "$ISSUES_ROOT/$to_rel")"
  # git mv 保住歷史；issues 不在 git 裡就退回一般搬移，但那種情況下凍結本來就不成立。
  if git -C "$ISSUES_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ISSUES_ROOT" mv "$from_rel" "$to_rel"
  else
    mv "$ISSUES_ROOT/$from_rel" "$ISSUES_ROOT/$to_rel"
  fi
  echo "$PREFIX MOVED $from_rel → $to_rel"
done

echo "$PREFIX ✅ ARCHIVE-SYNCED 搬了 $mismatches 個。$disclosure"
