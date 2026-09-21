#!/usr/bin/env bash
# build-independent-oracle-prompt.sh — 產生那份交給獨立 agent 的指示，兩個階段各一份。
#
# 它在回答一個問題：**施工的人自己挑的那條量測命令，漏掉了什麼？**
#
# 少了這一支，答案只有施工方自己說了算——它挑 oracle、它跑 oracle、它宣稱綠了。外界
# 2026 把這個形狀量成了硬數字（SWE-ABS 榜首 78.8%→62.2%；Building to the Test 給了
# oracle 之後 benchmark 近滿分而 library 是死的）。
#
# **這一趟不是 held-out 驗證，也不是第二個權威，散文不得這樣寫。** held-out 的定義是那份
# 測資被驗的人優化不到，而這裡：派工的是施工方、跑的是同一棵樹、探針由 LLM 從同一份
# assertion 推。它能宣稱的只有一件事——**兩份獨立推導出來的 oracle 差在哪**。
#
# 拿掉的那一樣東西是**敘事污染**：獨立 agent 看不到施工方的對話，所以看不到那些「我覺得
# 這樣就夠了」的自我背書。2026-09-21 實測過：拿一個只有這個 session 談過、而框架檔案裡
# 不存在的詞去問它，它回「完全沒有任何出處」。
#
# 兩個階段，順序由檔案系統擋住，不由叮嚀擋住：
#
#   phase 1  它只拿得到**一份去掉施工痕跡的單**（只有 plan 與 assertion，沒有 .spine/、
#            沒有 measure.sh）。施工方登錄的那條命令在那個目錄裡**物理上不存在**，所以
#            「先自己推」不是一句請求。它把自己的探針與結果寫進 phase1.json。
#   phase 2  phase1.json 在了才產得出來。這時才給它真的單、給它施工方的量測登錄，要它
#            比對兩邊。
#
# Usage:
#   build-independent-oracle-prompt.sh --issue <單的目錄> --tree <要量的 checkout> --phase 1|2
#
# **沒有第三個參數，這是刻意的。** 施工方交得出去的只有「單在哪」「樹在哪」；它的摘要、
# 結論、理由、辯護，一個字都進不了這份指示。留一個「可選的補充說明」等於把這一趟的唯一
# 根據送掉——那個參數看起來無害，而它正好是這支腳本要擋的東西。
#
# Exit: 0 產出了 / 2 參數不對、單不在、或 phase 2 的前提還沒成立

set -euo pipefail

ISSUE="" TREE="" PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --tree)  TREE="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "POLARIS_INDEPENDENT_ORACLE_UNKNOWN_ARG:$1" >&2
       echo "  這支只收 --issue／--tree／--phase。施工方的摘要不是參數，見檔頭。" >&2
       exit 2 ;;
  esac
done

[ -n "$ISSUE" ] || { echo "POLARIS_INDEPENDENT_ORACLE_NO_ISSUE" >&2; exit 2; }
[ -n "$TREE" ]  || { echo "POLARIS_INDEPENDENT_ORACLE_NO_TREE" >&2; exit 2; }
[ -d "$ISSUE" ] || { echo "POLARIS_INDEPENDENT_ORACLE_ISSUE_NOT_FOUND:$ISSUE" >&2; exit 2; }
[ -d "$TREE" ]  || { echo "POLARIS_INDEPENDENT_ORACLE_TREE_NOT_FOUND:$TREE" >&2; exit 2; }
[ -f "$ISSUE/index.md" ] || { echo "POLARIS_INDEPENDENT_ORACLE_NO_INDEX:$ISSUE/index.md" >&2; exit 2; }

ISSUE=$(cd "$ISSUE" && pwd)
TREE=$(cd "$TREE" && pwd)
OUT="$ISSUE/.spine/independent"
# 去掉施工痕跡的那一份**不放在單底下**。放在 $OUT/redacted 的話，它離真的單只有一個
# `..`——那等於把「物理上看不到」換回「請你不要看」，而這一趟的唯一根據就是前者。
# 名字也不帶單號：一個叫 DP-736-... 的目錄，find 一次就回來了。
REDACTED="${POLARIS_INDEPENDENT_ORACLE_REDACTED_DIR:-}"
P1="$OUT/phase1.json"
P2="$OUT/phase2.json"

# 這一段是白名單的宣告源，兩個階段共用，measure 也讀它。
read -r -d '' BOUNDS <<'BOUNDS_END' || true
**你能做什麼，以及不能做什麼。** 這一趟是唯讀的調查：

- 可以：讀檔（Read／Grep／Glob）、跑唯讀的 shell 命令去量東西、用已經在那棵樹裡的測試與
  腳本、對本機或公開的位址發唯讀請求。
- **不可以**：送 Slack 訊息、寫任何 JIRA 欄位或 comment、送出任何 PR review、推任何 ref、
  對 stage 或 production 做任何動作、改動那棵樹上的檔案、commit、安裝任何東西。

這幾條不是禮貌用語。你是來說出「施工方漏量了什麼」的，你自己送出去的任何東西都會變成
另一個要被驗的東西。看到一件該做而你不能做的事，**寫進回報裡讓人去做**，不要自己做。
BOUNDS_END

mkdir -p "$OUT"

case "$PHASE" in
  1)
    # 去掉施工痕跡：只留 plan 與 assertion。施工方的量測命令在這個目錄裡不存在。
    if [ -n "$REDACTED" ]; then
      rm -rf "$REDACTED"; mkdir -p "$REDACTED"
    else
      REDACTED=$(mktemp -d "${TMPDIR:-/tmp}/acceptance-XXXXXXXX")
    fi
    echo "$REDACTED" > "$OUT/redacted-dir.txt"
    python3 - "$ISSUE/index.md" "$REDACTED/acceptance.md" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()

# frontmatter 只留 plan 那一段：destination、frozen_by、hash 都是施工與流程的痕跡。
plan = ""
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if m:
    keep, on = [], False
    for line in m.group(1).split("\n"):
        if re.match(r"^plan:\s*$", line):
            on = True; keep.append(line); continue
        if on and line and not line.startswith((" ", "\t")):
            on = False
        if on:
            keep.append(line)
    plan = "\n".join(keep).rstrip()

fences = re.findall(
    r"<!-- POLARIS-FROZEN-([A-Za-z0-9_]+)-BEGIN -->\n(.*?)<!-- POLARIS-FROZEN-\1-END -->",
    text, re.S)
if not fences:
    sys.stderr.write("POLARIS_INDEPENDENT_ORACLE_NO_FENCE\n")
    sys.exit(2)

out = ["# 這一版怎麼算成功", ""]
if plan:
    out += ["## 這一版要做什麼（提單的人自己填的）", "", "```yaml", plan, "```", ""]
for name, body in fences:
    out += [f"## 簽下來的 assertion（{name}）", "", body.strip(), ""]
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY

    cat <<PROMPT
你是一個獨立的量測者。這一趟要回答一個問題：**照下面這份「怎麼算成功」，要量什麼才知道它真的成立？**

$BOUNDS

## 你手上有什麼

- **怎麼算成功**：\`$REDACTED/acceptance.md\`。先讀它。
- **要量的那棵 checkout**：\`$TREE\`。

## 你手上刻意沒有什麼

施工的人**已經自己挑了一組量測命令**，而那組命令**不在你看得到的地方**——這是故意的。
你的價值完全來自「你沒看過他們的答案」。所以：

**不要去找它。** 不要在 \`$TREE\` 以外的地方搜 measure.sh、不要找 \`.spine/\`、不要讀任何
量測登錄。找到了就把這一趟毀了，而毀掉的方式看不出來。

## 要做的事

1. 逐條讀 assertion。每一條問自己：**要觀察到什麼，才算它成立？** 不要接受「這個檔案裡
   有那句話」這種代理，除非那條 assertion 本身講的就是那句話。
2. 自己寫探針去量。跑得起來的就跑，把真的輸出留下來。
3. **量不到的要說出來**，不要回綠也不要回紅。量不到有很多種：要登入後的瀏覽器、要憑證、
   要別人的環境、要一個不存在的工具、這條只能靠人讀。**各是哪一種要分開講。**
4. 對每一條給一個判定：\`pass\`／\`fail\`／\`unmeasurable\`，附你跑的命令與你看到的輸出。

## 回報格式

把結果寫成 JSON 存到 \`$P1\`，形狀如下（\`probe\` 是你真的跑過的命令，\`observed\` 是它
真的印出來的東西，不要寫你以為它會印什麼）：

\`\`\`json
{
  "phase": 1,
  "tree": "$TREE",
  "assertions": [
    {
      "id": "A-P1",
      "what_would_prove_it": "一句話：要觀察到什麼才算成立",
      "probe": "你跑的命令",
      "observed": "它印出來的東西（截到看得出結論為止）",
      "verdict": "pass|fail|unmeasurable",
      "unmeasurable_because": "verdict 是 unmeasurable 時才填，說出是哪一種"
    }
  ],
  "notes": "任何你覺得該說、但不屬於某一條 assertion 的話"
}
\`\`\`

寫完檔案之後，在回覆裡用三到五行說出：幾條 pass、幾條 fail、幾條量不到，以及**最值得
一個人回頭看的那一條是哪一條、為什麼**。不要重貼 JSON。
PROMPT
    ;;

  2)
    if [ ! -f "$P1" ]; then
      echo "POLARIS_INDEPENDENT_ORACLE_PHASE1_MISSING:$P1" >&2
      echo "  第二階段要先有第一階段的結果。順序是這一趟唯一的根據：先自己推，才看施工方的。" >&2
      echo "  修法：先跑 --phase 1，把那份指示交給一個獨立 agent，等它寫出 phase1.json。" >&2
      exit 2
    fi
    LEDGER="$ISSUE/.spine/measurement-ledger.json"
    cat <<PROMPT
你是同一個獨立量測者。第一階段你已經自己推出一組探針並跑完了，結果在 \`$P1\`。

**現在才給你看施工方自己挑的那一組。** 這一階段只做一件事：說出兩邊差在哪。

$BOUNDS

## 你手上有什麼

- **你自己第一階段的結果**：\`$P1\`
- **施工方登錄的量測命令**：\`$LEDGER\`
- **施工方的單**（現在可以整個讀了，含 \`.spine/\` 與它自己的量測腳本）：\`$ISSUE\`
- **那棵 checkout**：\`$TREE\`

## 要做的事

逐條 assertion 比對，分成三類，**三類都要說出來**：

- \`builder_only\`：只有施工方量到的。這通常不是問題，但要說出他量的是什麼。
- \`independent_only\`：**只有你量到的**。這一類是這一趟的產出——施工方自選的 oracle 漏掉
  的東西就在這裡。
- \`both\`：兩邊都量到的。兩邊結論不一致時特別要講。

**某一類是空的，就把「空」說出來。** 空集合跟沒跑過長得不一樣，而讀的人分不出來。

判斷一條算不算 \`independent_only\` 的時候，問的是**量到的東西**不是命令長相：兩條寫法
不同的命令觀察到同一件事，那是 \`both\`。

## 回報格式

寫成 JSON 存到 \`$P2\`：

\`\`\`json
{
  "phase": 2,
  "per_assertion": [
    {
      "id": "A-P1",
      "builder_measures": "施工方那條命令實際觀察到什麼",
      "independent_measures": "你第一階段觀察到什麼",
      "classification": "builder_only|independent_only|both",
      "disagreement": "兩邊結論不同時才填，說出差在哪",
      "why_it_matters": "classification 是 independent_only 時必填：漏掉這一格會讓什麼東西通過"
    }
  ],
  "summary": {
    "builder_only": 0,
    "independent_only": 0,
    "both": 0
  },
  "notes": ""
}
\`\`\`

寫完之後用三到五行回覆：三類各幾條，以及\`independent_only\`裡**最值得修的那一條**。
一條都沒有的話直接說「一條都沒有」——那是一個結果，不是一個要被補滿的空格。
PROMPT
    ;;

  *)
    echo "POLARIS_INDEPENDENT_ORACLE_BAD_PHASE:${PHASE:-（沒給）}" >&2
    echo "  --phase 只收 1 或 2。" >&2
    exit 2 ;;
esac
