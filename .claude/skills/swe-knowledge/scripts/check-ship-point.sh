#!/usr/bin/env bash
# Purpose: 出貨動作之前，問那張單判過了沒（DP-865 A-P5）。
# Inputs:  --issues <單的根目錄>
#          --action merge|open|ready|tag|deploy
#          [--branch <要併的那條 branch 名>] [--base <併進去的 branch>] [--repo <owner/name>]
#          [--head <要出去的 commit>]... [--tag <tag 名>]... [--default-branch <那個 repo 的預設分支>]
#          [--text <命令或訊息本文>] [--text-file <檔>]
# Outputs: 擋下時 stderr 說出是哪一張單、站別是什麼、要怎麼走；tag 動作另說讀到的 tag 名，名字
#          含 $ 時說要用字面名字。放行時什麼都不印。
# Exit:    0 放行（對不到任何本地單、或對到的都判過）/ 1 擋下 / 2 用法錯
#
# 這是〈五條〉第 3 條「判定過才進預設分支」第一次有東西守。它守的三種動作都收不回來、都會
# 出這個 repo，而看 diff 的人看不出那張單有沒有被判過——那寫在單的 loop-state 裡，不在 diff 裡。
#
# 對不對得到一張單，只看這幾樣，任何一樣中了就算對到：
#   - branch 名或本文裡出現一個本地單的號（目錄名開頭那一段，例如 ABC-123）
#   - 要出去的 commit 等於某張單 delivery.json 或證據記的 head
#   - 本文（去尾端空白）的 sha256 等於某張單 deploy-requests.json 記的那一筆
# 對不到就放行，而且不印任何東西：別人的 PR、別人的發佈、沒有走過這套流程的工作，不是這一道
# 管的事。以前那一道（訊息雜湊在紀錄裡找不到就擋）把「對不到」當成「沒驗過」，那是一條沒有
# 人定義過的規則。
#
# 對到了，要那張單的站別是 delivered。併的時候還要 head 是交付紀錄記的那一個——不是的話，
# 交付之後又改過，那一站要量的是改完之後的東西。
#
# open 與 ready（DP-993）：開一顆不是 draft 的 PR、把 draft 轉成 ready，都是在說「這一版可以看了」，
# 而那句話要等這個 head 判過。判過指單上有 verify-ac 對這個 head 寫的那一行
# （`<!-- VERIFY-AC-VERDICT: head=… -->`，record-verdict.sh 寫，每一條不是過就是寫明未到站），
# 或交付紀錄釘在這個 head。命名空間的條件對這兩種收到的是 --action merge：梯子放行某一次併，就放行
# 為了那一次併而把 PR 轉成 ready。
#
# open 與 ready 對到的單上有這個 head 的判定行時，還要這個 head 的兩行九問紀錄都在單上（DP-1029；只靠
# 交付紀錄對到、沒有判定行的那一路照舊放行。那一型在真實樹上有幾張，量到的值不抄在這裡，要知道就問：
#   find <單的根目錄> -path '*/.spine/delivery.json' | while read d; do t=${d%/.spine/delivery.json}; grep -q VERIFY-AC-VERDICT "$t/index.md" 2>/dev/null || echo "$t"; done | wc -l
# 對比 delivery.json 的總數）：施工方那一行（行首
# `check-your-own-work 九問，head <sha>`）與驗證者那一行（同樣行首，接 `（驗證者）`；括號裡以「驗證者」開頭就是
# 驗證者那一行，後面可以帶字，例如 `（驗證者，第二輪）`；括號不以「驗證者」開頭的是施工方那一行，例如
# `（對這顆 diff 逐問答）`）。判定行比驗證者早寫得出來，只看判定行的話，驗證者後到的 head 照樣 ready。
# 兩行的行首可以先有標題或清單前綴（`## `、`- `）。缺哪一行就說哪一行。驗證者那一行寫「跑不到」帶理由、
# 或判綠，就算在，不再判它的內容。
# 同一行還有第二個讀者：交付紀錄的 self_check 那一格（verify-ac/scripts/record-delivery-intent.sh）仍只認行首
# 裸寫的九問行，帶標題或清單前綴的九問行它記成沒跑；這一道認、那一格不認。這顆不動那支（DP-1029 A-N2 把改動
# 限在這一支與 swe-knowledge 第 3 條），這裡只把這個差說出來。
#
# 驗證者在這個 head 判紅時（DP-1029 A-P3），ready 還要單上對它每一條 finding 逐條處置。紅與 finding 數先讀
# `.spine/independent/<head>.json` 的 verdict（push-verifier 寫）：FAIL 是紅；PASS 與 UNMEASURABLE 不看處置，驗證者
# 那一行寫的是「：紅」也以 json 為準；讀不到那份才看那一行冒號後的字，「紅」算 1 條。verdict 是 PARTIAL
# （push-verifier 逾時那半份，單上寫「沒跑完」）跟紅同一個待遇：那半份列了 finding 就要逐條處置，一條都沒列就擋下
# 並說驗證者沒跑完——它的答案還沒給完。處置寫在行首「回驗證者 <head>」那一段（前面可以是 `## `～`#### ` 標題），
# 底下一條一項、只數頂層項目，每一項是照做、說明為什麼不照做、拒絕、另開單四種處置之一。標題與第一個項目之間
# 可以有幾行前言或空行，不算也不中斷；數起來之後遇到下一段散文就停；不論數起來沒有，下一個標題、下一段
# 「回驗證者」、或一行九問紀錄就是這一段的結尾（驗證者那一行底下接的 1.～9. 與 finding 清單不是處置）。
# 處置條數少於 finding 數就擋，並說出紅幾條、處置幾條、寫在哪。open 不看這一格。merge、tag、deploy 不看九問行，
# 也不看處置。
#
# merge 的 base 不是那個 repo 的預設分支時（例如併進一條 feature branch），照 open 與 ready 判：
# 那不是進預設分支，〈五條〉第 3 條管不到它，但它仍要這個 head 判過。預設分支由呼叫者用
# --default-branch 給；沒給（問不到）就當成預設分支，照 delivered 判。
#
# 例外是只上 stage 的 tag（DP-907）：名字帶 beta 或 rc 段的，站別到 engineering 就放行。stage
# 驗收在 verify-ac 之前，那種 tag 不是進預設分支的出貨。一次給的 tag 有一個不是、或一個名字
# 都沒給，就照正式的判。
#
# 命名空間自己的梯子把某些出貨動作排在判定之前時（DP-908），由它宣告，核心不認得任何一家的梯子：
#   <!-- {任意前綴}-SHIP-POINT-CONDITION-{命名空間}: {命令} -->
# 對到的單站別還不夠時，在 repo 根跑那條命令，後面接單的目錄與這次動作的描述（--action、
# --branch、--base、--repo、--tag、--head、--text-file）。回 0 就放行那一張，非 0 照舊擋，並帶上
# 命令自己印的缺口。沒宣告的命名空間照舊。
#
# 擋不到的，明講：人自己在網頁上按的；跑在一支腳本裡面、沒有經過呼叫這一支的那些動作
# （釋出尾段自己讀交付紀錄）；對不到單的那些。
set -uo pipefail

ISSUES="" ACTION="" BRANCH="" BASE="" REPO="" TEXT="" DEFAULT_BRANCH="" HEADS=() TAGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issues)    ISSUES="${2:-}"; shift 2 ;;
    --action)    ACTION="${2:-}"; shift 2 ;;
    --branch)    BRANCH="${2:-}"; shift 2 ;;
    --base)      BASE="${2:-}"; shift 2 ;;
    --repo)      REPO="${2:-}"; shift 2 ;;
    --head)      HEADS+=("${2:-}"); shift 2 ;;
    --tag)       TAGS+=("${2:-}"); shift 2 ;;
    --default-branch) DEFAULT_BRANCH="${2:-}"; shift 2 ;;
    --text)      TEXT="${2:-}"; shift 2 ;;
    --text-file) TEXT="$(cat "${2:-/dev/null}")"; shift 2 ;;
    -h|--help)   sed -n '2,11p' "$0" >&2; exit 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$ACTION" in merge|open|ready|tag|deploy) ;; *) echo "--action 要是 merge、open、ready、tag 或 deploy（拿到 '$ACTION'）" >&2; exit 2 ;; esac
[[ -n "$ISSUES" ]] || { echo "--issues 是必填" >&2; exit 2; }
[[ -d "$ISSUES" ]] || exit 0

SKILLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$SKILLS_ROOT" "$ISSUES" "$ACTION" "$BRANCH" "$BASE" "$REPO" "$TEXT" "$(printf '%s\n' "${TAGS[@]+"${TAGS[@]}"}")" "$DEFAULT_BRANCH" \
  "${HEADS[@]+"${HEADS[@]}"}" <<'PY'
import glob, hashlib, json, os, re, shlex, subprocess, sys, tempfile

SKILLS, root, action, branch, base, repo, text, tag_lines, default_branch = sys.argv[1:10]
heads = {h for h in sys.argv[10:] if h}
tags = [t for t in tag_lines.splitlines() if t]
# 名字裡有一段是 beta 或 rc（前面是開頭或 _ . -，後面是結尾、分隔字元或數字）。
STAGE_ONLY = re.compile(r"(?:^|[_.-])(?:beta|rc)(?:[_.-]|\d|$)", re.I)
stage_only = action == "tag" and bool(tags) and all(STAGE_ONLY.search(t) for t in tags)
passing = {"engineering", "verify-ac", "delivered"} if stage_only else {"delivered"}
pr_action = action in ("merge", "open", "ready")
# 讀判定那一行就夠的動作：open、ready，與 base 確定不是預設分支的 merge
by_verdict = action in ("open", "ready") or (action == "merge" and bool(default_branch) and bool(base)
                                             and base != default_branch)
KEY = re.compile(r"(?<![A-Za-z0-9])([A-Z][A-Z0-9]*-\d+)(?![0-9])")

def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None

tickets = {}
for state_path in glob.glob(os.path.join(root, "**", ".spine", "loop-state.json"), recursive=True):
    ticket = os.path.dirname(os.path.dirname(state_path))
    match = KEY.match(os.path.basename(ticket))
    if match:
        tickets.setdefault(match.group(1), []).append(ticket)

def recorded_heads(ticket):
    found = set()
    delivery = read(os.path.join(ticket, ".spine", "delivery.json")) or {}
    found.add(delivery.get("head_sha"))
    for row in delivery.get("heads") or []:
        if isinstance(row, dict):
            found.add(row.get("head_sha"))
    for evidence in glob.glob(os.path.join(ticket, ".spine", "evidence", "*.json")):
        found.add((read(evidence) or {}).get("head_sha"))
    return {h for h in found if h}

def delivery_heads(ticket):
    delivery = read(os.path.join(ticket, ".spine", "delivery.json"))
    if not delivery:
        return set()
    found = {delivery.get("head_sha")}
    found.update(row.get("head_sha") for row in delivery.get("heads") or [] if isinstance(row, dict))
    return {h for h in found if h}

VERDICT_LINE = re.compile(r"<!--\s*VERIFY-AC-VERDICT:\s*head=([0-9a-f]{7,40})\b")

def verdict_heads(ticket):
    try:
        return set(VERDICT_LINE.findall(open(os.path.join(ticket, "index.md"), encoding="utf-8").read()))
    except OSError:
        return set()

# 九問紀錄的行首：`check-your-own-work 九問，head <sha>`，engineering 自己的例子還有 `head <a> → <b>` 兩段式（取後者）；
# 驗證者那一行在 sha 後面接一個以「驗證者」開頭的括號（`（驗證者）`，也可以是 `（驗證者，第二輪）`——push-verifier
# 寫的是固定格式，人手寫的會帶字；只認逐字 `（驗證者）` 時，帶字的那一行會被算成施工方那一行，一張只有驗證者行
# 的單就過了 A-P1）。括號不以「驗證者」開頭、或沒有括號的，是施工方那一行。行首可以先有標題（`## `）或清單
# （`- `、`1. `）前綴——真實樹上的施工方紀錄有這一型。施工方行與驗證者判紅那一行共用同一段行首，兩者認得的
# 形狀才不會分岔。
NINE_LEAD = (r"^(?:#{1,6}\s+|[-*]\s+|\d+[.)]\s+)?check-your-own-work 九問，head\s+"
             r"(?:[0-9a-f]{7,40}\s*→\s*)?([0-9a-f]{7,40})\s*")
VERIFIER_TAG = r"（驗證者[^）\n]*）"
NINE_LINE = re.compile(NINE_LEAD + r"(" + VERIFIER_TAG + r")?", re.M)

def nine_question_heads(ticket):
    """回 (施工方寫過的 head 集合, 驗證者寫過的 head 集合)。讀不到單就兩個都空。"""
    try:
        text_ = open(os.path.join(ticket, "index.md"), encoding="utf-8").read()
    except OSError:
        return set(), set()
    builder, verifier = set(), set()
    for sha, is_verifier in NINE_LINE.findall(text_):
        (verifier if is_verifier else builder).add(sha)
    return builder, verifier

def matches_head(recorded):
    return any(h.startswith(r) or r.startswith(h) for h in heads for r in recorded if len(h) >= 7)

# 驗證者判紅的 head，ready 還要單上對它每一條 finding 的處置（DP-1029 A-P3 重簽）。先讀 `.spine/independent/<head>.json`
# 的 verdict（push-verifier 寫）：FAIL 是紅；PARTIAL 是逾時那半份（單上寫「沒跑完」），跟紅同一個待遇；PASS 與
# UNMEASURABLE 不看處置，那一行寫什麼都以 json 為準。讀不到 json 才看驗證者那一行冒號後的字：「紅」當 1 條、
# 「沒跑完」當一條都還沒列。
VERIFIER_LABEL_LINE = re.compile(NINE_LEAD + VERIFIER_TAG + r"\s*：\s*(紅|沒跑完)", re.M)

def verifier_verdict(ticket):
    """回 (「紅」或「沒跑完」或 None, finding 數)。讀不到單就 (None, 0)。"""
    try:
        text_ = open(os.path.join(ticket, "index.md"), encoding="utf-8").read()
    except OSError:
        return None, 0
    ind = os.path.join(ticket, ".spine", "independent")
    try:
        names = sorted(os.listdir(ind))
    except OSError:
        names = []
    for fn in names:
        stem, ext = os.path.splitext(fn)
        if ext != ".json" or not matches_head({stem}):
            continue
        rec = read(os.path.join(ind, fn)) or {}
        n = len(rec.get("findings") or [])
        if rec.get("verdict") == "FAIL":
            return "紅", max(n, 1)
        if rec.get("verdict") == "PARTIAL":
            return "沒跑完", n
        if rec.get("verdict") in ("PASS", "UNMEASURABLE"):
            return None, 0
    for sha, label in VERIFIER_LABEL_LINE.findall(text_):
        if matches_head({sha}):
            return label, 1 if label == "紅" else 0
    return None, 0

# 處置紀錄：行首「回驗證者 <head>」開一段（前面可以是 `## `～`#### ` 標題，跟 prior-decisions.py 認段落的寫法一樣），
# 底下一條一項。只數不縮排的頂層項目（`- ` 或 `1. `）；縮排的子項與續行屬於上一條，不另算。標題與第一個項目之間
# 的前言行（真實樹上的處置段多半先有一句「幾條處置落在哪一顆」）跳過不算、也不中斷；數起來之後遇到非項目、非縮排、
# 非空的行（下一段散文）就停。不論數起來沒有，下一個標題、下一段「回驗證者 <head>」、或一行九問紀錄都是這一段的
# 結尾——驗證者那一行底下接的是它自己的 1.～9. 與 finding 清單，不是處置。
DISPOSITION_HEAD = re.compile(r"^(?:#{2,4}\s+)?回驗證者\s+([0-9a-f]{7,40})\b")
LIST_ITEM = re.compile(r"^(?:[-*]|\d+[.)])\s+\S")
HEADING = re.compile(r"^#{1,6}\s")

def section_ends(line):
    return bool(HEADING.match(line) or DISPOSITION_HEAD.match(line) or NINE_LINE.match(line))

def disposition_count(ticket):
    """單上對這個 head 的驗證者 finding 寫了幾條處置；沒有那一段就 0。"""
    try:
        lines = open(os.path.join(ticket, "index.md"), encoding="utf-8").read().split("\n")
    except OSError:
        return 0
    best = 0
    for i, line in enumerate(lines):
        m = DISPOSITION_HEAD.match(line)
        if not m or not matches_head({m.group(1)}):
            continue
        n = 0
        for nxt in lines[i + 1:]:
            if section_ends(nxt):
                break
            if LIST_ITEM.match(nxt):
                n += 1
            elif n and nxt.strip() and not nxt[0].isspace():
                break
        best = max(best, n)
    return best

mapped = {}
for key in KEY.findall(branch + "\n" + text):
    for ticket in tickets.get(key, []):
        mapped[ticket] = "號 " + key
body_sha = hashlib.sha256(text.rstrip().encode()).hexdigest() if text.strip() else None
for group in tickets.values():
    for ticket in group:
        if ticket in mapped:
            continue
        if heads and matches_head(recorded_heads(ticket)):
            mapped[ticket] = "head"
        elif body_sha and any(r.get("message_sha256") == body_sha
                              for r in read(os.path.join(ticket, ".spine", "deploy-requests.json")) or []
                              if isinstance(r, dict)):
            mapped[ticket] = "部署請求紀錄"

def declared_condition(namespace):
    pattern = re.compile(r"<!--\s*[A-Za-z0-9_-]*SHIP-POINT-CONDITION-" + re.escape(namespace) + r":\s*(.+?)\s*-->")
    for skill in sorted(glob.glob(os.path.join(SKILLS, "**", "SKILL.md"), recursive=True)):
        try:
            found = pattern.search(open(skill, encoding="utf-8").read())
        except OSError:
            continue
        if found:
            return found.group(1)
    return None

def namespace_allows(ticket, name):
    """回 (放不放行, 條件自己說的話)；沒宣告回 (False, None)。"""
    command = declared_condition(name.split(os.sep)[0])
    if not command:
        return False, None
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as body:
        body.write(text)
    args = [ticket, "--action", "merge" if pr_action else action, "--branch", branch, "--base", base, "--repo", repo, "--text-file", body.name]
    for t in tags:
        args += ["--tag", t]
    for h in sorted(heads):
        args += ["--head", h]
    try:
        out = subprocess.run(command + " " + " ".join(shlex.quote(a) for a in args), shell=True,
                             cwd=os.path.dirname(os.path.dirname(SKILLS)), capture_output=True, text=True,
                             errors="replace", timeout=120)
    except subprocess.TimeoutExpired:
        return False, f"命名空間的條件（{command}）兩分鐘沒有回答，這一次問不到，照舊擋。"
    finally:
        os.unlink(body.name)
    said = (out.stdout + out.stderr).strip()
    return out.returncode == 0, f"命名空間的條件（{command}）不成立：{said}" if out.returncode else said

def judged_note(ticket):
    """這次的 head 與最後一筆判定的 head，給 PR 那三種動作的擋訊息用。"""
    now = "、".join(sorted(h[:12] for h in heads)) or "問不到"
    recorded = delivery_heads(ticket) | (verdict_heads(ticket) if by_verdict else set())
    last = ("head " + "、".join(sorted(h[:12] for h in recorded))) if recorded else "沒有"
    # 併進預設分支只認交付紀錄，判定那一行不算，所以那一格要說它看的是交付紀錄
    what = "最後一筆判定" if by_verdict else "最後一筆交付紀錄"
    return f"這次的 head 是 {now}，{what}：{last}。"

FIX = {"merge": "先走 verify-ac 寫交付紀錄再併。",
       "merge-feature": "先走 verify-ac 對這個 head 寫判定（record-verdict.sh）再併。",
       "open": "先走 verify-ac 對這個 head 寫判定（record-verdict.sh）；要先開出來就帶 --draft。",
       "ready": "先走 verify-ac 對這個 head 寫判定（record-verdict.sh）再 gh pr ready；在那之前留在 draft。"}

blocked = []
for ticket, why in sorted(mapped.items()):
    state = read(os.path.join(ticket, ".spine", "loop-state.json")) or {}
    station = state.get("station") or "?"
    name = os.path.relpath(ticket, root)
    if by_verdict and heads and matches_head(verdict_heads(ticket) | delivery_heads(ticket)):
        # 九問那兩行只對「判定行對到這個 head」的 open／ready 要；只靠交付紀錄對到、沒有判定行的那一路
        # 照改前放行（A-N1；那一型佔真實樹的多數，怎麼量寫在檔頭，值不抄在這裡）。
        if action in ("open", "ready") and matches_head(verdict_heads(ticket)):
            builder, verifier = nine_question_heads(ticket)
            missing = []
            if not matches_head(builder):
                missing.append("施工方那一行（行首「check-your-own-work 九問，head <這個 head>」，跑 check-your-own-work 寫回單）")
            if not matches_head(verifier):
                missing.append("驗證者那一行（行首「check-your-own-work 九問，head <這個 head>（驗證者）」，等 push-verifier 寫回，它跑不到也會寫一行）")
            if missing:
                blocked.append(f"{name}（靠{why}對到）這個 head 判過了，但單上缺它的九問紀錄：{'；'.join(missing)}。"
                               f"順序是 push → push-verifier → 九問 → verify-ac 判定 → {action}，兩行都在了再 {action}。")
                continue
            if action == "ready":
                label, n_findings = verifier_verdict(ticket)
                if label == "沒跑完" and n_findings == 0:
                    blocked.append(f"{name}（靠{why}對到）驗證者在這個 head 沒跑完（push-verifier 逾時，那半份一條 finding 都還沒列），"
                                   f"答案還沒給完；等它重跑寫回單再 ready。")
                    continue
                if label:
                    n_done = disposition_count(ticket)
                    if n_done < n_findings:
                        said = f"判紅 {n_findings} 條" if label == "紅" else f"沒跑完（push-verifier 逾時），那半份已列 {n_findings} 條 finding"
                        blocked.append(f"{name}（靠{why}對到）驗證者在這個 head {said}，單上對它的逐條處置只有 {n_done} 條"
                                       f"（寫在行首「回驗證者 <這個 head>」那一段底下，前面可以是 ## 標題，標題與第一項之間可以有前言；"
                                       f"一條 finding 一個不縮排的清單項，子項不另算；段到下一個標題、下一段散文或九問行為止，所以寫在這個 head 的九問行前面；"
                                       f"四種處置：照做、說明為什麼不照做、拒絕、另開單）。"
                                       f"每一條都有處置了再 ready；照做的那一路推新的 head 讓驗證者重判。")
                        continue
        continue
    if station not in passing:
        allowed, said = namespace_allows(ticket, name)
        if allowed:
            continue
        if said:
            # PR 的三種動作被梯子擋下時，照樣說出這次的 head、最後一筆判定與修法
            tail = f"{judged_note(ticket)}修法：{FIX['merge-feature' if action == 'merge' and by_verdict else action]}" if pr_action else ""
            blocked.append(f"{name}（靠{why}對到）站別是 {station}。{said}" + (f"；{tail}" if tail else ""))
            continue
    if station not in passing and stage_only:
        blocked.append(f"{name}（靠{why}對到）站別是 {station}：只上 stage 的 tag 要等這張單開了輪次、站別到 engineering。")
    elif station not in passing and pr_action:
        blocked.append(f"{name}（靠{why}對到）站別是 {station}，還沒判過。{judged_note(ticket)}修法：{FIX['merge-feature' if action == 'merge' and by_verdict else action]}")
    elif station not in passing:
        blocked.append(f"{name}（靠{why}對到）站別是 {station}，還沒判過。先走 verify-ac，交付紀錄寫成時站別會自己記成 delivered。")
    elif pr_action and heads and not matches_head(delivery_heads(ticket)):
        blocked.append(f"{name}（靠{why}對到）判過，但這次的 head 不是交付紀錄記的那一個：交付之後又改過了。{judged_note(ticket)}修法：重走 verify-ac。")

if blocked:
    print(f"已擋下：這是一次出貨動作（{action}），而它對到的單還不能出去：", file=sys.stderr)
    for line in blocked:
        print("  - " + line, file=sys.stderr)
    if action == "tag":
        # 撞到的人要知道這一道看到的是哪個名字（DP-910）：命令寫成 git tag $T 時，它讀到的就是字面的 $T。
        judged = "" if stage_only else "，名字裡沒有 beta 或 rc 段，照正式 tag 判"
        print(f"讀到的 tag 名：{'、'.join(tags)}{judged}。" if tags else "沒讀到 tag 名，照正式 tag 判。", file=sys.stderr)
        if any("$" in t for t in tags):
            print("tag 名要用字面名字，不要用變數：這一道讀的是命令字面，看不到 shell 展開後的值。", file=sys.stderr)
    sys.exit(1)
PY
