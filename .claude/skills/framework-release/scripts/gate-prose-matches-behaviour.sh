#!/usr/bin/env bash
# gate-prose-matches-behaviour.sh — 散文裡指名的東西，要真的在。
#
# 擋三種形狀，都是「讀的人照做、然後自己撞上」的那一類：
#
#   1. 指向不存在的檔案。`engineering/SKILL.md` 與 `verify-ac/SKILL.md` 開頭各有一句
#      「前置必讀：.claude/skills/references/spine-*.md」，那兩個檔在 DP-462 搬家時就沒了，
#      而那兩行一路活到 4.1.0。每一個讀 SKILL.md 的人第一行就被指去一個空位。
#   2. 指名不存在的子命令。散文寫 `spine-loop-state.sh where`，而那支腳本的 case 裡沒有
#      `where`——執行才炸，而且炸在流程中間。
#   3. 指名不存在的旗標。散文寫 `--source`，腳本認的是 `--issue`。這個真的發生過：三站
#      改名之後，judge/work 兩支 SKILL.md 裡整批 `--source` 全部對不上。
#
# 為什麼要一道閘而不是靠讀：這三種都不會在寫的當下錯，它們是**搬家之後**才錯的，而搬家的
# 人不會回頭讀每一支 SKILL.md。gate-skill-script-references.sh 管的是腳本引用腳本；這一支管
# 的是散文引用行為，兩者不重疊。
#
# Usage: gate-prose-matches-behaviour.sh [--repo <path>] [--skill <名字>]
#
# `--skill` 讓一支 skill 單獨檢查自己的散文。這道閘量的東西**大部分**有擁有者
# ——一份散文指名的檔案、子命令、旗標，多數就在它自己那一棵樹底下。剩下的那些
# 指向別支 skill，那一部分沒有擁有者，所以共用的那一層留著，掃全樹。
# Exit:  0 全部對得上 / 1 有對不上的

set -euo pipefail

PREFIX="[polaris gate-prose-matches-behaviour]"
REPO_ROOT=""

ONLY_SKILL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --skill) ONLY_SKILL="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$REPO_ROOT" "$PREFIX" "$ONLY_SKILL" <<'PY'
import os
import re
import sys

# 一律轉絕對路徑。skill_dir_of 拿 abspath 跟 skills_root 比前綴，`--repo .` 進來時那個比較
# 永遠不成立，於是每一個 skill 相對的起點都靜靜消失，整批裸檔名變成假的紅。
repo_root, prefix = os.path.abspath(sys.argv[1]), sys.argv[2]
only_skill = sys.argv[3] if len(sys.argv) > 3 else ""
skills_root = os.path.join(repo_root, ".claude", "skills")

# 只看 fenced bash block 與 inline code 裡的東西。散文行文提到一個名字不算指名——
# 「像 spine-loop-state 那種狀態機」不是叫人去跑它。
FENCE = re.compile(r"^```(?:bash|sh)\s*$")
FENCE_END = re.compile(r"^```\s*$")
# `bash <path>` 起頭的一行命令，後面可能接子命令與旗標。續行的反斜線要接起來。
# rest 停在 `|`、`&&`、`;`、`>`。不停的話，一條 pipeline 裡下一段命令的旗標會被算到
# 這一支頭上——memory-hygiene 的 apply-flow 就是這樣被誣告了一次：`--memory-dir` 是給管線
# 另一端那支 .py 的，而這道閘說 validate-memory-hygiene-plan.sh 不認得它。
INVOCATION = re.compile(r"\bbash\s+(?P<path>[\w./-]+\.sh)(?P<rest>[^\n|;&>]*)")
# 行文裡的「前置必讀：`x/y.md`」這類指路。副檔名限定成文件，免得把命令當路徑。
#
# 帶 `/` 的一律判。沒有目錄的檔名分兩種，理由寫在下面 BARE_DOC 的用處那裡：裸的 `.md`
# 判（它幾乎都是自家 references/ 的鄰居），裸的設定檔讓（那是別的 repo 的根檔）。
# 讓出去多少，跑完會印出來——讓出去的精度要被數出來，不能安靜。
DOC_POINTER = re.compile(r"`([\w.-]+(?:/[\w.-]+)+\.(?:md|json|yaml|yml))`")
BARE_DOC = re.compile(r"`([\w.-]+\.(?:md|json|yaml|yml))`")
# 指路的第三種寫法：一個目錄，以 `/` 結尾。以前這一整類一個都沒被判——上面兩條都要求
# 結尾是 `.md`／`.json`／`.yaml`／`.yml`，而 `.claude/rules/{公司}/handbook/` 一個都不是。
# 於是它跟 gate-skill-knowledge-locality 之間有一格誰都沒有：那一道只判**版控之外**的
# 引用，`.claude/` 開頭的直接出局，而且它的訊息還寫著「斷指標由 gate-prose-matches-behaviour
# 管」——指向一道當時並不管它的閘。
DIR_POINTER = re.compile(r"`([\w.-]+(?:/[\w.-]+)*/)`")
# 同一件事的另一種寫法：`.claude/skills/x/references`——沒有結尾斜線，也沒有副檔名，所以
# 上面三條正則一條都不吃。全樹目前**一筆都沒有**（2026-08-09 量的：解得到 0、解不到 0），
# 而那正是要現在加的理由：一條只在「剛好有人這樣寫」時才存在的檢查，等於沒有檢查。它的
# 紅控在 selftest 的 fixture 上，不在這棵樹上。
NO_EXT_POINTER = re.compile(r"`((?:\.claude|_template)/[\w.-]+(?:/[\w.-]+)*)`")
# 判哪些目錄：只有這兩個前綴。判準跟裸檔名那一段是同一句話——**解不解得出唯一位置**。
#
# `.claude/` 與 `_template/` 是這個 repo 追蹤的兩棵樹，一份散文寫出它們就是在指這裡的
# 某個位置，對不對得上是可判的。其餘一律不判，因為它們解不出唯一位置：`issues/` 沒有
# 版控、`snapshots/` 與 `test-results/` 是跑起來才長出來的、`apps/main/` 與 `packages/`
# 講的是別的 repo 的樹，而 `archive/`、`triage/`、`released/` 這些在句子裡是概念不是路徑。
#
# 這個分界是量出來的，不是挑的：全樹 139 筆目錄型指標，全判的話 115 筆變紅——那會讓這
# 道閘在三次之內被關掉，連它本來判得到的那些也一起沒了（斷言 A-N3 就是為了擋這件事）。
# 照這個前綴判，12 筆解得到、3 筆解不到，而那 3 筆是同一個真的洞。
JUDGED_DIR_PREFIXES = (".claude/", "_template/")
# 子命令是一個完整的字，後面接空白或結束。`path/to/file.md` 是位置參數不是子命令——
# 只用 \b 收尾的話 `path` 會被當成子命令，然後永遠找不到。
SUBCOMMAND = re.compile(r"^\s+([a-z][a-z0-9-]*)(?=\s|$)")
FLAG = re.compile(r"(--[a-z][a-z0-9-]*)")
# 散文的第二種寫法：`$SKILL_DIR/scripts/x.sh`。這一整類原本一個都沒被檢查——
# gate-skill-script-references 只看腳本引用腳本，看不到 SKILL.md 怎麼寫。
SKILL_DIR_REF = re.compile(
    r"\$\{?(?:SKILL_DIR|SKILLS_DIR|SKILL_ROOT)\}?/((?:scripts/|references/|env/)?[\w.-]+\.(?:sh|py|mjs|md|json|yaml|yml))"
)

# 有些散文講的是**這個 repo 以外**的東西：使用者自己的 memory 目錄、跑起來才生出的
# 產物、別的 repo 的樹——`resources/cypress/fixtures/…` 在 be2-product，
# `{company}-web/codecov.yml` 在那支產品 repo。它們在這裡當然找不到，而「找不到」跟「死掉」
# 是兩件事。
#
# 處理不是讓它安靜——安靜的排除跟沒有排除，在出事的時候長得一樣。處理是**讓那份排除自己被
# 寫出來、被讀到、被數**：那份散文自己在檔案裡宣告哪一段前綴住在別處、為什麼。
#
#   <!-- PROSE-EXTERNAL-PATHS: resources/cypress/ — 住在那支產品 repo，不在這個 repo -->
#
# 宣告只對宣告它的那一份散文生效，而且**一條沒對上任何東西的宣告是紅的**：一個沒有人在用
# 的豁免會一直留著，然後在某一天悄悄接住一個真的死掉的指標。
EXTERNAL_DECL = re.compile(r"<!--\s*PROSE-EXTERNAL-PATHS:\s*(\S+)\s*(?:—|--)\s*([^>]*?)\s*-->")

problems = []
# 不被判定的第三態要有數字。一個安靜的豁免，下一次就會有人以為那些也被檢查過了。
unjudged = set()
# 目錄型指標裡不在管轄內的那些。跟裸檔名分開數：兩者讓出去的理由相同（解不出唯一
# 位置），但形狀不同，混成一個數字就看不出是哪一類在成長。
unjudged_dirs = set()
external_hits = []      # (檔, 路徑, 前綴, 理由)
stale_declarations = [] # 宣告了卻沒對上任何東西的前綴


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


# 一個名字只出現在註解裡，不算這支腳本認得它。腳本的 `# Usage:` 檔頭是散文的一種，而拿
# 散文去驗散文永遠是綠的：一支腳本停掉某個旗標卻沒改檔頭，這道閘就從兩邊都看不出來。
#
# 全樹目前**一筆都沒有**（2026-08-10 量的：收緊之後零筆新紅），所以紅控在 selftest 的
# fixture 上，不在這棵樹上——一條只在「剛好有人這樣寫」時才存在的檢查，等於沒有檢查。
#
# 收緊有代價，而且量過了：四筆本來對的散文變紅，全部指向 `place-issues-by-state.sh` 的
# `--issues` / `--check`。那支是個殼，真的參數在它 exec 的 python 那一支裡，而殼的檔頭
# 註解剛好把兩個旗標都寫了——所以它以前是靠註解變綠的，不是靠行為。修法是讓詞表跟得到
# 那種寫法的殼（見下面 delegate 那一段），不是放寬這一條。
#
# 只剝整行的註解，不剝行尾的。行尾那種要判斷 `#` 是不是在字串裡，而判錯的代價是把一段
# 真的程式碼剝掉、然後把對的散文判紅——那是這道閘最不該犯的錯（斷言 A-N3）。
LINE_COMMENT = re.compile(r"^[ \t]*#.*$", re.MULTILINE)


def script_vocabulary(script_path):
    """腳本認得的子命令與旗標。

    子命令從結尾那個 dispatch case 讀，旗標從所有 case 分支讀——兩者都是 `x|y)` 的形狀，
    分不開也不需要分開：一個名字只要出現在任何一個 case 標籤裡，這支腳本就處理得動它。
    """
    text = LINE_COMMENT.sub("", read(script_path))
    words = set()
    for label in re.findall(r"^\s*([\w|:*.-]+)\)", text, re.MULTILINE):
        for part in label.split("|"):
            part = part.strip()
            if part and part not in ("*", "esac"):
                words.add(part)
    words.update(re.findall(r"--[a-z][a-z0-9-]*", text))

    # 一支 `exec python3 "$SCRIPT_DIR/lib/x.py" "$@"` 的殼，它認得的字全在被 exec 的那一支
    # 裡面。只讀殼會得到一份空詞表，然後把散文裡每一個對的旗標都判紅——
    # validate-learning-seed-contract.sh 就是這個形狀。跟一層就夠，殼不會疊殼。
    #
    # 殼不只一種寫法：`place-issues-by-state.sh` 用的是
    # `exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/x.py" "$@"`，
    # 沒有 `SCRIPT_DIR` 這個名字。所以也認「某個展開的結尾接一條同目錄相對路徑」——
    # 那個展開求出來的就是這支腳本自己的目錄，跟上一種是同一件事。
    for delegate in re.findall(
            r"(?:\$\{?SCRIPT_DIR\}?|[)}])/([\w./-]+\.(?:py|sh|mjs))", text):
        target = os.path.join(os.path.dirname(script_path), delegate)
        if os.path.exists(target):
            words.update(re.findall(r"--[a-z][a-z0-9-]*", LINE_COMMENT.sub("", read(target))))
    return words


def declared_elsewhere(declared, quoted):
    """這條路徑有沒有被它所在的那份散文宣告成住在別的 repo。

    回 (前綴, 理由) 或 None。
    """
    for prefix, reason in declared:
        if quoted.startswith(prefix):
            return prefix, reason
    return None


def skill_dir_of(doc_path):
    """這份散文住在哪一支 skill 底下。解不出來就回 None（例如它根本不在 skills 樹裡）。"""
    current = os.path.dirname(os.path.abspath(doc_path))
    while current.startswith(skills_root) and current != skills_root:
        if os.path.dirname(current) == skills_root:
            return current
        current = os.path.dirname(current)
    return None


def resolve(doc_path, quoted):
    """把散文裡的路徑解成磁碟位置。

    一份住在 skill 裡的散文，講的是它自己那一棵樹。所以四個起點都試，都是「這份文件的
    人會怎麼寫」而不是為了讓紅變綠：

      repo 根        `.claude/skills/x/scripts/y.sh` —— SKILL.md 幾乎都這樣寫
      文件自己       同目錄的鄰居
      skill 目錄     `references/foo.md`、`scripts/bar.sh` —— reference 講自家東西的寫法
      skill 自己的 scripts/   `bash polaris-timeline.sh` —— 命令列裡的裸腳本名
      skill 自己的 references/ `memory-write-contract.md` —— Reference Loading 表整張都這樣寫
      skills 根      `learning/SKILL.md` —— 一支 skill 指名另一支

    這幾個起點不會把一個真的死掉的指標變活：一個不存在的東西在四個起點底下一樣不存在。
    """
    skill_dir = skill_dir_of(doc_path)
    bases = [repo_root, os.path.dirname(doc_path)]
    if skill_dir:
        bases += [skill_dir,
                  os.path.join(skill_dir, "scripts"),
                  os.path.join(skill_dir, "references")]
    bases.append(skills_root)
    for base in bases:
        candidate = os.path.join(base, quoted)
        if os.path.exists(candidate):
            return candidate
    return None


# 掃哪些散文：SKILL.md 與每支 skill 自己的 references/。
#
# 以前只掃 SKILL.md。references/ 是 SKILL.md 明文叫人去讀的東西，所以它指錯路的後果一模
# 一樣——而它整整一層沒有被看過：memory-hygiene 的一份 reference 指著七個在框架換層時就
# 消失的位置（一整個 `rules/` 層與 `specs/design-plans/`），而這道閘每一次都回綠。
#
# 一個掃不到的東西與一個掃過了沒問題的東西，在輸出上長得一樣。所以掃到的份數會被印出來，
# 而讓出去的精度（沒有目錄的檔名）本來就已經印出來了。
#
# `.claude/rules/` 也掃。它是這個 repo 的第二個散文面，而它一路沒有被看過——DP-479 那支
# 一次性掃描的路徑正則只認五個前綴，`rules/` 不在裡面，所以「132/132 全綠」是在一個看不到
# 這一層的鏡頭底下拍的。
#
# `_template/` **不掃**，而這句話就是那份宣告：那底下的散文講的是「將來某個人的 repo 會長成
# 什麼樣」，它指名的路徑在這裡本來就不存在，掃它只會製造一批永遠紅的雜訊。不掃了幾份會被
# 印出來——一個沒有數字的豁免，下一次就會被當成看過了。
rules_root = os.path.join(repo_root, ".claude", "rules")
template_root = os.path.join(repo_root, "_template")

_skill_body_cache: dict = {}


def skill_body(doc):
    """一份文件所屬的那支 skill 整個目錄的文字，宣告本身剝掉。

    引用常常出現在腳本裡而宣告只能寫在 SKILL.md，所以「這行宣告有沒有用」要以整支
    skill 為單位問——跟 gate-skill-knowledge-locality 同一個單位。
    """
    parts = os.path.relpath(doc, skills_root).split(os.sep)
    # 公司 skill 多包一層，以帶得到 SKILL.md 的那一層為準。
    depth = 2 if len(parts) > 2 and os.path.isfile(
        os.path.join(skills_root, parts[0], parts[1], "SKILL.md")) else 1
    root = os.path.join(skills_root, *parts[:depth])
    if root in _skill_body_cache:
        return _skill_body_cache[root]
    chunks = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "node_modules", "__pycache__")]
        for name in filenames:
            chunks.append(EXTERNAL_DECL.sub("", read(os.path.join(dirpath, name))))
    _skill_body_cache[root] = "\n".join(chunks)
    return _skill_body_cache[root]


scanned_skill_md = 0
scanned_reference = 0
scanned_rule = 0
skipped_template = 0
for dirpath, _, filenames in os.walk(template_root):
    skipped_template += sum(1 for name in filenames if name.endswith(".md"))

# `--skill` 把範圍收成那一支自己。`.claude/rules/` 不屬於任何一支 skill，所以單支模式
# 不掃它——那一層是共用那一條路才會問的東西。
if only_skill:
    only_root = os.path.join(skills_root, only_skill)
    if not os.path.isdir(only_root):
        print(f"{prefix} 量不到：{only_root} 不存在。", file=sys.stderr)
        sys.exit(2)
    walk_targets = [(only_root, "skill")]
else:
    walk_targets = [(skills_root, "skill"), (rules_root, "rule")]
for root, kind in walk_targets:
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
    in_references = os.path.basename(dirpath) == "references" or (
        os.sep + "references" + os.sep in dirpath + os.sep)
    for name in filenames:
        if kind == "rule":
            if not name.endswith(".md"):
                continue
            scanned_rule += 1
        elif name == "SKILL.md":
            scanned_skill_md += 1
        elif in_references and name.endswith(".md"):
            scanned_reference += 1
        else:
            continue
        doc = os.path.join(dirpath, name)
        rel_doc = os.path.relpath(doc, repo_root)
        text = read(doc)

        declared = EXTERNAL_DECL.findall(text)
        used = set()

        # 1. 指路到不存在的文件。
        for quoted in DOC_POINTER.findall(text):
            # 佔位符不是指路：`{issue}/index.md` 是一個要被代換的樣板。
            if "{" in quoted or quoted.startswith("<"):
                continue
            elsewhere = declared_elsewhere(declared, quoted)
            if elsewhere:
                used.add(elsewhere[0])
                external_hits.append((rel_doc, quoted) + elsewhere)
                continue
            if resolve(doc, quoted) is not None:
                continue
            problems.append(f"{rel_doc}: 指向不存在的 `{quoted}`")

        # 沒有目錄的檔名：以前整批讓出去。但一份住在 skill 裡的散文寫 `foo.md`，在它自己
        # 那一棵樹底下解得出唯一位置——SKILL.md 的 Reference Loading 表整張都是這個寫法，
        # 而那正是最不能斷的一種指路。所以解得出來的就判，解不出來的才讓。
        #
        # 讓出去的那些是別的 repo 的根檔（`package.json`、`CLAUDE.md`）。它們照樣被數、被印。
        for quoted in BARE_DOC.findall(text):
            if "/" in quoted or "{" in quoted:
                continue
            elsewhere = declared_elsewhere(declared, quoted)
            if elsewhere:
                used.add(elsewhere[0])
                external_hits.append((rel_doc, quoted) + elsewhere)
                continue
            if resolve(doc, quoted) is not None:
                continue
            # 裸的 `.md` 判，裸的設定檔讓。分界不是憑感覺：一份散文提到的 `.md` 幾乎都是
            # 它自家 references/ 的鄰居——那正是最不能斷的一種指路，而它整批躲在「解不出
            # 唯一位置」底下沒有人看。`workspace-config.yaml`、`package.json` 這類是使用者
            # 自己的檔或別的 repo 的根檔，這個 repo 裡本來就不會有。
            if quoted.endswith(".md"):
                problems.append(f"{rel_doc}: 指向不存在的 `{quoted}`")
                continue
            unjudged.add(f"{rel_doc}: `{quoted}`")

        # 1c. 目錄型指路。判準見 JUDGED_DIR_PREFIXES 的宣告。
        dir_candidates = set(DIR_POINTER.findall(text))
        for quoted in NO_EXT_POINTER.findall(text):
            # 有副檔名的那些是檔案，DOC_POINTER 已經判過了；再判一次只會重複計數。
            if "." not in quoted.rsplit("/", 1)[-1]:
                dir_candidates.add(quoted)
        for quoted in sorted(dir_candidates):
            if "{" in quoted:
                continue
            elsewhere = declared_elsewhere(declared, quoted)
            if elsewhere:
                used.add(elsewhere[0])
                external_hits.append((rel_doc, quoted) + elsewhere)
                continue
            if not quoted.startswith(JUDGED_DIR_PREFIXES):
                unjudged_dirs.add(f"{rel_doc}: `{quoted}`")
                continue
            if os.path.isdir(os.path.join(repo_root, quoted.rstrip("/"))):
                continue
            problems.append(f"{rel_doc}: 指向不存在的目錄 `{quoted}`")

        # 1b. `$SKILL_DIR/...`。變數的值是自明的：SKILL.md 自己那一支 skill 的目錄。
        for tail in SKILL_DIR_REF.findall(text):
            if not os.path.exists(os.path.join(dirpath, tail)):
                problems.append(f"{rel_doc}: 指向不存在的 `$SKILL_DIR/{tail}`")

        # 2 與 3. 命令、子命令、旗標。續行接起來再看。
        joined = re.sub(r"\\\n\s*", " ", text)
        for match in INVOCATION.finditer(joined):
            quoted = match.group("path")
            if "{" in quoted:
                continue
            script = resolve(doc, quoted)
            if script is None:
                problems.append(f"{rel_doc}: 指向不存在的腳本 `{quoted}`")
                continue
            vocabulary = script_vocabulary(script)
            rest = match.group("rest")
            sub = SUBCOMMAND.match(rest)
            if sub and sub.group(1) not in vocabulary:
                problems.append(
                    f"{rel_doc}: `{os.path.basename(quoted)} {sub.group(1)}` "
                    f"——那支腳本沒有這個子命令"
                )
            for flag in FLAG.findall(rest):
                if flag not in vocabulary:
                    problems.append(
                        f"{rel_doc}: `{os.path.basename(quoted)} {flag}` "
                        f"——那支腳本不認得這個旗標"
                    )

        # 「用到了」不等於「這份散文用 backtick 括起來」。這一行宣告同時服務兩道閘：這一道
        # 看指路對不對，gate-skill-knowledge-locality 看它是知識還是動手對象——而後者掃的是
        # 整支 skill（含腳本）的裸文字，宣告只能寫在 SKILL.md 裡。兩道閘對「用到了」各用
        # 一套定義的話，同一行宣告會在一道閘是必要的、在另一道閘是多餘的，於是誰都不敢改。
        body = skill_body(doc) if kind == "skill" else EXTERNAL_DECL.sub("", text)
        for declared_prefix, reason in declared:
            if declared_prefix not in used and declared_prefix not in body:
                stale_declarations.append(
                    f"{rel_doc}: `{declared_prefix}`（{reason}）沒有對上任何一條路徑")

# 掃了多少一律說出來，紅綠都說。一個什麼都沒掃到的執行與一個掃過了沒問題的執行，
# 在只印結論的輸出上分不出來。
COVERAGE = (f"掃過 {scanned_skill_md} 份 SKILL.md ＋ {scanned_reference} 份 reference"
            f" ＋ {scanned_rule} 份 rules（_template/ 的 {skipped_template} 份不掃，"
            f"它講的是別人將來的 repo）")
if scanned_skill_md == 0:
    print(f"{prefix} 空掃：一份 SKILL.md 都沒掃到，這不是「都對得上」", file=sys.stderr)
    sys.exit(2)

if external_hits:
    print(f"{prefix} {len(external_hits)} 條路徑被宣告成住在這個 repo 以外，這道閘沒有驗它們：",
          file=sys.stderr)
    for doc_rel, quoted, matched, reason in sorted(external_hits):
        print(f"{prefix}   {doc_rel}: `{quoted}` ← `{matched}`（{reason}）", file=sys.stderr)

problems.extend(stale_declarations)

if unjudged:
    print(f"{prefix} 沒有目錄的檔名 {len(unjudged)} 個，不在管轄內（解不出唯一位置）：",
          file=sys.stderr)
    for item in sorted(unjudged):
        print(f"{prefix}   {item}", file=sys.stderr)

if unjudged_dirs:
    print(f"{prefix} 目錄型指標 {len(unjudged_dirs)} 個不在管轄內"
          f"（不是 {' 或 '.join(JUDGED_DIR_PREFIXES)} 開頭，解不出唯一位置）：", file=sys.stderr)
    for item in sorted(unjudged_dirs):
        print(f"{prefix}   {item}", file=sys.stderr)

if problems:
    for problem in sorted(set(problems)):
        print(f"{prefix} {problem}", file=sys.stderr)
    print(f"{prefix} {COVERAGE}，其中 {len(set(problems))} 處與實際行為對不上。",
          file=sys.stderr)
    print(f"{prefix} 文字有問題就改文字；只有在描述是對的而行為錯了的時候才改腳本。",
          file=sys.stderr)
    sys.exit(1)

print(f"PROSE-MATCHES-BEHAVIOUR {COVERAGE}，指名的檔案、子命令與旗標都對得上"
      f"（另有 {len(unjudged)} 個沒有目錄的檔名、{len(unjudged_dirs)} 個目錄型指標"
      f"不在管轄內）。")
PY
