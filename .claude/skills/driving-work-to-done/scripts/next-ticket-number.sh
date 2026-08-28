#!/usr/bin/env bash
# next-ticket-number.sh — 在這個命名空間裡，本地開的下一張單該叫幾號。
#
# 答案不需要任何新的宣告：**宣告了狀態解析器的命名空間，它的單來自外部系統**，號也一樣
# 來自那裡——本地鑄造一個號出來，下一個人會拿它去那個系統搜，然後搜到別的東西或什麼都
# 沒有。沒宣告的命名空間，本地就是權威，取現有最大號加一。
#
# 多加一行「怎麼取號」的宣告等於把同一件事說兩次，而兩份會漂。
#
# Usage:
#   next-ticket-number.sh --issues <單的根目錄> --namespace <命名空間> [--prefix <前綴>]
# Exit:
#   0 印出下一個號（例如 `DP-488`）
#   3 這個命名空間的號來自外部系統，本地不鑄造（訊息說出該去哪裡開）
#   2 參數不對，或這個命名空間還沒有任何帶號的單而且沒給 --prefix

set -euo pipefail

PREFIX_TAG="[next-ticket-number]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISSUES=""
NAMESPACE=""
WANT_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues) ISSUES="${2:-}"; shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --prefix) WANT_PREFIX="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "$PREFIX_TAG 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$ISSUES" && -n "$NAMESPACE" ]] || {
  echo "$PREFIX_TAG 要 --issues <單的根目錄> --namespace <命名空間>。" >&2
  exit 2
}
[[ -d "$ISSUES" ]] || { echo "$PREFIX_TAG 單的根目錄不存在：$ISSUES" >&2; exit 2; }

python3 - "$SCRIPT_DIR" "$ISSUES" "$NAMESPACE" "$WANT_PREFIX" <<'PY'
import collections
import importlib.util
import os
import re
import sys

script_dir, issues, namespace, want_prefix = sys.argv[1:5]

spec = importlib.util.spec_from_file_location(
    "place", os.path.join(script_dir, "lib", "place_issues_by_state.py"))
place = importlib.util.module_from_spec(spec)
spec.loader.exec_module(place)

# 這一句就是整支的判斷：宣告了解析器 ＝ 它的單住在別人家。
resolvers = place.declared_resolvers()
if namespace in resolvers:
    print(f"POLARIS_TICKET_NUMBER_IS_EXTERNAL", file=sys.stderr)
    print(f"`{namespace}` 的單來自外部系統（它宣告了狀態解析器），號不由這裡鑄造。",
          file=sys.stderr)
    print("  這件事如果是在改框架本身（skill、腳本、規則），那它就是框架的工作——"
          "開在本地就是權威的那個命名空間裡。", file=sys.stderr)
    print("  如果它是產品工作，去那個系統開一張，再用它給的號。", file=sys.stderr)
    raise SystemExit(3)

TICKET = re.compile(r"^([A-Za-z][A-Za-z0-9]{0,7})-(\d+)")
seen = collections.defaultdict(list)
for found_namespace, ticket_dir in place.tickets(issues):
    if found_namespace != namespace:
        continue
    match = TICKET.match(os.path.basename(ticket_dir))
    if match:
        seen[match.group(1)].append(int(match.group(2)))

if want_prefix:
    prefix = want_prefix
elif len(seen) == 1:
    prefix = next(iter(seen))
elif seen:
    # 同一個命名空間裡混著幾種前綴時，用最多的那一個——但要說出來，不要安靜地挑。
    prefix = max(seen, key=lambda key: len(seen[key]))
    others = ", ".join(f"{k}×{len(v)}" for k, v in sorted(seen.items()) if k != prefix)
    print(f"{namespace} 底下有不只一種前綴，取張數最多的 {prefix}（另有 {others}）；"
          f"要別的用 --prefix。", file=sys.stderr)
else:
    print("POLARIS_TICKET_NUMBER_NO_PREFIX", file=sys.stderr)
    print(f"`{namespace}` 底下還沒有任何帶號的單，學不出前綴。第一張要用 --prefix 說一次。",
          file=sys.stderr)
    raise SystemExit(2)

print(f"{prefix}-{max(seen.get(prefix, [0])) + 1}")
PY
