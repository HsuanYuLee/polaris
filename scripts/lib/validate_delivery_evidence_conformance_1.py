"""Validate framework-release delivery evidence for every required DP task."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


CLI_NAME = os.environ.get("POLARIS_COMPAT_CLI", "validate-delivery-evidence-conformance.sh")
SCRIPT_DIR = Path(__file__).resolve().parent.parent
PARSE_TASK_MD = SCRIPT_DIR / "parse-task-md.sh"
HEAD_PATTERN = re.compile(r"^[0-9a-f]{7,40}$")


def die_usage(message: str) -> int:
    """Emit the legacy structured usage marker."""
    print(f"POLARIS_DELIVERY_EVIDENCE_USAGE: {message}", file=sys.stderr)
    return 2


class CompatParser(argparse.ArgumentParser):
    """Argparse parser that emits the gate's structured usage marker."""

    def error(self, message: str) -> None:
        if message.startswith("unrecognized arguments:"):
            unknown = message.removeprefix("unrecognized arguments:").strip().split()[0]
            message = f"unknown arg: {unknown}"
        raise SystemExit(die_usage(message))


def help_text() -> str:
    """Return a concise compatibility help surface."""
    return f"""{CLI_NAME} — framework-release delivery-evidence conformance gate.

Inputs:
  --mode planning|pre-release          (required)
  --source-refinement-json <path>      (resolve source.type + derive tasks dir)
  --tasks-dir <dir>                    (enumerate task.md under a tasks/ dir)
  --task-md <path> [--task-md ...]     (explicit resolved task.md list)
  --task-head-sha "WID=sha,WID=sha"    (DP-360 authority order #1 override map)
"""


def build_parser() -> CompatParser:
    """Build the compatibility CLI parser."""
    parser = CompatParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--mode", default="")
    parser.add_argument("--source-refinement-json", default="")
    parser.add_argument("--tasks-dir", default="")
    parser.add_argument("--task-md", action="append", default=[])
    parser.add_argument("--task-head-sha", default="")
    parser.add_argument("-h", "--help", action="store_true")
    return parser


def find_refinement_json(start: Path) -> Path | None:
    """Walk upward from a task location to its owning refinement.json."""
    current = start
    while True:
        candidate = current / "refinement.json"
        if candidate.is_file():
            return candidate
        if current.parent == current:
            return None
        current = current.parent


def read_source_type(refinement_json: Path | None) -> str:
    """Read source.type, matching the legacy no-op behavior on malformed input."""
    if refinement_json is None or not refinement_json.is_file():
        return ""
    try:
        data = json.loads(refinement_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    source = data.get("source") if isinstance(data, dict) else None
    if not isinstance(source, dict):
        return ""
    value = source.get("type")
    return value if isinstance(value, str) else ""


def enumerate_task_mds(scan_dir: Path) -> list[Path]:
    """Enumerate legacy flat and folder-native task files at max depth two."""
    candidates: set[Path] = set()
    if not scan_dir.is_dir():
        return []
    for child in scan_dir.iterdir():
        if child.is_file() and (
            child.name == "index.md"
            or re.fullmatch(r"[TV].*\.md", child.name)
        ):
            candidates.add(child)
        elif child.is_dir() and child.name not in {"pr-release", "archive"}:
            for nested in child.iterdir():
                if nested.is_file() and (
                    nested.name == "index.md"
                    or re.fullmatch(r"[TV].*\.md", nested.name)
                ):
                    candidates.add(nested)
    return sorted(candidates, key=lambda path: str(path))


def parse_field(task_md: Path, field: str) -> str:
    """Delegate task field reads to the DP-360 canonical reader."""
    result = subprocess.run(
        ["bash", str(PARSE_TASK_MD), str(task_md), "--no-resolve", "--field", field],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def parse_overrides(raw: str) -> dict[str, str]:
    """Parse the closeout-compatible comma-separated override map."""
    overrides: dict[str, str] = {}
    if not raw:
        return overrides
    for pair in raw.split(","):
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        if key not in overrides:
            overrides[key] = value
    return overrides


def is_required_task(work_item_id: str, shape: str, branch: str) -> bool:
    """Classify implementation T tasks and branch-bearing V tasks."""
    if re.search(r"-T[0-9]+", work_item_id) and shape == "implementation":
        return True
    return bool(
        re.search(r"-V[0-9]+", work_item_id) and branch and branch != "N/A"
    )


def validate(mode: str, task_mds: list[Path], overrides: dict[str, str]) -> int:
    """Validate or surface the delivery evidence contract."""
    violations: list[str] = []
    checked = 0
    for task_md in task_mds:
        if not task_md.is_file():
            violations.append(f"{task_md}: task.md not found")
            continue
        work_item_id = parse_field(task_md, "work_item_id")
        shape = parse_field(task_md, "task_shape")
        branch = parse_field(task_md, "task_branch")
        if not is_required_task(work_item_id, shape, branch):
            continue
        checked += 1
        label = work_item_id or str(task_md)

        if mode == "planning":
            branch_note = branch if branch and branch != "N/A" else "<derived at breakdown>"
            print(
                f"delivery-evidence-conformance[planning]: {label} -> /framework-release "
                "will require a resolvable delivered head (DP-360 authority order: "
                "--task-head-sha override OR task.md deliverable.head_sha; pr_url/pr_state "
                f"optional provenance, CLOSED=stale); branch={branch_note}",
                file=sys.stderr,
            )
            continue

        override_head = overrides.get(work_item_id, "")
        block_head = parse_field(task_md, "deliverable_head_sha")
        if override_head:
            resolved_head = override_head
            head_source = "--task-head-sha override"
        else:
            resolved_head = block_head
            head_source = "deliverable.head_sha"
        if not resolved_head:
            violations.append(
                f"{label}: no delivered head resolvable (neither --task-head-sha "
                f"{work_item_id}=<sha> override nor task.md deliverable.head_sha; DP-360 "
                "authority order exhausted; no fallback to branch ref / marker filename head)"
            )
            continue
        if not HEAD_PATTERN.fullmatch(resolved_head):
            violations.append(
                f"{label}: delivered head malformed ({head_source}): '{resolved_head}' "
                "(expected 7-40 hex)"
            )
        pr_state = parse_field(task_md, "deliverable_pr_state")
        if pr_state == "CLOSED":
            violations.append(
                f"{label}: deliverable.pr_state=CLOSED (stale/superseded delivery; "
                "re-deliver before release)"
            )
        elif pr_state and pr_state not in {"OPEN", "MERGED"}:
            violations.append(
                f"{label}: deliverable.pr_state invalid: '{pr_state}' "
                "(expected OPEN|MERGED when present)"
            )

    if violations:
        print(
            "POLARIS_DELIVERY_EVIDENCE_NON_CONFORMANT: "
            f"{len(violations)} non-conformant task(s) [mode={mode}, source=DP]",
            file=sys.stderr,
        )
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 2
    if mode == "planning":
        print(
            "delivery-evidence-conformance[planning]: PASS "
            f"({checked} required task(s); delivery-evidence contract surfaced)",
            file=sys.stderr,
        )
    else:
        print(
            "delivery-evidence-conformance[pre-release]: PASS "
            f"({checked} required task(s) conformant)",
            file=sys.stderr,
        )
    return 0


def main(argv: list[str]) -> int:
    """Run the delivery-evidence conformance CLI."""
    args = build_parser().parse_args(argv)
    if args.help:
        print(help_text(), end="")
        return 0
    if args.mode not in {"planning", "pre-release"}:
        return die_usage("--mode must be planning|pre-release")
    if not PARSE_TASK_MD.is_file():
        return die_usage(f"canonical reader not found: {PARSE_TASK_MD}")

    refinement_json = Path(args.source_refinement_json) if args.source_refinement_json else None
    task_mds = [Path(path) for path in args.task_md]
    tasks_dir = Path(args.tasks_dir) if args.tasks_dir else None
    if refinement_json is None:
        if tasks_dir is not None:
            refinement_json = find_refinement_json(tasks_dir)
        elif task_mds:
            refinement_json = find_refinement_json(task_mds[0].parent)

    source_type = read_source_type(refinement_json)
    if source_type != "dp":
        print(
            f"delivery-evidence-conformance[{args.mode}]: "
            f"source.type='{source_type or 'unknown'}' != dp; "
            "framework-release-only gate no-op PASS",
            file=sys.stderr,
        )
        return 0

    if not task_mds:
        scan_dir = tasks_dir
        if scan_dir is None and refinement_json is not None:
            scan_dir = refinement_json.parent / "tasks"
        if scan_dir is None or not scan_dir.is_dir():
            label = str(scan_dir) if scan_dir is not None else "<none>"
            print(
                f"delivery-evidence-conformance[{args.mode}]: no tasks dir at '{label}' "
                "(tasks not derived yet); nothing to check",
                file=sys.stderr,
            )
            return 0
        task_mds = enumerate_task_mds(scan_dir)
        if not task_mds:
            print(
                f"delivery-evidence-conformance[{args.mode}]: no candidate task.md "
                f"under '{scan_dir}'; nothing to check",
                file=sys.stderr,
            )
            return 0
    if not task_mds:
        return die_usage("no task.md files to check")
    return validate(args.mode, task_mds, parse_overrides(args.task_head_sha))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
