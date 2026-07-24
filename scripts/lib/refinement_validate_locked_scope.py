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
        raise ValueError(f"{ref}:{relative} is not observable")
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{ref}:{relative} is not valid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{ref}:{relative} must contain a JSON object")
    return value


def load_file(path: Path, label: str) -> dict:
    if not path.is_file():
        raise ValueError(f"{label} file is not observable: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} file is not valid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} file must contain a JSON object: {path}")
    return value


def source_identity(document: dict, label: str) -> tuple[str, str]:
    source = document.get("source")
    if source is None:
        source_type = "jira"
    elif isinstance(source, dict):
        source_type = source.get("type")
    else:
        raise ValueError(f"{label} source identity is invalid")
    if not isinstance(source_type, str) or not source_type:
        raise ValueError(f"{label} source.type identity is missing")
    if source_type == "jira":
        epic = document.get("epic")
        if not isinstance(epic, str) or not epic:
            raise ValueError(f"{label} epic identity is missing for source.type=jira")
        return source_type, epic
    if not isinstance(source, dict):
        raise ValueError(f"{label} source identity is missing")
    source_id = source.get("id")
    if not isinstance(source_id, str) or not source_id:
        raise ValueError(f"{label} source.id identity is missing for source.type={source_type}")
    return source_type, source_id


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


def protected_field_problems(before: dict, after: dict) -> list[str]:
    problems = []
    for field in LOCKED_FIELDS:
        if before.get(field) != after.get(field):
            problems.append(f"refinement.json LOCKED field changed: {field}")
    problems.extend(
        ac_problems(before.get("acceptance_criteria"), after.get("acceptance_criteria"))
    )
    return problems


def fail_unobservable(message: str) -> int:
    print("POLARIS_LOCKED_SCOPE_AUTHORITY_UNOBSERVABLE", file=sys.stderr)
    print(f"  - {message}", file=sys.stderr)
    return 2


def emit_comparison_result(problems: list[str], authority: str) -> int:
    if problems:
        print("POLARIS_LOCKED_SCOPE_VIOLATION", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 2
    print(f"PASS: refinement amendment respects LOCKED scope guard ({authority})")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("--container")
    parser.add_argument("--base-ref")
    parser.add_argument("--head-ref", default="HEAD")
    parser.add_argument("--repo")
    parser.add_argument("--current-file")
    parser.add_argument("--candidate-file")
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
#
# Explicit-file mode (DP-444):
#   validate-refinement-locked-scope.sh --current-file CURRENT.json
#     --candidate-file CANDIDATE.json
# Git compatibility mode:
#   validate-refinement-locked-scope.sh --container CONTAINER
#     --base-ref BASE [--head-ref HEAD] [--repo REPO]
""",
            end="",
            file=sys.stderr,
        )
        return 1
    explicit_requested = bool(args.current_file or args.candidate_file)
    if unknown:
        print(f"ERROR: unknown argument: {unknown[0]}", file=sys.stderr)
        return 1
    if explicit_requested:
        if not args.current_file or not args.candidate_file:
            return fail_unobservable(
                "explicit-file mode requires both --current-file and --candidate-file"
            )
        current_path = Path(args.current_file).resolve()
        candidate_path = Path(args.candidate_file).resolve()
        try:
            same_authority = current_path.samefile(candidate_path)
        except OSError as exc:
            return fail_unobservable(
                f"current/candidate authority cannot be identified: {exc}"
            )
        if same_authority:
            return fail_unobservable(
                "current and candidate authority resolve to the same file"
            )
        try:
            before = load_file(current_path, "current")
            after = load_file(candidate_path, "candidate")
            before_identity = source_identity(before, "current")
            after_identity = source_identity(after, "candidate")
        except ValueError as exc:
            return fail_unobservable(str(exc))
        if before_identity != after_identity:
            return fail_unobservable(
                "current/candidate source identity mismatch: "
                f"{before_identity!r} != {after_identity!r}"
            )
        return emit_comparison_result(
            protected_field_problems(before, after),
            f"explicit:{current_path} -> {candidate_path}",
        )
    if not args.container or not args.base_ref:
        print(
            "ERROR: explicit mode requires --current-file/--candidate-file; "
            "git mode requires --container/--base-ref",
            file=sys.stderr,
        )
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
    try:
        relative_container = container.relative_to(repo).as_posix()
    except ValueError:
        return fail_unobservable(
            f"container is outside the declared repository: {container} (repo={repo})"
        )
    relative_json = f"{relative_container.rstrip('/')}/refinement.json"
    for ref in (args.base_ref, args.head_ref):
        observable = git_output(repo, "cat-file", "-e", f"{ref}:{relative_json}")
        if observable.returncode:
            return fail_unobservable(
                f"git authority blob is not observable: {ref}:{relative_json}"
            )
    try:
        before = show(repo, args.base_ref, relative_json)
        after = show(repo, args.head_ref, relative_json)
    except ValueError as exc:
        return fail_unobservable(str(exc))
    return emit_comparison_result(
        protected_field_problems(before, after), relative_container
    )


if __name__ == "__main__":
    raise SystemExit(main())
