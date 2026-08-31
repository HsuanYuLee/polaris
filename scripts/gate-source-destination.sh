#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   宣告了留在本地的東西落在會被同步出去的位置。送出去收不回來，而 diff 裡它跟任何一個正常檔案長得一樣。
# gate-source-destination.sh — 宣告 `workspace` 就是「這批東西不會出去」，這裡驗那句話。
#
# `destination` 是人在第一關做的決定，寫在 `{單}/index.md` 的 frontmatter。它值錢的地方在於
# 它把「這是不是公司內容外流」從一個靠猜內容回答的問題，換成一個靠讀宣告回答的路徑問題。
# 而一個沒有人驗的宣告，跟沒有宣告的差別只有寫的時候多打幾個字——2026-08-03 那次拆卸把
# 驗它的那支腳本刪掉了，欄位活了下來，檢查沒有。
#
# 判的是位置，不是內容：**認不出來的位置算不成立**。sync-to-polaris.sh 是一連串具名的
# 步驟，它的標籤不是路徑，所以「會被同步出去的全集」推不便宜也推不穩。所以這裡只認一個
# 刻意很小的安全子集——確定不會出去的那幾種——其餘一律判紅。過度嚴格，不過度放行。
#
# 安全子集有一部分不是寫在這裡的：同步腳本自己用 `POLARIS-NOT-SYNCED:` 宣告哪些位置它確定
# 不複製，這道關卡去讀那些宣告。什麼會出去只有那支腳本說了算，這裡再抄一份就是第二個答案
# ——而 DP-525 之前這裡沒有那條線，於是兩張只改 `.changeset/` 的單被判了假紅，逼得它們把
# destination 宣告成不是它真正的樣子。
#
# 那支腳本在哪，也不寫在這裡：掃 SKILL.md 找 `POLARIS-SYNC-SCRIPT:`，由帶著它的那支 skill
# 自己說。DP-629 之前這裡寫死 `scripts/sync-to-polaris.sh`，而那支腳本 2026-08-03 就搬到
# repo 外面去了——閘從此每一次都讀不到，然後回答「你的檔案會漏出去」。它躺了 28 天，因為
# 這道閘只對 `destination: workspace` 的單生效，而那段期間沒有一張。
#
# 所以問不到與量到了是兩個出口，不是同一個：
#   問到了（含「它說零條」）  照舊嚴格判定，認不出來的位置算不成立。
#   沒人宣告／宣告指不到      exit 2 ＋ POLARIS_SOURCE_DESTINATION_UNMEASURABLE。
#                             不列 offender、不給那兩條修法——那兩條是對「真的會漏」開的，
#                             照著做會改掉一張本來就正確的單。
#
# 不對它發言的兩種單，各自說出理由，不混進綠燈裡：
#   沒有在這個工作區開過輪次   這張單的交付不在這裡（產品 repo 的單就是這樣）
#   宣告 destination: template  位置沒有限制；內容夠不夠通用是 scan-template-leaks 的問題
#
# Usage: gate-source-destination.sh --repo <工作區> --issue <單的相對路徑>
#                                   [--issues-root <單樹在哪>]
#                                   [--head <sha>] [--base <ref>] [--changed <path>]...
#
# `--issues-root` 是「單樹在哪」，`--repo` 是「git 操作在哪棵樹」。不給就是同一棵——那是
# 常態。兩者會分開，是因為單住在 issues/（版控在別處），而程式碼可以落在一個 worktree 上；
# 少了這個參數的話，兩棵樹一分開這道閘就必定去 worktree 底下找那張單，然後說它不在
# （DP-614 第二輪；work-76 的 DP-619 死在這裡）。
# Exit:  0 成立或不適用 / 1 有檔案落在會出去的位置 / 2 量不到

set -uo pipefail

# 「這支 skill 走哪個通道」由 lib/skill_scope.py 回答，跟同步腳本同一個地方。
SCRIPT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

PREFIX="[polaris gate-source-destination]"
REPO_PATH=""
ISSUES_ROOT=""
ISSUE_DIR=""
HEAD_REF=""
BASE_REF=""
CHANGED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    REPO_PATH="${2:-}"; shift 2 ;;
    --issue)   ISSUE_DIR="${2:-}"; shift 2 ;;
    --issues-root) ISSUES_ROOT="${2:-}"; shift 2 ;;
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

[[ -n "$ISSUES_ROOT" ]] || ISSUES_ROOT="$REPO_PATH"
[[ -d "$ISSUES_ROOT" ]] || { echo "$PREFIX 量不到：--issues-root「${ISSUES_ROOT}」不存在。" >&2; exit 2; }
ISSUE_ABS="$ISSUE_DIR"
[[ "$ISSUE_ABS" = /* ]] || ISSUE_ABS="$ISSUES_ROOT/$ISSUE_DIR"
INDEX="$ISSUE_ABS/index.md"
[[ -f "$INDEX" ]] || { echo "$PREFIX 量不到：$INDEX 不在。" >&2; exit 2; }

# ── 這條規則對這張單發不發言 ──────────────────────────────────────────────────
# 落腳處問既有的宣告，不自己推第二個答案。一張單沒有在這個工作區開過輪次，就是它的交付
# 不在這裡——產品 repo 的單長的就是這個樣子，對它判紅只會讓人學會關掉這道關卡。
if [[ ! -f "$ISSUE_ABS/.spine/loop-state.json" ]]; then
  echo "$PREFIX 不適用：$ISSUE_DIR 沒有在這個工作區開過輪次，這條規則不對它發言。"
  exit 0
fi

# ── 宣告 ──────────────────────────────────────────────────────────────────────
# 讀 frontmatter 的那幾行在 lib/issue_destination.sh，因為 release-version.sh 也要問同一件事
# ——同一個判斷寫兩次，兩份可以各自寫錯而沒有人發現。
# shellcheck source=lib/issue_destination.sh
source "$SCRIPT_LIB/issue_destination.sh"
DESTINATION="$(read_issue_destination "$INDEX" || true)"

if [[ -z "$DESTINATION" ]]; then
  {
    echo "$PREFIX 量不到：$ISSUE_DIR/index.md 的 frontmatter 沒有 destination。"
    echo "$PREFIX 這個欄位是必填的，不是可選的——一張沒有宣告目的地的單，正是這道關卡要"
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
    """自己宣告 company／personal 的 skill 目錄，相對於 repo。

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


DECLARED = re.compile(
    r"^\s*#\s*<!--\s*POLARIS-NOT-SYNCED:\s*(\S+)\s*(?:—\s*(.*?))?\s*-->\s*$",
    re.MULTILINE,
)
# 同步腳本住在哪，由帶著它的那支 skill 自己宣告。這裡不寫死路徑——寫死的那一版活了 28 天，
# 期間那支腳本已經搬到 repo 外面，而閘每一次都回答「你的檔案會漏出去」。
SYNC_SCRIPT_DECLARED = re.compile(
    r"<!--\s*[A-Za-z0-9_-]+-SYNC-SCRIPT:\s*(\S+)\s*-->"
)


def skill_roots():
    """掃宣告的兩棵樹：這個工作區的，加上使用者自己的。

    帶著同步腳本的那支 skill 可能不在這個 repo 裡（`framework-release` 就是這樣，它宣告
    `personal`，所以它只住在 `~/.claude/skills/`）。只掃 repo 那一棵的話，會找不到唯一
    知道答案的那一份。兩個位置在任何跑得動 Claude Code 的地方都問得到，不是這台機器獨有的。
    """
    roots = []
    for candidate in (os.path.join(repo, ".claude", "skills"),
                      os.path.join(os.path.expanduser("~"), ".claude", "skills")):
        if os.path.isdir(candidate) and candidate not in roots:
            roots.append(candidate)
    return roots


def locate_sync_script():
    """回 (同步腳本的絕對路徑, 宣告寫在哪個 SKILL.md)；沒有人宣告就回 (None, None)。

    宣告的值是**相對於宣告它的那份 SKILL.md**，所以那支 skill 整個搬走，宣告跟著走就還對。
    """
    for root in skill_roots():
        for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
            if "SKILL.md" not in filenames:
                continue
            dirnames[:] = []
            declaring = os.path.join(dirpath, "SKILL.md")
            try:
                with open(declaring, encoding="utf-8") as handle:
                    hit = SYNC_SCRIPT_DECLARED.search(handle.read())
            except (OSError, UnicodeDecodeError):
                continue
            if hit:
                return os.path.normpath(os.path.join(dirpath, hit.group(1))), declaring
    return None, None


def declared_not_synced(sync_script):
    """去問已經有答案的那一份：同步那支腳本自己宣告了哪些位置不會被複製出去。

    這裡不維護第二份清單。什麼會出去只有一個東西說了算，而它就是那支腳本；關卡再抄一份
    的話，兩份會各自演化，然後對一批確定不會出去的檔案判紅——那正是 DP-525 的來源。

    回 (清單, 狀態)。狀態有三種，而且三種要分得開：
      read        問到了。零條宣告也是問到了——那是一個答案，判定照舊嚴格。
      undeclared  沒有任何一份 SKILL.md 說同步腳本在哪。
      unreadable  有人宣告了，但那個位置讀不到。
    後兩種**不是**「你的檔案會漏出去」，它們是「這一次沒問到」，走另一個出口。
    """
    if sync_script is None:
        return [], "undeclared"
    try:
        with open(sync_script, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError):
        return [], "unreadable"
    return [(m.group(1), (m.group(2) or "").strip()) for m in DECLARED.finditer(text)], "read"


COMPANIES = company_dirs()
UNSYNCED_SKILLS = unsynced_skill_dirs()
SYNC_SCRIPT, DECLARED_IN = locate_sync_script()
NOT_SYNCED_PATHS, DECLARATION_STATE = declared_not_synced(SYNC_SCRIPT)

# ── 問不到就停在這裡，不要往下算 offender ────────────────────────────────────
# 這一段刻意在算 offender **之前**。放在後面的話，「不要指控使用者的檔案」要靠每個出口
# 各自記得；放在前面，那件事是結構保證的——沒有 offender 可以被算出來。
print(f"{prefix} {issue_dir} 宣告 destination=workspace，清單來自 {source_of_list}")
if DECLARATION_STATE != "read":
    sys.stdout.flush()
    print("POLARIS_SOURCE_DESTINATION_UNMEASURABLE", file=sys.stderr)
    if DECLARATION_STATE == "undeclared":
        print(f"{prefix} 量不到：沒有任何一份 SKILL.md 說同步腳本在哪。", file=sys.stderr)
    else:
        print(f"{prefix} 量不到：{DECLARED_IN} 宣告同步腳本在 {SYNC_SCRIPT}，"
              f"那個位置讀不到。", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"{prefix} 這不是「你的檔案會漏出去」，是這道關卡問不到它要問的東西——"
          f"哪些位置確定不會被同步，只有那支同步腳本說了算。", file=sys.stderr)
    print(f"{prefix} 修法：在帶著那支腳本的 skill 的 SKILL.md 裡加一行宣告，"
          f"值是相對於那份 SKILL.md 的路徑：", file=sys.stderr)
    print(f"{prefix}   <!-- POLARIS-SYNC-SCRIPT: scripts/sync-to-polaris.sh -->", file=sys.stderr)
    sys.exit(2)

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
            return f"{skill}/ 自己宣告了 company／personal"
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

print(f"{prefix} 不同步的位置讀自 {SYNC_SCRIPT}"
      f"（宣告在 {DECLARED_IN}）：{len(NOT_SYNCED_PATHS)} 條宣告")
print(f"{prefix} {len(changed)} 個檔案：留得住 {len(reasons)}、認不出來 {len(offenders)}")
for path, why in reasons:
    print(f"    ok   {path}  ← {why}")

if offenders:
    sys.stdout.flush()
    print("POLARIS_SOURCE_DESTINATION_ESCAPE", file=sys.stderr)
    print(f"{prefix} 這幾個檔案的位置認不出來，可能會被同步到 template repo：", file=sys.stderr)
    for path in offenders:
        print(f"    !!   {path}", file=sys.stderr)
    print("", file=sys.stderr)
    print(f"{prefix} 兩條路，都是人的決定，這道關卡不代人改宣告：", file=sys.stderr)
    print(f"{prefix}   1. 把檔案搬到不會出去的位置——公司自己的 skill、公司的規則目錄、"
          f"或任何沒有版控的地方。", file=sys.stderr)
    print(f"{prefix}   2. 把宣告改成 destination: template，並且讓內容夠通用。"
          f"那要回第一關重簽。", file=sys.stderr)
    sys.exit(1)

print(f"{prefix} 全部留得住。")
sys.exit(0)
PY
