#!/usr/bin/env bash
# 91 天的逐日匯入量：20 天是批次匯入（每天數千），其餘 71 天是平常日（每天數十）。數字是佔位。
# 另外放一份前一個人已經算好的全期統計，跟標本那一格的起點相同。
set -euo pipefail
python3 - <<'PY'
import datetime, random, statistics
random.seed(7)
start = datetime.date(2026, 8, 6)
batch = set(random.sample(range(91), 20))
rows = []
for i in range(91):
    n = random.randint(5200, 11800) if i in batch else random.randint(40, 130)
    rows.append((start + datetime.timedelta(days=i), n))
with open("daily-imports.csv", "w") as fh:
    fh.write("date,imported\n")
    fh.writelines(f"{d},{n}\n" for d, n in rows)
ns = [n for _, n in rows]
big = [n for n in ns if n > 1000]
with open("stats.txt", "w") as fh:
    fh.write(f"期間：{rows[0][0]} ～ {rows[-1][0]}（91 天）\n合計：{sum(ns):,}\n每天平均：{sum(ns) // len(ns):,}\n"
             f"中位數：{int(statistics.median(ns)):,}\n超過 1,000 的天數：{len(big)}，合計占 {round(100 * sum(big) / sum(ns))}%\n")
with open("STANDUP.md", "w") as fh:
    fh.write("# 站會\n\n## 昨天\n- 匯入流程的監控補上了\n\n## 今天\n- 跟 PM 對每日匯入量要不要擴容\n\n## 卡關\n- \n")
PY
