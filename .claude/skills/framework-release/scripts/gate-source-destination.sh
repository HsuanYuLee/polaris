#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   宣告了留在本地的東西落在會被同步出去的位置。送出去收不回來，而 diff 裡它跟任何一個正常檔案長得一樣。
# gate-source-destination.sh — 宣告 `workspace` 就是「這批東西不會出去」，這裡驗那句話。
#
# `destination` 是人在閘一做的決定，寫在 `{單}/index.md` 的 frontmatter。它值錢的地方在於
# 它把「這是不是公司內容外流」從一個靠猜內容回答的問題，換成一個靠讀宣告回答的路徑問題。
# 而一個沒有人驗的宣告，跟沒有宣告的差別只有寫的時候多打幾個字——2026-08-03 那次拆卸把
# 驗它的那支腳本刪掉了，欄位活了下來，檢查沒有。
#
# 判的是位置，不是內容：**認不出來的位置算不成立**。sync-to-polaris.sh 是一連串具名的
# 步驟，它的標籤不是路徑，所以「會被同步出去的全集」推不便宜也推不穩。所以這裡只認一個
# 刻意很小的安全子集——確定不會出去的那幾種——其餘一律判紅。過度嚴格，不過度放行。
#
# 安全子集有一部分不是寫在這裡的：sync-to-polaris.sh 自己用 `POLARIS-NOT-SYNCED:` 宣告
# 哪些位置它確定不複製，這道閘去讀那些宣告。什麼會出去只有那支腳本說了算，這裡再抄一份
# 就是第二個答案——而 DP-525 之前這裡沒有那條線，於是兩張只改 `.changeset/` 的單被判了
# 假紅，逼得它們把 destination 宣告成不是它真正的樣子。讀不到那份宣告時判定回到嚴格的
# 那一邊，並且把「這一次沒讀到」印出來：讀不到不是放行，但它也不該是安靜的。
#
# 不對它發言的兩種單，各自說出理由，不混進綠燈裡：
#   沒有在這個工作區開過輪次   這張單的交付不在這裡（產品 repo 的單就是這樣）
#   宣告 destination: template  位置沒有限制；內容夠不夠通用是 scan-template-leaks 的問題
#
# Usage: gate-source-destination.sh --repo <工作區> --issue <單的相對路徑>
#                                   [--head <sha>] [--base <ref>] [--changed <path>]...
# Exit:  0 成立或不適用 / 1 有檔案落在會出去的位置 / 2 量不到

set -uo pipefail

# 「這支 skill 走哪個通道」由 lib/skill_scope.py 回答，跟同步腳本同一個地方。
SCRIPT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

PREFIX="[polaris gate-source-destination]"
REPO_PATH=""
ISSUE_DIR=""
HEAD_REF=""
BASE_REF=""
CHANGED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO_PATH="${2:-}"; shift 2 ;;
    --issue)   ISSUE_DIR="${2:-}"; shift 2 ;;
    --head)    HEAD_REF="${2:-}"; shift 2 ;;
    --base)    BASE_REF="${2:-}"; shift 2 ;;
    --changed) CHANGED+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -d "$REPO_PATH" ]] || { echo "$PREFIX 量不到：--repo「${REPO_PATH}」不存在。" >&2; exit 2; }
[[ -n "$ISSUE_DIR" ]] || { echo "$PREFIX 量不到：--issue 是必填的。" >&2; exit 2; }

ISSUE_ABS="$ISSUE_DIR"
[[ "$ISSUE_ABS" = /* ]] || ISSUE_ABS="$REPO_PATH/$ISSUE_DIR"
INDEX="$ISSUE_ABS/index.md"
[[ -f "$INDEX" ]] || { echo "$PREFIX 量不到：$INDEX 不在。" >&2; exit 2; }

# ── 這條規則對這張單發不發言 ──────────────────────────────────────────────────
# 落腳處問既有的宣告，不自己推第二個答案。一張單沒有在這個工作區開過輪次，就是它的交付
# 不在這裡——產品 repo 的單長的就是這個樣子，對它判紅只會讓人學會關掉這道閘。
if [[ ! -f "$ISSUE_ABS/.spine/loop-state.json" ]]; then
  echo "$PREFIX 不適用：$ISSUE_DIR 沒有在這個工作區開過輪次，這條規則不對它發言。"
  exit 0
fi

# ── 宣告 ──────────────────────────────────────────────────────────────────────
# 只讀 frontmatter：正文裡的 `destination:` 是散文，不是宣告。
DESTINATION="$(awk '
  NR == 1 && $0 == "---" { inside = 1; next }
  inside && $0 == "---"   { exit }
  inside && /^destination:[[:space:]]*/ {
    sub(/^destination:[[:space:]]*/, "")
    gsub(/[[:space:]]*(#.*)?$/, "")
    print
    exit
  }
' "$INDEX")"

if [[ -z "$DESTINATION" ]]; then
  {
    echo "$PREFIX 量不到：$ISSUE_DIR/index.md 的 frontmatter 沒有 destination。"
    echo "$PREFIX 這個欄位是必填的，不是可選的——一張沒有宣告目的地的單，正是這道閘要"
    echo "$PREFIX 拿掉的那個安靜的第三態。在 frontmatter 加一行："
    echo "$PREFIX   destination: workspace   # 留在這裡，不會進 template repo"
    echo "$PREFIX   destination: template    # 會出去"
  } >&2
  exit 2
fi

case "$DESTINATION" in
  workspace) ;;
  template)
    echo "$PREFIX 不適用：$ISSUE_DIR 宣告 destination=template，位置沒有限制。"
    echo "$PREFIX 內容夠不夠通用是 scan-template-leaks.sh 的問題，不是這一道的。"
    exit 0 ;;
  *) echo "$PREFIX 量不到：不認得的 destination「${DESTINATION}」（只有 workspace 或 template）。" >&2
     exit 2 ;;
esac

# ── 這張單改到哪些檔案 ────────────────────────────────────────────────────────
if [[ ${#CHANGED[@]} -eq 0 ]]; then
  if [[ -z "$HEAD_REF" && -f "$ISSUE_ABS/.spine/delivery.json" ]]; then
    HEAD_REF="$(python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('head_sha') or '')
except Exception:
    print('')
" "$ISSUE_ABS/.spine/delivery.json" 2>/dev/null)"
  fi
  [[ -n "$HEAD_REF" ]] || HEAD_REF="HEAD"
  if [[ -z "$BASE_REF" ]]; then
    BASE_REF="$(git -C "$REPO_PATH" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    [[ -n "$BASE_REF" ]] || BASE_REF="origin/main"
  fi
  for ref in "$BASE_REF" "$HEAD_REF"; do
    git -C "$REPO_PATH" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || {
      echo "$PREFIX 量不到：$REPO_PATH 看不到 ${ref}。清單推不出來的時候不是通過。" >&2
      exit 2
    }
  done
  merge_base="$(git -C "$REPO_PATH" merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null)"
  [[ -n "$merge_base" ]] || {
    echo "$PREFIX 量不到：$BASE_REF 與 $HEAD_REF 之間沒有共同祖先。" >&2
    exit 2
  }
  while IFS= read -r line; do
    [[ -n "$line" ]] && CHANGED+=("$line")
  done < <(git -C "$REPO_PATH" diff --name-only "$merge_base" "$HEAD_REF" 2>/dev/null)
  SOURCE_OF_LIST="$BASE_REF...$HEAD_REF"
else
  SOURCE_OF_LIST="--changed 給的 ${#CHANGED[@]} 條"
fi

if [[ ${#CHANGED[@]} -eq 0 ]]; then
  echo "$PREFIX 不適用：$SOURCE_OF_LIST 在這個工作區裡沒有任何改動。"
  exit 0
fi

# ── 判 ────────────────────────────────────────────────────────────────────────
command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

python3 - "$SCRIPT_LIB" "$REPO_PATH" "$PREFIX" "$ISSUE_DIR" "$SOURCE_OF_LIST" "${CHANGED[@]}" <<'PY'
import os
import re
import subprocess
import sys

sys.path.insert(0, sys.argv[1])
from skill_scope import goes_to_template

repo, prefix, issue_dir, source_of_list = sys.argv[2:6]
changed = [p for p in sys.argv[6:] if p]


def company_dirs():
    """帶著自己 workspace-config.yaml 的頂層目錄——sync 用來排除的同一條規則。"""
    found = []
    try:
        entries = sorted(os.listdir(repo))
    except OSError:
        return found
    for name in entries:
        if os.path.isfile(os.path.join(repo, name, "workspace-config.yaml")):
            found.append(name)
    return found


def unsynced_skill_dirs():
    """自己宣告 company-only／maintainer-only 的 skill 目錄，相對於 repo。

    判準是那份 frontmatter，不是目錄名字——用名字比對只抓得到 symlink 與命名空間
    兩種形狀裡的一種。讀宣告的是 lib/skill_scope.py，跟同步腳本問同一個地方。
    """
    found = []
    skills_root = os.path.join(repo, ".claude", "skills")
    for dirpath, dirnames, filenames in os.walk(skills_root, followlinks=True):
        if "SKILL.md" not in filenames:
            continue
        dirnames[:] = []
        if not goes_to_template(os.path.join(dirpath, "SKILL.md")):
            found.append(os.path.relpath(dirpath, repo))
    return sorted(found)


SYNC_SCRIPT = ".claude/skills/framework-release/scripts/sync-to-polaris.sh"
DECLARED = re.compile(
    r"^\s*#\s*<!--\s*POLARIS-NOT-SYNCED:\s*(\S+)\s*(?:—\s*(.*?))?\s*-->\s*$",
    re.MULTILINE,
)


def declared_not_synced():
    """去問已經有答案的那一份：同步那支腳本自己宣告了哪些位置不會被複製出去。

    這裡不維護第二份清單。什麼會出去只有一個東西說了算，而它就是那支腳本；閘再抄一份
    的話，兩份會各自演化，然後對一批確定不會出去的檔案判紅——那正是 DP-525 的來源。

    回 (清單, 讀到了沒)。讀不到的時候清單是空的，判定回到原本的嚴格樣子：未知的位置
    算不成立。讀不到不是放行，但也不能安靜——所以那個布林值會被印出來。
    """
    try:
        with open(os.path.join(repo, SYNC_SCRIPT), encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError):
        return [], False
    return [(m.group(1), (m.group(2) or "").strip()) for m in DECLARED.finditer(text)], True


COMPANIES = company_dirs()
UNSYNCED_SKILLS = unsynced_skill_dirs()
NOT_SYNCED_PATHS, DECLARATION_READ = declared_not_synced()
IGNORED = set()
if changed:
    proc = subprocess.run(["git", "-C", repo, "check-ignore", "--stdin"],
                          input="\n".join(changed), capture_output=True, text=True)
    IGNORED = {line for line in proc.stdout.splitlines() if line}


def under(path, prefix_dir):
    return path == prefix_dir or path.startswith(prefix_dir.rstrip("/") + "/")


def workspace_only(path):
    """這條路徑是不是確定不會被同步出去。說不準就回 False——過度嚴格，不過度放行。"""
    if path in IGNORED:
        return "gitignore：沒有版控就不會被複製"
    for company in COMPANIES:
        for candidate in (company, f".claude/skills/{company}", f".claude/rules/{company}"):
            if under(path, candidate):
                return f"{candidate}/ 是公司自己的，sync 不碰"
    for skill in UNSYNCED_SKILLS:
        if under(path, skill):
            return f"{skill}/ 自己宣告了 company-only／maintainer-only"
    for declared, why in NOT_SYNCED_PATHS:
        if under(path, declared):
            return f"{SYNC_SCRIPT} 宣告 {declared} 不同步：{why}" if why else \
                   f"{SYNC_SCRIPT} 宣告 {declared} 不同步"
    return None


offenders = []
reasons = []
for path in changed:
    why = workspace_only(path)
    if why is None:
        offenders.append(path)
    else:
        reasons.append((path, why))

print(f"{prefix} {issue_dir} 宣告 destination=workspace，清單來自 {source_of_list}")
if DECLARATION_READ:
    print(f"{prefix} 不同步的位置讀自 {SYNC_SCRIPT}：{len(NOT_SYNCED_PATHS)} 條宣告")
else:
    print(f"{prefix} 讀不到 {SYNC_SCRIPT}，這一次沒有任何「不同步」的宣告可以用；"
          f"判定回到嚴格的那一邊，認不出來的位置一律算不成立。")
print(f"{prefix} {len(changed)} 個檔案：留得住 {len(reasons)}、認不出來 {len(offenders)}")
for path, why in reasons:
    print(f"    ok   {path}  ← {why}")

if offenders:
    print("POLARIS_SOURCE_DESTINATION_ESCAPE", file=sys.stderr)
    print(f"{prefix} 這幾個檔案的位置認不出來，可能會被同步到 template repo：", file=sys.stderr)
    for path in offenders:
        print(f"    !!   {path}", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"{prefix} 兩條路，都是人的決定，這道閘不代人改宣告：", file=sys.stderr)
    print(f"{prefix}   1. 把檔案搬到不會出去的位置——公司自己的 skill、公司的規則目錄、"
          f"或任何沒有版控的地方。", file=sys.stderr)
    print(f"{prefix}   2. 把宣告改成 destination: template，並且讓內容夠通用。"
          f"那要回閘一重簽。", file=sys.stderr)
    sys.exit(1)

print(f"{prefix} 全部留得住。")
sys.exit(0)
PY
