#!/usr/bin/env bash
# Purpose: 掃「執行宣告」這一面——mise 任務與 hook 註冊指名的檔案，還在不在。
# Inputs:  --repo <path>（預設從自己的位置往上找 repo root）
# Outputs: 每個死宣告印一行；有任何一個就 exit 1。不掃的那幾類會把理由印出來。
#
# 這支存在的理由是同一個病反覆發作：
#   - 2026-08-02 `teardown: scripts/ 歸零` 刪光 scripts/，`mise.toml` 13 個任務全部指向
#     被刪掉的檔案，`mise run` 跑什麼都失敗——直到 2026-08-03 才被人撞到。
#   - 同一次刪除讓 `.claude/settings.json` 的 SessionStart hook 指向不存在的
#     session-start-thread-anchor.sh，每次開 session 都在失敗，沒有人看到。
#
# 「刪掉一個還被引用的東西」在刪的當下沒有症狀——症狀在下一個人去用它的時候才出現，而那時
# 候沒有人記得那次刪除。所以它要有機械閘，不能靠刪的人自己記得掃一遍。
#
# 只掃三個地方，而且只掃這三個：
#   1. `mise.toml` 的 `[tasks.*] run`
#   2. `.claude/settings.json` 的 `hooks[].command`
#   3. `package.json` 的 `scripts`
#
# 第三處是 2026-08-13（DP-518）補的，而它補的方式說明了這支閘原本的問題：判準寫對了、
# 適用範圍抄漏了。`package.json` 的 `scripts` 完全符合下面那句「它們是入口」——而它整整
# 十條全部指向被同一次刪除帶走的 `scripts/`，其中三個目標在整棵樹上都不存在，
# 而這支閘印的是「✅ 5 個執行宣告都指得到現在存在的檔案」。同一次刪除、同一種入口、
# 同一個 repo，抓到 13 條、漏掉 10 條。
#
# 這三處的共同點是**它們是入口**：沒有別的東西引用它們，所以沒有別的閘會在它們壞掉時變紅。
# 腳本引用腳本那一面已經有 `gate-skill-script-references.sh` 在管（同目錄引用），這裡不重複掃——
# 兩支閘掃同一件事，遲早會對同一個東西給出不同答案。散文裡提到一個檔名也不算宣告：那是敘述，
# 把敘述算進來會讓這支閘變成沒有人敢看的雜訊來源。

set -euo pipefail

PREFIX="[polaris gate-dangling-declarations]"
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
fi

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
}

python3 - "$REPO_ROOT" "$PREFIX" <<'PY'
import json
import re
import sys
from pathlib import Path

root, prefix = Path(sys.argv[1]), sys.argv[2]

declarations = []   # (來源, 行號, 相對路徑)
unresolvable = []   # 帶變數解不開的，不猜，但要數

SCRIPT = re.compile(r'(?:^|\s)(?:bash|sh|python3)\s+"?([^\s"\';|)]+\.(?:sh|py))')


def record(src, lineno, raw):
    # $CLAUDE_PROJECT_DIR 就是 repo root，這一個展得開。其餘帶 $ 的展不開。
    rel = raw.replace("$CLAUDE_PROJECT_DIR/", "")
    if rel.startswith("./"):
        rel = rel[2:]
    if "$" in rel or "*" in rel:
        unresolvable.append((src, lineno, raw))
        return
    declarations.append((src, lineno, rel))


mise = root / "mise.toml"
if mise.is_file():
    for i, line in enumerate(mise.read_text().splitlines(), 1):
        m = re.match(r'\s*run\s*=\s*"(.*)"\s*$', line)
        if m:
            for p in SCRIPT.findall(m.group(1)):
                record("mise.toml", i, p)

settings = root / ".claude/settings.json"
if settings.is_file():
    data = json.loads(settings.read_text())
    for matchers in (data.get("hooks") or {}).values():
        for matcher in matchers:
            for hook in matcher.get("hooks", []):
                for p in SCRIPT.findall(hook.get("command", "")):
                    record(".claude/settings.json", 0, p)

pkg_scripts_total = 0
pkg_scripts_nonpath = []   # 沒有指名任何檔案路徑的（例如代理給 pnpm 的），判不了，但要數
pkg = root / "package.json"
if pkg.is_file():
    data = json.loads(pkg.read_text())
    for name, command in (data.get("scripts") or {}).items():
        pkg_scripts_total += 1
        found = SCRIPT.findall(command)
        if not found:
            pkg_scripts_nonpath.append(name)
        for p in found:
            record(f"package.json[scripts.{name}]", 0, p)

dangling = [(s, n, r) for s, n, r in declarations if not (root / r).exists()]

note = (f"不掃：腳本引用腳本（gate-skill-script-references 在管）、散文裡的檔名（不是宣告）。"
        f"解不開的帶變數路徑 {len(unresolvable)} 個，不猜。")

# 判不了的那一類要說出數量，不能從輸出裡消失：一條 `pnpm --dir X build` 沒有指名任何檔案，
# 這道閘對它是空的——它壞掉的時候由 pnpm 自己大聲失敗，不由這裡。把數字印出來，是為了讓
# 「這道閘看過幾條、放過幾條」是看得見的，而不是讓 5 這個數字看起來像 package.json 全過了。
if pkg_scripts_total:
    note += (f" package.json 的 scripts 共 {pkg_scripts_total} 條，其中 "
             f"{len(pkg_scripts_nonpath)} 條沒有指名檔案路徑、不判定"
             + (f"（{', '.join(pkg_scripts_nonpath)}）" if pkg_scripts_nonpath else "") + "。")

if dangling:
    print(f"{prefix} 指向不存在的檔案的宣告：", file=sys.stderr)
    for src, lineno, rel in dangling:
        print(f"  {src}{':' + str(lineno) if lineno else ''} → {rel}", file=sys.stderr)
    print(f"{prefix} ❌ DECLARATIONS-DANGLING {len(dangling)}/{len(declarations)} 個。{note}",
          file=sys.stderr)
    sys.exit(1)

print(f"{prefix} ✅ DECLARATIONS-LIVE {len(declarations)} 個執行宣告都指得到現在存在的檔案。{note}")
PY
