#!/usr/bin/env bash
# 為什麼這一道還在（門檻 2026-08-13，見 .claude/instructions/core/bootstrap.md）：
#   一支 skill 靠工作區底下沒有版控的東西才跑得動。帶出去之後別人拿到就是壞的，而在寫下它的人的機器上永遠是綠的。
# gate-skill-knowledge-locality.sh — 一支 skill 需要的知識，住不住在它自己身上。
#
# 為什麼這件事要有關卡：skill 目錄是唯一會被帶到 claude.ai 與 Cowork 的東西。一支 skill 到了
# 那裡，它引用的那些工作區底下的路徑不存在；在原機器上那條路徑跑得動，所以沒有人
# 發現。2026-08-07 rex 撞到的就是這個——web-dev-env 的五行環境宣告在他機器上全部非 0，
# 在寫下它們的人的機器上全部 exit 0，差別只有本機有沒有一個沒版控的目錄。
#
# 一筆往外的引用有兩種，這道關卡要求說出是哪一種：
#
#   動手對象  skill 操作的東西——被改的 repo、被寫出去的產出、被查詢的服務。它本來就在
#             外面，這是對的。
#   知識      skill 據以判斷「怎麼做」的東西。它必須住在 skill 自己的目錄裡。
#
# 分類寫在既有的宣告源上，不另開第二份：
#
#   <!-- PROSE-EXTERNAL-PATHS: {路徑前綴} — 動手對象：{理由} -->
#   <!-- PROSE-EXTERNAL-PATHS: {路徑前綴} — 知識：{理由} -->
#
# gate-prose-matches-behaviour 讀同一行的「路徑 + 理由」，這裡多讀理由開頭那個詞。兩個
# 消費者、一個宣告源——抄成兩份的話，兩邊會各自漂，而漂掉的那一刻沒有人在看。
#
# 判定只讀版控裡的東西，不問本機有什麼。以前它問，於是同一棵樹在兩台機器上答案不同——而且
# 差的方向是錯的：問題發生的那台（沒有那些目錄的那台）看到的是綠色。實測見 DP-470 K 組。
#
# Usage: gate-skill-knowledge-locality.sh [--repo <工作區>]
# Exit:  0 每一筆都分類過而且沒有知識住在外面 / 1 有未分類或有知識住在外面 / 2 量不到

set -uo pipefail

PREFIX="[polaris gate-skill-knowledge-locality]"
REPO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILLS_PATH="$REPO_PATH/.claude/skills"

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

python3 - "$REPO_PATH" "$PREFIX" "$SKILLS_PATH" <<'PY'
import os
import posixpath
import re
import subprocess
import sys

repo, prefix, skills_root = sys.argv[1:4]
skills_rel = os.path.relpath(skills_root, repo)
if not os.path.isdir(skills_root):
    print(f"{prefix} 量不到：{skills_root} 不存在。", file=sys.stderr)
    sys.exit(2)

# 管轄範圍要確定性地畫出來，不能靠「看起來像路徑」——`base/head`、`read/write`、
# `merged/open/closed` 都長得像路徑而且都不是。畫的方式是問版控：一條被 `.gitignore`
# 排除、而且沒有被追蹤的路徑，才在管轄內。解不出來的字串不在管轄內，數量會被印出來
# （一個安靜的第三態下一次就會被當成檢查過了）。
# 前面那個 `@` 是要擋 npm 的 scoped package：`@acme/web-main@8.7.0-rc.3` 長得跟一條
# 進到公司 checkout 的路徑一模一樣，而它是一個套件名字。
REFERENCE = re.compile(r"(?<![\w./@-])([\w.-]+/[\w./-]+)")
DECLARATION = re.compile(
    r"<!--\s*PROSE-EXTERNAL-PATHS:\s*(\S+)\s*(?:—|--)\s*([^>]*?)\s*-->")
KNOWLEDGE = "知識"
TARGET = "動手對象"
# 這幾個開頭不是往外，是這個 repo 自己的東西或相對路徑。
INTERNAL_PREFIXES = (".claude/", "_template/", "issues/", "./", "../",
                     ".codex/", ".polaris/")
# 裝出來的東西不是知識也不是動手對象，它由 package manager 決定。這一條看的是**任何一段**
# 而不是開頭：`.gitignore` 的 `node_modules/` 沒有錨定，於是 `$REPO_ROOT/node_modules/.bin/x`
# 這種變數起頭的字串會被判成「版控排除的路徑」，而它根本不是一條路徑。
INSTALLED = "node_modules"


# git 跑 hook 的時候環境裡一定有 GIT_DIR，而**顯式的 GIT_DIR 蓋過 `-C`**——於是這道關卡在
# hook 裡問的會是另一個 repo（或者像 2026-08-10 實測到的，直接 `fatal: not a git repository`）。
# DP-467 對十支腳本修過同一個形狀。整道關卡的每一次 git 呼叫都要用這份環境。
GIT_ENV = {k: v for k, v in os.environ.items()
           if k not in ("GIT_DIR", "GIT_WORK_TREE")}
# `check-ignore` 也讀使用者的 global ignore，而那是「這台機器才有」的東西——正是這道關卡
# 宣稱要避開的東西。2026-08-19 實測：`~/.gitignore` 的 `*.log` / `*.bak` / `[Ll]ogs` 讓
# 11 條腳本裡的暫存檔名被判成「往版控之外的引用」，換一台沒有那份 global ignore 的機器
# 就一條都沒有。答案要只由這個 repo 被追蹤的 `.gitignore` 決定。
GIT_ENV["GIT_CONFIG_GLOBAL"] = os.devnull


def git(*args: str) -> str:
    """跑一個唯讀的 git 指令。非 0 就是量不到——靜靜當成空結果會讓整道關卡變成永遠的綠。"""
    proc = subprocess.run(["git", "-C", repo, *args],
                          capture_output=True, text=True, env=GIT_ENV)
    if proc.returncode != 0:
        print(f"{prefix} 量不到：git {' '.join(args)} 回 {proc.returncode}"
              f"（{proc.stderr.strip()}）。", file=sys.stderr)
        sys.exit(2)
    return proc.stdout


# 版控的三個事實，整道關卡只從這裡取材。掃描對象、管轄範圍、豁免，全部由 commit 決定，
# 所以同一棵樹在任何一台機器上答案相同——那正是這道關卡以前做不到的事。
INDEX = [line.split("\t", 1) for line in git("ls-files", "-s").splitlines()
         if "\t" in line]
TRACKED = {path for _, path in INDEX}
# git 拒絕解析穿過 symlink 的路徑，而且一條就讓整批 check-ignore 回 128。哪些是 symlink
# 從索引問，不從本機看——`.agents/skills` 就是一個，它指回 `.claude/skills`。
SYMLINKS = {path for meta, path in INDEX if meta.startswith("120000 ")}


def excluded_by_version_control(candidates: list[str]) -> set[str]:
    """哪幾條路徑被版控排除掉。答案寫在 `.gitignore` 裡，而那是一個被追蹤的檔案。

    刻意不問「本機有沒有這個東西」。那正是這道關卡以前會因為在誰的機器上跑而給出不同答案
    的地方，而且錯的方向：2026-08-07 撞到的那五行，在對方機器上那個公司目錄整個不
    存在，於是那些引用全部落在管轄外、關卡判綠——**問題發生的那台機器，正是關卡看不見的
    那台**。`git check-ignore` 不需要那個東西存在也答得出來。

    被追蹤的路徑不算：它跟著 repo 走，不是「我這台才有」。
    """
    links = tuple(s + "/" for s in SYMLINKS)
    # `$SCRIPTS/../../verify-ac/scripts` 這種從 shell 變數摘出來的字串，正規化之後跑出這個
    # 工作區。它講的不是這裡的任何東西，而 git 對它一樣回 128。
    candidates = [c for c in candidates
                  if c.rstrip("/") not in SYMLINKS
                  and not c.startswith(links)
                  and not posixpath.normpath(c).startswith("..")]
    if not candidates:
        return set()
    # 每一條問兩次：光禿的與結尾帶 `/` 的。`.gitignore` 的目錄樣式（`/docs-manager/dist/`）
    # 只對目錄成立，而 git 要判斷一條路徑是不是目錄，就得去看檔案系統——於是同一條
    # `docs-manager/dist` 在有那個目錄的機器上是 IGNORED、在沒有的機器上不是。結尾那個斜線
    # 把「它是目錄」直接說出來，答案就只剩下 `.gitignore` 的內容在決定。
    bare = [c.rstrip("/") for c in candidates]
    # 索引裡的 symlink 上面已經濾掉了，但本機還會有沒被追蹤的（指向產品 checkout 的捷徑）。
    # git 對穿過它們的路徑一律 fatal，而且一條就讓整批回 128——整支關卡因此量不到。所以撞到
    # 一條就把它丟出候選再問一次，並把丟掉的逐條說出來：不判定不等於沒有那些東西。
    beyond_symlink = re.compile(r"pathspec '([^']+)' is beyond a symbolic link")
    dropped: list[str] = []
    while True:
        ignored = subprocess.run(
            ["git", "-C", repo, "check-ignore", "--stdin"],
            input="\n".join(bare + [c + "/" for c in bare]),
            capture_output=True, text=True, env=GIT_ENV)
        # 0 = 有命中、1 = 一條都沒命中，其餘是真的壞了——不得靜靜當成「沒有東西被排除」。
        if ignored.returncode in (0, 1):
            break
        hit = beyond_symlink.search(ignored.stderr)
        if not hit:
            print(f"{prefix} 量不到：git check-ignore 回 {ignored.returncode}"
                  f"（{ignored.stderr.strip()}）。", file=sys.stderr)
            sys.exit(2)
        bad = hit.group(1).rstrip("/")
        dropped.append(bad)
        bare = [c for c in bare if c != bad]
    if dropped:
        print(f"{prefix} DISCLOSURE 這幾條穿過本機的 symlink，git 答不出它們算不算被排除，"
              f"這道關卡沒有判它們：{', '.join(sorted(dropped))}", file=sys.stderr)
    hits = {p.rstrip("/") for p in ignored.stdout.splitlines() if p}
    return {h for h in hits if h not in TRACKED}


def skill_of(rel: str) -> str:
    """這個檔案屬於哪一支 skill。公司 skill 多包一層，那一層也算 skill 的一部分。

    分界看的是哪一層帶著 SKILL.md，不是那一層叫什麼名字——寫死一個公司名，換一家公司
    就會把它整批 skill 併成同一支來判。
    """
    parts = rel.split("/")
    if len(parts) > 2 and f"{skills_rel}/{parts[0]}/{parts[1]}/SKILL.md" in TRACKED:
        return "/".join(parts[:2])
    return parts[0]


# 先把候選收齊、一次問完版控，再分類。逐條問會對每一個長得像路徑的字串各開一個
# subprocess，而那種字串有兩千個。
skills: dict[str, dict] = {}
candidates: list[tuple[str, str, str]] = []   # (skill, 引用, 出處)
# 掃的是**被追蹤的**檔案，不是本機有的。沒進版控的 skill 不會被帶走，所以它不該影響判定；
# 拿本機列目錄的話，這台多七支沒 commit 的 skill 就會比 CI 多判七支。
for path in sorted(p for p in TRACKED
                   if p.startswith(skills_rel + "/") and p not in SYMLINKS):
    rel = path[len(skills_rel) + 1:]
    skill = skill_of(rel)
    entry = skills.setdefault(skill, {"declarations": [], "references": {}})
    try:
        text = open(os.path.join(repo, path), encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    for m in DECLARATION.finditer(text):
        entry["declarations"].append((m.group(1), m.group(2)))
    for m in set(REFERENCE.findall(text)):
        if m.startswith(INTERNAL_PREFIXES) or INSTALLED in m.split("/"):
            continue
        candidates.append((skill, m, path))

if not skills:
    print(f"{prefix} 量不到：{skills_rel}/ 底下沒有任何被追蹤的檔案。"
          f"一次什麼都沒掃到的執行，不是一次通過。", file=sys.stderr)
    sys.exit(2)

excluded = excluded_by_version_control(sorted({c[1] for c in candidates}))
out_of_jurisdiction = 0
for skill, ref, source in candidates:
    # 一支 skill 指名另一支 skill，寫的是名字不是路徑。它跟 `.claude/skills/{那個名字}`
    # 是同一件事，而那條寫全的路徑本來就在豁免裡——短名不該得到不同的答案。這在公司
    # skill 上特別會撞：`{公司}/repo-notes` 是 skill 名，而 `{公司}/` 同時是被 ignore 的
    # 公司 checkout。
    if ref in skills or ref.rstrip("/") not in excluded:
        out_of_jurisdiction += 1
        continue
    skills[skill]["references"].setdefault(ref, set()).add(source)

unclassified: list[str] = []
knowledge_outside: list[str] = []
classified = 0
for skill in sorted(skills):
    for ref, sources in sorted(skills[skill]["references"].items()):
        kind = None
        for declared_prefix, reason in skills[skill]["declarations"]:
            if not ref.startswith(declared_prefix.rstrip("/")):
                continue
            if reason.startswith(KNOWLEDGE):
                kind = KNOWLEDGE
            elif reason.startswith(TARGET):
                kind = TARGET
            break
        where = "、".join(sorted(sources)[:2])
        if kind is None:
            unclassified.append(f"  {skill}: `{ref}` ← {where}")
        elif kind == KNOWLEDGE:
            knowledge_outside.append(f"  {skill}: `{ref}` ← {where}")
        else:
            classified += 1

total_refs = sum(len(s["references"]) for s in skills.values())
print(f"{prefix} 掃過 {len(skills)} 支 skill，找到 {total_refs} 筆指向版控之外的引用："
      f"分類成動手對象 {classified} 筆、知識 {len(knowledge_outside)} 筆、"
      f"沒有分類 {len(unclassified)} 筆"
      f"（另有 {out_of_jurisdiction} 個字串不在管轄內：版控沒有排除它們——要嘛不是路徑，要嘛跟著 repo 走。"
      f"它們死了沒有，這一道不判；gate-prose-matches-behaviour 判其中一部分，"
      f"而它自己會把讓出去的那些逐條印出來）。")

if unclassified:
    print(f"{prefix} 沒有分類的 {len(unclassified)} 筆——一筆沒有說法的往外引用，"
          f"跟一筆說錯了的在出事的時候長得一樣：")
    print("\n".join(unclassified))
if knowledge_outside:
    print(f"{prefix} 被分類成知識、卻住在 skill 目錄外的 {len(knowledge_outside)} 筆——"
          f"這支 skill 被帶到 claude.ai 或 Cowork 就會少掉這些：")
    print("\n".join(knowledge_outside))

if unclassified or knowledge_outside:
    print(f"{prefix} 修法：知識搬進那支 skill 自己的目錄；真的是動手對象的，"
          f"在那支 skill 裡加一行 "
          f"<!-- PROSE-EXTERNAL-PATHS: {{路徑前綴}} — 動手對象：{{理由}} -->")
    sys.exit(1)

print(f"{prefix} ✅ 每一筆往外的引用都分類過，沒有知識住在 skill 目錄外。")
PY
