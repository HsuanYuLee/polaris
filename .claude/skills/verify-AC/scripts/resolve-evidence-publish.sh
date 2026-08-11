#!/usr/bin/env bash
# Purpose: 回答一件這支 skill 自己不知道的事——「這張單的證據報告要送去哪」。目的地由別的
#          skill 在自己的 SKILL.md 宣告，核心只負責找到那一行、跑它、把答案原樣交出去。
#
# Inputs:  namespaces                                   印出所有被宣告的命名空間，一行一個
#          publish --namespace N --report R --manifest M
#                                                       把報告與清單交給認領 N 的那個命令
#          [--skills <dir>]                             skill 樹的位置（預設從自己往上兩層）
# Outputs: namespaces → 每行一個；一個宣告都沒有時 exit 3 並說出缺什麼
#          publish    → 宣告的命令印什麼就印什麼
# Exit:    0 送出去了 / 2 參數不對 / 3 沒有人認領這個命名空間 / 宣告的命令自己的離場碼
#
# 宣告長這樣（前綴任意，核心不認得任何一個命名空間名）：
#
#   <!-- {任意前綴}-EVIDENCE-PUBLISH-{命名空間}: {命令} -->
#
# 那個命令會拿到兩個路徑，怎麼送、送到哪都是它的事：
#
#   {命令} publish --report <報告.md> --manifest <清單.json>
#
# **核心不認得任何一個目的地。** 沒有 JIRA、沒有 GitHub、沒有任何一種 wiki 語法、沒有任何
# 一個憑證變數名——這支 skill 是可攜的，被匯進沒有那家公司的環境時這一層照樣成立。
#
# **這裡不是閘。** 送不出去不改變任何一條斷言的判定，也不改交付紀錄：判定由 oracle 決定，
# 發佈是那個判定的投影。所以呼叫者拿到非 0 的時候要吵、要留紀錄，但不得回頭改判定。

set -euo pipefail

PREFIX="[evidence-publish]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE=""
NAMESPACE=""
REPORT=""
MANIFEST=""

usage() {
  sed -n '2,14p' "$0" >&2
  exit 2
}

[[ $# -gt 0 ]] || usage
MODE="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --report)    REPORT="${2:-}"; shift 2 ;;
    --manifest)  MANIFEST="${2:-}"; shift 2 ;;
    --skills)    SKILLS_DIR="${2:-}"; shift 2 ;;
    -h|--help)   usage ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "$PREFIX 量不到：$SKILLS_DIR 不存在，掃不到任何 SKILL.md。" >&2
  exit 2
fi

# 掃出所有宣告，一行 "命名空間<TAB>命令"。剖析走 python3：宣告行要非貪婪地吃到 `-->` 之前
# 為止，而 BSD sed 的 ERE 沒有 lazy quantifier，寫成貪婪的話同一行有兩個註解就會整段吞掉。
collect_declarations() {
  python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys

skills_root = sys.argv[1]
pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]*EVIDENCE-PUBLISH-([A-Za-z0-9_.-]+):\s*(.+?)\s*-->")

# symlink 指到的實體只算一次——頂層的公司 skill 可能是巢狀那一份的 symlink，兩邊都掃的話
# 同一個命名空間會出現兩次，而第二次會安靜地蓋掉第一次的命令。
seen = set()
for dirpath, _, filenames in sorted(os.walk(skills_root)):
    if "SKILL.md" not in filenames:
        continue
    path = os.path.join(dirpath, "SKILL.md")
    real = os.path.realpath(path)
    if real in seen:
        continue
    seen.add(real)
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    for namespace, command in pattern.findall(text):
        print(f"{namespace}\t{command}")
PY
}

case "$MODE" in
  namespaces)
    declarations="$(collect_declarations || true)"
    if [[ -z "$declarations" ]]; then
      echo "$PREFIX 沒有任何一支 skill 宣告 EVIDENCE-PUBLISH——報告產得出來，但沒有人說要送去哪。" >&2
      echo "$PREFIX 修法：在認領它的那支 skill 的 SKILL.md 放一行" >&2
      echo "$PREFIX   <!-- {前綴}-EVIDENCE-PUBLISH-{命名空間}: {把報告送出去的命令} -->" >&2
      exit 3
    fi
    printf '%s\n' "$declarations" | cut -f1 | sort -u
    ;;

  publish)
    [[ -n "$NAMESPACE" ]] || { echo "$PREFIX publish 要 --namespace" >&2; exit 2; }
    [[ -n "$REPORT" && -n "$MANIFEST" ]] || { echo "$PREFIX publish 要 --report 與 --manifest" >&2; exit 2; }
    [[ -f "$REPORT" ]]   || { echo "$PREFIX 找不到報告：$REPORT" >&2; exit 2; }
    [[ -f "$MANIFEST" ]] || { echo "$PREFIX 找不到清單：$MANIFEST" >&2; exit 2; }
    # 變數用大括號界定：macOS 內建的 bash 3.2 在變數緊接多位元組字元時會把後面那個字元的
    # 位元組讀進變數名，於是 `$NAMESPACE」` 變成一個 unbound variable。
    ns_command="$(collect_declarations | awk -F'\t' -v n="${NAMESPACE}" '$1==n {print $2; exit}')"
    if [[ -z "$ns_command" ]]; then
      echo "${PREFIX} 沒有人宣告命名空間「${NAMESPACE}」的發佈方式，報告留在本機：${REPORT}" >&2
      echo "${PREFIX} 修法：在認領它的那支 skill 的 SKILL.md 放一行" >&2
      echo "${PREFIX}   <!-- {前綴}-EVIDENCE-PUBLISH-${NAMESPACE}: {把報告送出去的命令} -->" >&2
      exit 3
    fi
    # 宣告的命令自己決定怎麼送；核心不解讀它印出來的東西，只轉交。
    eval "${ns_command} publish --report \"\${REPORT}\" --manifest \"\${MANIFEST}\""
    ;;

  *)
    echo "$PREFIX 不認得的模式：$MODE" >&2
    usage ;;
esac
