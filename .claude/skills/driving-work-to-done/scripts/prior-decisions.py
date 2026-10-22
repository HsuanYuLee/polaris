#!/usr/bin/env python3
"""prior-decisions.py — 一個決定要被做的那一刻，把同一件事既有的決定印出來。

為什麼是一支腳本：答案常常早就寫在某處，缺的是決定那一刻去讀。2026-10-22 量到使用者
糾正的四件，四件都早已寫在單、日誌或知識地圖裡。所以停點（spine-loop-state stop）與
指揮官對線下指令（command-post --say）那一刻，機械地把同一主題的既有決定印出來。

它只印，不判、不擋：找不到就印「找不到既有決定」，某個來源讀不到就說是哪一個，
exit code 永遠是 0。

來源：
  1. --issue 那張單的 index.md：〈使用者原話〉一節，與標題含「決定」「裁定」的段落。
  2. 其他 skill 宣告接進來的來源。核心不認得任何一個，掃所有 SKILL.md 找這一行：

       <!-- {任意前綴}-PRIOR-DECISIONS: {命令} -->

     跑 `{命令} KEY...`（在 repo 根目錄），環境變數 PRIOR_DECISIONS_BEFORE_EPOCH 帶著
     「只要這一刻以前的」。印出來的每一行原樣轉印；不印東西就是沒有命中。

鍵：--keys 直接給，加上 --text 裡出現的單號（`ABC-123`）與 PR 號（`#123`），
再加上 --issue 目錄名開頭的單號。

Usage:
  prior-decisions.py [--issue <單的目錄>] [--keys K ...] [--text <一段話>] [--before-epoch N]
"""
import argparse
import os
import re
import subprocess
import sys

DECLARATION = re.compile(r"<!--\s*[A-Z0-9][A-Z0-9-]*-PRIOR-DECISIONS:\s*(.+?)\s*-->")
KEY = re.compile(r"(?<![A-Za-z0-9])(?:[A-Z][A-Z0-9]*-\d+|#\d+)(?![0-9])")
DECISION_HEAD = re.compile(r"^(#{2,4})\s+.*(使用者原話|決定|裁定)")
SECTION_CAP = 12
SOURCE_TIMEOUT = 30


def skills_root():
    here = os.path.abspath(__file__)
    return os.path.dirname(os.path.dirname(os.path.dirname(here)))


def declared_sources(root=None):
    root = root or skills_root()
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        if "SKILL.md" not in filenames:
            continue
        try:
            with open(os.path.join(dirpath, "SKILL.md"), encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        for cmd in DECLARATION.findall(text):
            if cmd not in found:
                found.append(cmd)
    return found


def issue_sections(issue):
    """回傳 (lines, problem)。每一行是 `path:line 內容`。"""
    path = os.path.join(issue, "index.md")
    try:
        with open(path, encoding="utf-8") as fh:
            rows = fh.read().splitlines()
    except OSError as exc:
        return [], f"單的正文讀不到：{path}（{exc}）"
    out, level, taken = [], None, 0
    for no, row in enumerate(rows, 1):
        head = re.match(r"^(#{1,6})\s", row)
        if head:
            m = DECISION_HEAD.match(row)
            if m:
                level, taken = len(m.group(1)), 0
                out.append(f"{path}:{no} {row}")
                continue
            if level is not None and len(head.group(1)) <= level:
                level = None
        if level is not None and row.strip() and taken < SECTION_CAP:
            out.append(f"{path}:{no} {row.strip()[:300]}")
            taken += 1
    return out, None


def keys_of(args):
    keys = list(args.keys or [])
    for k in KEY.findall(args.text or ""):
        if k not in keys:
            keys.append(k)
    if args.issue:
        m = KEY.match(os.path.basename(os.path.normpath(args.issue)))
        if m and m.group(0) not in keys:
            keys.insert(0, m.group(0))
    return keys


def main(argv=None):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--issue")
    ap.add_argument("--keys", nargs="*")
    ap.add_argument("--text")
    ap.add_argument("--before-epoch", type=float)
    ap.add_argument("--skills-root", default=None)
    args = ap.parse_args(argv)

    keys = keys_of(args)
    blocks, problems = [], []
    if args.issue:
        lines, prob = issue_sections(args.issue)
        if prob:
            problems.append(prob)
        if lines:
            blocks.append(("這張單的正文", lines))
    repo_root = os.path.dirname(os.path.dirname(args.skills_root or skills_root()))
    env = dict(os.environ)
    if args.before_epoch:
        env["PRIOR_DECISIONS_BEFORE_EPOCH"] = str(args.before_epoch)
    if keys:
        for cmd in declared_sources(args.skills_root):
            try:
                res = subprocess.run(cmd.split() + keys, capture_output=True, text=True,
                                     cwd=repo_root, env=env, timeout=SOURCE_TIMEOUT)
            except (OSError, subprocess.SubprocessError) as exc:
                problems.append(f"來源讀不到：{cmd}（{type(exc).__name__}）")
                continue
            lines = [l for l in res.stdout.splitlines() if l.strip()]
            if res.returncode != 0:
                problems.append(f"來源讀不到：{cmd}（exit {res.returncode}："
                                + (res.stderr.strip().splitlines() or ["無輸出"])[-1][:160] + "）")
            if lines:
                blocks.append((cmd, lines))

    out = ["既有決定（鍵：" + ("、".join(keys) if keys else "無") + "）"]
    if not blocks:
        out.append("  找不到既有決定")
    for title, lines in blocks:
        out.append("  ── " + title)
        out += ["    " + l for l in lines]
    out += ["  " + p for p in problems]
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
