#!/usr/bin/env bash
# gate-layer-vocabulary.sh — 一段話寫進錯的層，這裡會說話。
#
# 這一套 skill 是分層的：核心四站不認得任何一個領域、領域 pack 不認得任何一家公司、
# 公司 skill 不重講核心的機制。三條界線都只靠散文守著，而散文不會報錯——一句寫錯層的
# 話在原地看起來完全正常，只有在有人把那一層單獨搬走的時候才發現它帶不動。
#
# 這道閘讀的是宣告，不是自己的判斷。宣告長這樣，一行說出「哪些詞」與「不得出現在哪」：
#
#   <!-- PROSE-LAYER: {規則名} — 不得出現在 {範圍} — {詞}|{詞}|... -->
#
# {範圍} 兩種寫法：
#   skill 名（逗號分隔）  直接指名要掃哪幾支
#   scope:company-only    掃所有這樣宣告自己的 skill——跟 sync-to-polaris 同一個權威
#
# {詞} 的位置放 @company-patterns 時，不是一份詞表，是「去問既有的那個權威」：
# scan-template-leaks.sh 從每一家自己的 workspace-config.yaml 推出公司樣式。這裡再抄
# 一份就是第二個答案，而兩份會漂。
#
# 被判的只有散文（.md）。腳本註解裡的同一個詞多半在**否認**那件事（「這裡不知道 branch
# 是什麼字」），對它判紅的閘會在三次之後被關掉。跳過了幾個檔案會被印出來——一個安靜的
# 第三態下一次就會被當成檢查過了。
#
# 一條規則都找不到時是 exit 2，不是 exit 0：沒有規則可判的綠燈跟判過了長得一樣。
#
# Usage: gate-layer-vocabulary.sh [--repo <工作區>] [--skills <skill 目錄>]
#                                 [--baseline <ref>] [--format summary|json]
# Exit:  0 三層都乾淨 / 1 有話寫在錯的層、或詞表被縮小 / 2 量不到

set -uo pipefail

PREFIX="[polaris gate-layer-vocabulary]"
REPO_PATH=""
SKILLS_PATH=""
BASELINE="origin/main"
FORMAT="summary"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    --skills) SKILLS_PATH="${2:-}"; shift 2 ;;
    # 詞表被縮小一個詞就能買到綠，所以要跟一個基準比。基準取不到會被說出來，不會被當成過了。
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "$PREFIX 不認得的參數：$1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO_PATH" ]] || REPO_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -n "$SKILLS_PATH" ]] || SKILLS_PATH="$REPO_PATH/.claude/skills"

command -v python3 >/dev/null 2>&1 || {
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "$PREFIX 修法：mise install" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

python3 - "$REPO_PATH" "$SKILLS_PATH" "$PREFIX" "$BASELINE" "$FORMAT" "$SCRIPT_DIR" <<'PY'
import json
import os
import re
import subprocess
import sys

repo, skills_root, prefix, baseline, fmt, script_dir = sys.argv[1:7]

if not os.path.isdir(skills_root):
    print(f"{prefix} 量不到：{skills_root} 不存在。", file=sys.stderr)
    sys.exit(2)

DECLARATION = re.compile(
    r"<!--\s*PROSE-LAYER:\s*([A-Za-z0-9_-]+)\s*(?:—|--)\s*"
    r"不得出現在\s*(\S+)\s*(?:—|--)\s*(.+?)\s*-->")
COMPANY_SCOPE = "scope:company-only"
DELEGATED = "@company-patterns"
COMPANY_DECL = re.compile(r"^\s*scope:\s*company-only\s*$", re.MULTILINE)


def skill_manifests():
    """所有 SKILL.md 的路徑。命名空間目錄底下那一層也算——公司 skill 就住在那裡。"""
    found = []
    for dirpath, dirnames, filenames in os.walk(skills_root):
        if "SKILL.md" in filenames:
            found.append(os.path.join(dirpath, "SKILL.md"))
            dirnames[:] = []
    return sorted(found)


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return ""


MANIFESTS = skill_manifests()

# ── 宣告 ───────────────────────────────────────────────────────────
rules = []
for manifest in MANIFESTS:
    for name, zone, words in DECLARATION.findall(read(manifest)):
        rules.append({"name": name, "zone": zone, "words_raw": words,
                      "declared_in": os.path.relpath(manifest, repo)})

if not rules:
    print(f"{prefix} 量不到：一條 PROSE-LAYER 宣告都沒有。一個沒有規則可判的綠燈，"
          f"跟判過了長得一樣。", file=sys.stderr)
    sys.exit(2)

# ── 範圍 ───────────────────────────────────────────────────────────
def company_skill_dirs():
    """自己宣告 scope: company-only 的 skill。symlink 與本體會看到同一支，去重。"""
    seen = {}
    for manifest in MANIFESTS:
        if COMPANY_DECL.search(read(manifest)):
            directory = os.path.dirname(manifest)
            seen[os.path.realpath(directory)] = directory
    return sorted(seen.values())


def resolve_zone(zone):
    """把宣告裡的範圍字串換成一組實際目錄。解不出來的回 None，由呼叫端判 exit 2。"""
    if zone == COMPANY_SCOPE:
        dirs = company_skill_dirs()
        return dirs if dirs else None
    dirs = []
    for name in zone.split(","):
        name = name.strip()
        if not name:
            continue
        candidate = os.path.join(skills_root, name)
        if not os.path.isdir(candidate):
            return None
        dirs.append(candidate)
    return dirs or None


# ── 掃 ─────────────────────────────────────────────────────────────
def word_pattern(word):
    """ASCII 的詞要前後不接字母數字，才不會在 SPECIAL 裡撈到 CI。中日文沒有那個邊界。"""
    if all(ord(ch) < 128 for ch in word):
        return re.compile(r"(?<![A-Za-z0-9])" + re.escape(word) + r"(?![A-Za-z0-9])",
                          re.IGNORECASE)
    return re.compile(re.escape(word))


def prose_and_skipped(directory):
    """(要掃的散文, 跳過的其他檔案數)。判的是散文，跳過幾個檔案要說出來。"""
    prose, skipped = [], 0
    for dirpath, _, filenames in os.walk(directory):
        for filename in sorted(filenames):
            path = os.path.join(dirpath, filename)
            (prose.append(path) if filename.endswith(".md") else None)
            if not filename.endswith(".md"):
                skipped += 1
    return sorted(prose), skipped


def scan_words(dirs, words):
    hits, scanned, skipped = [], 0, 0
    patterns = [(word, word_pattern(word)) for word in words]
    for directory in dirs:
        prose, missed = prose_and_skipped(directory)
        skipped += missed
        for path in prose:
            scanned += 1
            for lineno, line in enumerate(read(path).splitlines(), 1):
                if "PROSE-LAYER:" in line:
                    continue  # 宣告自己不算犯規
                for word, pattern in patterns:
                    if pattern.search(line):
                        hits.append({"file": os.path.relpath(path, repo),
                                     "line": lineno, "word": word,
                                     "text": line.strip()[:120]})
    return hits, scanned, skipped


def scan_delegated(dirs):
    """公司樣式問既有的權威，不在這裡再推一次。"""
    scanner = os.path.join(script_dir, "scan-template-leaks.sh")
    if not os.path.isfile(scanner):
        return None, 0, 0
    hits, scanned, skipped = [], 0, 0
    for directory in dirs:
        prose, missed = prose_and_skipped(directory)
        scanned += len(prose)
        skipped += missed
        proc = subprocess.run(
            ["bash", scanner, "--workspace", repo, "--source", "workspace",
             "--format", "json", "--only-path", os.path.relpath(directory, repo)],
            capture_output=True, text=True)
        if proc.returncode not in (0, 1):
            return None, scanned, skipped
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return None, scanned, skipped
        for hit in payload.get("hits", []):
            hits.append({"file": hit.get("file", "?"), "line": hit.get("line", 0),
                         "word": ",".join(hit.get("patterns", [])) or "company",
                         "text": str(hit.get("text", ""))[:120]})
    return hits, scanned, skipped


# ── 詞表有沒有被縮小 ───────────────────────────────────────────────
def baseline_words(rule):
    """同一條規則在基準上宣告了哪些詞。取不到回 None——那要被說出來，不是當成沒少。"""
    proc = subprocess.run(
        ["git", "-C", repo, "show", f"{baseline}:{rule['declared_in']}"],
        capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    for name, _zone, words in DECLARATION.findall(proc.stdout):
        if name == rule["name"]:
            return {w.strip() for w in words.split("|") if w.strip()}
    return None


# ── 判 ─────────────────────────────────────────────────────────────
results = []
unmeasurable = []
for rule in rules:
    dirs = resolve_zone(rule["zone"])
    if dirs is None:
        unmeasurable.append(f"{rule['name']}：範圍「{rule['zone']}」解不出任何目錄")
        continue
    words = [w.strip() for w in rule["words_raw"].split("|") if w.strip()]
    if words == [DELEGATED]:
        hits, scanned, skipped = scan_delegated(dirs)
        shrunk = []
        if hits is None:
            unmeasurable.append(f"{rule['name']}：{DELEGATED} 問不到 scan-template-leaks.sh")
            continue
    else:
        hits, scanned, skipped = scan_words(dirs, words)
        was = baseline_words(rule)
        shrunk = sorted(was - set(words)) if was is not None else []
        rule["baseline_seen"] = was is not None
    results.append({**rule, "words": words, "zone_dirs": [os.path.relpath(d, repo) for d in dirs],
                    "hits": hits, "scanned": scanned, "skipped": skipped, "shrunk": shrunk})

if unmeasurable:
    for note in unmeasurable:
        print(f"{prefix} 量不到：{note}", file=sys.stderr)
    print(f"{prefix} 宣告 {len(rules)} 條、判得動 {len(results)} 條。"
          f"判不動的那幾條不是綠的。", file=sys.stderr)
    sys.exit(2)

total_hits = sum(len(r["hits"]) for r in results)
total_shrunk = sum(len(r["shrunk"]) for r in results)

if fmt == "json":
    print(json.dumps({"rules": results, "hits": total_hits, "shrunk": total_shrunk},
                     ensure_ascii=False, indent=2))
else:
    print("Prose layer vocabulary")
    print(f"declared rules: {len(rules)}   evaluated: {len(results)}")
    for r in results:
        zone = ", ".join(r["zone_dirs"]) if len(r["zone_dirs"]) <= 4 \
            else f"{len(r['zone_dirs'])} 個目錄"
        print(f"  {r['name']}: {len(r['hits'])} hits  "
              f"({r['scanned']} 份散文，跳過 {r['skipped']} 個非 .md) — {zone}")
        if r["words"] != [DELEGATED] and not r.get("baseline_seen"):
            print(f"    基準 {baseline} 上沒有這條規則——新宣告，這一次比不到有沒有被縮小。")
        for word in r["shrunk"]:
            print(f"    !! 詞表少了「{word}」——縮小詞表買到的綠不算綠。")
        for hit in r["hits"]:
            print(f"    {hit['file']}:{hit['line']} 「{hit['word']}」 {hit['text']}")

if total_hits or total_shrunk:
    print(f"POLARIS_PROSE_LAYER_VIOLATION:{total_hits}:{total_shrunk}", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
