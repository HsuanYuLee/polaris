#!/usr/bin/env bash
# check-vr-config.sh — VR 設定裡的宣告，跟現實還對得起來嗎。
#
# 兩種「宣告與現實不符」在 2026-08-12 同時發生，而沒有任何東西會紅：
#
#   一、宣告的瀏覽器是 chromium，而某個 project 用的 device 跑的是 webkit。機器上沒裝，
#       於是那一趟每一張都 `Executable does not exist`——那句話講的是執行檔不在，不是
#       「你的宣告跟你的 project 對不起來」，所以人會先去找環境的問題。
#   二、設定裡列的頁面死了。2026-08-13 量：四個裡三個跟到最終位置之後是 404，而其中兩個
#       第一個回應碼是 301／302——只看第一跳會以為它們活著。設定檔自己那行「search-results
#       已移除 — production 404」證明這件事以前發生過、有人手動清過一次然後就沒再清。
#       **一次手動清理不會變成下一次的檢查。**
#
# 三個子命令，因為它們的代價不一樣：`browsers` 與 `knowledge` 不連網，`pages` 要連網。
# 把要連網的那一個混進來，會讓沒有網路的地方連前兩個都跑不了。
#
# Usage:
#   check-vr-config.sh browsers  [--config <公司設定>] [--vr-root <VR tooling 根>]
#   check-vr-config.sh pages     [--config <公司設定>] [--timeout <秒>] [--prober <cmd>]
#   check-vr-config.sh knowledge [--skill-dir <path>]
#
# Exit:
#   0 — 量到了，而且對得起來
#   1 — 量到了，而且是紅的
#   2 — 量不到（設定不在、那棵 tooling 樹不在、一個目標都沒列到、連不上）
#
# **量不到不是紅也不是綠。** VR 的 tooling 樹不在版控裡（見
# `references/visual-regression-config.md`），所以「它不在」是常態而不是錯誤；對它判紅會
# 讓這道檢查在三次之後被關掉，判綠則是說謊。

set -uo pipefail

PREFIX="[polaris check-vr-config]"
SUB="${1:-}"
[[ -n "$SUB" ]] && shift

CONFIG=""
VR_ROOT=""
SKILL_DIR=""
TIMEOUT=20
# 探測那一步抽成可替換的：判定邏輯（跟到最終位置之後是不是 2xx、連不上算什麼）要能在沒有
# 網路的地方被注入驗證，否則它的紅控只能靠某個外部站台今天剛好是什麼樣子。
PROBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)    CONFIG="${2:-}"; shift 2 ;;
    --vr-root)   VR_ROOT="${2:-}"; shift 2 ;;
    --skill-dir) SKILL_DIR="${2:-}"; shift 2 ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 ;;
    --prober)    PROBER="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

# 工作區根往上找，不從腳本位置往下數固定層數——DP-518 修過同一類的錯，那個相對深度在
# 腳本歸位到 skill 目錄之後就停錯了一層。
find_workspace_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.claude/skills" ]] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

[[ -n "$SKILL_DIR" ]] || SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$SUB" in
  browsers)
    [[ -n "$CONFIG" ]] || { echo "$PREFIX 量不到：browsers 要 --config <公司設定>。" >&2; exit 2; }
    [[ -f "$CONFIG" ]] || { echo "$PREFIX 量不到：設定檔不在 ${CONFIG}。" >&2; exit 2; }
    if [[ -z "$VR_ROOT" ]]; then
      echo "$PREFIX 量不到：browsers 要 --vr-root <VR tooling 根>——那棵樹不在版控裡，" >&2
      echo "$PREFIX 位置只有這台機器知道，所以不從設定推。" >&2
      exit 2
    fi
    python3 - "$CONFIG" "$VR_ROOT" "$PREFIX" <<'PY'
import os
import re
import sys

config_path, vr_root, prefix = sys.argv[1:4]

# 具名 device → 引擎。表是 Playwright 自己的分法，這裡只認它分得出來的那三種；認不出來的
# device 名字要說出來，不要當成 chromium。
WEBKIT = re.compile(r"iPhone|iPad|Safari|Desktop Safari", re.IGNORECASE)
FIREFOX = re.compile(r"Firefox", re.IGNORECASE)
CHROMIUM = re.compile(r"Chrome|Chromium|Pixel|Galaxy|Nexus|Moto|Edge", re.IGNORECASE)


def engine_of(device_name):
    if WEBKIT.search(device_name):
        return "webkit"
    if FIREFOX.search(device_name):
        return "firefox"
    if CHROMIUM.search(device_name):
        return "chromium"
    return None


# 宣告的集合從公司設定往上找 root defaults；剖析器故意很窄，看不懂就拒絕。
def declared_browsers(path):
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(path))),
                        "workspace-config.yaml")
    for candidate in (path, root):
        if not os.path.isfile(candidate):
            continue
        with open(candidate, encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"\s*browsers:\s*\[(.*)\]\s*$", line)
                if m:
                    return [v.strip().strip("\"'") for v in m.group(1).split(",") if v.strip()]
    return []


declared = declared_browsers(config_path)
if not declared:
    print(f"{prefix} 量不到：兩份設定裡都找不到 browsers 宣告。", file=sys.stderr)
    sys.exit(2)

configs = []
for dirpath, dirnames, filenames in os.walk(vr_root):
    dirnames[:] = [d for d in dirnames if d != "node_modules"]
    for fn in filenames:
        if fn in ("playwright.config.ts", "playwright.config.js", "playwright.config.mjs"):
            configs.append(os.path.join(dirpath, fn))

if not configs:
    print(f"{prefix} 量不到：{vr_root} 底下一份 playwright 設定都沒有。", file=sys.stderr)
    print(f"{prefix} 0 份設定的 0 個不符，跟「都對得起來」在輸出上長得一樣。", file=sys.stderr)
    sys.exit(2)

PROJECT = re.compile(r"name:\s*['\"]([^'\"]+)['\"]", re.MULTILINE)
DEVICE = re.compile(r"devices\[['\"]([^'\"]+)['\"]\]")
BROWSER_NAME = re.compile(r"browserName:\s*['\"]([^'\"]+)['\"]")

projects = 0
bad = []
undecided = []
for path in configs:
    with open(path, encoding="utf-8") as fh:
        body = fh.read()
    starts = [m for m in PROJECT.finditer(body)]
    for i, m in enumerate(starts):
        projects += 1
        end = starts[i + 1].start() if i + 1 < len(starts) else len(body)
        chunk = body[m.end():end]
        rel = os.path.relpath(path, vr_root)
        name = m.group(1)
        explicit = BROWSER_NAME.search(chunk)
        device = DEVICE.search(chunk)
        if explicit:
            engine, how = explicit.group(1), "browserName"
        elif device:
            engine, how = engine_of(device.group(1)), f"devices['{device.group(1)}']"
            if engine is None:
                undecided.append(f"{rel}: project '{name}' 用 {how}，這張表認不出它的引擎")
                continue
        else:
            # 兩者都沒有＝吃 Playwright 的預設。**這一種不得靜靜算成通過**——它到底跑哪
            # 一顆由執行時的預設決定，而那正是這道檢查在問的東西。
            undecided.append(f"{rel}: project '{name}' 既沒有 device 也沒有 browserName，跑哪一顆由執行時的預設決定")
            continue
        if engine not in declared:
            bad.append(f"{rel}: project '{name}' 經 {how} 解出 {engine}，不在宣告的 {declared} 裡")

for line in bad:
    print("MISMATCH", line)
for line in undecided:
    print("UNDECIDED", line)
print(f"VR-BROWSERS-CHECKED configs={len(configs)} projects={projects} "
      f"declared={','.join(declared)} mismatch={len(bad)} undecided={len(undecided)}")
if bad or undecided:
    print(f"{prefix} 修法是改宣告或改那個 project，**不是去裝一顆瀏覽器**——", file=sys.stderr)
    print(f"{prefix} 裝下去等於偷偷擴充工具鏈，而宣告仍然是錯的。", file=sys.stderr)
    sys.exit(1)
PY
    exit $?
    ;;

  pages)
    [[ -n "$CONFIG" ]] || { echo "$PREFIX 量不到：pages 要 --config <公司設定>。" >&2; exit 2; }
    [[ -f "$CONFIG" ]] || { echo "$PREFIX 量不到：設定檔不在 ${CONFIG}。" >&2; exit 2; }
    if [[ -z "$PROBER" ]]; then
      command -v curl >/dev/null 2>&1 || {
        echo "POLARIS_TOOL_MISSING:curl" >&2; exit 2; }
    fi
    python3 - "$CONFIG" "$PREFIX" "$TIMEOUT" "$PROBER" <<'PY'
import re
import subprocess
import sys

config_path, prefix, timeout, prober = sys.argv[1:5]

with open(config_path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()

# 窄剖析：找 visual_regression.domains 底下每個 domain 的 sit_url 與 pages[].path。
sit_url = None
locale = None
paths = []
in_vr = False
for line in lines:
    if re.match(r"^\S", line):
        in_vr = line.startswith("visual_regression:")
        continue
    if not in_vr:
        continue
    m = re.search(r"sit_url:\s*['\"]?([^'\"#\s]+)", line)
    if m and sit_url is None:
        sit_url = m.group(1)
    m = re.search(r"locales:\s*\[\s*['\"]?([^'\",\]]+)", line)
    if m and locale is None:
        locale = m.group(1)
    m = re.search(r"^\s*path:\s*['\"]([^'\"]+)['\"]", line)
    if m:
        paths.append(m.group(1))

if not sit_url or not paths:
    print(f"{prefix} 量不到：設定裡 sit_url={sit_url!r}、頁面 {len(paths)} 個。", file=sys.stderr)
    print(f"{prefix} 0 個頁面的 0 個死連結，跟「都還在」在輸出上長得一樣。", file=sys.stderr)
    sys.exit(2)

prefix_path = f"/{locale}" if locale else ""
dead = []
unreachable = []
for path in paths:
    url = sit_url.rstrip("/") + prefix_path + path
    argv = ([prober, url] if prober else
            ["curl", "-sL", "-o", "/dev/null", "-w", "%{http_code} %{url_effective}",
             "--max-time", str(timeout), "-A", "Mozilla/5.0", url])
    out = subprocess.run(argv, capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        unreachable.append(f"{url}: 探測回 {out.returncode}")
        continue
    code, _, final = out.stdout.strip().partition(" ")
    # 跟到最終位置才判。只看第一跳的話，一個轉去錯誤頁的 301 讀起來是正常的——
    # 2026-08-13 量到的四個裡就有兩個是這樣死的。
    if not code.startswith("2"):
        dead.append(f"{url} → {code} {final}")

if unreachable:
    for line in unreachable:
        print("UNREACHABLE", line)
    print(f"{prefix} 量不到：{len(unreachable)}/{len(paths)} 個目標連不上。連不上不是「頁面死了」。",
          file=sys.stderr)
    sys.exit(2)

for line in dead:
    print("DEAD", line)
print(f"VR-PAGES-CHECKED base={sit_url} pages={len(paths)} dead={len(dead)}")
sys.exit(1 if dead else 0)
PY
    exit $?
    ;;

  knowledge)
    [[ -d "$SKILL_DIR" ]] || { echo "$PREFIX 量不到：skill 目錄不在 ${SKILL_DIR}。" >&2; exit 2; }
    python3 - "$SKILL_DIR" "$PREFIX" <<'PY'
import os
import re
import sys

skill_dir, prefix = sys.argv[1], sys.argv[2]

# 兩件只有撞過才知道的事。憑據挑行為而不是句子原文：改寫措辭不會紅，抽掉內容才會紅。
CONTRACT = {
    "tooling-tree-unversioned": (
        "references/visual-regression-config.md",
        [
            ("說出它不在版控裡", r"不在版控|沒有版控"),
            ("說出後果", r"丟了就沒了|沒有歷史"),
        ],
        "G-N4",
    ),
    "readiness-selector-per-tree": (
        "references/visual-regression-config.md",
        [
            ("不同 viewport 可能是兩棵樹", r"兩棵|不同的樹"),
            ("逾時讀起來像別的事", r"逾時"),
            ("不要跨樹共用等待條件", r"共用"),
        ],
        "G-N4",
    ),
}
ANCHOR = re.compile(r"<!--\s*VR-CONTRACT:\s*([a-z0-9-]+)\s*-->")

wanted = sorted({spec[0] for spec in CONTRACT.values()})
missing = [f for f in wanted if not os.path.isfile(os.path.join(skill_dir, f))]
if missing:
    print(f"{prefix} 量不到：散文檔不在——{', '.join(missing)}", file=sys.stderr)
    sys.exit(2)

bodies = {}
for rel in wanted:
    with open(os.path.join(skill_dir, rel), encoding="utf-8") as fh:
        bodies[rel] = fh.read()

anchors = sum(len(ANCHOR.findall(b)) for b in bodies.values())
if anchors == 0:
    print(f"{prefix} 量不到：一個錨都沒有。0 個錨跟「全部都在」長得一樣。", file=sys.stderr)
    sys.exit(2)


def section_of(body, name):
    hit = next((m for m in ANCHOR.finditer(body) if m.group(1) == name), None)
    if hit is None:
        return None
    nxt = ANCHOR.search(body, hit.end())
    return body[hit.end(): nxt.start() if nxt else len(body)]


def matches(pattern, text):
    """散文硬斷在 80 欄，一個詞會被切在兩行——原文與去掉換行的版本各比一次。"""
    if re.search(pattern, text, re.IGNORECASE | re.DOTALL):
        return True
    return bool(re.search(pattern, re.sub(r"\n\s*", "", text), re.IGNORECASE | re.DOTALL))


failures = []
checks = 0
for name, (rel, evidence, assertions) in sorted(CONTRACT.items()):
    section = section_of(bodies[rel], name)
    if section is None:
        failures.append(f"{rel}：契約點 `{name}` 的錨不在了（守 {assertions}）")
        continue
    for label, pattern in evidence:
        checks += 1
        if not matches(pattern, section):
            failures.append(f"{rel}：契約點 `{name}` 還在，但那一段沒有說「{label}」（守 {assertions}）")

print(f"VR-KNOWLEDGE-CHECKED anchors={anchors} contract_points={len(CONTRACT)} evidence_checks={checks}")
if failures:
    for line in failures:
        print(f"{prefix} 紅：{line}", file=sys.stderr)
    sys.exit(1)
PY
    exit $?
    ;;

  *)
    echo "$PREFIX 用法：check-vr-config.sh browsers|pages|knowledge [...]" >&2
    exit 2
    ;;
esac
