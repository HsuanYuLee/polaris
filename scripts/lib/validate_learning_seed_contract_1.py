"""Validate learning Route A and refinement structural seed boundaries."""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path


USAGE = """Usage:
  bash scripts/validate-learning-seed-contract.sh --producer learning --diff-range <base..head>
  bash scripts/validate-learning-seed-contract.sh --producer refinement --source-container <DP-folder>
  bash scripts/validate-learning-seed-contract.sh --self-test
"""
CANONICAL_DP = re.compile(
    r"^docs-manager/src/content/docs/specs/design-plans/DP-[^/]+/"
    r"(?:index\.md|plan\.md|refinement\.md|refinement\.json)$"
)


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
        for path in result.stdout.splitlines():
            if CANONICAL_DP.match(path):
                print(f"ERROR: learning Route A may not write canonical DP file: {path}", file=sys.stderr)
                return 1
        print("PASS: learning seed diff respects Route A contract")
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
        container = repo / "docs-manager/src/content/docs/specs/design-plans/DP-EXAMPLE-test"
        (container / "artifacts").mkdir(parents=True)
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
        refinement = repo / "docs-manager/src/content/docs/specs/design-plans/DP-EXAMPLE-refinement"
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
