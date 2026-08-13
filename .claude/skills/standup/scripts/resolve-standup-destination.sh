#!/usr/bin/env bash
# resolve-standup-destination.sh — 報告要送到哪，問這一支，不要問散文。
#
# 這支 skill 不認得任何一個目的地。哪一家公司把 standup 送到哪裡、那裡的表單長什麼形狀、
# 送出是人做的還是程式做的，全部住在那家公司自己的 `workspace-config.yaml`——跟 JIRA
# instance、Slack channel 同一類，都是公司資料。
#
# 為什麼要是一支腳本而不是一句散文：宣告缺席的時候，「說出來然後停在本地」與「安靜地
# 當成沒有目的地」在輸出上長得一模一樣，而只有前者是對的。一句散文說不出離場碼。
#
# 這一支存在的由來是量出來的：整個 publish 半邊寫死指向一個 2026-06-25 起就不再被寫入
# 的地方，而沒有任何東西會紅。DP-519 E-P1／E-P2／E-P3 簽下這件事。
#
# 宣告長這樣（公司自己的 workspace-config.yaml，頂層）：
#
#   standup:
#     destination:
#       name: "…"           # 選填，給人看的名字
#       url: "…"            # 必填，送到哪
#       shape: "…"          # 必填，那裡的表單形狀（見 references/standup-template.md）
#       publish: manual|api # 必填，送出是誰做的
#
# Usage:
#   resolve-standup-destination.sh --config <path>
#   resolve-standup-destination.sh --company <name> [--workspace <root>]
#
# Exit:
#   0 — 解析出來了            STANDUP-DESTINATION …
#   3 — 宣告在，但缺必要欄位   STANDUP-DESTINATION-INCOMPLETE …
#   4 — 沒有宣告              STANDUP-DESTINATION-UNDECLARED … reason=…
#   2 — 量不到（參數不對、python3 不在）
#
# 3 與 4 分開，是因為半條宣告比沒有宣告糟：它看起來像有人設定過。4 底下的兩種
# （設定檔整個不在／設定檔在但沒有 standup 區塊）共用離場碼，但 `reason=` 不一樣——
# 一句共用的「找不到」會讓兩種完全不同的修法變成同一個問題。

set -uo pipefail

PREFIX="[polaris resolve-standup-destination]"
CONFIG=""
COMPANY=""
WORKSPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)    CONFIG="${2:-}"; shift 2 ;;
    --company)   COMPANY="${2:-}"; shift 2 ;;
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

# 工作區根往上找，不從腳本位置往上數固定層數——目錄深度是會變的東西，數字不是。
find_workspace_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.claude/skills" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

if [[ -z "$CONFIG" ]]; then
  if [[ -z "$COMPANY" ]]; then
    echo "$PREFIX 量不到：要嘛給 --config <path>，要嘛給 --company <name>。" >&2
    exit 2
  fi
  if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE="$(find_workspace_root)" || {
      echo "$PREFIX 量不到：從 $(dirname "${BASH_SOURCE[0]}") 往上找不到帶 .claude/skills 的" >&2
      echo "$PREFIX 工作區根。這支 skill 被單獨帶到別的地方時是正常的——用 --config 指路。" >&2
      exit 2
    }
  fi
  CONFIG="$WORKSPACE/$COMPANY/workspace-config.yaml"
fi

LABEL="${COMPANY:-$CONFIG}"

if [[ ! -f "$CONFIG" ]]; then
  echo "STANDUP-DESTINATION-UNDECLARED company=$LABEL reason=config-not-found path=$CONFIG"
  echo "$PREFIX 這不是壞掉，是一個要被說出來的狀態：報告照常產出並寫在本地，不猜目的地。"
  exit 4
fi

python3 - "$CONFIG" "$LABEL" "$PREFIX" <<'PY'
import sys

config_path, label, prefix = sys.argv[1:4]

REQUIRED = ("url", "shape", "publish")

with open(config_path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()


def strip_value(raw):
    """去掉行尾註解與引號。值裡本來就帶 # 的情況這裡看不懂——那種要拒絕，不要猜。"""
    value = raw.strip()
    if value and value[0] in "\"'":
        quote = value[0]
        end = value.find(quote, 1)
        if end == -1:
            return None
        return value[1:end]
    value = value.split("#", 1)[0].strip()
    return value


# 剖析器故意很窄：這支 skill 要能被單獨帶到沒有 pyyaml 的地方。窄的代價是看不懂的縮排要
# 拒絕，不是略過——略過的話一個打錯的縮排會靜靜地變成「沒有宣告」。
fields = {}
saw_standup = False
saw_destination = False
in_standup = False
in_destination = False
for line in lines:
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    indent = len(line) - len(line.lstrip())
    if indent == 0:
        in_standup = line.rstrip().startswith("standup:")
        saw_standup = saw_standup or in_standup
        in_destination = False
        continue
    if not in_standup:
        continue
    if indent == 2:
        in_destination = line.strip().startswith("destination:")
        saw_destination = saw_destination or in_destination
        continue
    if in_destination and indent == 4 and ":" in line:
        key, _, raw = line.strip().partition(":")
        value = strip_value(raw)
        if value is None:
            print(f"{prefix} 量不到：{config_path} 的 standup.destination.{key.strip()} 這一行看不懂。",
                  file=sys.stderr)
            sys.exit(2)
        fields[key.strip()] = value

if not saw_standup or not saw_destination:
    missing_block = "standup" if not saw_standup else "standup.destination"
    print(f"STANDUP-DESTINATION-UNDECLARED company={label} reason=no-{missing_block.replace('.', '-')}-block "
          f"path={config_path}")
    print(f"{prefix} 這不是壞掉，是一個要被說出來的狀態：報告照常產出並寫在本地，不猜目的地。")
    sys.exit(4)

missing = [k for k in REQUIRED if not fields.get(k)]
if missing:
    print(f"STANDUP-DESTINATION-INCOMPLETE company={label} missing={','.join(missing)} "
          f"path={config_path}", file=sys.stderr)
    print(f"{prefix} 半條宣告比沒有宣告糟：它看起來像有人設定過。補齊那幾格再跑一次。",
          file=sys.stderr)
    sys.exit(3)

name = fields.get("name") or "(未命名)"
print(f"STANDUP-DESTINATION company={label} name={name} url={fields['url']} "
      f"shape={fields['shape']} publish={fields['publish']}")
sys.exit(0)
PY
