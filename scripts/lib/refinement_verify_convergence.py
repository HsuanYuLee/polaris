#!/usr/bin/env python3
"""Verify canonical refinement convergence and representative task metadata."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

USAGE = """Usage:
  verify-refinement-convergence.sh --root <workspace_root> [--allow-scan-failures] [--skip-direct-source] [--sample-task <path>]

Default contract:
  - sample task frontmatter must contain explicit status
  - docs-manager direct-source contract must pass
  - canonical refinement scan must be fully green

--allow-scan-failures keeps the report deterministic but does not fail on remaining
safe_empty / needs_review / schema_error backlog. This is intended for pre-wash stages.
"""


def usage(message: str | None = None, code: int = 64) -> None:
    if message:
        print(message, file=sys.stderr)
    print(USAGE, end="", file=sys.stderr)
    raise SystemExit(code)


def has_status_frontmatter(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return False
    match = re.match(r"(?s)^---\n(.*?)\n---\n", text)
    return bool(match and re.search(r"(?m)^status:\s*\S", match.group(1)))


def main(argv: list[str]) -> int:
    root_arg = ""
    allow_scan_failures = False
    skip_direct_source = False
    sample_task_arg = ""
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in {"--root", "--sample-task"}:
            value = argv[i + 1] if i + 1 < len(argv) else ""
            if arg == "--root":
                root_arg = value
            else:
                sample_task_arg = value
            i += 2
        elif arg == "--allow-scan-failures":
            allow_scan_failures = True
            i += 1
        elif arg == "--skip-direct-source":
            skip_direct_source = True
            i += 1
        elif arg in {"-h", "--help"}:
            print(USAGE, end="", file=sys.stderr)
            return 0
        else:
            usage(f"unknown argument: {arg}")

    if not root_arg or not Path(root_arg).is_dir():
        print("--root is required and must exist", file=sys.stderr)
        return 64
    root = Path(root_arg).resolve()
    scripts_dir = Path(__file__).resolve().parents[1]

    if sample_task_arg:
        sample_task = Path(sample_task_arg)
    else:
        companies = root / "docs-manager/src/content/docs/specs/companies"
        candidates = sorted(companies.glob("*/*/tasks/T1/index.md")) if companies.is_dir() else []
        preferred = [path for path in candidates if has_status_frontmatter(path)]
        sample_task = preferred[0] if preferred else (candidates[0] if candidates else Path())
    if not sample_task_arg and not candidates:
        print("failed to resolve representative sample task under canonical company specs", file=sys.stderr)
        return 1

    backfill = subprocess.run(
        [str(scripts_dir / "backfill-refinement-predecessor-audit.sh"), "--root", str(root), "--mode", "report", "--format", "json"],
        capture_output=True,
        text=True,
    )
    if backfill.returncode:
        sys.stdout.write(backfill.stdout)
        sys.stderr.write(backfill.stderr)
        return backfill.returncode
    scan = subprocess.run(
        [str(scripts_dir / "validate-refinement-json.sh"), "--scan", str(root)],
        capture_output=True,
        text=True,
    )
    if scan.returncode not in {0, 1}:
        sys.stdout.write(scan.stdout)
        sys.stderr.write(scan.stderr)
        return scan.returncode

    backfill_payload = json.loads(backfill.stdout)
    summary = backfill_payload["summary"]
    summary_line = next(
        (line.strip() for line in scan.stdout.splitlines() if line.startswith("refinement.json scan:")),
        "",
    )
    if not summary_line:
        print("FAIL: validator scan summary line missing", file=sys.stderr)
        return 1
    match = re.match(r"refinement\.json scan: (\d+) pass, (\d+) fail \(total (\d+)\)", summary_line)
    if not match:
        print(f"FAIL: unexpected validator scan summary: {summary_line}", file=sys.stderr)
        return 1
    validator_pass, validator_fail, validator_total = map(int, match.groups())
    status_present = sample_task.is_file() and has_status_frontmatter(sample_task)
    derived_fail = summary["safe_empty"] + summary["needs_review"] + summary["schema_error"]
    scan_consistent = (
        validator_total == summary["total"]
        and validator_pass == summary["already_ok"]
        and validator_fail == derived_fail
    )

    print(f"root={summary['root']}")
    for key in ("total", "already_ok", "safe_empty", "needs_review", "schema_error"):
        print(f"{key}={summary[key]}")
    print(f"validator_pass={validator_pass}")
    print(f"validator_fail={validator_fail}")
    print(f"validator_total={validator_total}")
    print(f"scan_consistent={'true' if scan_consistent else 'false'}")
    print(f"sample_status_frontmatter={'true' if status_present else 'false'}")
    print(f"allow_scan_failures={'true' if allow_scan_failures else 'false'}")

    if not status_present:
        print(f"FAIL: sample task missing explicit status frontmatter: {sample_task}", file=sys.stderr)
        return 1
    if not scan_consistent:
        print("FAIL: backfill classifier and validator scan are out of sync", file=sys.stderr)
        return 1
    if not allow_scan_failures and derived_fail > 0:
        print("FAIL: canonical refinement scan still has backlog", file=sys.stderr)
        return 1

    if skip_direct_source:
        print("direct_source=SKIP")
    else:
        direct = subprocess.run(
            ["bash", str(scripts_dir / "verify-docs-manager-direct-source.sh")],
            stdout=subprocess.DEVNULL,
        )
        if direct.returncode:
            return direct.returncode
        print("direct_source=PASS")
    print("PASS: refinement convergence verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
