"""Validate the DP-420 current-head gap ledger and bounded delegation authority.

The ledger records an LLM-owned semantic disposition.  This module only checks
mechanically observable properties: identities, enum/state consistency, a
single owner, evidence shape, and whether the paths relevant to an observation
changed after its recorded Git head.
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
ALLOWED_ACTIONS = ("gap_disposition", "task_repair")
FORBIDDEN_ACTIONS = (
    "bypass",
    "cross_source_mutation",
    "partial_release",
    "release",
    "successor_source",
)
DISPOSITION_STATES = {
    "persisting_owned": ("persisting", False),
    "resolved_by_owner": ("resolved", True),
    "obsolete": ("target_absent", True),
    "working_as_designed": ("allowed_by_contract", True),
    "out_of_scope": ("out_of_scope", True),
}
EVIDENCE_KINDS = {"command_result", "contract", "release", "test"}
SOURCE_RE = re.compile(r"^(?:DP|[A-Z][A-Z0-9]+)-[0-9]+$")
WORK_ITEM_RE = re.compile(r"^([A-Z][A-Z0-9]*-[0-9]+)-[TV][0-9]+[a-z]*$")
FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


@dataclass(frozen=True)
class ValidationResult:
    source_id: str | None
    current_head_sha: str | None
    active_gap_ids: tuple[str, ...]
    authority: dict[str, Any] | None
    errors: tuple[str, ...]

    def payload(self) -> dict[str, Any]:
        return {
            "schema_version": SCHEMA_VERSION,
            "source_id": self.source_id,
            "status": "PASS" if not self.errors else "FAIL",
            "validated_head_sha": self.current_head_sha,
            "active_gap_ids": list(self.active_gap_ids),
            "delegation_authority": self.authority if not self.errors else None,
            "errors": list(self.errors),
        }


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=True,
    )


def _current_head(repo: Path) -> tuple[str | None, str | None]:
    proc = _git(repo, "rev-parse", "HEAD")
    if proc.returncode != 0:
        return None, f"repo has no readable Git HEAD: {proc.stderr.strip() or proc.stdout.strip()}"
    value = proc.stdout.strip()
    if not FULL_SHA_RE.fullmatch(value):
        return None, "git rev-parse HEAD did not return a full SHA"
    return value, None


def _paths_current(repo: Path, recorded_head: str, scope_paths: list[str]) -> list[str]:
    errors: list[str] = []
    exists = _git(repo, "cat-file", "-e", f"{recorded_head}^{{commit}}")
    if exists.returncode != 0:
        return [f"recorded head is not a commit in repo: {recorded_head}"]
    ancestor = _git(repo, "merge-base", "--is-ancestor", recorded_head, "HEAD")
    if ancestor.returncode == 1:
        errors.append("recorded head is not an ancestor of current HEAD")
    elif ancestor.returncode != 0:
        errors.append(f"cannot verify recorded-head ancestry: {ancestor.stderr.strip()}")

    tracked = _git(repo, "ls-files", "--", *scope_paths)
    if tracked.returncode != 0:
        errors.append(f"cannot inspect tracked scope paths: {tracked.stderr.strip()}")
    elif not tracked.stdout.strip():
        errors.append("scope paths do not resolve to tracked files at HEAD")
    untracked = _git(repo, "ls-files", "--others", "--exclude-standard", "--", *scope_paths)
    if untracked.returncode != 0:
        errors.append(f"cannot inspect untracked scope paths: {untracked.stderr.strip()}")
    elif untracked.stdout.strip():
        errors.append(f"scope paths contain untracked files: {untracked.stdout.splitlines()}")

    # The ledger itself can be committed after the observation without making
    # the observation stale.  Only explicitly governed scope paths determine
    # currentness, including both committed and worktree changes.
    committed = _git(repo, "diff", "--quiet", recorded_head, "HEAD", "--", *scope_paths)
    if committed.returncode == 1:
        errors.append("scope paths changed after recorded head")
    elif committed.returncode != 0:
        errors.append(f"cannot compare recorded head to HEAD: {committed.stderr.strip()}")

    worktree = _git(repo, "diff", "--quiet", "HEAD", "--", *scope_paths)
    if worktree.returncode == 1:
        errors.append("scope paths have uncommitted changes")
    elif worktree.returncode != 0:
        errors.append(f"cannot inspect worktree currentness: {worktree.stderr.strip()}")

    staged = _git(repo, "diff", "--cached", "--quiet", "HEAD", "--", *scope_paths)
    if staged.returncode == 1:
        errors.append("scope paths have staged changes")
    elif staged.returncode != 0:
        errors.append(f"cannot inspect index currentness: {staged.stderr.strip()}")
    return errors


def _validate_authority(source_id: str, authority: Any) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    if not isinstance(authority, dict):
        return None, ["authority must be an object"]
    if authority.get("source_id") != source_id:
        errors.append("authority.source_id must equal ledger source_id")
    if authority.get("same_source_only") is not True:
        errors.append("authority.same_source_only must be true")
    allowed = authority.get("allowed_actions")
    if allowed != list(ALLOWED_ACTIONS):
        errors.append(f"authority.allowed_actions must equal {list(ALLOWED_ACTIONS)}")
    forbidden = authority.get("forbidden_actions")
    if forbidden != list(FORBIDDEN_ACTIONS):
        errors.append(f"authority.forbidden_actions must equal {list(FORBIDDEN_ACTIONS)}")
    if set(allowed or []) & set(forbidden or []):
        errors.append("authority allowed_actions and forbidden_actions overlap")
    if errors:
        return None, errors
    return {
        "source_id": source_id,
        "same_source_only": True,
        "allowed_actions": list(ALLOWED_ACTIONS),
        "forbidden_actions": list(FORBIDDEN_ACTIONS),
    }, []


def _same_source_work_item_exists(source_container: Path, work_item_id: str) -> bool:
    task_id = work_item_id.rsplit("-", 1)[-1]
    return any(
        candidate.is_file()
        for candidate in (
            source_container / "tasks" / task_id / "index.md",
            source_container / "tasks" / f"{task_id}.md",
            source_container / "tasks" / "pr-release" / task_id / "index.md",
            source_container / "tasks" / "pr-release" / f"{task_id}.md",
        )
    )


def _validate_owner(
    prefix: str,
    source_id: str,
    source_container: Path,
    disposition: str,
    owner: Any,
) -> list[str]:
    errors: list[str] = []
    if disposition == "persisting_owned":
        if not isinstance(owner, dict):
            return [f"{prefix}.owner must be one object for a persisting gap"]
        if owner.get("source_id") != source_id:
            errors.append(f"{prefix}.owner.source_id must equal {source_id} for persisting_owned")
        work_item_id = owner.get("work_item_id")
        match = WORK_ITEM_RE.fullmatch(work_item_id) if isinstance(work_item_id, str) else None
        if match is None or match.group(1) != source_id:
            errors.append(f"{prefix}.owner.work_item_id must be a same-source T/V work item")
        elif not _same_source_work_item_exists(source_container, work_item_id):
            errors.append(f"{prefix}.owner.work_item_id does not exist in source container")
        return errors

    if disposition == "resolved_by_owner":
        if not isinstance(owner, dict):
            return [f"{prefix}.owner must identify the resolving owner"]
        owner_source = owner.get("source_id")
        if not isinstance(owner_source, str) or not SOURCE_RE.fullmatch(owner_source):
            errors.append(f"{prefix}.owner.source_id must be a source identity")
        elif owner_source not in {source_id, "DP-422", "DP-423"}:
            errors.append(
                f"{prefix}.owner.source_id must be the ledger source or canonical foreign owner DP-422/DP-423"
            )
        work_item_id = owner.get("work_item_id")
        if work_item_id is not None:
            match = WORK_ITEM_RE.fullmatch(work_item_id) if isinstance(work_item_id, str) else None
            if match is None or match.group(1) != owner_source:
                errors.append(f"{prefix}.owner.work_item_id must belong to owner.source_id")
            elif owner_source == source_id and not _same_source_work_item_exists(source_container, work_item_id):
                errors.append(f"{prefix}.owner.work_item_id does not exist in source container")
        return errors

    if owner is not None:
        errors.append(f"{prefix}.owner must be null for disposition={disposition}")
    return errors


def _argv_tokens(argv: list[str]) -> list[str]:
    tokens = list(argv)
    for index, token in enumerate(argv[:-1]):
        if token in {"-c", "-lc"}:
            try:
                tokens.extend(shlex.split(argv[index + 1]))
            except ValueError:
                # Malformed shell text is not interpreted as evidence input;
                # the caller will still require at least one tracked path.
                pass
    return tokens


def _tracked_reproducer_paths(repo: Path, argv: list[str]) -> set[str]:
    paths: set[str] = set()
    for token in _argv_tokens(argv):
        candidate = token.split("::", 1)[0]
        if candidate in {"", ".", "./"} or candidate.startswith("-") or Path(candidate).is_absolute():
            continue
        proc = _git(repo, "ls-files", "--", candidate)
        if proc.returncode == 0:
            paths.update(line for line in proc.stdout.splitlines() if line)
    return paths


def _tracked_evidence_path(repo: Path, value: str) -> bool:
    candidate = value.split("::", 1)[0]
    if not candidate or Path(candidate).is_absolute():
        return False
    proc = _git(repo, "ls-files", "--error-unmatch", "--", candidate)
    return proc.returncode == 0 and (repo / candidate).is_file()


def validate_payload(
    payload: Any,
    repo: Path,
    source_container: Path,
    *,
    require_terminal: bool = False,
) -> ValidationResult:
    errors: list[str] = []
    active: list[str] = []
    if not isinstance(payload, dict):
        return ValidationResult(None, None, (), None, ("ledger must be a JSON object",))
    if payload.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}")
    source_id = payload.get("source_id")
    if not isinstance(source_id, str) or not SOURCE_RE.fullmatch(source_id):
        errors.append("source_id must be a DP or JIRA source identity")
        source_id = None

    refinement_json = source_container / "refinement.json"
    try:
        container_source_id = json.loads(refinement_json.read_text(encoding="utf-8")).get("source", {}).get("id")
    except Exception as exc:
        container_source_id = None
        errors.append(f"source container has no readable refinement.json: {exc}")
    if source_id and container_source_id != source_id:
        errors.append("source container refinement identity does not match ledger source_id")

    current_head, head_error = _current_head(repo)
    if head_error:
        errors.append(head_error)

    authority, authority_errors = _validate_authority(source_id or "", payload.get("authority"))
    errors.extend(authority_errors)

    gaps = payload.get("gaps")
    if not isinstance(gaps, list) or not gaps:
        errors.append("gaps must be a non-empty array")
        gaps = []

    seen_gap_ids: set[str] = set()
    seen_gap_keys: set[str] = set()
    seen_reproducer_ids: set[str] = set()
    for index, gap in enumerate(gaps):
        prefix = f"gaps[{index}]"
        if not isinstance(gap, dict):
            errors.append(f"{prefix} must be an object")
            continue
        required = {
            "gap_id", "gap_key", "source_id", "reproducer", "head", "observed",
            "disposition", "owner", "terminal", "evidence", "currentness",
        }
        missing = sorted(required - set(gap))
        if missing:
            errors.append(f"{prefix} missing fields: {missing}")
            continue
        gap_id = gap.get("gap_id")
        gap_key = gap.get("gap_key")
        if not isinstance(gap_id, str) or not gap_id:
            errors.append(f"{prefix}.gap_id must be non-empty")
        elif gap_id in seen_gap_ids:
            errors.append(f"duplicate gap_id: {gap_id}")
        else:
            seen_gap_ids.add(gap_id)
        if not isinstance(gap_key, str) or not gap_key:
            errors.append(f"{prefix}.gap_key must be non-empty")
        elif gap_key in seen_gap_keys:
            errors.append(f"duplicate gap_key has multiple implementation records: {gap_key}")
        else:
            seen_gap_keys.add(gap_key)
        if gap.get("source_id") != source_id:
            errors.append(f"{prefix}.source_id must equal ledger source_id")

        reproducer = gap.get("reproducer")
        reproducer_argv: list[str] = []
        if not isinstance(reproducer, dict):
            errors.append(f"{prefix}.reproducer must be an object")
        else:
            reproducer_id = reproducer.get("id")
            if not isinstance(reproducer_id, str) or not reproducer_id:
                errors.append(f"{prefix}.reproducer.id must be non-empty")
            elif reproducer_id in seen_reproducer_ids:
                errors.append(f"duplicate reproducer.id: {reproducer_id}")
            else:
                seen_reproducer_ids.add(reproducer_id)
            if reproducer.get("kind") != "command":
                errors.append(f"{prefix}.reproducer.kind must be command")
            argv = reproducer.get("argv")
            if not isinstance(argv, list) or not argv or not all(isinstance(x, str) and x for x in argv):
                errors.append(f"{prefix}.reproducer.argv must be a non-empty string array")
            else:
                reproducer_argv = argv

        disposition = gap.get("disposition")
        if disposition not in DISPOSITION_STATES:
            errors.append(f"{prefix}.disposition is unsupported: {disposition}")
            expected_state = None
            expected_terminal = None
        else:
            expected_state, expected_terminal = DISPOSITION_STATES[disposition]
            if disposition == "persisting_owned" and isinstance(gap_id, str):
                active.append(gap_id)
        observed = gap.get("observed")
        if not isinstance(observed, dict):
            errors.append(f"{prefix}.observed must be an object")
        else:
            if observed.get("state") != expected_state:
                errors.append(f"{prefix}.observed.state must be {expected_state!r}")
            if not isinstance(observed.get("exit_code"), int):
                errors.append(f"{prefix}.observed.exit_code must be an integer")
        if gap.get("terminal") is not expected_terminal:
            errors.append(f"{prefix}.terminal must be {expected_terminal!r}")
        if isinstance(disposition, str):
            errors.extend(
                _validate_owner(prefix, source_id or "", source_container, disposition, gap.get("owner"))
            )

        evidence = gap.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            errors.append(f"{prefix}.evidence must be a non-empty array")
        else:
            for evidence_index, item in enumerate(evidence):
                eprefix = f"{prefix}.evidence[{evidence_index}]"
                if not isinstance(item, dict) or item.get("kind") not in EVIDENCE_KINDS:
                    errors.append(f"{eprefix}.kind must be one of {sorted(EVIDENCE_KINDS)}")
                    continue
                if item.get("kind") == "command_result" and item.get("reproducer_id") != reproducer.get("id"):
                    errors.append(f"{eprefix}.reproducer_id must match reproducer.id")
                if item.get("kind") == "command_result":
                    if not isinstance(item.get("exit_code"), int):
                        errors.append(f"{eprefix}.exit_code must be an integer")
                    elif isinstance(observed, dict) and item.get("exit_code") != observed.get("exit_code"):
                        errors.append(f"{eprefix}.exit_code must match observed.exit_code")
                if item.get("kind") != "command_result" and not any(
                    isinstance(item.get(field), str) and item.get(field)
                    for field in ("path", "uri", "test_id")
                ):
                    errors.append(f"{eprefix} must identify path, uri, or test_id")
                if item.get("kind") in {"contract", "test"}:
                    evidence_path = item.get("path") or item.get("test_id")
                    if not isinstance(evidence_path, str) or not _tracked_evidence_path(repo, evidence_path):
                        errors.append(f"{eprefix} must identify an existing tracked repo file")

        head = gap.get("head")
        currentness = gap.get("currentness")
        if not isinstance(head, str) or not FULL_SHA_RE.fullmatch(head):
            errors.append(f"{prefix}.head must be a full Git commit SHA")
        if not isinstance(currentness, dict):
            errors.append(f"{prefix}.currentness must be an object")
        else:
            if currentness.get("status") != "current":
                errors.append(f"{prefix}.currentness.status must be current")
            scope_paths = currentness.get("scope_paths")
            if not isinstance(scope_paths, list) or not scope_paths or not all(
                isinstance(path, str) and path and not Path(path).is_absolute() for path in scope_paths
            ):
                errors.append(f"{prefix}.currentness.scope_paths must be non-empty repo-relative paths")
            elif isinstance(head, str) and FULL_SHA_RE.fullmatch(head):
                errors.extend(f"{prefix}.currentness: {error}" for error in _paths_current(repo, head, scope_paths))
                referenced_paths = _tracked_reproducer_paths(repo, reproducer_argv)
                if not referenced_paths:
                    errors.append(f"{prefix}.reproducer.argv must reference at least one tracked repo file")
                missing_reproducer_paths = sorted(referenced_paths - set(scope_paths))
                if missing_reproducer_paths:
                    errors.append(
                        f"{prefix}.currentness.scope_paths missing tracked reproducer inputs: "
                        f"{missing_reproducer_paths}"
                    )

    if require_terminal and active:
        errors.append(f"terminal query has persisting gaps: {sorted(active)}")
    return ValidationResult(
        source_id,
        current_head,
        tuple(sorted(active)),
        authority,
        tuple(errors),
    )


def validate_file(
    path: Path,
    repo: Path,
    source_container: Path,
    *,
    require_terminal: bool = False,
) -> ValidationResult:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return ValidationResult(None, None, (), None, (f"ledger is not valid JSON: {exc}",))
    return validate_payload(payload, repo, source_container, require_terminal=require_terminal)


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--source-container", required=True)
    parser.add_argument("--source-id")
    parser.add_argument("--require-terminal", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = validate_file(
        Path(args.ledger).resolve(),
        Path(args.repo).resolve(),
        Path(args.source_container).resolve(),
        require_terminal=args.require_terminal,
    )
    errors = list(result.errors)
    if args.source_id and result.source_id != args.source_id:
        errors.append(f"ledger source_id {result.source_id!r} does not match requested source {args.source_id!r}")
        result = ValidationResult(result.source_id, result.current_head_sha, result.active_gap_ids, result.authority, tuple(errors))
    if args.json:
        print(json.dumps(result.payload(), ensure_ascii=False, indent=2, sort_keys=True))
    elif result.errors:
        for error in result.errors:
            print(f"POLARIS_CURRENT_HEAD_GAP_LEDGER: {error}")
    else:
        print(f"PASS: current-head gap ledger ({result.source_id}, active={len(result.active_gap_ids)})")
    return 2 if result.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
