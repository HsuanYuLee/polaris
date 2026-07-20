"""Fail closed when a filesystem selftest is absent from the aggregate corpus."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


USAGE = """usage: validate-selftest-enrollment.sh [--root <repo>]

Cross-checks every *-selftest.sh on the filesystem against the aggregate runner's
enrolled corpus. Any selftest not enrolled => exit 2 (fail-closed).
"""


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[2]
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in {"-h", "--help"}:
            print(USAGE, file=sys.stderr, end="")
            return 0
        if arg != "--root" or index + 1 >= len(argv):
            print(f"POLARIS_SELFTEST_ENROLLMENT_ARG: unknown argument: {arg}", file=sys.stderr)
            print(USAGE, file=sys.stderr, end="")
            return 2
        root = Path(argv[index + 1]).resolve()
        index += 2
    runner = root / "scripts/run-aggregate-selftests.sh"
    if not runner.is_file():
        print(f"POLARIS_SELFTEST_ENROLLMENT_NO_RUNNER: aggregate runner missing: {runner}", file=sys.stderr)
        return 2
    filesystem = sorted(
        {
            path.relative_to(root).as_posix()
            for parent in (root / "scripts", root / "scripts/selftests")
            if parent.is_dir()
            for path in parent.glob("*-selftest.sh")
            if path.is_file()
        }
    )
    if not filesystem:
        print(f"POLARIS_SELFTEST_ENROLLMENT_EMPTY: no selftests found on filesystem under {root}", file=sys.stderr)
        return 2
    result = subprocess.run(
        ["bash", str(runner), "--root", str(root), "--list"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
        return result.returncode
    enrolled = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    gaps = [path for path in filesystem if path not in enrolled]
    if gaps:
        print(
            f"POLARIS_SELFTEST_ENROLLMENT_GAP: {len(gaps)} selftest(s) on filesystem not enrolled in aggregate runner:",
            file=sys.stderr,
        )
        for gap in gaps:
            print(f"  {gap}", file=sys.stderr)
        return 2
    print(
        f"PASS: selftest enrollment — all {len(filesystem)} filesystem selftests enrolled in aggregate runner"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
