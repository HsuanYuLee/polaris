"""Resolve the mechanically decidable DP-420 source-certification inputs.

The shell entrypoint remains orchestration-only: this module validates source
lifecycle, archived prerequisite releases, owner uniqueness, and the exact
task/evidence inventory that canonical evidence validators must consume.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
TASK_ID_RE = re.compile(r"^T[0-9]+$")
RELEASE_TAG_RE = re.compile(r"/releases/tag/(v[0-9]+\.[0-9]+\.[0-9]+)$")
REQUIRED_FOREIGN_SOURCES = ("DP-422", "DP-423")
REQUIRED_OWNER_MATRIX = {
    "pytest_corpus_migration": ("DP-420", "owned"),
    "current_head_gap_authority_and_certification": ("DP-420", "owned"),
    "skill_flow_producer_consumer_task_shape_scope_w12_safe_help": ("DP-422", "resolved_by_owner"),
    "handbook_repo_policy_changeset_generated_artifact_w11": ("DP-423", "resolved_by_owner"),
    "task_md_core_packaging_consumer_residual": ("DP-420-T5", "owned"),
    "release_closeout_pr_repo_context": ("DP-420-T11", "owned"),
    "recovery_successor": (None, "DP-427_ABANDONED"),
}


@dataclass(frozen=True)
class TaskRecord:
    work_item_id: str
    task_md: Path
    head_sha: str
    evidence: Path
    execution_cwd: Path


def _load_json(path: Path, label: str, errors: list[str]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{label} is not readable JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{label} must be a JSON object")
        return {}
    return value


def _frontmatter_value(path: Path, key: str) -> str | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end < 0:
        return None
    match = re.search(rf"(?m)^{re.escape(key)}:\s*['\"]?([^'\"\n]+)['\"]?\s*$", text[4:end])
    return match.group(1).strip() if match else None


def _deliverable_head(path: Path) -> str | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    frontmatter = text[4:end] if end >= 0 else ""
    match = re.search(r"(?m)^\s{2}head_sha:\s*([0-9a-f]{40})\s*$", frontmatter)
    return match.group(1) if match else None


def _git_tag_exists(repo: Path, tag: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}"],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def _find_source(design_plans_root: Path, source_id: str, archived: bool) -> Path | None:
    base = design_plans_root / "archive" if archived else design_plans_root
    matches = sorted(path for path in base.glob(f"{source_id}-*") if path.is_dir())
    return matches[0] if len(matches) == 1 else None


def _release_tags_by_owner(gap_ledger: dict[str, Any]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for gap in gap_ledger.get("gaps", []):
        if not isinstance(gap, dict):
            continue
        owner = gap.get("owner")
        source_id = owner.get("source_id") if isinstance(owner, dict) else None
        if source_id not in REQUIRED_FOREIGN_SOURCES:
            continue
        for evidence in gap.get("evidence", []):
            if not isinstance(evidence, dict) or evidence.get("kind") != "release":
                continue
            match = RELEASE_TAG_RE.search(str(evidence.get("uri", "")))
            if match:
                result.setdefault(source_id, set()).add(match.group(1))
    return result


def _normalized_command(value: str) -> str:
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    lines = [line.rstrip() for line in value.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def validate_archived_identity(*, repo: Path, task_md: Path, evidence: Path) -> list[str]:
    """Validate immutable evidence after its task worktree has been cleaned up."""
    errors: list[str] = []
    payload = _load_json(evidence, "archived evidence", errors)
    parser = repo / "scripts/parse-task-md.sh"
    result = subprocess.run(
        ["bash", str(parser), str(task_md), "--no-resolve", "--field", "verify_command"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        errors.append("archived task verify command is not parseable")
        return errors
    command_hash = hashlib.sha256(
        _normalized_command(result.stdout).encode("utf-8")
    ).hexdigest()
    identity = payload.get("evidence_identity")
    if payload.get("normalized_verify_command_hash") != command_hash:
        errors.append("archived evidence verify command hash drift")
    if not isinstance(identity, dict) or identity.get("normalized_verify_command_hash") != command_hash:
        errors.append("archived evidence identity command hash drift")
    if not isinstance(payload.get("execution_cwd"), str) or not Path(payload["execution_cwd"]).is_absolute():
        errors.append("archived evidence execution_cwd must remain an absolute recorded path")
    return errors


def validate(
    *,
    repo: Path,
    source_container: Path,
    evidence_root: Path,
    gap_ledger_path: Path,
    script_ledger_path: Path,
    current_work_item: str,
    max_age_hours: int,
    now: datetime | None = None,
) -> tuple[list[TaskRecord], list[str]]:
    errors: list[str] = []
    refinement = _load_json(source_container / "refinement.json", "refinement.json", errors)
    gap_ledger = _load_json(gap_ledger_path, "gap ledger", errors)
    _load_json(script_ledger_path, "script ledger", errors)
    source_id = str(refinement.get("source_id") or gap_ledger.get("source_id") or "DP-420")
    if source_id != "DP-420":
        errors.append(f"source identity must be DP-420, got {source_id}")

    design_plans_root = source_container.parent
    release_tags = _release_tags_by_owner(gap_ledger)
    for foreign_source in REQUIRED_FOREIGN_SOURCES:
        container = _find_source(design_plans_root, foreign_source, archived=True)
        if container is None:
            errors.append(f"{foreign_source} must resolve uniquely under archive/")
            continue
        if _frontmatter_value(container / "index.md", "status") != "IMPLEMENTED":
            errors.append(f"{foreign_source} archived source status must be IMPLEMENTED")
        tags = release_tags.get(foreign_source, set())
        if len(tags) != 1:
            errors.append(f"{foreign_source} must have exactly one release evidence tag in the gap ledger")
            continue
        tag = next(iter(tags))
        if not _git_tag_exists(repo, tag):
            errors.append(f"{foreign_source} release tag is not present in Git: {tag}")

    matrix = refinement.get("gap_owner_matrix")
    if not isinstance(matrix, list) or not matrix:
        errors.append("refinement gap_owner_matrix must be non-empty")
    else:
        observed_matrix: dict[str, tuple[str | None, str | None]] = {}
        for index, row in enumerate(matrix):
            if not isinstance(row, dict):
                errors.append(f"gap_owner_matrix[{index}] must be an object")
                continue
            family = row.get("family")
            if not isinstance(family, str) or not family:
                errors.append(f"gap_owner_matrix[{index}].family is required")
            elif family in observed_matrix:
                errors.append(f"owner collision: duplicate family {family}")
            else:
                observed_matrix[family] = (row.get("owner"), row.get("disposition"))
            owner = row.get("owner")
            disposition = row.get("disposition")
            if owner is None and disposition != "DP-427_ABANDONED":
                errors.append(f"gap_owner_matrix[{index}] has no implementation owner")
        missing_families = sorted(set(REQUIRED_OWNER_MATRIX) - set(observed_matrix))
        unexpected_families = sorted(set(observed_matrix) - set(REQUIRED_OWNER_MATRIX))
        if missing_families:
            errors.append(f"owner inventory is incomplete; missing families: {missing_families}")
        if unexpected_families:
            errors.append(f"owner inventory contains uncontracted families: {unexpected_families}")
        for family, expected in REQUIRED_OWNER_MATRIX.items():
            observed = observed_matrix.get(family)
            if observed is not None and observed != expected:
                errors.append(
                    f"owner inventory mismatch for {family}: expected {expected}, got {observed}"
                )

    planned_ids = {
        str(task.get("id"))
        for task in refinement.get("tasks", [])
        if isinstance(task, dict) and TASK_ID_RE.fullmatch(str(task.get("id", "")))
    }
    current_match = re.fullmatch(rf"{re.escape(source_id)}-(T[0-9]+)", current_work_item)
    if current_match is None:
        errors.append(
            f"current work item must be a canonical {source_id} task identity, got {current_work_item}"
        )
        current_id = current_work_item.rsplit("-", 1)[-1]
    else:
        current_id = current_match.group(1)
    if current_id not in planned_ids:
        errors.append(f"current work item {current_id} is not present in refinement.tasks")
    pr_release = source_container / "tasks" / "pr-release"
    actual_terminal = {
        path.parent.name for path in pr_release.glob("T*/index.md") if path.is_file()
    }
    active_tasks = sorted(
        path.parent.name
        for path in (source_container / "tasks").glob("T*/index.md")
        if path.is_file()
    )
    if active_tasks == [current_id] and current_id not in actual_terminal:
        expected_terminal = planned_ids - {current_id}
    elif active_tasks == [] and current_id in actual_terminal:
        expected_terminal = planned_ids
    else:
        expected_terminal = planned_ids - {current_id}
        errors.append(
            "current task lifecycle must be either sole active task or finalized under "
            f"pr-release; current={current_id}, active={active_tasks}, "
            f"terminal={current_id in actual_terminal}"
        )
    missing = sorted(expected_terminal - actual_terminal)
    unexpected = sorted(actual_terminal - expected_terminal)
    if missing:
        errors.append(f"planned tasks are not terminal under pr-release: {missing}")
    if unexpected:
        errors.append(f"unplanned terminal task entries exist: {unexpected}")
    records: list[TaskRecord] = []
    current_time = now or datetime.now(timezone.utc)
    max_age = timedelta(hours=max_age_hours)
    for task_id in sorted(actual_terminal, key=lambda value: int(value[1:])):
        task_md = pr_release / task_id / "index.md"
        if _frontmatter_value(task_md, "status") != "IMPLEMENTED":
            errors.append(f"{task_id} status must be IMPLEMENTED")
            continue
        head_sha = _deliverable_head(task_md)
        if head_sha is None or not FULL_SHA_RE.fullmatch(head_sha):
            errors.append(f"{task_id} deliverable.head_sha is missing or invalid")
            continue
        work_item_id = f"DP-420-{task_id}"
        evidence = evidence_root / "verify" / f"polaris-verified-{work_item_id}-{head_sha}.json"
        payload = _load_json(evidence, f"{work_item_id} evidence", errors)
        identity = payload.get("evidence_identity")
        required_identity = (
            payload.get("head_sha"),
            payload.get("normalized_verify_command_hash"),
            payload.get("verification_context_hash"),
        )
        if not isinstance(identity, dict) or tuple(identity.get(key) for key in (
            "head_sha", "normalized_verify_command_hash", "verification_context_hash"
        )) != required_identity or any(not isinstance(value, str) or not value for value in required_identity):
            errors.append(f"{work_item_id} evidence does not contain one exact three-field identity tuple")
            continue
        at_value = payload.get("at")
        try:
            observed_at = datetime.fromisoformat(str(at_value).replace("Z", "+00:00"))
        except ValueError:
            errors.append(f"{work_item_id} evidence timestamp is invalid")
            continue
        if current_time - observed_at > max_age:
            errors.append(f"{work_item_id} evidence is older than {max_age_hours} hours")
        execution_cwd = Path(str(payload.get("execution_cwd", "")))
        if not execution_cwd.is_absolute():
            errors.append(f"{work_item_id} evidence execution_cwd is not absolute: {execution_cwd}")
            continue
        records.append(TaskRecord(work_item_id, task_md, head_sha, evidence, execution_cwd))
    return records, errors


def main(argv: list[str] | None = None) -> int:
    effective_argv = list(sys.argv[1:] if argv is None else argv)
    if effective_argv and effective_argv[0] == "--validate-archived-identity":
        archived_parser = argparse.ArgumentParser(allow_abbrev=False)
        archived_parser.add_argument("--validate-archived-identity", action="store_true")
        archived_parser.add_argument("--repo", required=True, type=Path)
        archived_parser.add_argument("--task-md", required=True, type=Path)
        archived_parser.add_argument("--evidence", required=True, type=Path)
        archived_args = archived_parser.parse_args(effective_argv)
        archived_errors = validate_archived_identity(
            repo=archived_args.repo.resolve(),
            task_md=archived_args.task_md.resolve(),
            evidence=archived_args.evidence.resolve(),
        )
        for error in archived_errors:
            print(f"POLARIS_DP420_CERTIFICATION: {error}", file=sys.stderr)
        return 2 if archived_errors else 0
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--source-container", required=True, type=Path)
    parser.add_argument("--evidence-root", required=True, type=Path)
    parser.add_argument("--gap-ledger", required=True, type=Path)
    parser.add_argument("--script-ledger", required=True, type=Path)
    parser.add_argument("--current-work-item", default="DP-420-T14")
    parser.add_argument("--max-age-hours", type=int, default=48)
    parser.add_argument("--records", action="store_true")
    args = parser.parse_args(effective_argv)
    records, errors = validate(
        repo=args.repo.resolve(),
        source_container=args.source_container.resolve(),
        evidence_root=args.evidence_root.resolve(),
        gap_ledger_path=args.gap_ledger.resolve(),
        script_ledger_path=args.script_ledger.resolve(),
        current_work_item=args.current_work_item,
        max_age_hours=args.max_age_hours,
    )
    if errors:
        for error in errors:
            print(f"POLARIS_DP420_CERTIFICATION: {error}", file=sys.stderr)
        return 2
    if args.records:
        for record in records:
            print("\t".join(map(str, (
                record.work_item_id,
                record.task_md,
                record.head_sha,
                record.evidence,
                record.execution_cwd,
            ))))
    else:
        print(f"PASS: DP-420 source certification inputs ({len(records)} terminal tasks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
