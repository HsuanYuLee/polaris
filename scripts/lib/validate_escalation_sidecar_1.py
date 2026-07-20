"""Validate engineering scope-escalation sidecar schema and lineage."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path


CLI_NAME = os.environ.get("POLARIS_COMPAT_CLI", "validate-escalation-sidecar.sh")
SIDECAR_CAP_BYTES = 20_480
ALLOWED_FLAVORS = {"plan-defect", "scope-drift", "env-drift"}
ESCALATION_COUNT_MAX = 2
REQUIRED_SECTIONS = (
    "## Gate Closure",
    "## Current Measurement",
    "## Explained Delta",
    "## Proposed Fixes",
    "## Residual Blockers",
    "## Closure Forecast",
    "## Required Planner Decisions",
)
FORECAST_SIGNAL = re.compile(
    r"\b(?:yes|no|pass|fail|sufficient|insufficient|會過|不會過|仍會失敗|足夠|不足)\b",
    re.IGNORECASE,
)


def usage() -> int:
    """Print the compatibility usage contract."""
    print(f"usage: {CLI_NAME} <path/to/sidecar.md>", file=sys.stderr)
    print(f"       {CLI_NAME} --self-test", file=sys.stderr)
    return 2


def extract_frontmatter_scalar(path: Path, key: str) -> str:
    """Return a top-level scalar from the first frontmatter block."""
    in_frontmatter = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "---":
            if not in_frontmatter:
                in_frontmatter = True
                continue
            break
        if not in_frontmatter or line[:1].isspace() or ":" not in line:
            continue
        candidate, value = line.split(":", 1)
        if candidate.strip() == key:
            return value.strip()
    return ""


def extract_section(path: Path, heading: str) -> str:
    """Return an exact level-two Markdown section body."""
    output: list[str] = []
    in_section = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == heading:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            output.append(line)
    return "\n".join(output).rstrip("\n")


def body_byte_size(path: Path) -> int:
    """Return post-frontmatter body bytes using awk-compatible line endings."""
    output: list[str] = []
    frontmatter_state = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "---":
            if frontmatter_state == 0:
                frontmatter_state = 1
                continue
            if frontmatter_state == 1:
                frontmatter_state = 2
                continue
        if frontmatter_state == 2:
            output.append(line)
    return len(("\n".join(output) + ("\n" if output else "")).encode("utf-8"))


def lineage_files(sidecar: Path) -> list[Path]:
    """Return sibling files sharing the legacy task lineage stem."""
    task_id = re.sub(r"-[0-9]+\.md$", "", sidecar.name)
    return sorted(sidecar.parent.glob(f"{task_id}-*.md"), key=lambda path: str(path))


def max_lineage_count(sidecar: Path) -> int:
    """Return the highest sibling escalation count, excluding the current file."""
    highest = 0
    self_path = sidecar.resolve()
    for sibling in lineage_files(sidecar):
        if not sibling.is_file() or sibling.resolve() == self_path:
            continue
        count = extract_frontmatter_scalar(sibling, "escalation_count")
        if count.isdigit():
            highest = max(highest, int(count))
    return highest


def duplicate_lineage_slot(sidecar: Path, count: str) -> Path | None:
    """Return a sibling that already occupies an escalation count slot."""
    self_path = sidecar.resolve()
    for sibling in lineage_files(sidecar):
        if not sibling.is_file() or sibling.resolve() == self_path:
            continue
        if extract_frontmatter_scalar(sibling, "escalation_count") == count:
            return sibling
    return None


def validate_file(path: Path) -> int:
    """Validate one sidecar and aggregate every schema violation."""
    if not path.is_file():
        print(f"error: file not found: {path}", file=sys.stderr)
        return 2

    errors: list[str] = []
    if not re.fullmatch(r"T[0-9]+[a-z]*-[12]\.md", path.name):
        errors.append(
            f"filename '{path.name}' does not match required pattern "
            "T{n}[suffix]-{count}.md (count ∈ {1,2})"
        )

    skill = extract_frontmatter_scalar(path, "skill")
    ticket = extract_frontmatter_scalar(path, "ticket")
    epic = extract_frontmatter_scalar(path, "epic")
    flavor = extract_frontmatter_scalar(path, "flavor")
    count = extract_frontmatter_scalar(path, "escalation_count")
    timestamp = extract_frontmatter_scalar(path, "timestamp")
    truncated = extract_frontmatter_scalar(path, "truncated")
    scrubbed = extract_frontmatter_scalar(path, "scrubbed")

    if skill != "engineering":
        errors.append(f"frontmatter 'skill' must be 'engineering' (got '{skill}')")
    if not ticket:
        errors.append("frontmatter 'ticket' is required (current task JIRA key)")
    if not epic:
        errors.append("frontmatter 'epic' is required (parent Epic key)")
    if flavor not in ALLOWED_FLAVORS:
        errors.append(
            "frontmatter 'flavor' must be one of plan-defect|scope-drift|env-drift "
            f"(got '{flavor}') — see skills/references/escalation-flavor-guide.md"
        )
    if count not in {"1", "2"}:
        errors.append(
            f"frontmatter 'escalation_count' must be 1 or 2 (got '{count}') — see DP-044 D5"
        )
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", timestamp):
        errors.append(
            "frontmatter 'timestamp' must be ISO 8601 with Z suffix "
            f"(got '{timestamp}')"
        )
    if truncated not in {"true", "false"}:
        errors.append(
            f"frontmatter 'truncated' must be a bool (true|false), got '{truncated}'"
        )
    if scrubbed not in {"true", "false"}:
        errors.append(
            f"frontmatter 'scrubbed' must be a bool (true|false), got '{scrubbed}'"
        )

    text = path.read_text(encoding="utf-8")
    if "## Summary" not in text:
        errors.append("missing required section '## Summary'")
    else:
        summary_size = len(extract_section(path, "## Summary").encode("utf-8"))
        if summary_size > 500:
            errors.append(
                f"'## Summary' body exceeds 500 chars (got {summary_size}) — D7 cap"
            )
        if summary_size == 0:
            errors.append("'## Summary' body is empty")
    if "## Raw Evidence" not in text:
        errors.append("missing required section '## Raw Evidence'")
    for section in REQUIRED_SECTIONS:
        if section not in text:
            errors.append(f"missing required gate-closure section '{section}'")
        elif len(extract_section(path, section).encode("utf-8")) == 0:
            errors.append(f"required gate-closure section '{section}' is empty")

    closure_body = extract_section(path, "## Closure Forecast")
    if closure_body and not FORECAST_SIGNAL.search(closure_body):
        errors.append(
            "'## Closure Forecast' must explicitly say whether the proposed planner "
            "decision is sufficient to pass the gate"
        )

    size = body_byte_size(path)
    if size > SIDECAR_CAP_BYTES:
        errors.append(
            f"body size {size} bytes exceeds 20KB cap — run "
            f"'python3 scripts/snapshot-scrub.py --file {path}' to truncate"
        )

    if count in {"1", "2"}:
        numeric_count = int(count)
        prior = max_lineage_count(path)
        if prior >= ESCALATION_COUNT_MAX:
            errors.append(
                f"lineage already has escalation_count={prior} — cap reached "
                "(DP-044 D5: route to refinement, not breakdown)"
            )
        if numeric_count > prior + 1:
            errors.append(
                f"escalation_count={numeric_count} skips a slot (highest prior in lineage "
                f"is {prior}; expected {prior + 1})"
            )
        duplicate = duplicate_lineage_slot(path, count)
        if duplicate is not None:
            errors.append(
                f"escalation_count={numeric_count} duplicates an existing sibling: {duplicate}"
            )

    if errors:
        print(f"✗ validate-escalation-sidecar.sh FAIL — {path}", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 2
    print(f"✓ validate-escalation-sidecar.sh PASS — {path}")
    return 0


GOOD_SIDECAR = """---
skill: engineering
ticket: ABC-123
epic: EPIC-1
flavor: env-drift
escalation_count: 1
timestamp: 2026-04-27T10:00:00Z
truncated: false
scrubbed: true
---

## Summary

CI gate `tsc:baseline` failed: baseline 10, actual 12. Proposed storage fix is necessary
but insufficient; residual baseline drift remains.

## Gate Closure

Gate: tsc baseline. Pass condition: actual type errors must be <= baseline.

## Current Measurement

Baseline: 10. Actual: 12. Exit code: 1.

## Explained Delta

+1 storage helper typing; +1 residual baseline drift.

## Proposed Fixes

Add storage helper to Allowed Files and approve residual baseline handling.

## Residual Blockers

If only storage is approved, actual becomes 11 and still exceeds baseline 10.

## Closure Forecast

No — storage-only permission is insufficient; both planner decisions are required to pass.

## Required Planner Decisions

1. Approve storage helper typing fix.
2. Decide residual baseline/env handling.

## Raw Evidence

```
$ ci-local.sh --repo
[FAIL] tsc:baseline (12 new errors in KkStorage.ts)
```
"""

BAD_SIDECAR = """---
skill: engineering
ticket: ABC-456
epic: EPIC-1
flavor: bogus-flavor
escalation_count: 1
timestamp: 2026-04-27T10:00:00Z
truncated: false
scrubbed: true
---

## Raw Evidence

(no summary above)
"""

SECOND_SIDECAR = """---
skill: engineering
ticket: ABC-123
epic: EPIC-1
flavor: plan-defect
escalation_count: 2
timestamp: 2026-04-27T11:00:00Z
truncated: false
scrubbed: true
---

## Summary

Second escalation on the same lineage; planner re-classified flavor.

## Gate Closure

Gate: tsc baseline. Pass condition: actual <= baseline.

## Current Measurement

Baseline: 10. Actual: 11.

## Explained Delta

Residual baseline drift remains.

## Proposed Fixes

Route to refinement or approve env handling.

## Residual Blockers

No in-task source file remains that can close the gate.

## Closure Forecast

No — another task.md scope tweak is insufficient.

## Required Planner Decisions

Route to refinement or approve baseline/env handling.

## Raw Evidence

```
$ ci-local.sh --repo
[FAIL] tsc:baseline (still failing after first revision)
```
"""


def self_test() -> int:
    """Run the legacy embedded sidecar cases."""
    with tempfile.TemporaryDirectory() as directory:
        epic_dir = Path(directory) / "specs" / "EPIC-1" / "escalations"
        epic_dir.mkdir(parents=True)
        good = epic_dir / "T3-1.md"
        bad = epic_dir / "T4-1.md"
        second = epic_dir / "T3-2.md"
        good.write_text(GOOD_SIDECAR, encoding="utf-8")
        print("self-test: validating GOOD sidecar")
        if validate_file(good):
            print("self-test: FAIL — good sidecar rejected", file=sys.stderr)
            return 1

        bad.write_text(BAD_SIDECAR, encoding="utf-8")
        print("self-test: validating BAD sidecar (expect FAIL)")
        stderr = sys.stderr
        with open(os.devnull, "w", encoding="utf-8") as sink:
            sys.stderr = sink
            try:
                bad_result = validate_file(bad)
            finally:
                sys.stderr = stderr
        if bad_result == 0:
            print("self-test: FAIL — bad sidecar incorrectly passed", file=sys.stderr)
            return 1

        second.write_text(SECOND_SIDECAR, encoding="utf-8")
        print("self-test: validating second-iteration sidecar (count=2)")
        if validate_file(second):
            print("self-test: FAIL — count=2 sidecar rejected", file=sys.stderr)
            return 1
        print("self-test: ALL PASS")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the compatibility CLI parser."""
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("path", nargs="?")
    parser.add_argument("extra", nargs="*")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    """Run the escalation sidecar CLI."""
    if not argv:
        return usage()
    args = build_parser().parse_args(argv)
    if args.self_test:
        return self_test()
    if args.help:
        return usage()
    if not args.path:
        return usage()
    return validate_file(Path(args.path))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
