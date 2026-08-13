#!/usr/bin/env bash
# Purpose: 每支 skill 底下的腳本，從自己的位置算起指名另一個東西時，那個東西要真的在。
#          腳本搬家會把這種寫死的相對路徑一個一個變成執行期才炸的洞。
# Inputs:  --repo <path>（預設從自己的位置往上找 git 根）、--skill <名字>（只看那一支）
# Outputs: 每個對不上的引用印一行；有任何一個就 exit 1。掃不到東西 exit 2。
#          每次都印一行 DISCLOSURE，說出這道閘判不了的那幾類各有幾條。
#
# 為什麼需要這道閘：shellcheck 不解析變數路徑，per-skill selftest 只跑得到自己那支的
# happy path。DP-462 把共用的 scripts/ 拆進各 skill 之後，三個不同的斷點都是在**釋出
# 執行到一半**才炸出來的——`gates/gate-spine-delivery.sh`、`gate-pr-language.sh` 整支不見、
# `lib/tool-resolution.sh` 沒跟著搬。那時候版號已經壓下去了。
#
# **管轄的分界不是「跨不跨目錄」**（DP-513）。這道閘到 v4.35.0 為止只認得指向同目錄與
# `lib/`／`env/`／`selftests/`／`gates/` 的引用，而且要求副檔名是 `.sh`／`.py`／`.mjs`——
# 於是 `$SCRIPT_DIR/../../x/y.sh`、指向目錄的、指向 `.md` 的，一條都不在它眼裡，而它印的是
# 「241 個檔的同目錄引用都對得上」。實際後果：兩支 `fetch-pr-info.sh` 的 `github-rest.sh`
# 候選清單三條全是 DP-462 之前的 repo 根佈局，三條都落空，於是那整條 REST 路徑永久是死的
# ——而因為每個呼叫點都用 `declare -F` 包著、有 `gh` 的 else 分支，輸出上跟它正常運作
# 長得一模一樣。那不是一個 crash，是一個安靜的第三態。
#
# 放寬之後分界有兩層，兩層都跟目錄無關：
#
# 一、**這條引用指名了東西嗎。** 往上爬完之後還剩不剩一個具名的元件。`$SCRIPT_DIR/../..`
#    這種沒有——對它做存在性檢查永遠是綠的，因為它一定指得到工作區的某一層。這一類**不判定**，
#    但**要印出條數**：一道對這一類回綠、卻不說自己跳過了它們的閘，就是它在擋的那種第三態。
#
# 二、**它被存在性檢查包住嗎。** 包住的是**候選**，不是要求：`for candidate in …` 那種清單，
#    或 `if [[ -f X ]]; then . X; fi` 那種先問再用。候選**整組全部落空才判紅，而且判一次
#    不是逐條**——一組三條候選噴三行，讀的人會以為有三個洞。沒被包住的，不存在就是紅的。
#
#    **一組只有一個目標的時候不判定**，理由寫在下面 `groups` 那一段：那個形狀分不出「一條
#    永遠走不到的 fallback」與「一個本來就該落空的探測」。它進 DISCLOSURE，不靜默跳過。
#
# 判不了的每一類都印出條數（見 DISCLOSURE 那一行）。不判定不等於沒有那些東西。

set -euo pipefail

PREFIX="[polaris gate-skill-script-references]"
REPO_ROOT=""
# 這道閘量的東西有明確的擁有者：一支 skill 的腳本指向它自己位置算起的東西，完全在那一支
# 之內。所以它要能被那一支單獨叫起來檢查自己——`--skill <名字>`。共用的那一層只剩「掃過
# 每一支」，而那件事沒有擁有者：沒有任何一支 skill 該負責別支有沒有被掃到。
ONLY_SKILL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --skill) ONLY_SKILL="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi

python3 - "$REPO_ROOT" "$PREFIX" "$ONLY_SKILL" <<'PY'
import collections
import os
import re
import subprocess
import sys

repo_root, prefix, only_skill = sys.argv[1], sys.argv[2], sys.argv[3]
repo_root = os.path.realpath(repo_root)
scope = f".claude/skills/{only_skill}" if only_skill else ".claude/skills"

# 只看「從腳本自己的位置算起」的引用。指向 repo 根、或值來自環境的變數不在這裡管。
#
# **哪個變數算「從自己的位置算起」，由賦值的形狀決定，不由名字決定。** 名字白名單是這道閘
# 兩次踩過的同一個坑：第一版只認大寫，漏掉 `$script_dir`，那個洞活到 4.0.0 的釋出尾段才炸；
# 補成大小寫都收之後，`polaris-doctor.sh` 的 `SCRIPT_DIR="$WORKSPACE_ROOT/scripts"` 又解不開
# ——不是因為它不自明，而是因為 `WORKSPACE_ROOT` 不在名單上，儘管它自己就是
# `$(cd "$(dirname "$0")/.." && pwd)`。所以下面追的是任何變數，只要它的值追得回這支腳本
# 自己的位置。
#
# 名字白名單留下來只做一件事：一個**看起來**是自我定位、卻追不回來的變數（`$SCRIPT_DIR`
# 被指派成別的東西），要被算進 DISCLOSURE 而不是靜默漏掉。
ANY_VAR = r"[A-Za-z_][A-Za-z0-9_]*"
SELF_DIR_VARS = r"(?i:SCRIPT_DIR|SCRIPTS|HERE|LIB_DIR|SKILLS_DIR)"
SELF_DIR_NAME = re.compile(rf"^{SELF_DIR_VARS}$")
# 尾段是**任何具名的東西**，不再限定副檔名與子目錄名：目標可以是目錄（`../../verify-ac/scripts`）、
# 可以是散文（`../dispatch-context-bundle.md`）、也可以在上面幾層。`:` 排掉是因為
# `PATH="$SCRIPT_DIR/bin:$PATH"` 那種的尾段不是一個路徑。
_TAIL = r"[^\s\"'`;:)|&<>]*"
REF_VAR = re.compile(rf"\$\{{?({ANY_VAR})\}}?/({_TAIL})")
# 當場算的那種：`$(cd "$(dirname "$0")/.." && pwd)/lib/x.py`。中間可能有幾層 `..`，
# 要照著往上退，否則會把 selftest 指向 scripts/ 的正常引用誤判成斷掉。
REF_INLINE = re.compile(
    rf'\$\(cd\s+"\$\(dirname[^)]*\)((?:/\.\.)*)"?\s*&&\s*pwd\)/({_TAIL})'
)
# 一個變數的值只有這四種寫法追得回這支腳本自己的位置。第一種與第二種直接從 `$0` 算起，
# 第三與第四種從另一個已經解得出來的變數接下去。**其餘一律當成追不回來**——
# `SCRIPT_DIR="$WORKSPACE_ROOT/scripts"` 那種，值來自別的地方，猜它等於製造假綠。
# 以前的版本對認不出來的賦值一律退回「就是同目錄」，而那個猜測在樹上剛好每次都對，
# 於是它看起來像解析。一個猜對的東西跟一個解對的東西，在輸出上長得一模一樣。
ASSIGN_SELF = re.compile(
    rf'({ANY_VAR})=\s*"?\$\(cd\s+"\$\(dirname[^)]*\)((?:/\.\.)*)"?\s*&&\s*pwd\)'
)
ASSIGN_DIRNAME = re.compile(
    rf'({ANY_VAR})=\s*"?\$\(dirname\s+"?\$\{{?(?:0|BASH_SOURCE\[0\])\}}?"?\)'
)
ASSIGN_CHAIN = re.compile(
    rf'({ANY_VAR})=\s*"?\$\(cd\s+"\$\{{?({ANY_VAR})\}}?((?:/\.\.)*)"\s*&&\s*pwd\)'
)
ASSIGN_SUFFIX = re.compile(
    rf'({ANY_VAR})=\s*"\$\{{?({ANY_VAR})\}}?/([\w./-]+)"'
)
# 重新指派不一定在行首：`--repo) REPO_PATH="$2"; shift 2 ;;` 就在 case 分支裡，而它是
# 這個變數真正的值來源。綁行首會漏掉它，然後把一個 runtime 才知道的值當成解出來了。
# 前面不能是 `-`（`--repo=*` 那種樣式）、字母數字、`$` 或引號。
ASSIGN_ANY = re.compile(rf'(?<![\w$"\'\-])(?:local\s+|export\s+)?({ANY_VAR})=(?!=)')
CODE_SUFFIXES = (".sh", ".py", ".mjs")
HEREDOC_OPEN = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
# 存在性檢查：`[[ -f X ]]`、`[ -d X ]`、`test -x X`。被它包住的引用是候選，不是要求。
EXISTS_TEST = re.compile(r"(\[\[?\s+-[efdrwxsLhp]\b|\btest\s+-[efdrwxsLhp]\b)")
FOR_OPEN = re.compile(r"^\s*for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b")
# 這一行是在**建立**那個東西，不是在讀它。要求它先存在會噴假紅。
CREATE_CMD = re.compile(r"\b(mkdir|touch|install\s+-d)\b")
REDIRECT_TAIL = re.compile(r">>?\s*\"?$")
# 一組候選要在 `do` 之後幾行內看到對迴圈變數的存在性檢查才算被包住。窗口刻意小：
# 拉大只會把不相干的檢查算進來，而那會讓一組真的沒被包住的候選變成綠的。
GUARD_LOOKAHEAD = 12
# 被存在性檢查問過的引用相隔幾行以內算同一組候選。刻意小：拉大會把兩個不相干的探測併成
# 一組，而那時候其中一個命中就會讓另一個永遠不被判定。
GUARD_CHAIN_GAP = 4


def blank_heredocs(lines):
    """把 heredoc 的內容換成空行，行號保留。

    heredoc 裡的東西是要寫到別的地方去的資料，不是這個檔自己的引用——selftest 的
    fixture 就長這樣，不排掉的話這道閘會擋下自己的 selftest。**換成空行而不是刪掉**：
    行號要留著，否則 DISCLOSURE 與紅字指的行數是錯的，而那比不指行數糟。

    Args: lines = 原始檔案的每一行
    Returns: 同長度的 list，heredoc body 的位置是空字串
    """
    out, delimiter = [], None
    for line in lines:
        if delimiter is None:
            out.append(line)
            match = HEREDOC_OPEN.search(line)
            if match:
                delimiter = match.group(1)
        elif line.strip() == delimiter:
            out.append(line)
            delimiter = None
        else:
            out.append("")
    return out


def resolve_self_dirs(lines, here):
    """算出哪些變數的值追得回這支腳本自己的位置、以及追到哪裡。

    逐行往下走，因為變數會接著另一個變數（`SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"`）。
    認不出來的賦值把那個變數整支標成不自明——同一個變數在同一個檔裡被重新指派過（`--skills)
    SKILLS_DIR="${2:-}"`）也算，因為那之後它指向哪要看有沒有帶那個旗標。

    Args: lines = 已經把 heredoc 換成空行的每一行；here = 這個檔所在的目錄
    Returns: 變數名（大寫）到目錄的 dict。不自明的變數**不在裡面**——「解不出來」與
        「解出來是同目錄」必須長得不一樣，否則下游分不出猜的跟解的。
    """
    base_of, opaque = {}, set()
    for line in lines:
        if not ASSIGN_ANY.search(line):
            continue
        match = ASSIGN_SELF.search(line)
        if match:
            resolved = here
            for _ in range(match.group(2).count("..")):
                resolved = os.path.dirname(resolved)
            base_of[match.group(1).upper()] = resolved
            continue
        match = ASSIGN_DIRNAME.search(line)
        if match:
            base_of[match.group(1).upper()] = here
            continue
        match = ASSIGN_CHAIN.search(line)
        if match and match.group(2).upper() in base_of:
            resolved = base_of[match.group(2).upper()]
            for _ in range(match.group(3).count("..")):
                resolved = os.path.dirname(resolved)
            base_of[match.group(1).upper()] = resolved
            continue
        match = ASSIGN_SUFFIX.search(line)
        if match and match.group(2).upper() in base_of:
            base_of[match.group(1).upper()] = os.path.normpath(
                os.path.join(base_of[match.group(2).upper()], match.group(3))
            )
            continue
        opaque.add(ASSIGN_ANY.search(line).group(1).upper())
    # 被標成不自明的就不留一個猜出來的值——留著等於讓下游以為它解出來了。
    for name in opaque:
        base_of.pop(name, None)
    return base_of


def in_comment(line, start):
    """這個位置是不是落在註解裡。

    判準是它前面有沒有一個 `#`，而那個 `#` 在行首或前面是空白，且不在字串裡（用它前面的
    引號數是不是偶數判斷）。註解裡的路徑常常在**否認**某件事——「這一版之前會把 X 判紅」——
    對它判紅的閘會在三次之後被關掉。

    Args: line = 整行, start = 引用在行內的起始位置
    Returns: True 表示在註解裡
    """
    head = line[:start]
    for i, char in enumerate(head):
        if char != "#":
            continue
        if i and head[i - 1] not in " \t":
            continue
        if head[:i].count('"') % 2 or head[:i].count("'") % 2:
            continue
        return True
    return False


def guarded_for_spans(lines):
    """找出「候選清單」的行範圍。

    形狀是 `for VAR in \\ <多行清單> do` 而且 `do` 之後幾行內有對 `$VAR` 的存在性檢查。
    清單裡的每一條都是同一組候選——所以它們要一起判，全落空才紅。

    Args: lines = 已經把 heredoc 換成空行的每一行
    Returns: list of (start_index, end_index) —— 半開區間，涵蓋 `for` 到 `do`
    """
    spans = []
    for index, line in enumerate(lines):
        match = FOR_OPEN.match(line)
        if not match:
            continue
        var = match.group(1)
        end = index
        while end < len(lines) and not re.search(r"(^|\s|;)do\s*$", lines[end]):
            end += 1
            if end - index > 40:
                break
        if end >= len(lines):
            continue
        window = "\n".join(lines[end : end + GUARD_LOOKAHEAD])
        if EXISTS_TEST.search(window) and re.search(rf"\$\{{?{var}\}}?\b", window):
            spans.append((index, end + 1))
    return spans


# GIT_DIR 要拿掉：git 跑 hook 的時候一定會設它，而顯式的 GIT_DIR 蓋過 `-C`——這道閘會
# 安靜地列出另一個 repo 的檔案。DP-467 對十支腳本修過同一個形狀。
listed = subprocess.run(
    ["git", "-C", repo_root, "ls-files", scope],
    capture_output=True, text=True, check=True,
    env={k: v for k, v in os.environ.items()
         if k not in ("GIT_DIR", "GIT_WORK_TREE")},
).stdout.split()
if only_skill and not listed:
    print(f"{prefix} 量不到：版控裡沒有 {scope}。", file=sys.stderr)
    sys.exit(2)

skipped = collections.Counter()
problems = []
judged = 0
group_count = 0
scanned = 0

for rel in listed:
    if not rel.endswith(CODE_SUFFIXES):
        continue
    path = os.path.join(repo_root, rel)
    try:
        raw = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    scanned += 1
    here = os.path.dirname(path)
    lines = blank_heredocs(raw.split("\n"))
    body = "\n".join(lines)

    # 變數不一定指向自己那一層。`script_dir="$(cd "$(dirname "$0")/.." && pwd)"` 在
    # selftest 裡很常見——它指的是 scripts/，不是 selftests/。照著它的 `..` 往上退，
    # 不然這道閘會對一批寫得完全正確的 selftest 判紅。
    #
    # 這個洞原本被一份重複的檔遮著：同一支腳本在 scripts/ 與 scripts/selftests/ 各有一份，
    # 於是錯的解析也找得到檔案。刪掉重複的那一刻它才露出來。
    base_of = resolve_self_dirs(lines, here)

    spans = guarded_for_spans(lines)
    refs = []
    for index, line in enumerate(lines):
        found = []
        for match in REF_VAR.finditer(line):
            name = match.group(1).upper()
            if name in base_of:
                found.append((match.start(), base_of[name], match.group(2)))
                continue
            # 解不出這個變數指向哪，就不猜。在註解裡的那些先歸註解那一類，因為
            # 註解裡的路徑常常在否認某件事，而那跟「值不自明」是兩個不同的原因。
            if in_comment(line, match.start()):
                skipped["註解裡"] += 1
            elif SELF_DIR_NAME.match(match.group(1)):
                skipped["路徑不自明（變數解不出來、帶展開或 glob）"] += 1
            else:
                skipped["變數的值追不回這支腳本自己的位置"] += 1
        for match in REF_INLINE.finditer(line):
            base = here
            for _ in range(match.group(1).count("..")):
                base = os.path.dirname(base)
            found.append((match.start(), base, match.group(2)))
        for start, base, tail in found:
            if in_comment(line, start):
                skipped["註解裡"] += 1
                continue
            if "$" in tail or "*" in tail or "?" in tail:
                skipped["路徑不自明（變數解不出來、帶展開或 glob）"] += 1
                continue
            # `${SUBJECT_OVERRIDE:-$SCRIPTS/x.sh}` 的尾段會多帶一個外層的收合括號。
            clean = tail.rstrip("/")
            if clean.endswith("}") and "{" not in clean:
                clean = clean[:-1]
            if not [s for s in clean.split("/") if s not in ("", ".", "..")]:
                skipped["純往上爬（沒指名任何東西）"] += 1
                continue
            head = line[:start]
            if CREATE_CMD.search(head) or REDIRECT_TAIL.search(head):
                skipped["這一行在建立它，不是在讀它"] += 1
                continue
            target = os.path.realpath(os.path.join(base, clean))
            if target != repo_root and not target.startswith(repo_root + os.sep):
                skipped["解析後落到 repo 之外"] += 1
                continue
            refs.append({
                "line": index + 1,
                "tail": clean,
                "target": target,
                "tested": bool(EXISTS_TEST.search(line)),
                "span": next((s for s in spans if s[0] <= index < s[1]), None),
            })

    # 被存在性檢查問過的目標，在這個檔裡的每一次出現都是候選——`if [[ -f X ]]; then . X; fi`
    # 的第二行沒有帶檢查，但它跟第一行問的是同一個東西。只看單行的話那一行會被判成要求。
    tested_targets = {r["target"] for r in refs if r["tested"]}

    # 一組候選是**寫在一起的那幾條**，不是「同一個目標的那幾條」。第一版用目標當鍵，於是
    # `if [[ -f a ]] … elif [[ -f b ]] …` 這種鏈被切成兩組各一個目標，兩組都變成不判定——
    # 而它跟 `for candidate in a b` 是同一件事。所以改用相鄰性：被存在性檢查問過的引用，
    # 彼此相隔不超過 GUARD_CHAIN_GAP 行的算同一組（可遞移）。
    chain_of = {}
    guarded = sorted((r for r in refs if r["target"] in tested_targets),
                     key=lambda r: r["line"])
    chain = 0
    for position, ref in enumerate(guarded):
        if position and ref["line"] - guarded[position - 1]["line"] > GUARD_CHAIN_GAP:
            chain += 1
        chain_of[id(ref)] = chain

    groups = collections.OrderedDict()
    for ref in refs:
        if ref["span"] is not None:
            key = ("candidates", ref["span"][0])
        elif id(ref) in chain_of:
            key = ("guarded", chain_of[id(ref)])
        else:
            key = ("required", ref["line"], ref["tail"])
        groups.setdefault(key, []).append(ref)

    for key, members in groups.items():
        if key[0] != "required":
            group_count += 1
        if any(os.path.exists(m["target"]) for m in members):
            judged += len(members)
            continue
        if key[0] == "required":
            judged += len(members)
            problems.append(f"  {rel}:{members[0]['line']} -> {members[0]['tail']}")
            continue
        # 一組候選有兩個以上不同的目標、而全部落空：作者自己寫下了「我預期其中一個在這裡」，
        # 而沒有一個在，所以那是矛盾，判得出來。
        #
        # 只有一個目標的時候沒有那句話可以拿來對照，**這道閘分不出兩件事**：一條永遠走不到
        # 的 fallback（`fetch-pr-info.sh` 那種，REST 路徑死了幾個月），以及一個本來就該落空
        # 的探測（DP-513 當時的標本是 `polaris-toolchain.sh:18`，問的是「這個 skill 目錄自己
        # 是不是 workspace 根」——在那棵樹上答案就是不是，而 manifest 真的存在、在 repo 根）。
        # 兩者的形狀一模一樣，差別只在意圖。所以這一類不判定，進 DISCLOSURE。
        #
        # 那個標本 DP-518 退場了（那支 runner 的 parser 在更早一次搬家就被刪掉，整支是屍體），
        # 所以這一格的計數現在是 0——樹上活著的實例歸零，紅控只剩 selftest 的 fixture。
        # 這不改變判準，但它是下一次問「這道閘擋得住什麼」時該先讀到的話。
        if len({m["target"] for m in members}) < 2:
            skipped["只有一條候選而它落空（死 fallback 與該落空的探測分不出來）"] += 1
            continue
        judged += len(members)
        where = ",".join(str(m["line"]) for m in members)
        listing = "、".join(m["tail"] for m in members)
        problems.append(
            f"  {rel}:{where} -> 這一組候選 {len(members)} 條全部落空：{listing}"
        )

if scanned == 0:
    print(f"{prefix} 量不到：{scope} 底下沒有掃得到的腳本。", file=sys.stderr)
    print(f"{prefix} 這是掃描壞了，不是這個 repo 真的沒有腳本。", file=sys.stderr)
    sys.exit(2)

# 判不了的那幾類每次都印，綠的那一次也印——綠的時候才是最容易被讀成「掃完了」的時候。
CLASSES = [
    "純往上爬（沒指名任何東西）",
    "路徑不自明（變數解不出來、帶展開或 glob）",
    "解析後落到 repo 之外",
    "註解裡",
    "這一行在建立它，不是在讀它",
    "變數的值追不回這支腳本自己的位置",
    "只有一條候選而它落空（死 fallback 與該落空的探測分不出來）",
]
disclosure = "、".join(f"{name} {skipped[name]}" for name in CLASSES)
print(f"{prefix} DISCLOSURE 這道閘判不了的幾類，各自的條數：{disclosure}。"
      f"不判定不等於沒有那些東西——那幾條由看 diff 的人負責，不由這道閘。")
# 紅字走 stderr、揭露走 stdout，兩條管子各自有緩衝——不沖的話揭露會印在紅字後面，
# 讀的人會以為那是這次判定的結論。
sys.stdout.flush()

if problems:
    print(f"{prefix} 引用指向不存在的東西：", file=sys.stderr)
    print("\n".join(sorted(set(problems))), file=sys.stderr)
    print(f"{prefix} ❌ {len(set(problems))} 個斷掉的引用"
          f"（掃了 {scanned} 個檔、判了 {judged} 條）", file=sys.stderr)
    raise SystemExit(1)

print(f"{prefix} ✅ {judged} 條指名的引用都對得上"
      f"（{scanned} 個檔，其中 {group_count} 組是被存在性檢查包住的候選）。")
PY
