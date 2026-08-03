#!/usr/bin/env bash
# record-knowledge-pack.sh — 這張單載了哪個領域的「怎麼算 done」，記在狀態裡。
#
# 為什麼需要這支：散文寫「判斷是 SWE 工作就去載 swe-knowledge」，而散文 routing 指向一個
# 不存在或沒被讀到的東西時，**完全是安靜的**。`sync-company-skill-links.sh` 的檔頭記著這個
# repo 自己的案例：六支公司 skill 在存在期間一次都沒被載入過，沒有人發現，因為 routing 散文
# 照樣把工作分派出去，只是分派到一份從未被讀取的程序。
#
# 所以「載了什麼」不能只存在於對話裡。它要落在單的狀態上，而且 pack 的名字要當場被解析成
# 一個真的存在的 SKILL.md——解析不到就 exit 非 0，不寫任何東西。
#
# 「沒有適用的領域」是一個被記下來的選擇，不是欄位空著。所以 --pack none 也要寫，而且要
# 帶 --why：一個沒有理由的 none 跟忘記記是同一個樣子。
#
# Subcommands:
#   record --state <path> --pack <name>|none [--why <text>]
#   check  --state <path>          記過就 0，沒記過就 2
#   show   --state <path>
#
# Exit codes:
#   0  成功
#   2  拒絕（pack 解析不到、none 沒帶理由、狀態不存在、參數錯）

set -uo pipefail

PREFIX="[record-knowledge-pack]"

usage() {
  cat >&2 <<'EOF'
Usage:
  record-knowledge-pack.sh record --state <path> --pack <name>|none [--why <text>]
  record-knowledge-pack.sh check  --state <path>
  record-knowledge-pack.sh show   --state <path>
EOF
}

die() {
  local marker="$1"
  shift
  echo "$marker" >&2
  echo "$PREFIX $*" >&2
  exit 2
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

# Description: 解析一個 pack 名字，印出它的 SKILL.md 絕對路徑。
# Args:   $1 = pack 名字
# Output: 路徑，解析不到就沒有輸出（回 1）
#
# 從這支腳本自己的位置往上找 skills 根，不從 cwd、也不從 repo 根找：這一組東西要能被整包
# 複製到另一個 repo（或 claude.ai / Cowork）還成立，那些地方沒有這個 repo 的目錄結構，但
# 「pack 是我的鄰居」在哪裡都成立。
resolve_pack() {
  local name="$1" skills_dir candidate
  skills_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || return 1
  candidate="$skills_dir/$name/SKILL.md"
  [[ -f "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

STATE=""
PACK=""
WHY=""

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state) STATE="${2:-}"; shift 2 ;;
      --pack)  PACK="${2:-}"; shift 2 ;;
      --why)   WHY="${2:-}"; shift 2 ;;
      *) usage; exit 2 ;;
    esac
  done
  [[ -n "$STATE" ]] || { usage; exit 2; }
}

cmd_record() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "沒有 loop state：${STATE}。先跑 spine-loop-state.sh init。"
  [[ -n "$PACK" ]] || { usage; exit 2; }
  require_python3

  local resolved=""
  if [[ "$PACK" == "none" ]]; then
    # 一個沒有理由的 none，跟根本忘了記，在檔案裡長得一樣。要它說出為什麼。
    [[ -n "$WHY" ]] || die "POLARIS_KNOWLEDGE_PACK_NONE_UNJUSTIFIED" \
      "--pack none 要帶 --why。「沒有適用的領域」是一個被記下來的選擇，不是欄位空著。"
  else
    resolved="$(resolve_pack "$PACK")" || die "POLARIS_KNOWLEDGE_PACK_UNRESOLVED" \
      "解析不到 pack「${PACK}」——找不到它的 SKILL.md。指名一個不存在的 pack 是安靜的失敗：
$PREFIX routing 照樣把工作分派出去，只是分派到一份從未被讀取的程序。
$PREFIX 要嘛用一個真的存在的 pack 名字，要嘛 --pack none --why '<為什麼這件工作沒有領域完成條件>'。"
  fi

  python3 - "$STATE" "$PACK" "$resolved" "$WHY" <<'PY'
import json
import sys

state_path, pack, resolved, why = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = json.load(open(state_path, encoding="utf-8"))

# 一張單只有一筆。重新判定領域是覆蓋，不是追加——兩筆並存等於兩個「怎麼算 done」。
entry = {"pack": pack}
if resolved:
    entry["skill"] = resolved
if why:
    entry["why"] = why
data["knowledge_pack"] = entry

with open(state_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print(f"KNOWLEDGE-PACK {pack}" + (f" -> {resolved}" if resolved else ""))
PY
}

cmd_check() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "沒有 loop state：$STATE"
  require_python3
  python3 - "$STATE" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
entry = data.get("knowledge_pack")
if not entry or not entry.get("pack"):
    print("KNOWLEDGE-PACK-UNRECORDED 這張單沒有記過領域知識。", file=sys.stderr)
    print("流程不得在「需要什麼知識」還沒被回答的情況下照常往下走——"
          "記一個 pack，或記 none 並說出理由。", file=sys.stderr)
    sys.exit(2)
print(f"KNOWLEDGE-PACK-RECORDED {entry['pack']}")
PY
}

cmd_show() {
  parse_args "$@"
  [[ -f "$STATE" ]] || die "POLARIS_SPINE_LOOP_STATE_MISSING" "沒有 loop state：$STATE"
  require_python3
  python3 - "$STATE" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
print(json.dumps(data.get("knowledge_pack", {}), ensure_ascii=False, indent=2))
PY
}

[[ $# -gt 0 ]] || { usage; exit 2; }
SUB="$1"
shift
case "$SUB" in
  record) cmd_record "$@" ;;
  check)  cmd_check "$@" ;;
  show)   cmd_show "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
