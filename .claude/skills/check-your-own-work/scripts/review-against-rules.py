#!/usr/bin/env python3
"""讓一個沒看過施工對話的 agent，拿指名的那幾節規矩，逐條審一份要交出去的東西。

用途：交付物（報告、對外訊息稿、PR 描述）交給別人之前，讀規矩的一方換成一個專門讀規矩的
      agent。施工的那一方當下讀不讀得到那一節，不再決定那一節有沒有被對過。
輸入：--deliverable 交付物檔案（.html 先去掉標籤成文字）；--rule <檔案>[#<節名>]，可給多次，
      沒給節名就是整份檔案；--out 結果寫到哪；--agent-cmd 換掉啟動命令，prompt 接在最後一個參數。
輸出：審查結果原樣寫進 --out 並印出。每一條是「符合／不符合／無法判斷｜規則：「…」｜交付物：
      「…」｜理由」，開頭說出讀了哪幾節，結尾一行計數。
離場：0 ＝ 審出來了，不論幾條不符合——這是意見，不擋人；2 ＝ 交付物或某一節讀不到；
      3 ＝ agent 跑不起來或非 0；4 ＝ agent 有輸出，但不是上面那個形狀（沒審到，不是沒問題）。

agent 跑在一個新開的空目錄裡，手上只有這份 prompt：看不到施工的對話，也讀不到這個 repo。
"""

import argparse
import html
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_AGENT = "claude -p --setting-sources project --strict-mcp-config --no-session-persistence"
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
VERDICT_LINE = re.compile(r"^- (符合|不符合|無法判斷)｜規則：「")

PROMPT = """你是審查者。下面有一份要交給別人看的東西（交付物），以及寫它時要遵守的幾節規矩。
你沒有看過寫它的那段對話，也不需要看。只根據下面給你的文字判斷。

做法：把每一節規矩拆成一條一條可以判斷的要求，逐條拿去對交付物。
每一條輸出一行，形狀固定，不要加別的格式：

- 不符合｜規則：「<規矩原句，照抄>」｜交付物：「<交付物裡對不上的那一句，照抄>」｜<一句理由>
- 不符合｜規則：「<規矩原句>」｜交付物：「（沒有）」｜<交付物裡根本沒有對應的句子時，照這一行寫，引號不省>
- 符合｜規則：「<規矩原句>」｜交付物：「<對得上的那一句>」｜<一句理由>
- 無法判斷｜規則：「<規矩原句>」｜交付物：「（沒有）」｜<缺了什麼才判得出來>

輸出的第一段，每一節各一行：讀了：<那一節的來源>
最後一行：結論：不符合 N 條、符合 M 條、無法判斷 K 條
不符合的排在前面。不要給分數，不要總評。

{rules}

==== 交付物（{deliverable_name}）====
{deliverable}
==== 交付物結束 ====
"""


def read_text(path: Path) -> str:
    """讀一個檔案；.html 去掉 script、style 與標籤，留下讀的人看得到的文字。"""
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in (".html", ".htm"):
        text = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", text, flags=re.S | re.I)
        text = html.unescape(re.sub(r"<[^>]+>", "\n", text))
        text = re.sub(r"\n\s*\n+", "\n", text)
    return text.strip()


def extract_section(text: str, name: str):
    """回傳標題含 name 的那一節（到下一個同級或更高的標題為止），找不到回 None。

    標題常帶〈〉或冒號後的說明，所以比的是「包含」，不是相等。
    """
    lines = text.splitlines()
    in_fence = False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            in_fence = not in_fence
        m = None if in_fence else HEADING.match(line)
        if not m or name not in m.group(2):
            continue
        level = len(m.group(1))
        out, fence = [line], False
        for nxt in lines[i + 1:]:
            if nxt.startswith("```"):
                fence = not fence
            h = None if fence else HEADING.match(nxt)
            if h and len(h.group(1)) <= level:
                break
            out.append(nxt)
        return "\n".join(out).strip()
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--deliverable", required=True)
    ap.add_argument("--rule", action="append", required=True, help="<檔案>[#<節名>]，可給多次")
    ap.add_argument("--out")
    ap.add_argument("--agent-cmd", default=DEFAULT_AGENT)
    ap.add_argument("--print-prompt", action="store_true", help="只印 prompt，不派 agent")
    a = ap.parse_args()

    deliverable = Path(a.deliverable)
    if not deliverable.is_file():
        print(f"讀不到交付物：{deliverable}", file=sys.stderr)
        return 2

    blocks = []
    for spec in a.rule:
        path_s, _, name = spec.partition("#")
        path = Path(path_s)
        if not path.is_file():
            print(f"讀不到規矩檔：{path}", file=sys.stderr)
            return 2
        text = path.read_text(encoding="utf-8")
        body = extract_section(text, name) if name else text.strip()
        if body is None:
            print(f"{path} 裡找不到標題含「{name}」的那一節", file=sys.stderr)
            return 2
        source = f"{path_s}〈{name}〉" if name else path_s
        blocks.append(f"==== 規矩：{source} ====\n{body}\n==== 這一節結束 ====")

    prompt = PROMPT.format(rules="\n\n".join(blocks), deliverable_name=deliverable.name,
                           deliverable=read_text(deliverable))
    if a.print_prompt:
        print(prompt)
        return 0

    with tempfile.TemporaryDirectory(prefix="rule-review-") as blank:
        try:
            run = subprocess.run([*shlex.split(a.agent_cmd), prompt], cwd=blank,
                                 capture_output=True, text=True)
        except OSError as e:
            print(f"agent 跑不起來（{a.agent_cmd}）：{e}", file=sys.stderr)
            return 3
    if run.returncode != 0:
        print(f"agent 回 {run.returncode}：{run.stderr.strip()[:500]}", file=sys.stderr)
        return 3

    # 交付物裡沒有對應句子的那幾條，agent 常省掉引號；補回來，讀的人與後續比對看到的是同一個形狀。
    result = run.stdout.strip().replace("｜交付物：（沒有）｜", "｜交付物：「（沒有）」｜")
    if a.out:
        Path(a.out).write_text(result + "\n", encoding="utf-8")
    print(result)
    if "讀了：" not in result or not any(VERDICT_LINE.match(l) for l in result.splitlines()):
        print("agent 的輸出不是逐條判定的形狀：這一趟沒審到，不代表沒有問題", file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
