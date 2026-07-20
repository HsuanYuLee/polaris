"""Ensure skills and scripts consume runtime tools through capability ids."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


SKILL_PATTERNS = (
    "npx playwright",
    "pnpm --dir docs-manager",
    r"scripts/polaris-viewer\.sh",
    r"scripts/verify-docs-manager-runtime\.sh",
    r"mockoon-runner\.sh",
)
SCRIPT_PATTERN = (
    r"npx --prefix .*playwright|npm install --prefix .*scripts/(e2e|mockoon)|"
    r"scripts/(e2e|mockoon)/node_modules"
)


def run_rg(args: list[str]) -> int:
    result = subprocess.run(["rg", *args], text=True, capture_output=True, check=False)
    if result.stdout:
        print(result.stdout, end="")
    if result.returncode not in {0, 1} and result.stderr:
        print(result.stderr, file=sys.stderr, end="")
    return result.returncode


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    failures = 0
    print("Checking skill/reference runtime tool invocations...")
    for pattern in SKILL_PATTERNS:
        if run_rg(["-n", "--glob", "*.md", "--glob", "SKILL.md", pattern, str(root / ".claude/skills")]) == 0:
            failures += 1
    print("Checking script runtime tool invocations...")
    result = run_rg(
        [
            "-n",
            "--glob", "!**/node_modules/**",
            "--glob", "!**/scripts/polaris-toolchain.sh",
            "--glob", "!**/scripts/validate-polaris-toolchain-consumers.sh",
            "--glob", "!**/scripts/lib/validate_polaris_toolchain_consumers_1.py",
            "--glob", "!**/scripts/mockoon/mockoon-runner.sh",
            "--glob", "!**/scripts/e2e/e2e-verify.sh",
            "--glob", "!**/scripts/verify-docs-manager-runtime.sh",
            SCRIPT_PATTERN,
            str(root / "scripts"),
            str(root / ".claude/skills"),
        ]
    )
    if result == 0:
        failures += 1
    if failures:
        print(
            """FAIL: direct runtime tool invocation found.

Use:
  scripts/polaris-toolchain.sh run docs.viewer.<command>
  scripts/polaris-toolchain.sh run fixtures.mockoon.<command>
  scripts/polaris-toolchain.sh run browser.playwright.<command>

Compatibility wrappers are allowed only in scripts/e2e, scripts/mockoon, and docs-manager runtime scripts.""",
            file=sys.stderr,
        )
        return 1
    print("PASS: Polaris toolchain consumers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
