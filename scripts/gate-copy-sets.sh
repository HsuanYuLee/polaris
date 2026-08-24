#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   同名副本漂開，而其中一份會被同步到 template repo 出去；漂掉的那一刻兩份各自看起來都正常。
# Purpose: 同一個名字在多支 skill 底下各有一份時，那幾份還一不一樣、說不說得出為什麼。
# Inputs:  --repo <path>（預設從自己的位置往上找 repo root）、--declaration <path>
# Outputs: 三類問題各自列出是哪一支、在哪；有任何一類就 exit 1。不在管轄的數量會印出來。
#
# DP-462 拆掉共用 `scripts/` 之後，同一支腳本在多個 skill 目錄底下各有一份。那個形狀本身
# 是刻意的——skill 要能整包被帶到 claude.ai 與 Cowork，指向目錄外的東西在那裡不存在。
# 問題不在「有副本」，在**沒有任何東西在維持它們一致**。DP-467 H-N1 簽下這件事。
#
# 這支存在的理由是那次判定的量測**住在釋出封存裡**：
# `issues/.../DP-467-.../.spine/evidence/h-n1-check.py`，沒有任何閘叫它。一支不被呼叫的
# 檢查跟沒有那支檢查的差別只有磁碟空間，而它比沒有更糟——H-N1 在紀錄上是「有東西在守」。
# 2026-08-12 拿那份封存的腳本對當時的樹跑一次，三類全中。
#
# 問三件事：
#   一、每一組同名副本都逐位元相同。不同就是已經漂了。
#   二、每一組副本都在宣告源裡有理由。沒列到的是「不知道什麼時候多出來的」。
#   三、宣告源列了但樹上只剩一份的，判紅。一份追不上現況的清單會讓人以為那些還在。
#
# **發現靠掃描，不靠清單。** 副本是誰、有幾份，從磁碟數出來；宣告源只回答「為什麼」。
# 把「有哪些副本」也寫進宣告源的話，那份清單自己就是第二個會漂的來源。
#
# 管轄範圍分成兩半，而且兩半的判準不一樣（見 DP-514 A-P4）：
#
#   - `.sh` / `.py` / `.mjs`：不限位置，同檔名就是同一組。
#   - `.md`：只算 `{skill}/references/` **直屬**的那一層。
#
# 散文那一半要收窄，是因為檔名在散文裡同時被拿來當**位置**用：`SKILL.md` 24 份、
# `references/handbook/{對象}/index.md` 9 份、兩個不同產品的 `testing.md`——同名但不是同
# 一個東西。純用檔名分組會噴 16 組，其中大半是假的，而一道會噴假紅的閘會在三次之後被關掉。
# 收窄之後 12 組全是真副本、0 個假陽性（2026-08-12 量的）。
#
# **鍵是檔名，所以同一份東西被抄成另一個名字這道閘看不見。** 這不是能靠換鍵修掉的——內容
# 相同才算副本的話，兩份剛好一樣的空 wrapper 就是假紅；內容不同又本來就是它要抓的東西。
# 所以它每一次都把這個盲區印出來（`DISCLOSURE:`），而不是靜靜地讓讀的人以為掃完了：一個
# 沒被說出來的盲區，跟沒有那個盲區在輸出上長得一樣。真正在擋這一類的是看 diff 的人。
#
# 反過來，**腳本那一半刻意不收窄**。用「相對 skill 根的路徑」當鍵看起來更精確，實際上會
# 靜靜地弄丟 `approval-staleness.sh`——它在 review-inbox 底下是 `scripts/`、在
# request-pr-review 底下是 `scripts/lib/`，而那兩份現在逐位元相同、是真的副本。一個讓
# 真副本掉出管轄的判準，就是 A-N2 講的那種「靠放寬判準換綠」。
#
# Exit:
#   0 — 每一組副本都一致、都有理由，宣告源沒有過期項
#   1 — 量到了，而且是紅的（漂了、無主、或宣告過期）
#   2 — 量不到（repo 根解錯、宣告源不在、python3 不在、掃到的檔案少到掃描本身壞了）

set -euo pipefail

PREFIX="[polaris gate-copy-sets]"
REPO_ROOT=""
DECLARATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --declaration) DECLARATION="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,41p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$SELF_DIR" rev-parse --show-toplevel)"
fi
[[ -n "$DECLARATION" ]] || DECLARATION="$SELF_DIR/copy-sets.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$REPO_ROOT" "$DECLARATION" "$PREFIX" <<'PY'
import collections
import hashlib
import json
import pathlib
import sys

repo_root, declaration, prefix = sys.argv[1], sys.argv[2], sys.argv[3]

SCRIPT_SUFFIXES = (".sh", ".py", ".mjs")
PROSE_SUFFIX = ".md"
PROSE_DIR = "references"

# preflight：管轄內掃不到這個數量，代表掃描本身壞了，不是 repo 真的沒東西。門檻遠低於
# 實際值（2026-08-12 是 316），它擋的是「根解錯 → 空掃 → 回綠」那一種，不是拿來當品質線。
MIN_TOTAL_FILES = 50

skills_root = pathlib.Path(repo_root).resolve() / ".claude" / "skills"
if not skills_root.is_dir():
    print(f"{prefix} 量不到：{skills_root} 不存在。根解錯了，不是這個 repo 沒有 skill。", file=sys.stderr)
    sys.exit(2)

decl_path = pathlib.Path(declaration)
if not decl_path.is_file():
    print(f"{prefix} 量不到：宣告源不在 {decl_path}", file=sys.stderr)
    sys.exit(2)

declared = {}
excluded_names = {}
doc = json.loads(decl_path.read_text(encoding="utf-8"))
for group in doc.get("copy_groups", []):
    for name in group["scripts"]:
        declared[name] = group["why"]
for item in doc.get("not_copy_sets", []):
    excluded_names[item["name"]] = item["why"]

# skill 根是「帶著 SKILL.md 的那個目錄」。巢狀的公司 skill 各自是一個 skill，所以長的先比。
skill_roots = sorted(
    {p.parent for p in skills_root.rglob("SKILL.md")}, key=lambda p: -len(str(p))
)


def skill_root_of(path):
    for root in skill_roots:
        if root in path.parents:
            return root
    return None


groups = collections.defaultdict(list)
seen = set()
skipped = collections.Counter()
excluded_hits = collections.Counter()

for path in sorted(skills_root.rglob("*")):
    # symlink 指到的實體只算一次——頂層的公司 skill 是巢狀那一份的 symlink，兩邊都數的話
    # 每一支公司腳本都會憑空多出一份「副本」。
    if not path.is_file() or path.is_symlink():
        continue
    real = path.resolve()
    if real in seen:
        continue
    seen.add(real)

    root = skill_root_of(path)
    if root is None:
        skipped["不住在任何 skill 底下"] += 1
        continue
    rel = path.relative_to(root)

    if path.suffix in SCRIPT_SUFFIXES:
        pass
    elif path.suffix == PROSE_SUFFIX:
        if rel.parent.as_posix() != PROSE_DIR:
            skipped[f"不是 {PROSE_DIR}/ 直屬的 .md"] += 1
            continue
    else:
        skipped["副檔名不在管轄內"] += 1
        continue

    if path.name in excluded_names:
        skipped["宣告源指名不算副本"] += 1
        excluded_hits[path.name] += 1
        continue

    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    groups[path.name].append((str(path.relative_to(skills_root)), digest))

total = sum(len(v) for v in groups.values())
if total < MIN_TOTAL_FILES:
    print(
        f"{prefix} 量不到：管轄內只掃到 {total} 個檔（下限 {MIN_TOTAL_FILES}）。"
        f"這是掃描壞了，不是 repo 真的沒東西。",
        file=sys.stderr,
    )
    sys.exit(2)

copy_sets = {name: items for name, items in groups.items() if len(items) > 1}

skipped_note = "、".join(f"{k} {v}" for k, v in sorted(skipped.items())) or "沒有"
print(
    f"{prefix} MEASURED 管轄內 {total} 個檔，{len(copy_sets)} 組同名多份、"
    f"共 {sum(len(v) for v in copy_sets.values())} 份（不在管轄：{skipped_note}）"
)

# 這道判準看不見的那一類要每次都說出來（DP-514 A-P4 (f)）。它印在判定之前，因為綠的那一次
# 才是最容易被讀成「掃完了」的那一次。
print(
    f"{prefix} DISCLOSURE 鍵是檔名，所以「同一份東西被抄成另一個名字」這一類這道閘看不見"
    f"（管轄內 {len(groups)} 個不同名字）。擋這一類的是看 diff 的人，不是這道閘。"
)

failures = []

drifted = {n: v for n, v in copy_sets.items() if len({d for _, d in v}) > 1}
if drifted:
    failures.append("POLARIS_COPY_SET_DRIFTED")
    print("POLARIS_COPY_SET_DRIFTED", file=sys.stderr)
    print(f"{prefix} 這幾組同名副本的內容已經不一樣了——沒有任何東西在維持它們一致：", file=sys.stderr)
    for name, items in sorted(drifted.items()):
        kinds = len({d for _, d in items})
        print(f"{prefix}   {name}：{len(items)} 份 / {kinds} 種", file=sys.stderr)
        for path, digest in sorted(items):
            print(f"{prefix}       {digest[:8]}  {path}", file=sys.stderr)

undeclared = sorted(n for n in copy_sets if n not in declared)
if undeclared:
    failures.append("POLARIS_COPY_SET_UNDECLARED")
    print("POLARIS_COPY_SET_UNDECLARED", file=sys.stderr)
    print(f"{prefix} 這幾組有副本，但宣告源沒說為什麼：", file=sys.stderr)
    for name in undeclared:
        print(f"{prefix}   {name}（{len(copy_sets[name])} 份）", file=sys.stderr)
        for path, _ in sorted(copy_sets[name]):
            print(f"{prefix}       {path}", file=sys.stderr)

stale = sorted(n for n in declared if n not in copy_sets)
if stale:
    failures.append("POLARIS_COPY_SET_STALE_DECLARATION")
    print("POLARIS_COPY_SET_STALE_DECLARATION", file=sys.stderr)
    print(f"{prefix} 宣告源說這幾支有副本，但樹上只剩一份或已經不在：", file=sys.stderr)
    for name in stale:
        found = len(groups.get(name, []))
        print(f"{prefix}   {name}（現在 {found} 份）", file=sys.stderr)

# 排除清單自己也會過期：指名一個現在根本沒有多份的名字，讀的人會以為那裡有一個被壓下去的
# 假紅。它跟宣告源過期是同一個形狀，所以判同一種紅。
stale_exclusions = sorted(n for n in excluded_names if excluded_hits[n] < 2)
if stale_exclusions:
    failures.append("POLARIS_COPY_SET_STALE_DECLARATION")
    print("POLARIS_COPY_SET_STALE_DECLARATION", file=sys.stderr)
    print(f"{prefix} 排除清單指名了這幾個名字，但它們現在根本不是同名多份：", file=sys.stderr)
    for name in stale_exclusions:
        print(f"{prefix}   {name}（管轄內 {excluded_hits[name]} 個）", file=sys.stderr)

if failures:
    print(f"{prefix} {len(set(failures))} 類問題。", file=sys.stderr)
    sys.exit(1)

print(f"{prefix} ✅ {len(copy_sets)} 組副本逐位元一致，且都在宣告源裡有理由。")
PY
