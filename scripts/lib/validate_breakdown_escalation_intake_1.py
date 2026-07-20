"""Validate breakdown intake decisions for engineering escalation sidecars."""

from __future__ import annotations

import argparse
import io
import os
import re
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any


CLI_NAME = os.environ.get("POLARIS_COMPAT_CLI", "validate-breakdown-escalation-intake.sh")
ALLOWED_ROUTES = {"engineering", "refinement", "wait", "baseline_approval", "task_update"}
ALLOWED_FLAVORS = {"plan-defect", "scope-drift", "env-drift"}
ALLOWED_SCOPES = {"packaging", "full"}
NEGATIVE_FORECAST = re.compile(
    r"(^|[^A-Za-z])(no|fail|fails|failed|insufficient|not sufficient|still fail|"
    r"cannot pass|won't pass|不會過|仍會失敗|仍然失敗|不足|無法通過|不能回 engineering|"
    r"不可回 engineering)([^A-Za-z]|$)",
    re.IGNORECASE,
)
RESIDUAL_DECISION = re.compile(
    r"residual|baseline|env|environment|upstream|sibling|wait|refinement|剩餘|殘留|"
    r"基線|環境|等待|上游|同線|同支|改開 refinement|退 refinement",
    re.IGNORECASE,
)


def usage() -> int:
    """Print the compatibility usage contract and return the usage status."""
    print(
        f"usage: {CLI_NAME} --sidecar <path> --route <route> --closes-gate "
        "<true|false> --flavor <flavor> --disposition <text> --decision <text> "
        "[--decision <text>...] [--scope <packaging|full>] "
        "[--task-md <path> --repo <path> --head-sha <sha>] [--inbox-dir <path>]",
        file=sys.stderr,
    )
    print(f"       {CLI_NAME} --self-test", file=sys.stderr)
    print(file=sys.stderr)
    print(
        "routes: engineering | refinement | wait | baseline_approval | task_update",
        file=sys.stderr,
    )
    print("flavor: plan-defect | scope-drift | env-drift", file=sys.stderr)
    print(
        "scope:  packaging (per-task Allowed Files / estimate_points backfill; default full)",
        file=sys.stderr,
    )
    print(
        'disposition: "accepted flavor: X" when X matches sidecar flavor, or '
        '"re-classified to X: reason" when it differs',
        file=sys.stderr,
    )
    return 2


class CompatParser(argparse.ArgumentParser):
    """Argparse parser that retains the legacy gate's terse usage behavior."""

    def error(self, message: str) -> None:
        if message.startswith("unrecognized arguments:"):
            unknown = message.removeprefix("unrecognized arguments:").strip().split()[0]
            print(f"unknown argument: {unknown}", file=sys.stderr)
        raise SystemExit(usage())


def extract_frontmatter_scalar(path: Path, key: str) -> str:
    """Return a top-level scalar from the first Markdown frontmatter block."""
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
    """Return a level-two Markdown section body without trailing newlines."""
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


def required_decision_count(text: str) -> int:
    """Count list items, treating non-empty prose as one decision."""
    count = sum(
        1 for line in text.splitlines() if re.match(r"^\s*(?:[0-9]+\.|-|\*)\s+", line)
    )
    return count or (1 if text.strip() else 0)


def validate_flavor_disposition(source: str, final: str, disposition: str) -> bool:
    """Validate accepted/re-classified disposition wording."""
    if final == source:
        return bool(
            re.match(
                rf"^accepted flavor:\s*{re.escape(final)}(?:\s|$)",
                disposition,
                re.IGNORECASE,
            )
        )
    return bool(
        re.match(
            rf"^re-classified to\s+{re.escape(final)}:\s*\S.*",
            disposition,
            re.IGNORECASE,
        )
    )


def validate(
    sidecar: Path,
    route: str,
    closes_gate: str,
    flavor: str,
    disposition: str,
    scope: str,
    decisions: list[str],
) -> int:
    """Validate one intake decision and preserve legacy diagnostics."""
    if not sidecar.is_file():
        print(f"error: sidecar not found: {sidecar}", file=sys.stderr)
        return 2

    errors: list[str] = []
    if route not in ALLOWED_ROUTES:
        errors.append(
            f"route must be one of engineering|refinement|wait|baseline_approval|task_update "
            f"(got '{route}')"
        )
    if scope not in ALLOWED_SCOPES:
        errors.append(f"scope must be one of packaging|full (got '{scope}')")
    if scope == "packaging":
        if flavor != "plan-defect":
            errors.append(
                f"scope=packaging requires flavor=plan-defect (got flavor='{flavor}')"
            )
        if route != "task_update":
            errors.append(
                "scope=packaging requires route=task_update; a packaging backfill is landed "
                f"by breakdown, not bounced to route=refinement (got route='{route}')"
            )
    if closes_gate not in {"true", "false"}:
        errors.append(f"closes-gate must be true or false (got '{closes_gate}')")
    if flavor not in ALLOWED_FLAVORS:
        errors.append(
            f"flavor must be one of plan-defect|scope-drift|env-drift (got '{flavor}')"
        )

    source_flavor = extract_frontmatter_scalar(sidecar, "flavor")
    if source_flavor not in ALLOWED_FLAVORS:
        errors.append(
            "sidecar frontmatter 'flavor' must be one of plan-defect|scope-drift|env-drift "
            f"(got '{source_flavor}')"
        )
    if not disposition.strip():
        errors.append(
            "--disposition is required and must contain the breakdown flavor disposition"
        )
    elif (
        source_flavor in ALLOWED_FLAVORS
        and flavor in ALLOWED_FLAVORS
        and not validate_flavor_disposition(source_flavor, flavor, disposition)
    ):
        if flavor == source_flavor:
            errors.append(
                f"--disposition must start with 'accepted flavor: {flavor}' when breakdown "
                "keeps the engineering flavor"
            )
        else:
            errors.append(
                f"--disposition must start with 're-classified to {flavor}: <reason>' when "
                f"breakdown changes engineering flavor '{source_flavor}'"
            )
    if not decisions:
        errors.append("at least one --decision is required")

    closure = extract_section(sidecar, "## Closure Forecast")
    required = extract_section(sidecar, "## Required Planner Decisions")
    if not closure.strip():
        errors.append("sidecar missing non-empty '## Closure Forecast'")
    if not required.strip():
        errors.append("sidecar missing non-empty '## Required Planner Decisions'")

    decision_text = "\n".join(decisions)
    if route == "engineering" and closes_gate != "true":
        errors.append(
            "route=engineering requires --closes-gate true; failed gates cannot be routed "
            "back to engineering"
        )
    if NEGATIVE_FORECAST.search(closure):
        if route == "engineering":
            required_count = required_decision_count(required)
            if len(decisions) < required_count:
                errors.append(
                    "sidecar Closure Forecast is negative/insufficient and has "
                    f"{required_count} required planner decisions, but intake supplied only "
                    f"{len(decisions)} decision(s)"
                )
            if RESIDUAL_DECISION.search(required) and not RESIDUAL_DECISION.search(
                decision_text
            ):
                errors.append(
                    "sidecar requires residual/baseline/env handling, but intake decisions "
                    "do not mention such handling"
                )
        if route == "task_update" and closes_gate != "true":
            errors.append(
                "route=task_update with a negative Closure Forecast requires --closes-gate "
                "true; otherwise do not mark processed"
            )
    if route == "baseline_approval" and not RESIDUAL_DECISION.search(decision_text):
        errors.append(
            "route=baseline_approval must include a baseline/env decision in --decision"
        )

    if errors:
        print(f"✗ validate-breakdown-escalation-intake.sh FAIL — {sidecar}", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        print(
            "  action: do not edit task.md, do not write JIRA, do not set processed:true",
            file=sys.stderr,
        )
        return 1

    suffix = ""
    if scope == "packaging":
        suffix = " scope=packaging escalation_count_delta=0"
    print(
        "✓ validate-breakdown-escalation-intake.sh PASS — "
        f"route={route} closes_gate={closes_gate} flavor={flavor}{suffix}"
    )
    return 0


SELF_TEST_SIDECAR = """---
skill: engineering
ticket: TASK-3711
epic: EPIC-478
flavor: env-drift
escalation_count: 1
timestamp: 2026-04-27T07:34:56Z
truncated: false
scrubbed: true
---

## Summary

Storage helper typing is necessary but insufficient; residual baseline drift remains.

## Closure Forecast

No — storage-only permission is insufficient. It can remove two errors, but ci-local will still fail.

## Required Planner Decisions

1. Decide whether storage helper typing edits are folded into T3a.
2. Decide how the residual +12 baseline/env mismatch is resolved before engineering resumes.
"""


def quiet_validate(*args: Any) -> int:
    """Run a negative self-test case without leaking expected diagnostics."""
    with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
        return validate(*args)


def self_test() -> int:
    """Run the legacy embedded behavior cases."""
    with tempfile.TemporaryDirectory() as directory:
        sidecar = Path(directory) / "T3a-1.md"
        sidecar.write_text(SELF_TEST_SIDECAR, encoding="utf-8")

        print("self-test: partial route to engineering must FAIL")
        if quiet_validate(
            sidecar,
            "engineering",
            "true",
            "plan-defect",
            "re-classified to plan-defect: storage helper belongs to this task",
            "full",
            ["storage helper typing folded into T3a"],
        ) == 0:
            print("self-test failed: partial engineering decision passed", file=sys.stderr)
            return 1

        print("self-test: accepted flavor requires accepted disposition")
        if quiet_validate(
            sidecar,
            "wait",
            "false",
            "env-drift",
            "re-classified to env-drift: missing accepted wording",
            "full",
            ["residual baseline/env handled by waiting for sibling baseline correction"],
        ) == 0:
            print(
                "self-test failed: accepted flavor with re-classified wording passed",
                file=sys.stderr,
            )
            return 1

        print("self-test: complete route to engineering must PASS")
        if validate(
            sidecar,
            "engineering",
            "true",
            "env-drift",
            "accepted flavor: env-drift",
            "full",
            [
                "storage helper typing folded into T3a",
                "residual baseline/env handled by waiting for sibling baseline correction "
                "before engineering resumes",
            ],
        ):
            return 1

        print("self-test: re-classified disposition must PASS")
        if validate(
            sidecar,
            "refinement",
            "false",
            "plan-defect",
            "re-classified to plan-defect: storage helper belongs to the original task and "
            "residual scope needs replanning",
            "full",
            ["residual baseline/env indicates deeper planning drift; route refinement instead of engineering"],
        ):
            return 1

        print("self-test: route to refinement with closes=false must PASS")
        if validate(
            sidecar,
            "refinement",
            "false",
            "env-drift",
            "accepted flavor: env-drift",
            "full",
            ["residual baseline/env indicates deeper planning drift; route refinement instead of engineering"],
        ):
            return 1

        print("self-test: packaging plan-defect task_update must PASS with no-increment token")
        output = io.StringIO()
        with redirect_stdout(output):
            result = validate(
                sidecar,
                "task_update",
                "true",
                "plan-defect",
                "re-classified to plan-defect: only the per-task packaging field needs a backfill",
                "packaging",
                ["widen the per-task Allowed Files glob so the colocated change is in scope"],
            )
        if result or "escalation_count_delta=0" not in output.getvalue():
            print(
                "self-test failed: packaging task_update did not emit escalation_count_delta=0",
                file=sys.stderr,
            )
            return 1

        print("self-test: packaging scope with non-task_update route must FAIL")
        if quiet_validate(
            sidecar,
            "refinement",
            "false",
            "plan-defect",
            "re-classified to plan-defect: only the per-task packaging field needs a backfill",
            "packaging",
            ["this should be rejected because packaging requires task_update"],
        ) == 0:
            print(
                "self-test failed: packaging scope with route=refinement passed",
                file=sys.stderr,
            )
            return 1
    return 0


def build_parser() -> CompatParser:
    """Build the compatibility CLI parser."""
    parser = CompatParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--sidecar", default="")
    parser.add_argument("--route", default="")
    parser.add_argument("--closes-gate", default="")
    parser.add_argument("--flavor", default="")
    parser.add_argument("--disposition", default="")
    parser.add_argument("--scope", default="full")
    parser.add_argument("--decision", action="append", default=[])
    parser.add_argument("--task-md", default="")
    parser.add_argument("--repo", default="")
    parser.add_argument("--head-sha", default="")
    parser.add_argument("--inbox-dir", default="")
    parser.add_argument("-h", "--help", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    """Run the compatibility CLI."""
    args = build_parser().parse_args(argv)
    if args.self_test:
        return self_test()
    if args.help:
        return usage()
    if not all((args.sidecar, args.route, args.closes_gate, args.flavor, args.disposition)):
        return usage()

    result = validate(
        Path(args.sidecar),
        args.route,
        args.closes_gate,
        args.flavor,
        args.disposition,
        args.scope,
        args.decision,
    )
    if result:
        return result
    if args.route == "task_update" and args.task_md:
        repo = args.repo
        if not repo:
            probe = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            repo = probe.stdout.strip() if probe.returncode == 0 else str(Path.cwd())
        script_dir = Path(__file__).resolve().parent.parent
        refresh_args = [
            "bash",
            str(script_dir / "refresh-baseline-snapshot.sh"),
            "--repo",
            repo,
            "--task-md",
            args.task_md,
            "--evidence",
            args.sidecar,
        ]
        if args.head_sha:
            refresh_args.extend(("--head-sha", args.head_sha))
        return subprocess.run(refresh_args, check=False).returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
