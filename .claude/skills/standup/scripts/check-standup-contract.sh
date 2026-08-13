#!/usr/bin/env bash
# check-standup-contract.sh — standup 的散文契約有沒有還說著它該說的話。
#
# 這支擋的是「搬家之後才錯」的那一類：一段契約被後續改寫順手刪掉、或被稀釋成一句沒有內容
# 的話，而沒有任何東西會紅。它跟 gate-prose-matches-behaviour.sh 不重疊——那一支問「散文
# 指名的檔案／子命令／旗標存不存在」，這一支問「契約有沒有說某件事」。
#
# 每個契約點在散文裡有一個錨（`<!-- STANDUP-CONTRACT: <名字> -->`），錨底下那一段必須帶著
# 幾個表示它真的有內容的憑據。只有錨沒有內容一樣判紅——不然刪掉散文、留下註解就過了。
#
# 契約點的由來全部是量出來的失效，不是預防性的清單：2026-08-12 寫 standup 時四次被使用者
# 校正，DP-516 把那四次凍結成斷言，這支腳本是它們的量測面。
#
# Usage:
#   check-standup-contract.sh [--skill-dir <path>]
#
# Exit:
#   0 — 每個契約點都在，而且有內容
#   1 — 量到了，而且是紅的（缺錨、或錨底下沒內容）
#   2 — 量不到（skill 目錄不在、散文檔不在、python3 不在）

set -euo pipefail

PREFIX="[polaris check-standup-contract]"
SKILL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill-dir) SKILL_DIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SKILL_DIR" ]]; then
  SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

python3 - "$SKILL_DIR" "$PREFIX" <<'PY'
import os
import re
import sys

skill_dir, prefix = os.path.abspath(sys.argv[1]), sys.argv[2]

# 契約點：錨名 → (住在哪個檔, 這一段要出現什麼才算有內容, 這一條在守哪些斷言)
#
# 「要出現什麼」刻意挑**行為憑據**而不是句子原文：憑據是「這段話有沒有回答那個問題」的
# 代理，改寫措辭不會紅，抽掉內容才會紅。每一組是 (人看得懂的名字, 正則)。
CONTRACT = {
    "evidence-window": (
        "references/standup-data-collection-flow.md",
        [
            ("視窗綁在查詢那一層", r"查詢那一層|不是事後過濾"),
            ("指名 YDY_DATE", r"YDY_DATE"),
        ],
        "A-P4",
    ),
    "comments-are-collected": (
        "references/standup-data-collection-flow.md",
        [
            ("留言要收", r"留言"),
            ("用 created 綁視窗", r"created\s*>=\s*YDY_DATE"),
        ],
        "A-P1 A-P3",
    ),
    "newest-wins": (
        "references/standup-data-collection-flow.md",
        [
            ("兩邊都指名", r"留言.*描述|描述.*留言"),
            ("理由是可否排先後", r"append-only|只能追加"),
            ("要說出來", r"說出來|讓看的人知道"),
        ],
        "A-P2",
    ),
    "ydy-includes-pr": (
        "references/standup-data-collection-flow.md",
        [
            ("被 merge 的 PR", r"merge"),
            ("收到的意見", r"review comment|收到的意見"),
            ("CI 狀態", r"CI"),
        ],
        "A-P5",
    ),
    "status-is-not-intent": (
        "references/standup-data-collection-flow.md",
        [
            ("狀態名不是待辦", r"狀態名"),
            ("現況表會 stale", r"拆單表|現況表"),
            ("回空不等於不存在", r"回空"),
            ("推論要標成待驗", r"待驗"),
        ],
        "A-N1 A-N2 A-N3",
    ),
    "bos-admission": (
        "references/standup-planning-flow.md",
        [
            ("判準是我在等誰", r"我在等"),
            ("自己動得了的是待辦", r"待辦"),
            ("邊界案例指名", r"QA"),
            ("空著是一個答案", r"留白|空著"),
            ("待辦不得被搬過去填", r"搬過去填"),
            # DP-519 F-P4：判準從一句話變成一張照著判得出來的表。三種措辭各自要在。
            ("措辭：等 X 確認", r"等 X 確認"),
            ("措辭：等 X 回", r"等 X 回"),
            ("措辭：等 X review", r"等 X review"),
            ("理由是要開會或通知當事人", r"開會|通知當事人"),
        ],
        "C-P1 C-P2 C-P3 C-P4 C-N1 F-P4 F-P5 F-N2",
    ),
    "destination-is-declared": (
        "references/standup-format-publish-flow.md",
        [
            ("這支 skill 不認得目的地", r"不認得任何一個目的地"),
            ("問那支解析器", r"resolve-standup-destination\.sh"),
            ("四種離場碼各自不同", r"離場碼互不相同|不得收斂成同一句"),
            ("缺席時不猜也不沿用", r"不猜、也不沿用|不猜也不沿用"),
            ("缺席時報告照常寫本地", r"照常產出、照常寫本地檔案|報告照常產出"),
            ("不新開對外寫入通道", r"不新開對外寫入通道"),
        ],
        "E-P1 E-P2 E-P3 E-N2",
    ),
    "epic-three-cells": (
        "references/standup-template.md",
        [
            ("主體是 epic", r"主體是 epic"),
            ("三格的名字", r"昨日.*今日.*卡關"),
            ("舊四區塊對映到哪", r"舊區塊"),
            ("口頭同步只留在本地", r"只留在本地"),
            ("沒有 epic 的不散落", r"其他（無 Epic）"),
            ("只有一份說法", r"唯一一份說法|兩套形狀並存"),
            ("本地就是要送出去的那一份", r"本地檔案就是要送出去的那一份"),
        ],
        "E-P4 E-P5 E-N3",
    ),
    "plan-vs-actual-source": (
        "references/standup-planning-flow.md",
        [
            ("來源是自己寫的那份", r"自己每天落下的那份本地檔案"),
            ("指名它住在哪", r"standups/"),
            ("每次說出拿哪一份比的", r"拿哪一份比的要說出來"),
            ("沒有可比的也要說", r"不沉默跳過"),
        ],
        "F-P1 F-P2",
    ),
    "no-orphan-input": (
        "references/standup-data-collection-flow.md",
        [
            ("那條讀取被拿掉了", r"整個拿掉"),
            ("理由是沒有生產者", r"沒有人在寫|沒有生產者"),
            ("跟「問不到」分得開", r"根本沒有生產者"),
        ],
        "F-P3",
    ),
    "terse-output": (
        "references/standup-template.md",
        [
            ("第一句可以動手", r"可以動手"),
            ("兩分鐘內做得到", r"兩分鐘"),
            ("一格一件事", r"一格講一件事|第二件事另外"),
            ("清單上限五項", r"超過五項|五項就切"),
            ("不要開場白收尾", r"開場白"),
        ],
        "D-P1 D-P2 D-P3 D-P4 D-P5",
    ),
    "evidence-exempt": (
        "references/standup-template.md",
        [
            ("證據不套", r"不套"),
            ("指名哪些屬於證據", r"量測條件"),
            ("可追的東西留著", r"單號|連結"),
        ],
        "D-N1 D-N2",
    ),
    "drift-surfaced": (
        "references/standup-format-publish-flow.md",
        [
            ("逐條列出", r"逐條"),
            ("證據與推論分開", r"待驗"),
            ("不生出假的落差", r"不要為了有東西可報|兩邊一致"),
        ],
        "B-P1 B-P2 B-P4 B-N3",
    ),
    "drift-needs-consent": (
        "references/standup-format-publish-flow.md",
        [
            ("人點頭才寫", r"點頭才寫|同意之後"),
            ("順序不得顛倒", r"順序不得顛倒"),
            ("過既有的 gate", r"validate-language-policy\.sh"),
            ("逐次同意", r"逐次"),
            ("不擴大改動範圍", r"不順手整理"),
            ("不新開通道", r"不新開|不為這件事新增"),
        ],
        "B-P3 B-P5 B-N1 B-N2 B-N4",
    ),
    "unmeasurable-is-not-silent": (
        "references/standup-data-collection-flow.md",
        [
            ("說出缺的是哪一類", r"說出缺的是哪一類"),
            ("不沿用上一次", r"不沿用上一次"),
            ("不用推論補上", r"不用推論補上"),
            ("回空不當成沒有", r"不當成「沒有」|問不到的來源回空"),
        ],
        "A-P6",
    ),
}

# 不變量：這張單收窄行為，不得順手改掉既有的結構。錨管「有沒有說新的」，這一組管
# 「舊的還在不在」——兩者方向相反，缺一邊就有一整類的漂沒有人看得到。
INVARIANTS = [
    ("references/standup-format-publish-flow.md", "三格還在",
     r"昨日.*今日.*卡關", "E-P4"),
    ("references/standup-format-publish-flow.md", "分組規則還在",
     r"排序以 epic 為主體", "E-P4"),
    ("references/standup-format-publish-flow.md", "連結寫法還在",
     r"\[KEY title\]\(URL\)", "D-N3"),
    ("references/standup-planning-flow.md", "卡關三個來源還在",
     r"DISCUSS.*持續存在的 blocker.*口述", "C-N2"),
    ("references/standup-planning-flow.md", "判準不擴張來源",
     r"不擴張", "C-N2 F-N1"),
]

# 被取代掉的不變量：**不是刪掉，是換掉，而且換掉這件事要看得見。** 一個不變量默默消失
# 與一個不變量被有意識地替換，在檔案裡長得一樣——所以舊的那一條連同它守的斷言留在這裡，
# 每次執行都印出來。DP-519 E-P4／E-N3 換掉了輸出的形狀，D-N3 守的那兩條隨之失效。
SUPERSEDED = [
    ("四個區塊還在（YDY/TDT/BOS/口頭同步）", "D-N3", "三格還在（昨日/今日/卡關）", "E-P4 E-N3"),
    ("YDY 與 TDT 都依 team 分組", "D-N3", "排序以 epic 為主體", "E-P4"),
]

# 不得再出現的東西：一個沒有生產者的輸入、一份被刪掉的散文。這一組跟上面兩組方向都不同
# ——它問「舊的走乾淨了沒」。留一句指向不存在的東西的指示，讀的人只會照做然後自己撞上。
ABSENT = [
    ("沒有生產者的排序輸入", r"daily-triage", "F-P3"),
    ("被刪掉的 Confluence 操作手冊", r"confluence-page-update", "F-P3"),
]

ANCHOR = re.compile(r"<!--\s*STANDUP-CONTRACT:\s*([a-z0-9-]+)\s*-->")

# ── preflight：量不到就用 2 停下來，不要走進判定 ──────────────────────────────
if not os.path.isdir(skill_dir):
    print(f"{prefix} 量不到：skill 目錄不在 {skill_dir}", file=sys.stderr)
    sys.exit(2)

wanted_files = sorted({spec[0] for spec in CONTRACT.values()} | {inv[0] for inv in INVARIANTS})
missing_files = [f for f in wanted_files if not os.path.isfile(os.path.join(skill_dir, f))]
if missing_files:
    print(f"{prefix} 量不到：散文檔不在——{', '.join(missing_files)}", file=sys.stderr)
    sys.exit(2)

bodies = {}
for rel in wanted_files:
    with open(os.path.join(skill_dir, rel), encoding="utf-8") as fh:
        bodies[rel] = fh.read()

total_anchors = sum(len(ANCHOR.findall(body)) for body in bodies.values())
if total_anchors == 0:
    print(f"{prefix} 量不到：{len(wanted_files)} 個散文檔裡一個錨都沒有。", file=sys.stderr)
    print(f"{prefix} 0 個錨跟「全部都在」在輸出上長得一樣，所以這不算綠。", file=sys.stderr)
    sys.exit(2)


def matches(pattern, text):
    """散文硬斷在 80 欄，一個詞會被切在兩行。

    只比原文的話，`說出缺的是\\n哪一類` 會判紅——而那是排版，不是契約變了。所以原文與
    去掉換行的版本各比一次，任一中就算。兩種都比是因為去換行會把 ASCII 詞黏起來
    （`review\\ncomment` → `reviewcomment`），只留一種都會有一類假紅。
    """
    if re.search(pattern, text, re.IGNORECASE | re.DOTALL):
        return True
    return bool(re.search(pattern, re.sub(r"\n\s*", "", text), re.IGNORECASE | re.DOTALL))


def section_of(body, anchor_name):
    """錨底下到下一個錨（或檔尾）之間那一段。契約點的內容住在這裡。"""
    hit = None
    for m in ANCHOR.finditer(body):
        if m.group(1) == anchor_name:
            hit = m
            break
    if hit is None:
        return None
    nxt = ANCHOR.search(body, hit.end())
    return body[hit.end(): nxt.start() if nxt else len(body)]


failures = []
checked = 0

for name, (rel, evidence, assertions) in sorted(CONTRACT.items()):
    body = bodies[rel]
    section = section_of(body, name)
    if section is None:
        failures.append(f"{rel}：契約點 `{name}` 的錨不在了（守 {assertions}）")
        continue
    for label, pattern in evidence:
        checked += 1
        if not matches(pattern, section):
            failures.append(
                f"{rel}：契約點 `{name}` 還在，但那一段沒有說「{label}」（守 {assertions}）"
            )

for rel, label, pattern, assertions in INVARIANTS:
    checked += 1
    if not matches(pattern, bodies[rel]):
        failures.append(f"{rel}：既有結構被動到了——「{label}」不見了（守 {assertions}）")

# ── 舊的走乾淨了沒 ──────────────────────────────────────────────────────────
# 掃整個 skill 目錄，不只掃那幾份契約散文：一句指向死掉的東西的指示，出現在腳本註解或
# SKILL.md 裡跟出現在契約裡一樣會誤導人。掃了幾個檔案要印出來——掃到 0 個檔案跟「掃過了、
# 乾淨」在輸出上長得一樣。
scanned = []
for dirpath, dirnames, filenames in os.walk(skill_dir):
    dirnames[:] = [d for d in dirnames if d not in ("__pycache__", ".git")]
    for fn in filenames:
        if fn.endswith((".md", ".sh", ".py", ".mjs", ".yaml", ".yml")):
            scanned.append(os.path.join(dirpath, fn))

def absence_exempt(path):
    """宣告面與注入面自己要寫得出那個字串，所以這兩處不受這一組管。

    - 這支腳本：它就是「不得出現」這句話住的地方。
    - `scripts/selftests/` 底下：那些字串是餵給檢查的輸入，不是給人讀的指示。

    豁免要說出來，不要靜靜地跳過——一個沒被說出的豁免，跟沒有豁免在出事的時候長得一樣。
    """
    if os.path.basename(path) == "check-standup-contract.sh":
        return True
    return f"{os.sep}selftests{os.sep}" in path


exempt = [p for p in scanned if absence_exempt(p)]
for label, pattern, assertions in ABSENT:
    checked += 1
    hits = []
    for path in scanned:
        if absence_exempt(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        if re.search(pattern, text, re.IGNORECASE):
            hits.append(os.path.relpath(path, skill_dir))
    for hit in hits:
        failures.append(f"{hit}：不該再出現的東西還在——「{label}」（守 {assertions}）")

print(
    f"{prefix} MEASURED anchors={total_anchors} contract_points={len(CONTRACT)} "
    f"invariants={len(INVARIANTS)} absent_checks={len(ABSENT)} "
    f"scanned_files={len(scanned) - len(exempt)} exempt_files={len(exempt)} "
    f"evidence_checks={checked}"
)
if exempt:
    print(f"{prefix} DISCLOSURE 不受「不得再出現」那一組管的檔案（宣告面與注入面）：")
    for path in sorted(os.path.relpath(p, skill_dir) for p in exempt):
        print(f"{prefix}   {path}")
print(f"{prefix} DISCLOSURE 逐個契約點與它守的斷言：")
for name, (rel, _evidence, assertions) in sorted(CONTRACT.items()):
    print(f"{prefix}   {name} → {assertions}（{rel}）")
print(f"{prefix} DISCLOSURE 被取代掉的不變量（不是消失，是換掉）：")
for old_label, old_assertions, new_label, new_assertions in SUPERSEDED:
    print(f"{prefix}   「{old_label}」（守 {old_assertions}）→ 「{new_label}」（守 {new_assertions}）")

if failures:
    for line in failures:
        print(f"{prefix} 紅：{line}", file=sys.stderr)
    print(f"{prefix} {len(failures)} 處對不上。", file=sys.stderr)
    sys.exit(1)

print(f"{prefix} OK 每個契約點都在，而且有內容。")
PY
