#!/usr/bin/env bash
# 算出這一趟巡檢的時間窗：現在該不該跑一輪、下一輪要等多久。
#
# 用法：
#   resolve-sweep-window.sh [--interval 20m] [--until 18:00]
#
# 輸出（stdout，JSON 一行）：
#   interval_seconds  一輪之間隔多久
#   until_epoch       停止時間的 epoch 秒
#   until_human       停止時間，給人看的字串
#   should_run        現在還在窗內、可以跑一輪
#   next_delay        下一輪要等幾秒；0 表示不再排下一輪
#   reason            should_run=false 或 next_delay=0 時的原因
set -euo pipefail

interval="20m"
until_at="18:00"
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="$2"; shift 2 ;;
    --until)    until_at="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

INTERVAL="$interval" UNTIL="$until_at" python3 - <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta

def parse_interval(text):
    """把 '20m' / '90s' / '1h' / '20' 換成秒數。純數字當分鐘。"""
    m = re.fullmatch(r'\s*(\d+)\s*([smh]?)\s*', text, re.I)
    if not m:
        raise SystemExit(f"POLARIS_SWEEP_BAD_INTERVAL: 讀不懂間隔 {text!r}，形狀是 20m / 90s / 1h")
    n, unit = int(m.group(1)), (m.group(2) or 'm').lower()
    return n * {'s': 1, 'm': 60, 'h': 3600}[unit]

def parse_until(text, now):
    """把 '18:00' / '1800' / '18' 換成今天的那個時刻。已過的時刻不推到明天——巡檢是當日的事。"""
    t = text.strip()
    m = re.fullmatch(r'(\d{1,2})[:：]?(\d{2})?', t)
    if not m:
        raise SystemExit(f"POLARIS_SWEEP_BAD_UNTIL: 讀不懂停止時間 {text!r}，形狀是 18:00")
    hour, minute = int(m.group(1)), int(m.group(2) or 0)
    return now.replace(hour=hour, minute=minute, second=0, microsecond=0)

now = datetime.now()
interval_seconds = parse_interval(os.environ['INTERVAL'])
until = parse_until(os.environ['UNTIL'], now)

remaining = (until - now).total_seconds()
should_run = remaining > 0
reason = ""
next_delay = 0

if not should_run:
    reason = f"現在 {now:%H:%M} 已過停止時間 {until:%H:%M}，這一趟不跑"
elif remaining <= interval_seconds:
    reason = f"距停止時間 {until:%H:%M} 只剩 {int(remaining // 60)} 分鐘，跑完這一輪就收工"

print(json.dumps({
    "interval_seconds": interval_seconds,
    "until_epoch": int(until.timestamp()),
    "until_human": f"{until:%H:%M}",
    "now_human": f"{now:%H:%M}",
    "should_run": should_run,
    "next_delay": interval_seconds if (should_run and remaining > interval_seconds) else 0,
    "reason": reason,
}, ensure_ascii=False))
PY
