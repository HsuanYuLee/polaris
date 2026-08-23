#!/usr/bin/env python3
"""reply-guard.py — Stop hook：在話講完的那一刻，量一次自己剛講的話。

為什麼是 hook 而不是規則、也不是任何一支 skill
------------------------------------------------
怎麼跟人講話是這個框架的事，不是某一支 skill 的知識——skill 會被單獨帶到別的環境，
而「講話要讓人聽得懂」在那裡也成立，卻不屬於其中任何一支。2026-08-23 那一版把八個
徵兆寫進常駐規則，隔天三則回覆全部照犯（13、6、2 處）：規則只有被讀到才生效，而讀到
不等於照做。hook 不同的地方只有一件，它必然執行。

離場碼 2 會把 stderr 交回給模型並要它繼續，所以這一支真的會擋。防無限迴圈靠
stop_hook_active：已經因為它擋過一次就放行，剩下的由人看。

三種用法：
  echo '<Stop hook 的 JSON>' | python3 reply-guard.py     # 當 hook，會擋
  python3 reply-guard.py <檔案> [檔案...]                  # 手動量詞與句型
  python3 reply-guard.py --judge [1|2] <檔案>...           # 找另一個模型判結構
      1＝對話裡那位讀者（預設）　2＝素未謀面的同事

詞與句型 regex 抓得到，所以那一半掛在 hook 上、每次自己跑。結構抓不到——「讀完知不知道
要做什麼」沒有機械的量法，全世界的 prose linter 都不做這件事。那一半要找另一個模型判，
所以它慢、要花錢、不掛在 hook 上，是要看分數的時候自己跑。

"""
# 這一行是宣告，不是註解：同步問「這個 hook 出不出得去」時讀的就是它。機制沒有一個字綁
# 這台機器或這家公司——這個工作區自己的詞彙住在旁邊那份 reply-guard-words.json，那一份
# 不出去。
# POLARIS-SCOPE: standalone
import json
import os
import re
import sys

# 詞表是某一個工作區自己的東西，不屬於機制。旁邊那份 reply-guard-words.json 拿掉之後，
# 下面 PATTERNS 那幾條（跟中文這個語言有關、跟哪個 repo 無關）照樣跑，而且會說出詞表沒載到。
WORDS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reply-guard-words.json")


def load_words():
    try:
        with open(WORDS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return [], [], False
    return (list(data.get("internal") or []), list(data.get("coined") or []), True)


INTERNAL, COINED, WORDS_LOADED = load_words()

PATTERNS = [
    ("破折號成對夾插入語", re.compile(r"——[^\n——]{1,40}——")),
    ("名詞化動詞", re.compile(r"(進行|做出|產生|造成|加以|給予)[一-鿿]{2}")),
    ("冒號宣告句", re.compile(r"只有一[個件條][^\n]{0,6}：")),
    ("不是X是Y 堆疊", re.compile(r"不是[^，。\n]{1,24}，[是而]")),
    ("被動的「是…出來的」", re.compile(r"是[^，。\n]{2,12}出來的")),
]


def find(text):
    """回傳 [(行號, 類別, 命中的字)]。引述不算犯——指名一個詞是為了說它不好，
    跟拿它來講話是兩件事。圍籬區塊與引文行整行跳過。"""
    hits = []
    in_fence = False
    for i, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or line.lstrip().startswith(">"):
            continue
        # 用「」或反引號框起來的是在指名一個詞，不是拿它來講話，同引文處理。
        bare = re.sub(r"「[^」\n]{0,40}」|`[^`\n]{0,60}`", "", line)
        for word in INTERNAL:
            if word in bare:
                hits.append((i, "框架內部詞", word))
        for word in COINED:
            if word in bare:
                hits.append((i, "自造詞", word))
        for name, pat in PATTERNS:
            for m in pat.finditer(bare):
                hits.append((i, name, m.group(0)[:24]))
    return hits


def shape(text):
    """量得到但不擋人的幾項：長度、粗體密度、清單長度。"""
    chars = len(re.sub(r"\s", "", text))
    bold = len(re.findall(r"\*\*[^*\n]+\*\*", text))
    longest, run = 0, 0
    for line in text.split("\n"):
        run = run + 1 if re.match(r"^\s*([-*]|\d+\.)\s", line) else 0
        longest = max(longest, run)
    return chars, bold, longest


def last_reply(payload):
    """Stop hook 給的最後一則助理發言。新版直接給，舊版要自己讀 transcript。"""
    direct = payload.get("last_assistant_message")
    if isinstance(direct, str) and direct.strip():
        return direct
    path = payload.get("transcript_path")
    if not path:
        return None
    found = None
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "assistant":
                    continue
                parts = [c.get("text", "") for c in d.get("message", {}).get("content", [])
                         if c.get("type") == "text"]
                text = "\n".join(p for p in parts if p.strip())
                if text.strip():
                    found = text
    except OSError:
        return None
    return found


def report(text, name):
    hits = find(text)
    chars, bold, longest = shape(text)
    print("== %s ==" % name)
    if not WORDS_LOADED:
        print("  注意：詞表沒載到（%s），這一趟只量句型。" % WORDS_FILE)
    print("字數 %d／粗體 %d 處／最長的清單 %d 項" % (chars, bold, longest))
    for i, kind, what in hits:
        print("  第 %-4d 行  %-14s %s" % (i, kind, what))
    print("  問題共 %d 處\n" % len(hits))
    return len(hits)


# 兩個標準，兩種讀者。
#
# 這個分別是 2026-08-24 第一次拿 --judge 量自己時撞出來的：用第二關的標準去判一則對話中
# 的回覆，它每次都掛在「這句要回頭看上文」，而在對話裡回頭看上文本來就成立。不分開的話，
# 分數永遠說同一件事，而那件事不是當下要改的那件。
READER = {
    "1": "這則回覆是寫給對話裡那位工程師的，他知道前面聊過什麼。"
         "所以「上一則」「你剛講的那個」這種指涉不算問題，"
         "他不認得的自造詞、以及只有某個 repo 裡才有定義的詞才算。",
    "2": "把這則回覆原封不動轉給一位素未謀面的同事，他沒有讀過前面任何一句。",
}

EXTRA = {
    "1": "",
    "2": "\n4. colleague_would_reply：那位同事會願意回你，還是會覺得這是 AI 產的東西"
         "而不想理？願意回才算 pass。",
}


def rubric(stage):
    return RUBRIC % (READER[stage], EXTRA[stage])


RUBRIC = """你要判一則回覆，語言是繁體中文。

讀者：%s

每題只答 pass 或 fail，各附一句話理由（繁體中文，不超過 30 字）：

1. reader_knows_next_step：讀完之後，讀的人能不能用一句話說出「所以我接下來該做什麼」？
2. no_lookup_needed：有沒有任何詞、代稱、縮寫，這位讀者得回頭問寫的人才懂？沒有才算 pass。
3. claims_have_evidence：每一個判斷有沒有帶得走的根據（檔案路徑、數字、命令輸出、連結）？
   全部都有才算 pass，有任何一個空口斷言就 fail。%s

只輸出 JSON，不要任何其他文字，key 就是上面那幾個名字，值是
{"verdict":"pass","why":"..."}。

要判的回覆從下一行開始：
"""


def judge(text, name, stage):
    """找另一個模型判結構。慢、要花錢，所以不掛在 hook 上。"""
    import subprocess
    proc = subprocess.run(
        ["claude", "-p", "--model", "sonnet"],
        input=rubric(stage) + text, capture_output=True, text=True, timeout=180)
    raw = proc.stdout.strip()
    m = re.search(r"\{.*\}", raw, re.S)
    if not m:
        print("== %s ==\n  判不出來：%s\n" % (name, (raw or proc.stderr)[:200]))
        return None
    try:
        result = json.loads(m.group(0))
    except ValueError:
        print("== %s ==\n  回傳不是 JSON\n" % name)
        return None
    passed = sum(1 for v in result.values() if v.get("verdict") == "pass")
    print("== %s ==  %d/%d" % (name, passed, len(result)))
    for key, v in result.items():
        mark = "通過" if v.get("verdict") == "pass" else "不通過"
        print("  %-24s %s  %s" % (key, mark, v.get("why", "")))
    print()
    return passed, len(result)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--judge":
        args = sys.argv[2:]
        stage = "1"
        if args and args[0] in ("1", "2"):
            stage, args = args[0], args[1:]
        got = [r for r in (judge(open(f, encoding="utf-8").read(), f.split("/")[-1], stage)
                           for f in args) if r]
        if got:
            print("合計 %d/%d（第 %s 關的標準）"
                  % (sum(p for p, _ in got), sum(n for _, n in got), stage))
        return 0

    if len(sys.argv) > 1:
        total = 0
        for path in sys.argv[1:]:
            total += report(open(path, encoding="utf-8").read(), path)
        print("全部合計 %d 處" % total)
        return 0

    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0

    # 已經因為這一支擋過一次就放行，不然會永遠停不下來。
    if payload.get("stop_hook_active"):
        return 0

    text = last_reply(payload)
    if not text:
        return 0

    hits = find(text)
    if not hits:
        return 0

    lines = ["這則回覆有 %d 處讀的人會回頭問你在說什麼，改掉再送：" % len(hits)]
    if not WORDS_LOADED:
        lines.append("  （詞表沒載到，這一趟只量了句型）")
    for i, kind, what in hits[:12]:
        lines.append("  第 %d 行 %s：%s" % (i, kind, what))
    if len(hits) > 12:
        lines.append("  還有 %d 處" % (len(hits) - 12))
    sys.stderr.write("\n".join(lines) + "\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
