#!/usr/bin/env bash
# request-pr-review-shape-selftest.sh — DP-515 的斷言，一條一個 case。
#
# Usage: request-pr-review-shape-selftest.sh --assertion <ID>
#        request-pr-review-shape-selftest.sh --list
#        request-pr-review-shape-selftest.sh              （不帶參數＝跑全部）
#
# Exit: 0 這條成立 / 1 這條不成立 / 2 量不到（前置條件沒到，不得被讀成成立）
#
# 這一支量的是**這支 skill 長什麼形狀**：名字說不說得出它在做什麼、目錄裡剩下的東西是不是
# 都被那三步用得到。行為本身由同目錄的 request-pr-review-selftest.sh 量（DP-511 的 18 條），
# 這裡不重複——A-N1 直接把那一支整套跑一遍當作「改名沒改行為」的證據。
#
# 每個 case 至少印一行 `MEASURED …`，說出它真的量到了什麼。掃不到目標、樣本數 0 一律走
# exit 2，不走 exit 0：一個什麼都沒掃到的負向檢查，跟一個掃過而且乾淨的檢查在輸出上長得
# 一模一樣。

set -uo pipefail

SELFTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELFTEST_DIR/.." && pwd)"
SKILL_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
SKILLS_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SKILLS_ROOT/../.." && pwd)"

# 這支 skill 改名前叫什麼。它不是外部座標，是這張單自己的主題——「舊名字有沒有清乾淨」
# 這個問題沒有第二個問法。
OLD_SKILL_NAME="check-pr-approvals"
NEW_SKILL_NAME="request-pr-review"

# 唯讀動詞：以這些開頭的名字讀起來像「只是去看一眼」，而這支會把訊息送出去。
READ_ONLY_VERBS="check list show get view scan read status query fetch"

# 同一個座標系上的三支：誰看誰的 PR。
SIBLING_SKILLS="review-pr review-inbox ${NEW_SKILL_NAME}"

# 這張單從這支 skill 底下刪掉的東西，分兩種——它們的「刪對了沒」問法不一樣。
# 有複本的：別處那幾份要還在而且彼此逐位元組相同（DP-467 H-N1：複本是對的，漂才是病）。
# 這裡獨有的：全樹要零命中，不然就是刪掉了還有人在找。
DUPLICATED_ELSEWHERE="gate-pr-language.sh pr-state-snapshot.sh resolve-pr-work-source.sh sync-spec-sidebar-metadata.sh validate-specs-collection-shape.sh specs-root.sh validate_specs_collection_shape_1.py"
UNIQUE_AND_UNREFERENCED="pr-action-classifier.sh pr-review-state-classifier.sh pr-state-contract.md"

# 舊名字不掃這幾處，理由各自不同，逐條印出來——一個沒說出口的豁免，跟沒有豁免在出事的
# 時候長得一樣。
NAME_SCAN_SKIPS="CHANGELOG.md 與 .changeset/（歷史紀錄：那幾版當時就叫那個名字，而宣告改名的那一則本來就得說出舊名字；改掉等於竄改） docs-manager/（另一個 repo 的稽核封存） issues/（單的內文講的就是這次改名） node_modules/（不是我們的東西） selftests/（舊名字是這一支的題目，問不出口就沒有人在問）"

list_assertions() {
  grep -oE '^  [A-B]-[PN][0-9][A-B|PN0-9-]*\)' "$1" | tr -d ' )' | tr '|' '\n' | grep -E '^[A-B]-[PN][0-9]$'
}

ASSERTION=""
case "${1:-}" in
  "")
    rc=0; failed=""; unmeasured=""
    for one in $(list_assertions "$0"); do
      out="$(bash "$0" --assertion "$one" 2>&1)"; case "$?" in
        0) printf '  ✅ %s\n' "$one" ;;
        2) printf '  ❔ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; unmeasured="${unmeasured}${one} " ;;
        *) printf '  ❌ %s — %s\n' "$one" "$(printf '%s' "$out" | tail -1)"; failed="${failed}${one} "; rc=1 ;;
      esac
    done
    [[ -z "$unmeasured" ]] || echo "量不到（不是過）：${unmeasured}" >&2
    [[ -z "$failed" ]] || echo "沒過：${failed}" >&2
    exit "$rc" ;;
  --list) list_assertions "$0"; exit 0 ;;
  --assertion) ASSERTION="${2:-}" ;;
  *) echo "用法：$0 [--assertion <ID>] [--list]" >&2; exit 2 ;;
esac
[[ -n "$ASSERTION" ]] || { echo "要 --assertion" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -f -r "$WORK"' EXIT

measured() { echo "MEASURED $*"; }
fail() { echo "FAILED $*" >&2; exit 1; }
unmeasurable() { echo "UNMEASURABLE $*" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || unmeasurable "沒有 python3，這一條量不到"

# SKILL.md frontmatter 的 name。剖析走 python3：frontmatter 是 YAML，而 description 那一段
# 有多行與引號，用 sed 抓行會把它吃進來。
frontmatter_name() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"\A---\n(.*?)\n---\n", text, re.S)
if not m:
    sys.exit(1)
n = re.search(r"^name:\s*(\S+)\s*$", m.group(1), re.M)
print(n.group(1) if n else "")
PY
}

# 這張單改動的 base。用 merge-base 問 git，不假設任何一條分支的名字之外的東西。
# 併回主幹之後就沒有 diff 可看了——那時候這幾條回「量不到」，那是真話，不是紅。
diff_base() {
  git -C "$REPO_ROOT" merge-base HEAD main 2>/dev/null
}

# ---------------------------------------------------------------- A：名字

case "$ASSERTION" in

  A-P1)
    # 名字要說出那三步，而且要讀得出它會送東西出去。
    md="$SKILL_DIR/SKILL.md"
    [[ -f "$md" ]] || unmeasurable "找不到 $md"
    dir_name="$(basename "$SKILL_DIR")"
    fm_name="$(frontmatter_name "$md")"
    [[ -n "$fm_name" ]] || unmeasurable "SKILL.md 的 frontmatter 讀不到 name"
    [[ "$dir_name" == "$fm_name" ]] \
      || fail "目錄叫 ${dir_name}，frontmatter 說 ${fm_name}——兩個名字就是兩支 skill"
    first_token="${fm_name%%-*}"
    for verb in $READ_ONLY_VERBS; do
      [[ "$first_token" != "$verb" ]] \
        || fail "名字以唯讀動詞「${verb}」開頭，但這支會把訊息送出去"
    done
    case "$fm_name" in
      *review*) ;;
      *) fail "名字裡沒有 review——讀不出它處理的是什麼" ;;
    esac
    case "$fm_name" in
      *pr*|*PR*) ;;
      *) fail "名字裡沒有 pr——讀不出它處理的是什麼" ;;
    esac
    measured "名字「${fm_name}」與目錄同名；不以 ${READ_ONLY_VERBS// /、} 這幾個唯讀動詞開頭；帶著 review 與 pr"
    ;;

  A-P2)
    # 三支各佔一格，而且那個座標系是互相寫下來的——每一支都要指得出另外兩支。
    missing=""
    for s in $SIBLING_SKILLS; do
      [[ -f "$SKILLS_ROOT/$s/SKILL.md" ]] || missing="${missing}${s} "
    done
    [[ -z "$missing" ]] || unmeasurable "這幾支不在這棵樹上，量不到座標系：${missing}"
    for s in $SIBLING_SKILLS; do
      for other in $SIBLING_SKILLS; do
        [[ "$s" != "$other" ]] || continue
        grep -qF "$other" "$SKILLS_ROOT/$s/SKILL.md" \
          || fail "${s}/SKILL.md 沒有提到 ${other}——三支之中有一支不知道另外那一格是誰"
      done
    done
    measured "$(echo $SIBLING_SKILLS | tr ' ' '、') 三支都在，而且每一支都指得出另外兩支"
    ;;

  A-P3)
    # 全樹不得再出現舊名字。掃出來的東西要有量，不然這一條在一棵空樹上也會綠。
    scanned="$WORK/scanned.txt"
    ( cd "$REPO_ROOT" && git ls-files ) > "$scanned" 2>/dev/null \
      || unmeasurable "問不到版控裡有哪些檔案，這一條量不到"
    total="$(wc -l < "$scanned" | tr -d ' ')"
    [[ "$total" -gt 0 ]] || unmeasurable "版控裡一個檔案都沒有，這一條量不到"
    hits="$WORK/hits.txt"; : > "$hits"
    while IFS= read -r f; do
      case "$f" in
        CHANGELOG.md|.changeset/*|docs-manager/*|issues/*|*/node_modules/*|node_modules/*|*/selftests/*) continue ;;
      esac
      [[ -f "$REPO_ROOT/$f" ]] || continue
      grep -qF "$OLD_SKILL_NAME" "$REPO_ROOT/$f" 2>/dev/null && echo "$f" >> "$hits"
    done < "$scanned"
    if [[ -s "$hits" ]]; then
      fail "還有 $(wc -l < "$hits" | tr -d ' ') 個檔案指著舊名字「${OLD_SKILL_NAME}」：$(tr '\n' ' ' < "$hits")"
    fi
    measured "掃過版控裡 ${total} 個檔案，沒有一個還指著「${OLD_SKILL_NAME}」；不掃：${NAME_SCAN_SKIPS}"
    ;;

  A-N1)
    # 改名不改行為：DP-511 那 18 條整套重跑一次。
    behaviour_suite="$SELFTEST_DIR/${NEW_SKILL_NAME}-selftest.sh"
    [[ -f "$behaviour_suite" ]] || unmeasurable "找不到行為那一套：$behaviour_suite"
    count="$(bash "$behaviour_suite" --list 2>/dev/null | grep -c .)"
    [[ "$count" -gt 0 ]] || unmeasurable "行為那一套列不出任何斷言，量不到"
    # 那一套裡有幾條要呼叫者給座標（POLARIS_PR_CONTEXT_REPOS）。這裡原樣往下傳，不自己
    # 填一個——一個把公司 repo 名寫死在檢查裡的檢查，正是 DP-511 A-N1 擋的東西。
    out="$WORK/behaviour.txt"
    if ! bash "$behaviour_suite" > "$out" 2>&1; then
      fail "行為那一套有紅的：$(grep -E '❌|沒過' "$out" | tr '\n' ' ')"
    fi
    if grep -q '量不到' "$out"; then
      # 不判紅也不判過：那幾條量不到，是因為呼叫者沒給座標，跟「改名有沒有改行為」無關。
      # 把它讀成過，等於用一個沒跑完的樣本宣稱行為沒變。
      unmeasurable "行為那一套有量不到的（要座標的那幾條需要 POLARIS_PR_CONTEXT_REPOS）：$(grep '量不到' "$out" | tr '\n' ' ')"
    fi
    measured "行為那 ${count} 條全綠——輸出欄位與退出碼沒有因為改名而變"
    ;;

  A-N2)
    # 不留舊名字的目錄、檔案或 symlink。
    leftovers="$(find "$SKILLS_ROOT" -name "*${OLD_SKILL_NAME}*" 2>/dev/null | tr '\n' ' ')"
    [[ -z "$leftovers" ]] || fail "skill 樹裡還有叫舊名字的東西：${leftovers}"
    links="$WORK/links.txt"
    find "$SKILLS_ROOT" -maxdepth 2 -type l > "$links" 2>/dev/null
    while IFS= read -r l; do
      [[ -n "$l" ]] || continue
      target="$(cd "$(dirname "$l")" && cd "$(readlink "$l")" 2>/dev/null && pwd)" || continue
      [[ "$target" != "$SKILL_DIR" ]] \
        || fail "有一個 symlink 用別的名字指著這支 skill：$l"
    done < "$links"
    measured "skill 樹裡沒有叫「${OLD_SKILL_NAME}」的東西，也沒有用別的名字指過來的 symlink（掃過 $(grep -c . "$links") 個 symlink）"
    ;;

# ---------------------------------------------------------------- B：只剩用得到的東西

  B-P1)
    # 從 SKILL.md 指名的腳本出發做遞移閉包，跟 scripts/ 底下實際有的東西比。
    reach="$WORK/reach.txt"
    python3 - "$SKILL_DIR" > "$reach" <<'PY'
import os, re, sys

skill = sys.argv[1]
scripts = os.path.join(skill, "scripts")

# 起點：SKILL.md 與 references/ 指名的 scripts/… 路徑。散文也是入口——語言閘就是散文
# 指名的，只讀 SKILL.md 會把它算成不可達。
seeds = set()
prose = [os.path.join(skill, "SKILL.md")]
refdir = os.path.join(skill, "references")
if os.path.isdir(refdir):
    prose += [os.path.join(refdir, f) for f in os.listdir(refdir) if f.endswith(".md")]
for p in prose:
    if not os.path.isfile(p):
        continue
    for m in re.findall(r"scripts/([A-Za-z0-9_./-]+\.(?:sh|py))", open(p, encoding="utf-8").read()):
        seeds.add(m)

# 逐層追腳本自己引用的同目錄檔案。
seen, queue = set(), list(seeds)
while queue:
    rel = queue.pop()
    if rel in seen:
        continue
    seen.add(rel)
    path = os.path.join(scripts, rel)
    if not os.path.isfile(path):
        continue
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    for m in re.findall(r"(?:lib/)?[A-Za-z0-9_-]+\.(?:sh|py)", text):
        cand = m
        for prefix in ("", "lib/"):
            if os.path.isfile(os.path.join(scripts, prefix + cand)):
                queue.append(prefix + cand)
                break

for rel in sorted(seen):
    if os.path.isfile(os.path.join(scripts, rel)):
        print(rel)
PY
    [[ -s "$reach" ]] || unmeasurable "從散文出發追不到任何腳本，這一條量不到"
    actual="$WORK/actual.txt"
    ( cd "$SKILL_DIR/scripts" && find . -type f \( -name '*.sh' -o -name '*.py' \) \
        -not -path './selftests/*' | sed 's|^\./||' | sort ) > "$actual"
    [[ -s "$actual" ]] || unmeasurable "scripts/ 底下一個腳本都沒有，這一條量不到"
    orphans="$(comm -13 <(sort "$reach") "$actual" | tr '\n' ' ')"
    [[ -z "$orphans" ]] \
      || fail "這幾支在 scripts/ 底下，但那三步到不了：${orphans}"
    measured "scripts/ 底下 $(grep -c . "$actual") 支（selftests/ 不算，它是量測不是那三步），全部從 SKILL.md 追得到"
    ;;

  B-P2)
    # 刪掉的東西不會讓別人壞掉：有複本的，複本還在而且彼此逐位元組相同；獨有的，全樹零命中。
    for n in $DUPLICATED_ELSEWHERE; do
      copies="$WORK/copies.txt"
      find "$SKILLS_ROOT" -name "$n" -type f 2>/dev/null | sort > "$copies"
      [[ -s "$copies" ]] || fail "「${n}」在別的 skill 也不見了——這張單只該刪自己這一份"
      grep -q "^${SKILL_DIR}/" "$copies" \
        && fail "「${n}」還在 ${NEW_SKILL_NAME} 底下，沒有刪掉"
      sums="$(while IFS= read -r c; do md5 -q "$c" 2>/dev/null || md5sum "$c" | cut -d' ' -f1; done < "$copies" | sort -u | wc -l | tr -d ' ')"
      [[ "$sums" == "1" ]] \
        || fail "「${n}」的 $(grep -c . "$copies") 份複本彼此不一樣——漂掉了（DP-467 H-N1）"
    done
    for n in $UNIQUE_AND_UNREFERENCED; do
      # selftests/ 不算：那裡指名被刪的檔案，正是它在做的事——「這幾個刪乾淨了沒」這個
      # 問題問不出口的話，就沒有人在問它。
      hits="$(grep -rlF "$n" "$SKILLS_ROOT" 2>/dev/null | grep -v '/selftests/' | tr '\n' ' ')"
      [[ -z "$hits" ]] || fail "刪掉的「${n}」還有人在找：${hits}"
    done
    measured "有複本的 $(echo $DUPLICATED_ELSEWHERE | wc -w | tr -d ' ') 個：複本都還在而且彼此逐位元組相同；獨有的 $(echo $UNIQUE_AND_UNREFERENCED | wc -w | tr -d ' ') 個：全樹零命中（selftests/ 不算，被刪的檔名是它的題目）"
    ;;

  B-P3)
    # references/ 與 Lazy-load Map 要一一對上：多出來的是孤兒，少掉的是指向不存在的東西。
    md="$SKILL_DIR/SKILL.md"
    [[ -f "$md" ]] || unmeasurable "找不到 $md"
    listed="$WORK/listed.txt"
    grep -oE 'references/[A-Za-z0-9_.-]+\.md' "$md" | sed 's|^references/||' | sort -u > "$listed"
    [[ -s "$listed" ]] || unmeasurable "SKILL.md 一份 reference 都沒指名，這一條量不到"
    present="$WORK/present.txt"
    ( cd "$SKILL_DIR/references" 2>/dev/null && ls -1 *.md 2>/dev/null | sort ) > "$present"
    [[ -s "$present" ]] || unmeasurable "references/ 底下一份都沒有，這一條量不到"
    orphan="$(comm -13 "$listed" "$present" | tr '\n' ' ')"
    [[ -z "$orphan" ]] || fail "這幾份 reference 沒有人指名，是孤兒：${orphan}"
    dangling="$(comm -23 "$listed" "$present" | tr '\n' ' ')"
    [[ -z "$dangling" ]] || fail "Lazy-load Map 指著不存在的 reference：${dangling}"
    measured "references/ $(grep -c . "$present") 份與 Lazy-load Map $(grep -c . "$listed") 列一一對上"
    ;;

  B-N1)
    # 不動別的 skill 的複本：那五個名字在別的 skill 底下都還在，而且沒有一份落在這支底下。
    kept=0
    for n in $DUPLICATED_ELSEWHERE; do
      elsewhere="$(find "$SKILLS_ROOT" -name "$n" -type f -not -path "${SKILL_DIR}/*" 2>/dev/null | wc -l | tr -d ' ')"
      [[ "$elsewhere" -gt 0 ]] || fail "「${n}」在別的 skill 底下一份都不剩了"
      kept=$((kept + elsewhere))
    done
    # 這一條原本還有第二半：比 `merge-base(HEAD, main)..HEAD`，只要這張單在本 skill 以外
    # 刪掉任何檔案就判紅。那一半**拿掉了**，而且不是因為它擋錯人——是因為它問的問題在
    # 這裡問不出來。
    #
    # 「這張單」指的是寫下它的 DP-515。一支常駐的 selftest 手上永遠只有「當下這條分支對
    # 主幹的 diff」，它分不出那是 DP-515 還是後來的任何一張單。所以 DP-515 併回主幹之後，
    # 這一半對每一張後來的單都是誤判：DP-518 退場一支死掉的 runner 時被判紅，訊息說
    # 「這張單在 request-pr-review 以外刪了東西」——那次刪除跟這支 skill 沒有半點關係。
    #
    # 「先問 diff 有沒有動到這支 skill，動到才判」也不成立，DP-518 當場試過：改這支
    # selftest 本身就算動到，於是同一個誤判立刻回來。一條單票範圍的負向斷言沒有辦法用
    # 常駐 selftest 表達——它的紅控是那張單的 PR diff，由看 diff 的人負責，不由這裡。
    #
    # 留下來的是它真正還成立的那一半：那幾份複本現在還在不在。這一條說得出自己只做了
    # 一半，因為一個安靜地縮水的負向檢查，跟一個完整的負向檢查在輸出上長得一樣。
    measured "別的 skill 底下留著 ${kept} 份複本（「這張單有沒有刪到別人家」那一半由 PR diff 判，不由常駐 selftest 判——理由見這一格的註解）"
    ;;

  B-N2)
    # 不留指向不存在的東西的話。兩道閘就是問這件事的，跑它們，不自己寫第二套。
    gates_dir="$SKILLS_ROOT/framework-release/scripts"
    ran=0
    for g in gate-skill-script-references.sh gate-prose-matches-behaviour.sh; do
      [[ -f "$gates_dir/$g" ]] || continue
      bash "$gates_dir/$g" > "$WORK/$g.out" 2>&1 \
        || fail "${g} 判紅：$(tail -3 "$WORK/$g.out" | tr '\n' ' ')"
      ran=$((ran + 1))
    done
    [[ "$ran" -gt 0 ]] || unmeasurable "這棵樹上沒有那兩道閘，這一條量不到"
    inside="$WORK/inside.txt"; : > "$inside"
    for n in $DUPLICATED_ELSEWHERE $UNIQUE_AND_UNREFERENCED; do
      grep -rlF "$n" "$SKILL_DIR" 2>/dev/null | grep -v '/selftests/' >> "$inside"
    done
    if [[ -s "$inside" ]]; then
      fail "這支 skill 裡還有句子指名被刪的檔案：$(sort -u "$inside" | tr '\n' ' ')"
    fi
    measured "${ran} 道閘綠；這支 skill 裡沒有一句話指名那 $(echo $DUPLICATED_ELSEWHERE $UNIQUE_AND_UNREFERENCED | wc -w | tr -d ' ') 個被刪的檔案（selftests/ 不算）"
    ;;

  B-N3)
    # 不順手改行為：留下來的腳本，這張單只動得了註解。
    base="$(diff_base)"
    [[ -n "$base" ]] || unmeasurable "問不到這張單的 base（併回主幹之後沒有 diff 可看），這一條量不到"
    # 配對交給 git 自己算（-M --name-status），不用「把新路徑的 skill 名換成舊的」去推。
    # 只給新路徑當 pathspec 的那一版，git 看不到舊路徑，於是每一支都被算成整支新增——
    # 而那看起來會像「每一支都被大改了」。
    pairs="$WORK/pairs.txt"
    git -C "$REPO_ROOT" diff -M --name-status "$base"..HEAD -- ".claude/skills" > "$pairs" 2>/dev/null
    [[ -s "$pairs" ]] || unmeasurable "這張單在 .claude/skills 底下沒有改到任何東西，沒有樣本"
    scanned=0; bad=""
    while IFS=$'\t' read -r status a b; do
      case "$status" in
        R*) old_path="$a"; new_path="$b" ;;
        M)  old_path="$a"; new_path="$a" ;;
        *)  continue ;;
      esac
      case "$new_path" in
        ".claude/skills/${NEW_SKILL_NAME}/scripts/"*) ;;
        *) continue ;;
      esac
      case "$new_path" in */selftests/*) continue ;; esac
      scanned=$((scanned + 1))
      git -C "$REPO_ROOT" show "$base:$old_path" > "$WORK/old.blob" 2>/dev/null || continue
      git -C "$REPO_ROOT" show "HEAD:$new_path" > "$WORK/new.blob" 2>/dev/null || continue
      code_lines="$(diff "$WORK/old.blob" "$WORK/new.blob" \
        | grep -E '^[<>]' | grep -vE '^[<>][[:space:]]*#' | grep -vE '^[<>][[:space:]]*$' | wc -l | tr -d ' ')"
      [[ "$code_lines" == "0" ]] || bad="${bad}${new_path}(${code_lines} 行) "
    done < "$pairs"
    [[ "$scanned" -gt 0 ]] || unmeasurable "這張單沒有改到任何一支留下來的腳本，沒有樣本"
    [[ -z "$bad" ]] || fail "這幾支被改到的不只是註解：${bad}"
    measured "${scanned} 支留下來的腳本逐支跟 base ${base:0:12} 的版本比對，改動全部落在註解上"
    ;;

  *)
    echo "不認得的斷言：$ASSERTION" >&2
    echo "有的是：$(list_assertions "$0" | tr '\n' ' ')" >&2
    exit 2 ;;
esac
