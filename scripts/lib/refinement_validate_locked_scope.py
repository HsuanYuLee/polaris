"""比較 LOCKED refinement amendment 的 protected JSON fields。"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
from pathlib import Path


LOCKED_FIELDS = ("goal", "background", "decisions", "scope")


def git_output(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)


def show(repo: Path, ref: str, relative: str) -> dict:
    result = git_output(repo, "show", f"{ref}:{relative}")
    if result.returncode:
        return {}
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def strip_detail(ac: dict) -> dict:
    clone = copy.deepcopy(ac)
    verification = clone.get("verification")
    if isinstance(verification, dict):
        verification.pop("detail", None)
    return clone


def ac_problems(before_acs: object, after_acs: object) -> list[str]:
    if before_acs == after_acs:
        return []
    if not isinstance(before_acs, list) or not isinstance(after_acs, list):
        return ["refinement.json LOCKED field changed: acceptance_criteria"]
    problems: list[str] = []

    def index(entries: list, side: str) -> dict[str, dict]:
        indexed: dict[str, dict] = {}
        for entry in entries:
            ac_id = entry.get("id") if isinstance(entry, dict) else None
            if not isinstance(ac_id, str) or not ac_id:
                problems.append(
                    f"refinement.json acceptance_criteria entry without usable id ({side}); cannot pair per-AC-id"
                )
            elif ac_id in indexed:
                problems.append(f"refinement.json acceptance_criteria duplicate id ({side}): {ac_id}")
            else:
                indexed[ac_id] = entry
        return indexed

    before = index(before_acs, "base")
    after = index(after_acs, "head")
    if problems:
        return problems
    for ac_id in sorted(set(after) - set(before)):
        problems.append(f"refinement.json acceptance_criteria AC added (locked): {ac_id}")
    for ac_id in sorted(set(before) - set(after)):
        problems.append(f"refinement.json acceptance_criteria AC removed (locked): {ac_id}")
    for ac_id in sorted(set(before) & set(after)):
        left, right = strip_detail(before[ac_id]), strip_detail(after[ac_id])
        if left != right:
            changed = sorted(key for key in set(left) | set(right) if left.get(key) != right.get(key))
            problems.append(
                f"refinement.json acceptance_criteria LOCKED field changed ({ac_id}): {', '.join(changed)}"
            )
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--container")
    parser.add_argument("--base-ref")
    parser.add_argument("--head-ref", default="HEAD")
    parser.add_argument("--repo")
    parser.add_argument("-h", "--help", action="store_true")
    args, unknown = parser.parse_known_args(argv)
    if args.help:
        print(
            """# JSON-authority only; DP-311 T5: per-field acceptance_criteria granularity).
#
# Compares a refinement amendment diff against the LOCKED-protected JSON
# authority fields in `refinement.json`. The top-level fields `goal`,
# `background`, `decisions`, `scope` stay whole-field locked: any change exits
# 2 with `POLARIS_LOCKED_SCOPE_VIOLATION` on stderr.
#
# `acceptance_criteria` is compared per-AC-id (DP-311 T5):
#   - AC add / remove / id rename (id-set change) is a violation.
#   - Within each id-paired AC, every field except `verification.detail` is
#     locked (id / text / category / verification.method and any other field).
#     Only `acceptance_criteria[].verification.detail` may change during an
#     amendment.
#
# DP-298 T2 removed the `refinement.md` `## Scope` / heading-diff business-read
# branch: `refinement.json` is the single authoritative source for LOCKED scope,
# and the derived `refinement.md` body is no longer read to make a LOCKED-scope
# decision (it is a render target, not authority). The only remaining reference
# to `refinement.md` in this guard is this comment — there is no executing path
""",
            end="",
            file=sys.stderr,
        )
        return 1
    if unknown or not args.container or not args.base_ref:
        if unknown:
            print(f"ERROR: unknown argument: {unknown[0]}", file=sys.stderr)
        else:
            print("ERROR: --container and --base-ref are required", file=sys.stderr)
        return 1
    container = Path(args.container).resolve()
    if not container.is_dir():
        print(f"ERROR: container directory not found: {args.container}", file=sys.stderr)
        return 1
    if args.repo:
        repo = Path(args.repo).resolve()
    else:
        result = git_output(container, "rev-parse", "--show-toplevel")
        if result.returncode:
            print(f"ERROR: could not resolve git repo for {container}", file=sys.stderr)
            return 1
        repo = Path(result.stdout.strip()).resolve()
    relative_container = Path(Path(container).relative_to(repo)).as_posix()
    relative_json = f"{relative_container.rstrip('/')}/refinement.json"
    diff = git_output(repo, "diff", "--quiet", args.base_ref, args.head_ref, "--", relative_json)
    problems: list[str] = []
    if diff.returncode:
        before, after = show(repo, args.base_ref, relative_json), show(repo, args.head_ref, relative_json)
        for field in LOCKED_FIELDS:
            if before.get(field) != after.get(field):
                problems.append(f"refinement.json LOCKED field changed: {field}")
        problems.extend(ac_problems(before.get("acceptance_criteria"), after.get("acceptance_criteria")))
    if problems:
        print("POLARIS_LOCKED_SCOPE_VIOLATION", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 2
    print(f"PASS: refinement amendment respects LOCKED scope guard ({relative_container})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
