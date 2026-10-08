#!/usr/bin/env python3
"""check-prd-provenance.py — 開發計畫交出去之前，逐條問「這一條是誰要的」。

用法：
  python3 check-prd-provenance.py <開發計畫檔（.md 或 .html）>

計畫檔要帶一行 `<!-- PRD-ISSUE: {單的目錄} -->`（絕對路徑，或相對於計畫檔）。
檢查從那個目錄讀兩份東西：
  - requirement-snapshot.md：開單那一刻存下的需求原文
  - index.md 的〈使用者原話〉一節

依據標記的寫法與規則在 references/prd-template.md〈依據標記〉。

離場碼：0 全部有出處／1 有項目不合規則（逐條列出）／2 讀不到計畫、快照或單的正文
只用 python3 標準函式庫，不依賴任何一家 LLM 工具。
"""

import html
import os
import re
import sys

MARK = re.compile(r"〔(?:依據|出處)\s*([SP]\d+)：([^〕]*)〕")
ISSUE = re.compile(r"<!--\s*PRD-ISSUE:\s*(.+?)\s*-->")
QUOTE = re.compile(r"「([^」]+)」")
DERIVE = re.compile(r"←\s*([SP]\d+(?:\s*[、,]\s*[SP]\d+)*)")
DISPOSITION_AGAINST = ("RD 不做", "跟需求單位相反", "跟需求方相反")
FROM_REQUESTER = ("需求單位", "需求方")
EXCLUDING_HEADINGS = ("不做什麼", "Out of scope", "依賴")
SEPARATOR = re.compile(r"^\|[\s\-:|]+\|?$")


def die(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def html_to_text(src):
    src = re.sub(r"(?is)<(script|style)\b.*?</\1>", "", src)
    # 表頭列不是項目：<thead> 裡的列、含 <th> 的列，儲存格換成「‖」，轉出來不以「|」開頭
    src = re.sub(r"(?is)<thead\b.*?</thead>", lambda m: re.sub(r"(?i)<td\b", "<th", m.group(0)), src)
    src = re.sub(r"(?is)<tr\b(?:(?!</tr>).)*?<th\b.*?</tr>",
                 lambda m: re.sub(r"(?i)<t[dh]\b[^>]*>", " ‖ ", m.group(0)), src)
    src = re.sub(r"(?i)<h([1-6])\b[^>]*>", lambda m: "\n" + "#" * int(m.group(1)) + " ", src)
    src = re.sub(r"(?i)</(h[1-6]|p|li|tr|div|section|table|ul|ol)>|<br\s*/?>", "\n", src)
    src = re.sub(r"(?i)<li\b[^>]*>", "\n- ", src)
    src = re.sub(r"(?i)<t[dh]\b[^>]*>", " | ", src)
    src = re.sub(r"(?s)<(?!!--)[^>]+>", "", src)
    return html.unescape(src)


def norm(s):
    return re.sub(r"\s+", "", s)


def read(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        die(2, f"讀不到{what}：{path}（{exc.strerror}）。問不到不放行。")


def sections(text):
    """回傳 [(標題鏈, 行)]，標題鏈是由上而下的標題文字。"""
    chain, out = [], []
    for line in text.splitlines():
        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            level = len(m.group(1))
            chain = [c for c in chain if c[0] < level] + [(level, m.group(2).strip())]
            continue
        out.append(([c[1] for c in chain], line))
    return out


def where(chain):
    """這一行屬於模板的哪一格需要出處；不需要回 None。"""
    joined = " / ".join(chain)
    if re.search(r"(^|/ )3\.\s*目標與範圍", joined):
        return "第 3 章"
    if re.search(r"(^|/ )5\.\s*時程規劃", joined):
        return "第 5 章"
    if re.search(r"(^|/ )8\.\s*待確認事項", joined):
        return "第 8 章"
    if re.search(r"附錄\s*B", joined):
        return "附錄 B"
    return None


def is_item(line, place, in_cooperation, header=False):
    s = line.strip()
    table_row = s.startswith("|") and not SEPARATOR.match(s) and not header
    list_item = bool(re.match(r"^(-|\*|\d+\.)\s+", s))
    if place == "第 3 章":
        return list_item
    if place == "第 5 章":
        return list_item and in_cooperation
    if place in ("第 8 章", "附錄 B"):
        return table_row
    return False


def tokens(s):
    words = {w.lower() for w in re.findall(r"[A-Za-z0-9]{2,}", s)}
    cjk = re.sub(r"[^一-鿿]", " ", s)
    grams = {a + b for part in cjk.split() for a, b in zip(part, part[1:])}
    return words | grams


def main():
    if len(sys.argv) != 2:
        die(2, __doc__.strip())
    plan_path = sys.argv[1]
    raw = read(plan_path, "開發計畫")
    m = ISSUE.search(raw)
    if not m:
        die(2, "計畫檔沒有帶 `<!-- PRD-ISSUE: {單的目錄} -->`，找不到需求原文快照與〈使用者原話〉。"
               "補上那一行再跑（寫法見 prd-template.md〈依據標記〉）。")
    issue = m.group(1)
    if not os.path.isabs(issue):
        issue = os.path.join(os.path.dirname(os.path.abspath(plan_path)), issue)
    snapshot = read(os.path.join(issue, "requirement-snapshot.md"), "需求原文快照")
    index = read(os.path.join(issue, "index.md"), "單的正文")
    um = re.search(r"(?ms)^##\s*使用者原話\s*$(.*?)(?=^##\s|\Z)", index)
    if not um:
        die(2, f"單的正文沒有〈使用者原話〉一節：{os.path.join(issue, 'index.md')}。問不到不放行。")
    user_said = norm(um.group(1))
    snap_norm = norm(snapshot)

    text = html_to_text(raw) if plan_path.lower().endswith((".html", ".htm")) else raw
    items, marks, problems = [], {}, []
    in_coop = False
    rows = sections(text)
    for i, (chain, line) in enumerate(rows):
        # Markdown 的表頭列是分隔線上面那一列
        header = i + 1 < len(rows) and bool(SEPARATOR.match(rows[i + 1][1].strip()))
        place = where(chain)
        if place == "第 5 章" and "需要配合的事" in line:
            in_coop = True
        if place != "第 5 章":
            in_coop = False
        found = MARK.findall(line)
        for mid, body in found:
            marks[mid] = (place, body, line.strip())
        if place and is_item(line, place, in_coop, header):
            items.append((place, line.strip(), found))

    for place, line, found in items:
        if not found:
            problems.append(f"{place}：沒有依據標記 —— {line}")

    # 每一個標記本身的規則
    for mid, (place, body, line) in marks.items():
        kind = body.split("｜")[0].strip()
        if kind.startswith(FROM_REQUESTER):
            q = QUOTE.findall(kind)
            if not q:
                problems.append(f"{mid}：標成需求單位原文卻沒有引文「…」—— {line}")
            for quote in q:
                if norm(quote) not in snap_norm:
                    problems.append(f"{mid}：需求單位原文的引文在快照裡找不到逐字相同的一段：「{quote}」")
        elif kind.startswith("使用者"):
            q = QUOTE.findall(kind)
            if not q:
                problems.append(f"{mid}：標成使用者原話卻沒有引文「…」—— {line}")
            for quote in q:
                if norm(quote) not in user_said:
                    problems.append(f"{mid}：使用者原話在單的〈使用者原話〉一節裡找不到：「{quote}」")
        elif kind.startswith("RD 推導"):
            d = DERIVE.search(kind)
            if not d:
                problems.append(f"{mid}：RD 推導沒有寫推導自哪一條（←S1）—— {line}")
            else:
                for ref in re.split(r"\s*[、,]\s*", d.group(1)):
                    if ref not in marks:
                        problems.append(f"{mid}：推導指到一個不存在的標記 {ref}")
        elif kind.startswith("RD 提案"):
            if place != "第 8 章":
                problems.append(f"{mid}：RD 提案只能寫在第 8 章，這一條在{place or '正文'} —— {line}")
            parts = [p.strip() for p in body.split("｜")]
            if not any(p.startswith("向") for p in parts) or not any(re.search(r"\d{4}-\d{2}-\d{2}", p) for p in parts):
                problems.append(f"{mid}：RD 提案要寫向誰確認與確認期限（｜向〈誰〉確認｜YYYY-MM-DD 前）")
        else:
            problems.append(f"{mid}：不認得的依據種類「{kind}」，只有需求單位／使用者／RD 推導／RD 提案四種")

    # 提案往下傳染：推導鏈上有提案的，也是提案
    def from_proposal(mid, seen=()):
        if mid in seen or mid not in marks:
            return None
        body = marks[mid][1]
        if body.strip().startswith("RD 提案"):
            return mid
        d = DERIVE.search(body)
        if d:
            for ref in re.split(r"\s*[、,]\s*", d.group(1)):
                hit = from_proposal(ref, seen + (mid,))
                if hit:
                    return hit
        return None

    for mid, (place, body, line) in marks.items():
        if body.strip().startswith("RD 推導") and place != "第 8 章":
            root = from_proposal(mid)
            if root:
                problems.append(f"{mid}：推導自提案 {root}，提案往下傳染，它也是提案，不能寫在{place or '正文'} —— {line}")

    # 需求方自己排除的，不能寫成 RD 不做或跟需求方相反
    # 標題或粗體小標（**不做什麼（Out of scope）：**）都算一段的開頭
    excluded, head = [], ""
    for l in snapshot.splitlines():
        h = re.match(r"^#{1,6}\s+(.*)", l) or re.match(r"^\*\*(.+?)\*\*\s*$", l.strip())
        if h:
            head = h.group(1).strip()
        elif l.strip() and any(k.lower() in head.lower() for k in EXCLUDING_HEADINGS):
            excluded.append((head, l.strip().lstrip("*- ").strip()))
    df = {}
    for line in snapshot.splitlines():
        for t in tokens(line):
            df[t] = df.get(t, 0) + 1
    for mid, (place, body, line) in marks.items():
        parts = [p.strip() for p in body.split("｜")]
        if not parts[0].startswith(FROM_REQUESTER) or not any(p in DISPOSITION_AGAINST for p in parts[1:]):
            continue
        mine = {t for t in tokens(line) if df.get(t, 0) and df[t] <= 2}
        for head, para in excluded:
            shared = mine & tokens(para)
            if len(shared) >= 2:
                problems.append(f"{mid}：需求單位自己在〈{head}〉排除或標成未確認，不是 RD 不做、也不是跟需求單位相反，改接｜需求單位排除〈{head}〉。"
                                f"快照那一段：{para}")
                break

    if problems:
        print(f"開發計畫有 {len(problems)} 條依據問題，不交件：")
        for p in problems:
            print(f"  - {p}")
        sys.exit(1)
    print(f"依據齊全：{len(items)} 個該帶標記的項目、{len(marks)} 個標記，全部對得上。")


if __name__ == "__main__":
    main()
