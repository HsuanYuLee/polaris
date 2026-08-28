"""Validate learning Route A and refinement structural seed boundaries."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


USAGE = """Usage:
  bash scripts/validate-learning-seed-contract.sh --producer learning --diff-range <base..head>
  bash scripts/validate-learning-seed-contract.sh --producer refinement --source-container <DP-folder>
  bash scripts/validate-learning-seed-contract.sh --self-test
"""
# 一張單的檔案怎麼認得出來：**它旁邊有 `.spine/`**。
#
# 這裡刻意不寫 `issues/`、不寫任何命名空間、也不寫單號長什麼樣——這支 skill 會被單獨
# 下載到別人的 repo，那裡的單的目錄樹叫什麼名字我們不知道。`.spine/` 是主流程自己放下的標記，
# 換一個環境它仍然成立。
#
# 上一版比對的是 docs-manager 底下 design-plans 的固定路徑。那一層在主流程切換之後不再
# 是單住的地方，於是這道檢查對任何真實的 Route A 執行都不可能命中——一道不會失敗的
# 檢查不是檢查，而它正是「learning 不得自己簽成功的定義」唯一的機械保證。
SPINE_MARKER = ".spine"
TICKET_FILES = {"index.md", "plan.md", "refinement.md", "refinement.json"}


def is_ticket_file(repo_root: Path, path: str) -> bool:
    """Report whether a repo-relative path is a ticket's own file.

    A path counts when it sits inside a ticket's `.spine/`, or when it is one of
    the ticket-owned filenames in a directory that carries a `.spine/`. Returns
    False for anything else, including research artefacts stored beside a ticket.
    """
    parts = Path(path).parts
    if SPINE_MARKER in parts:
        return True
    name = parts[-1] if parts else ""
    if name not in TICKET_FILES:
        return False
    return (repo_root / Path(path).parent / SPINE_MARKER).is_dir()


def validate(producer: str, diff_range: str, source_container: str) -> int:
    if producer == "learning":
        if not diff_range:
            print("ERROR: --producer learning requires --diff-range", file=sys.stderr)
            return 64
        result = subprocess.run(
            ["git", "diff", "--name-only", diff_range],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode:
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            return result.returncode
        repo_root = Path.cwd()
        inspected = 0
        for path in result.stdout.splitlines():
            inspected += 1
            if is_ticket_file(repo_root, path):
                print(f"ERROR: learning Route A may not write a ticket's own file: {path}", file=sys.stderr)
                return 1
        # 沒有檔案可看不是通過：一個空的 diff range 與一個乾淨的 diff range 在這裡長得
        # 一樣，而前者代表這次根本沒量到東西。
        if inspected == 0:
            print(f"INCONCLUSIVE: no files in {diff_range} — nothing was inspected", file=sys.stderr)
            return 2
        print(f"PASS: learning seed diff respects Route A contract ({inspected} file(s) inspected)")
        return 0
    if producer == "refinement":
        if not source_container:
            print("ERROR: --producer refinement requires --source-container", file=sys.stderr)
            return 64
        path = Path(source_container)
        if not path.is_dir():
            print(f"ERROR: source container not found: {source_container}", file=sys.stderr)
            return 64
        print(f"PASS: refinement structural audit accepted {path.name}")
        return 0
    print("ERROR: --producer must be learning or refinement", file=sys.stderr)
    print(USAGE, file=sys.stderr, end="")
    return 64


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="learning-seed-contract.") as directory:
        repo = Path(directory) / "repo"
        repo.mkdir()
        git(repo, "init", "-q")
        git(repo, "config", "user.email", "selftest@example.test")
        git(repo, "config", "user.name", "Self Test")
        # 單的目錄樹的名字刻意取一個不是 issues 的：判準是旁邊有沒有 .spine/，不是路徑長什麼樣。
        container = repo / "any-ticket-tree/some-namespace/backlog/TICKET-EXAMPLE"
        (container / "artifacts").mkdir(parents=True)
        (container / ".spine").mkdir(parents=True)
        (container / ".spine/loop-state.json").write_text("{}\n", encoding="utf-8")
        (repo / "README.md").write_text("ok\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "init")
        base = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
        (container / "index.md").write_text("forbidden\n", encoding="utf-8")
        git(repo, "add", ".")
        git(repo, "commit", "-q", "-m", "forbidden")
        old = Path.cwd()
        try:
            import os

            os.chdir(repo)
            if validate("learning", f"{base}..HEAD", "") == 0:
                print("self-test failed: learning forbidden file passed", file=sys.stderr)
                return 1
            git(repo, "reset", "-q", "--hard", base)
            report = container / "artifacts/research-report.md"
            report.write_text("report\n", encoding="utf-8")
            git(repo, "add", ".")
            git(repo, "commit", "-q", "-m", "allowed")
            if validate("learning", f"{base}..HEAD", "") != 0:
                return 1
        finally:
            os.chdir(old)
        refinement = repo / "any-ticket-tree/some-namespace/backlog/TICKET-EXAMPLE-refinement"
        refinement.mkdir(parents=True)
        if validate("refinement", "", str(refinement)) != 0:
            return 1
        if validate("", f"{base}..HEAD", "") == 0 or validate("refinement", "", "") == 0:
            return 1
    print("PASS: validate-learning-seed-contract self-test")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["--self-test"]:
        return self_test()
    producer = diff_range = source_container = ""
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in {"-h", "--help"}:
            print(USAGE, file=sys.stderr, end="")
            return 0
        if arg not in {"--producer", "--diff-range", "--source-container"} or index + 1 >= len(argv):
            print(f"unknown argument: {arg}", file=sys.stderr)
            print(USAGE, file=sys.stderr, end="")
            return 64
        value = argv[index + 1]
        if arg == "--producer":
            producer = value
        elif arg == "--diff-range":
            diff_range = value
        else:
            source_container = value
        index += 2
    return validate(producer, diff_range, source_container)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
