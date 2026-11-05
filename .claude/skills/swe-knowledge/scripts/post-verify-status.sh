#!/usr/bin/env bash
# post-verify-status.sh — 把「這個 head 判過了沒」貼成 GitHub 上那顆 commit 的 status（DP-993 A-P5）。
#
# 出貨點那道 PreToolUse hook 只在 Claude Code 裡生效，換一個 agent 就沒有人在擋。commit status
# 跟宿主無關：誰打開那顆 PR 都看得到 `polaris/verify-ac` 是 pending、success 還是 failure。
# 它只貼狀態，不改任何 repo 的 branch protection 或 ruleset，也不把這個 context 設成 required check
# ——框架對 repo 的支援一律外掛。
#
# 三個時機，各由一個呼叫端貼：
#   pending  push-verifier 對新 head 派出驗證者的時候
#   failure  驗證者判紅、或跑不到（UNMEASURABLE／PARTIAL）的時候
#   success  verify-ac 對這個 head 寫成判定那一行、或寫成交付紀錄的時候（經 SKILL.md 的
#            SWE-VERDICT-RECORDED 與 SWE-DELIVERY-RECORDED 兩行宣告叫進來）
#
# Usage: post-verify-status.sh --repo <checkout> --sha <commit> --state pending|success|failure --description <text> [--remote <name>]
#        post-verify-status.sh delivered <單的目錄>
#        post-verify-status.sh verdict <單的目錄> <head>
#        後兩種讀那張單的 delivery.json（或 index.md 裡對那個 head 的判定那一行）與落腳處，對每一個
#        找得到那顆 commit 的落腳處貼 success。
# Output: 貼了的一行 `POSTED: <owner/name>@<sha12> <state>`；貼不成的一行 `NOT POSTED: <原因>`。
# Exit:  0 貼了，或貼不成但已經說出原因（貼狀態不是關卡，不讓交付或 push 因它失敗）/ 2 參數不對
set -uo pipefail

CONTEXT="polaris/verify-ac"
say() { printf '%s\n' "$*"; }

post() {
  local repo="$1" sha="$2" state="$3" desc="$4" remote="${5:-origin}" url slug
  url="$(git -C "$repo" remote get-url "$remote" 2>/dev/null || true)"
  slug="$(printf '%s' "$url" | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')"
  [[ -n "$slug" ]] || { say "NOT POSTED: $repo 的 ${remote}（${url:-沒有}）不是 GitHub 的網址"; return 0; }
  command -v gh >/dev/null || { say "NOT POSTED: 沒有 gh，問不到 GitHub"; return 0; }
  # GitHub 的 status 只收完整 sha，而手給的與判定行裡的 head 常是短的（DP-996）
  local full
  # 本機沒有的那顆，已經是完整 sha 就照原樣貼
  if full="$(git -C "$repo" rev-parse --verify --quiet "${sha}^{commit}" 2>/dev/null)"; then sha="$full"
  elif [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then say "NOT POSTED: ${sha} 在 $repo 解不出一顆 commit，也不是完整 sha"; return 0; fi
  local out
  if out="$(gh api -X POST "repos/$slug/statuses/$sha" -f state="$state" -f context="$CONTEXT" \
      -f description="${desc:0:140}" 2>&1)"; then
    say "POSTED: $slug@${sha:0:12} $state"
  else
    say "NOT POSTED: $slug@${sha:0:12} ${state}（gh：$(printf '%s' "$out" | tail -1 | cut -c1-200)）"
  fi
}

# landing_post <單> <description> <sha>...：對每一個找得到那顆 commit 的落腳處貼 success。
landing_post() {
  local ticket="$1" desc="$2" spine landings repo sha posted=0; shift 2
  spine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/driving-work-to-done/scripts/spine-loop-state.sh"
  landings="$(bash "$spine" landing --state "$ticket/.spine/loop-state.json" 2>/dev/null || true)"
  [[ -n "$landings" ]] || { say "NOT POSTED: $(basename "$ticket") 問不到落腳處"; return 0; }
  while IFS= read -r repo; do
    [[ -d "$repo" ]] || continue
    for sha in "$@"; do
      git -C "$repo" cat-file -e "${sha}^{commit}" 2>/dev/null || continue
      post "$repo" "$sha" success "$desc"; posted=1
    done
  done <<<"$landings"
  [[ $posted == 1 ]] || say "NOT POSTED: $(basename "$ticket") 的落腳處裡找不到 $*"
  return 0
}

cmd_verdict() {
  local ticket="${1:-}" head="${2:-}" line key
  [[ -f "$ticket/index.md" && -n "$head" ]] || { echo "verdict 後面要接帶 index.md 的單與 head" >&2; exit 2; }
  line="$(grep -oE "<!-- *VERIFY-AC-VERDICT: head=${head}[0-9a-f]* [^>]*-->" "$ticket/index.md" | tail -1 || true)"
  [[ -n "$line" ]] || { say "NOT POSTED: $(basename "$ticket") 沒有對 ${head:0:12} 的判定那一行"; return 0; }
  key="$(basename "$ticket" | grep -oE '^[A-Z][A-Z0-9]*-[0-9]+' || basename "$ticket")"
  local pass at items n
  pass="$(sed -nE 's/.* pass=([0-9]+\/[0-9]+).*/\1/p' <<<"$line")"
  at="$(sed -nE 's/.* at=([^ ]+).*/\1/p' <<<"$line")"
  items="$(sed -nE 's/.* not_yet=([^ ]+).*/\1/p' <<<"$line")"
  n=0; [[ "$items" == "-" || -z "$items" ]] || n="$(tr ';' '\n' <<<"$items" | grep -c .)"
  landing_post "$ticket" "${key} verify-ac 過 ${pass}，未到站 ${n} 條（${at}）" "$(sed -nE 's/.*head=([0-9a-f]+).*/\1/p' <<<"$line")"
}

cmd_delivered() {
  local ticket="${1:-}" name at heads key
  [[ -f "$ticket/.spine/delivery.json" ]] || { echo "delivered 後面要接帶 .spine/delivery.json 的單（拿到 '$ticket'）" >&2; exit 2; }
  read -r name at heads < <(python3 - "$ticket/.spine/delivery.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
hs = [d.get("head_sha")] + [r.get("head_sha") for r in d.get("heads") or [] if isinstance(r, dict)]
print(d.get("issue") or "?", d.get("judged_at") or "?", ",".join(sorted({h for h in hs if h})))
PY
)
  key="$(printf '%s' "$name" | grep -oE '^[A-Z][A-Z0-9]*-[0-9]+' || printf '%s' "$name")"
  landing_post "$ticket" "${key} verify-ac PASS，未到站 0 條，交付紀錄寫成（${at}）" ${heads//,/ }
}

cmd_post() {
  local REPO="" SHA="" STATE="" DESC="" REMOTE="origin"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) REPO="${2:-}"; shift 2 ;;
      --sha) SHA="${2:-}"; shift 2 ;;
      --state) STATE="${2:-}"; shift 2 ;;
      --description) DESC="${2:-}"; shift 2 ;;
      --remote) REMOTE="${2:-}"; shift 2 ;;
      -h|--help) sed -n '2,19p' "$0" >&2; exit 2 ;;
      *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  case "$STATE" in pending|success|failure) ;; *) echo "--state 要是 pending、success 或 failure（拿到 '$STATE'）" >&2; exit 2 ;; esac
  [[ -n "$REPO" && -n "$SHA" ]] || { echo "--repo 與 --sha 是必填" >&2; exit 2; }
  post "$REPO" "$SHA" "$STATE" "$DESC" "$REMOTE"
}

case "${1:-}" in
  delivered) shift; cmd_delivered "$@" ;;
  verdict) shift; cmd_verdict "$@" ;;
  *) cmd_post "$@" ;;
esac
