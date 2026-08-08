#!/usr/bin/env bash
# Purpose: .gitignore 同時是分類宣告。這道閘檢查兩件事：
#          （一）沒有規則指向一個已經不存在的東西；
#          （二）沒有「存在但沒被版控」的路徑落在三類之外。
# Inputs:  --repo <path>（預設從自己的位置往上找 git 根）
# Outputs: 每個問題印一行；有任何一個就 exit 1。
#
# 三類是：versioned-elsewhere（在別的 repo 裡被版控）、machine-local（只屬於這台機器）、
# regenerable（可以重新產生）。第四類 recurring 不是東西的分類，是規則的分類——它防的是
# 還沒發生的那一次（node_modules、__pycache__、.DS_Store），所以豁免「目標必須存在」。
#
# 為什麼需要這道閘：whitelist 模式（`*` 之後逐條 `!`）下每條排除規則都被 `*` 遮住，
# 死規則永遠看不出來——2026-08-03 實測 89 條裡 34 條拿掉之後判定完全不變。改成 blacklist
# 之後每個忽略路徑都歸因得到唯一一條規則，死活與分類才變成可以機械判定的東西。

set -euo pipefail

PREFIX="[polaris gate-ignore-classes]"
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fi

python3 - "$REPO_ROOT" "$PREFIX" <<'PY'
import re
import subprocess
import sys

repo_root, prefix = sys.argv[1], sys.argv[2]

CLASS_HEADER = re.compile(r"^#\s*===\s*class:\s*([a-z-]+)\s*===\s*$")
DECLARED_CLASSES = {
    "versioned-elsewhere",
    "machine-local",
    "regenerable",
    "recurring",
}
# recurring 的規則綁的是一類形狀不是一個位置，所以「目標現在不存在」對它不是問題。
EXEMPT_FROM_LIVENESS = {"recurring"}

# linked worktree 裡量不到死活的那三類——也就是 recurring 以外的全部。machine-local 的東西
# 住在主 checkout（公司目錄、`/workspace-config.yaml`），versioned-elsewhere 的巢狀 repo
# 只 clone 在主 checkout（`/issues/`、specs），regenerable 的東西要跑過一次才會出現
# （`/.pytest_cache/`、`/.pnpm-store/`）。三者在一個乾淨的 worktree 裡本來就不在，那不是
# 「規則死了」——**死活這件事只在有那些東西的那棵樹上才判得出來。**
#
# 這裡不改成豁免，改成**說出來**：豁免會讓「量不到」跟「量到而且沒事」在輸出上長得一樣，
# 而這道閘的整個存在理由就是死規則看不出來。所以在 worktree 上這一段逐條列印、不擋 push，
# 另一半（忽略路徑歸不歸得到類）照常擋——那一半在哪棵樹上都量得到。
UNMEASURABLE_IN_LINKED_WORKTREE = {"machine-local", "regenerable", "versioned-elsewhere"}


def git(*args):
    """在 repo 裡跑 git，回傳 stdout。"""
    return subprocess.run(
        ["git", "-C", repo_root, *args], capture_output=True, text=True, check=True
    ).stdout


def parse_rules():
    """把 .gitignore 讀成 {行號: (pattern, class)}；class 為 None 表示不在任何標頭底下。"""
    rules, current = {}, None
    with open(f"{repo_root}/.gitignore", encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            header = CLASS_HEADER.match(raw.rstrip("\n"))
            if header:
                current = header.group(1)
                continue
            stripped = raw.strip()
            if stripped and not stripped.startswith("#"):
                rules[number] = (stripped, current)
    return rules


def attribution(paths):
    """對每個路徑問 git 是哪一條規則讓它被忽略，回傳 {行號: [路徑…]}。"""
    result = subprocess.run(
        ["git", "-C", repo_root, "check-ignore", "-v", "--stdin"],
        input="\n".join(paths), capture_output=True, text=True,
    )
    hits = {}
    for line in result.stdout.splitlines():
        source, path = line.split("\t", 1)
        parts = source.split(":")
        if parts[0].endswith(".gitignore") and parts[1].isdigit():
            hits.setdefault(int(parts[1]), []).append(path)
        else:
            hits.setdefault(("external", source), []).append(path)
    return hits


# `--git-common-dir` 在主 checkout 回相對的 `.git`，在 linked worktree 回主 checkout 的
# 絕對路徑。兩者不同就是 linked worktree。
in_linked_worktree = git("rev-parse", "--git-common-dir").strip() not in (".git", f"{repo_root}/.git")

rules = parse_rules()
ignored = [
    line[3:].strip().strip('"')
    for line in git("status", "--ignored=matching", "--porcelain", "-uall").splitlines()
    if line.startswith("!!")
]
hits = attribution(ignored)

problems = []
unmeasurable = []

unknown = {c for _, c in rules.values() if c is not None} - DECLARED_CLASSES
for name in sorted(unknown):
    problems.append(f"  未宣告的分類：# === class: {name} ===")

for number, (pattern, klass) in sorted(rules.items()):
    if klass is None:
        problems.append(f"  L{number} `{pattern}` 不在任何分類標頭底下")
    elif klass not in EXEMPT_FROM_LIVENESS and number not in hits:
        line = f"  L{number} `{pattern}`"
        if in_linked_worktree and klass in UNMEASURABLE_IN_LINKED_WORKTREE:
            unmeasurable.append(f"{line}（{klass}，本來就住在主 checkout 或還沒被產生）")
        else:
            problems.append(f"{line} 現在沒有排除到任何東西（指向已經不存在的機制？）")

for key, paths in hits.items():
    if isinstance(key, tuple):
        problems.append(f"  {paths[0]} 被 {key[1]} 排除，不在 .gitignore 的分類裡")

covered = {p for paths in hits.values() for p in paths}
for path in ignored:
    if path not in covered:
        problems.append(f"  {path} 存在、沒被版控，但歸不到任何一條規則")

if unmeasurable:
    print(
        f"{prefix} ⚠️ 這是 linked worktree，{len(unmeasurable)} 條規則的死活量不到"
        f"（machine-local / regenerable 的東西不在這棵樹上）。逐條列出，不擋 push："
    )
    print("\n".join(unmeasurable))
    print(f"{prefix} 要判它們死活，在主 checkout 上跑一次這道閘。")

if problems:
    print(f"{prefix} .gitignore 的分類宣告對不上現況：", file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    print(f"{prefix} ❌ {len(problems)} 個問題", file=sys.stderr)
    raise SystemExit(1)

by_class = {}
for number, (_, klass) in rules.items():
    by_class[klass] = by_class.get(klass, 0) + 1
summary = "、".join(f"{k} {v} 條" for k, v in sorted(by_class.items()))
exempt = sum(v for k, v in by_class.items() if k in EXEMPT_FROM_LIVENESS)
# 兩行分開印：一行講規則指不指得到東西，一行講忽略路徑歸不歸得到類。
# 這是兩個不同的問題，混成一行的話只有一個證據字串，兩件事就分不出是哪一件過了。
measured = len(rules) - exempt - len(unmeasurable)
print(
    f"{prefix} ✅ RULES-LIVE {measured} 條規則都指得到現在存在的東西"
    f"（recurring {exempt} 條豁免，量不到 {len(unmeasurable)} 條已逐條列出）。"
)
print(f"{prefix} ✅ PATHS-CLASSED {len(ignored)} 個忽略路徑全部歸得到類（{summary}）。")
PY
