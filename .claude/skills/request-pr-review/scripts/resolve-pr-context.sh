#!/usr/bin/env bash
# Purpose: 回答兩件這支 skill 自己不知道的事——「要看哪些 org 的 PR」與「某個 repo 的 PR
#          要通知誰」。兩者都由別的 skill 在自己的 SKILL.md 宣告，核心只負責找到那一行、
#          跑它、把答案原樣交出去。
#
# Inputs:  orgs                          印出所有被宣告的 org，一行一個
#          notify --org X --repo Y       把 repo 交給認領 X 的那個命令，印出它的答案
#          ticket --org X                把 stdin 整批交給認領 X 的那個命令，印出它的答案
#          [--skills <dir>]              skill 樹的位置（預設從自己的位置往上兩層）
# Outputs: orgs            → 每行一個 org；一個宣告都沒有時 exit 3 並說出缺什麼
#          notify / ticket → 宣告的命令印什麼就印什麼；沒有人認領那個 org 時 exit 3
#
# 為什麼是一行同時回答兩件事：要查「某家公司怎麼通知」得先知道它的 org 叫什麼，而 org 本身
# 就是要被查出來的東西。把 org 寫進宣告行的鍵裡，掃一次就同時得到「要 query 誰」與「怎麼
# 通知」，不需要先有一個答案才能問下一個。
#
# 宣告長這樣（前綴任意，核心不認得任何一個 org 名）：
#
#   <!-- {任意前綴}-PR-CONTEXT-{org}: {命令} -->
#
# 那個命令要認得兩個模式，核心把第一個參數當模式名交過去：
#
#   {命令} notify --repo <repo>   → 印出「這個 repo 的 PR 該通知誰」
#   {命令} ticket                 → 從 stdin 讀「repo<TAB>number<TAB>title<TAB>branch」，
#                                   印出「repo<TAB>number<TAB>單號<TAB>單的 URL」
#
# 兩個模式印什麼格式核心都不管——核心不認得任何一種傳輸方式、任何一個目的地，也不認得任何
# 一家公司的單號長什麼樣。ticket 走 TSV 而不是把 PR 的 JSON 丟過去，是因為那個資料結構是
# 核心的事；交出去等於逼每一家公司的知識層都得認得它，那是反過來的依賴。

set -euo pipefail

PREFIX="[pr-context]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE=""
ORG=""
REPO=""

usage() {
  sed -n '2,12p' "$0" >&2
  exit 2
}

[[ $# -gt 0 ]] || usage
MODE="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --skills) SKILLS_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "$PREFIX 量不到：$SKILLS_DIR 不存在，掃不到任何 SKILL.md。" >&2
  exit 2
fi

# 掃出所有宣告，一行 "org<TAB>命令"。剖析走 python3：宣告行要非貪婪地吃到 `-->` 之前為止，
# 而 BSD sed 的 ERE 沒有 lazy quantifier，寫成貪婪的話同一行有兩個註解就會整段吞掉。
collect_declarations() {
  python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys

skills_root = sys.argv[1]
# 前綴由宣告者自己定，核心只認 `-PR-CONTEXT-{org}:` 這一段，跟 ISSUE-STATE / ENVIRONMENT
# 兩個既有宣告點同一個形狀。
pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]+-PR-CONTEXT-([A-Za-z0-9_.-]+):\s*(.+?)\s*-->")

# symlink 指到的實體只算一次——頂層的公司 skill 是巢狀那一份的 symlink，兩邊都掃的話
# 同一個 org 會出現兩次，而第二次會安靜地蓋掉第一次的命令。
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
    for org, command in pattern.findall(text):
        print(f"{org}\t{command}")
PY
}

case "$MODE" in
  orgs)
    declarations="$(collect_declarations || true)"
    if [[ -z "$declarations" ]]; then
      echo "$PREFIX 沒有任何一支 skill 宣告 PR-CONTEXT——不知道要看哪個 org 的 PR。" >&2
      echo "$PREFIX 修法：在認領它的那支 skill 的 SKILL.md 放一行" >&2
      echo "$PREFIX   <!-- {前綴}-PR-CONTEXT-{org}: {回答「這個 repo 通知誰」的命令} -->" >&2
      exit 3
    fi
    printf '%s\n' "$declarations" | cut -f1 | sort -u
    ;;

  notify|ticket)
    [[ -n "$ORG" ]] || { echo "${PREFIX} ${MODE} 要 --org" >&2; exit 2; }
    [[ "$MODE" != "notify" || -n "$REPO" ]] || { echo "$PREFIX notify 要 --repo" >&2; exit 2; }
    # 變數用大括號界定：macOS 內建的 bash 3.2 在變數緊接多位元組字元時會把後面那個字元的
    # 位元組讀進變數名，於是 `$ORG」` 變成一個 unbound variable。
    org_command="$(collect_declarations | awk -F'\t' -v o="${ORG}" '$1==o {print $2; exit}')"
    if [[ -z "$org_command" ]]; then
      echo "${PREFIX} 沒有人宣告 org「${ORG}」，所以答不出它的 ${MODE}。" >&2
      exit 3
    fi
    # 宣告的命令自己決定怎麼回答；核心不解讀它印出來的東西，只轉交。
    if [[ "$MODE" == "notify" ]]; then
      eval "${org_command} notify --repo \"\${REPO}\""
    else
      eval "${org_command} ticket"
    fi
    ;;

  *)
    echo "$PREFIX 不認得的模式：$MODE" >&2
    usage
    ;;
esac
