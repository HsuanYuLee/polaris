#!/usr/bin/env python3
"""README lint：說明文件講的 skill 名單，跟真的存在的 SKILL.md 對不對得上。

兩個方向都查，因為只查一邊會漏掉一整類：

1. **幽靈**——README 指名了一支沒有 SKILL.md 的 skill。讀的人照著打，什麼都不會發生。
2. **沒被提過**——有 SKILL.md 卻沒有出現在 README 裡。加了一支新的、忘了寫進去，是完全
   安靜的：沒有東西會紅，只是沒有人知道它存在。

外加一個數字：README 裡寫的「N 支 skill」要等於實際數量。

**為什麼這一支還在**（門檻 2026-08-13，見 `.claude/instructions/core/bootstrap.md`）：
README 會跟著 template repo 出去，是別人 clone 下來第一眼讀到的東西；而「加了一支 skill
沒寫進 README」在那個 diff 裡看不出來。2026-08-14（DP-537）之前它還查觸發詞表、mermaid
圖、導入文件的用詞——那些文件那一版整批刪掉了，檢查跟著走。

Usage:
  python3 scripts/readme-lint.py            # 只檢查
  python3 scripts/readme-lint.py --fix      # 順手改掉數字
  python3 scripts/readme-lint.py --verbose  # 全部細節

Exit codes: 0 = 乾淨, 1 = 對不上, 2 = 量不到（找不到要比對的東西）
"""

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from skill_scope import goes_to_template  # noqa: E402


def _default_root() -> Path:
    """從這支腳本自己的位置往上找到帶著 `.claude/skills/` 的那一層。

    以前寫死 `parent.parent`，那算出來的是這支 skill 自己的目錄；於是照文件打的
    `python3 .claude/skills/.../readme-lint.py` 掃到 0 支 skill，印出「OK (0 skills,
    all documented)」——一個什麼都沒量到的綠燈，跟真的乾淨長得一模一樣。
    """
    here = Path(__file__).resolve()
    for candidate in here.parents:
        if (candidate / ".claude" / "skills").is_dir():
            return candidate
    return here.parent.parent


ROOT = Path(os.environ.get("POLARIS_README_LINT_ROOT", _default_root())).resolve()
SKILLS_DIR = ROOT / ".claude" / "skills"
README = ROOT / "README.md"

# 看起來像 skill 名字、但不是的。少了這一份，每個帶連字號的識別字都會被當成幽靈。
KNOWN_NON_SKILLS = {
    "skill-creator",     # Claude 自己的功能，不是我們的 SKILL.md
    "pre-commit",        # git 的概念
    "co-authored-by",    # git trailer
    "loop-state",        # 單的狀態檔，不是 skill
}


def template_facing_skills() -> set[str]:
    """README 該列出來的那些 skill。

    三種東西被排除，各有各的理由：

    - **命名空間目錄**（底下還有 skill 的那一層）本身不是一支 skill。判準是形狀不是名字
      ——用名字比對就等於用位置判斷公司身分。
    - **指進命名空間的 symlink**。runtime 要靠 depth-one 才註冊得到那些 skill，所以同一支
      會被看到兩次；而且它的名字帶著公司代號，寫進會同步出去的 README 就是洩漏。
    - **自己宣告不出去的**（`scope: company` / `personal`），跟同步腳本問
      同一個讀取器：宣告在 frontmatter 頂層，不在路徑上、也不在正文裡。
    """
    skills = set()
    for path in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        directory = path.parent
        if directory.is_symlink():
            continue
        if not goes_to_template(path):
            continue
        skills.add(directory.name)
    return skills


def mentioned_in(text: str, skills: set[str]) -> set[str]:
    """那份文字裡出現過的 skill 名字。"""
    found = set()
    for skill in skills:
        if re.search(rf"(?<![a-z0-9\-]){re.escape(skill)}(?![a-z0-9\-])", text):
            found.add(skill)
    return found


def phantoms_in(text: str, skills: set[str]) -> list[tuple[str, int]]:
    """反引號括起來、看起來是 skill 名字、但沒有 SKILL.md 的那些。

    只認反引號，而且只在附近提到 skill 的段落裡認——不然檔名、分支名、套件名都會中。
    """
    hits = []
    for m in re.finditer(r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`", text):
        name = m.group(1)
        if name in skills or name in KNOWN_NON_SKILLS:
            continue
        window = text[max(0, m.start() - 300):m.end() + 300].lower()
        if any(word in window for word in ("skill", "技能", "觸發", "trigger")):
            hits.append((name, text[:m.start()].count("\n") + 1))
    return hits


def count_claims(text: str) -> list[tuple[int, int]]:
    """文字裡宣告的 skill 數量，回 (數字, 位置)。"""
    return [
        (int(m.group(1)), m.start())
        for m in re.finditer(r"(\d+)\s*(?:支|個)\s*skill", text)
    ]


def main() -> int:
    """對著 README 查那三件事，並且一定說出自己掃了什麼。"""
    parser = argparse.ArgumentParser(description="README lint")
    parser.add_argument("--fix", action="store_true", help="順手把過期的數字改掉")
    parser.add_argument("--verbose", action="store_true", help="列出每一支的對照結果")
    args = parser.parse_args()

    if not README.exists():
        print(f"README-LINT UNMEASURABLE 找不到 {README}", file=sys.stderr)
        return 2

    skills = template_facing_skills()
    if not skills:
        print("README-LINT UNMEASURABLE 一支 skill 都沒掃到", file=sys.stderr)
        return 2

    text = README.read_text(encoding="utf-8")
    rel = README.relative_to(ROOT)
    print(f"README-LINT 掃過 {len(skills)} 支會出去的 skill，對照 {rel}")

    stale = [(n, pos) for n, pos in count_claims(text) if n != len(skills)]
    if stale and args.fix:
        text = re.sub(r"(\d+)(\s*(?:支|個)\s*skill)", lambda m: f"{len(skills)}{m.group(2)}", text)
        README.write_text(text, encoding="utf-8")
        print(f"  已改掉 {len(stale)} 處過期的數量")
        stale = []

    mentioned = mentioned_in(text, skills)
    missing = sorted(skills - mentioned)
    ghosts = phantoms_in(text, skills)

    if args.verbose:
        for skill in sorted(skills):
            print(f"  {'✓' if skill in mentioned else '✗'} {skill}")

    if not stale and not missing and not ghosts:
        print(f"README-LINT OK {len(skills)} 支都被提到，沒有指向不存在的東西")
        return 0

    for stated, pos in stale:
        line = text[:pos].count("\n") + 1
        print(f"  數量對不上 {rel}:{line} — 寫著 {stated}，實際 {len(skills)}"
              "（--fix 可以改掉）")
    for name, line in ghosts:
        print(f"  幽靈 {rel}:{line} — `{name}` 沒有 SKILL.md")
    for skill in missing:
        print(f"  沒被提過 {skill} — 有 SKILL.md，但 README 一次都沒寫到它")
    return 1


if __name__ == "__main__":
    sys.exit(main())
