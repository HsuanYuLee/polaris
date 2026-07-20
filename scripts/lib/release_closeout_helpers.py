"""Structured helpers for release and closeout shell orchestration.

The public CLIs remain shell-owned because they coordinate git, gh and other
commands.  This module owns JSON/frontmatter parsing, report rendering and
bounded artifact rewrites so those operations are independently testable.
"""

from __future__ import annotations

import fnmatch
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit


def print_scalar(value: object) -> None:
    if value is None:
        print("")
    elif isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, list):
        for item in value:
            print(item)
    else:
        print(value)


def json_field(args: list[str]) -> int:
    data = json.loads(args[0])
    expression = args[1]
    if expression.startswith("d.get("):
        value = eval(expression, {"__builtins__": {}}, {"d": data})
    else:
        value = data.get(expression)
    print_scalar(value)
    return 0


def emit_result(args: list[str]) -> int:
    source_id, surface_class, required, status, reason = args
    payload = {
        "source_id": source_id,
        "surface_class": surface_class,
        "release_required": required == "true",
        "status": status,
        "blocking_reason": None if reason == "pass" else reason,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def frontmatter_status(path: Path) -> str:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---\n", 4)
    if end == -1:
        return ""
    for line in text[4:end].splitlines():
        if line.startswith("status:"):
            return line.split(":", 1)[1].strip()
    return ""


def ac_status(path: Path) -> str:
    in_block = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "ac_verification:":
            in_block = True
            continue
        if in_block and line and not line.startswith((" ", "-")) and ":" in line:
            break
        if in_block:
            match = re.match(r"\s+status:\s*(\S+)", line)
            if match:
                return match.group(1)
    return ""


def parent_verification_invalid(args: list[str]) -> int:
    task = Path(args[0]).resolve()
    parts = task.parts
    if "tasks" not in parts:
        return 0
    index = len(parts) - 1 - list(reversed(parts)).index("tasks")
    tasks_dir = Path(*parts[: index + 1])
    parent_dir = tasks_dir.parent
    parent = next(
        (
            parent_dir / name
            for name in ("index.md", "plan.md", "refinement.md")
            if (parent_dir / name).exists()
        ),
        None,
    )
    if parent is None or frontmatter_status(parent) != "IMPLEMENTED":
        return 0
    invalid = False
    for path in tasks_dir.rglob("*"):
        if not path.is_file():
            continue
        if not (
            re.fullmatch(r"V\d+[a-z]*\.md", path.name)
            or (
                path.name == "index.md"
                and re.fullmatch(r"V\d+[a-z]*", path.parent.name)
            )
        ):
            continue
        if "/tasks/pr-release/" not in str(path):
            invalid = True
        elif frontmatter_status(path) != "IMPLEMENTED" or ac_status(path) != "PASS":
            invalid = True
    return 1 if invalid else 0


def render_closeout_drift(args: list[str]) -> int:
    tsv, gh_ok, stranded_days = Path(args[0]), args[1] == "1", int(args[2])
    results = []
    for line in tsv.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        fields = line.split("\t")
        (
            dp,
            classification,
            action,
            covered,
            total,
            changelog_hit,
            pr_merged,
            pr_open,
            pr_unchecked,
            verification_pending,
            container,
        ) = fields
        unchecked = pr_unchecked == "1"
        results.append(
            {
                "dp": dp,
                "container": container,
                "classification": classification,
                "action": action,
                "pr_evidence_unchecked": unchecked,
                "evidence": {
                    "completion_gate_markers": {
                        "covered": int(covered),
                        "total": int(total),
                    },
                    "changelog": changelog_hit == "1",
                    "merged_pr": "unchecked"
                    if unchecked
                    else ("merged" if pr_merged == "1" else "none"),
                    "in_flight_open_pr": pr_open == "1",
                    "verification_pending": verification_pending == "1",
                },
            }
        )
    report = {
        "schema_version": 1,
        "report_kind": "closeout_drift",
        "gh_available": gh_ok,
        "stranded_threshold_days": stranded_days,
        "results": results,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


def resolve_current_task(args: list[str]) -> int:
    path = Path(args[0])
    parts = list(path.parts)
    try:
        index = parts.index("design-plans")
    except ValueError:
        print(path)
        return 0
    if index + 1 < len(parts) and parts[index + 1] != "archive":
        print(Path(*parts[: index + 1], "archive", *parts[index + 1 :]))
    else:
        print(path)
    return 0


def source_container(args: list[str]) -> int:
    path = Path(args[0]).resolve()
    if "tasks" not in path.parts:
        print("")
        return 0
    index = len(path.parts) - 1 - list(reversed(path.parts)).index("tasks")
    print(Path(*path.parts[:index]).as_posix())
    return 0


def parent_file(args: list[str]) -> int:
    path = Path(args[0]).resolve()
    if "tasks" not in path.parts:
        print("")
        return 0
    index = len(path.parts) - 1 - list(reversed(path.parts)).index("tasks")
    parent = Path(*path.parts[:index])
    for name in ("index.md", "refinement.md", "plan.md"):
        candidate = parent / name
        if candidate.exists():
            print(candidate)
            return 0
    print("")
    return 0


def update_status(args: list[str]) -> int:
    path, new_status = Path(args[0]), args[1]
    content = path.read_text(encoding="utf-8")
    lines = content.split("\n")
    if lines and lines[0] == "---":
        try:
            close_index = lines.index("---", 1)
        except ValueError:
            print(f"ERROR: unclosed frontmatter in {path}", file=sys.stderr)
            return 1
        frontmatter = lines[1:close_index]
        for index, line in enumerate(frontmatter):
            if re.match(r"^status:\s*", line):
                frontmatter[index] = f"status: {new_status}"
                break
        else:
            frontmatter.append(f"status: {new_status}")
        output = (
            "---\n"
            + "\n".join(frontmatter)
            + "\n---\n"
            + "\n".join(lines[close_index + 1 :])
        )
    else:
        output = f"---\nstatus: {new_status}\n---\n\n" + content
    path.write_text(output, encoding="utf-8")
    return 0


def ac_verification_fields(args: list[str]) -> int:
    status = ""
    disposition = ""
    try:
        text = Path(args[0]).read_text(encoding="utf-8")
    except OSError:
        text = ""
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        if end != -1:
            in_block = False
            for line in text[4:end].splitlines():
                if line == "ac_verification:":
                    in_block = True
                    continue
                if in_block and line and not line.startswith((" ", "-")):
                    break
                if in_block:
                    match = re.match(r"\s+status:\s*(\S+)", line)
                    if match and not status:
                        status = match.group(1)
                    match = re.match(r"\s+human_disposition:\s*(\S+)", line)
                    if match and not disposition:
                        disposition = match.group(1)
    print(f"{status}\t{disposition}")
    return 0


def attach_preflight(args: list[str]) -> int:
    path, evidence = Path(args[0]), args[1]
    content = path.read_text(encoding="utf-8")
    block = f"release_preflight:\n  evidence: {evidence}\n"
    match = re.match(r"^---\n(.*?)^---\n", content, flags=re.DOTALL | re.MULTILINE)
    if not match:
        output = "---\n" + block + "---\n" + content
    else:
        frontmatter = re.sub(
            r"^release_preflight:(?:\n(?:[ \t]+[^\n]*))*\n?",
            "",
            match.group(1),
            flags=re.MULTILINE,
        )
        if frontmatter and not frontmatter.endswith("\n"):
            frontmatter += "\n"
        output = "---\n" + frontmatter + block + "---\n" + content[match.end() :]
    path.write_text(output, encoding="utf-8")
    return 0


def parse_pr_url(args: list[str]) -> int:
    match = re.match(
        r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$",
        args[0].strip(),
    )
    if not match:
        return 1
    owner, repo, number = match.groups()
    print(f"{owner}/{repo}\t{number}")
    return 0


def repo_slug(args: list[str]) -> int:
    value = args[0].strip()
    match = re.search(r"github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$", value)
    print(f"{match.group(1)}/{match.group(2)}" if match else "")
    return 0


def validate_pr_evidence(args: list[str]) -> int:
    path, task_id, head_sha, pr_url, pr_number = args
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    assert data.get("writer") == "polaris-pr-create.sh", data
    assert data.get("task_id") == task_id, data
    assert str(data.get("head_sha")) == head_sha, data
    assert data.get("pr_url") == pr_url, data
    assert str(data.get("pr_number")) == str(pr_number), data
    assert data.get("task_artifact_sha256"), data
    assert data.get("gate_summary"), data
    return 0


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}
    result: dict[str, str] = {}
    current = None
    for raw in text[4:end].splitlines():
        if not raw.startswith(" ") and ":" in raw:
            key, value = raw.split(":", 1)
            current = key.strip()
            result[current] = value.strip()
            continue
        if current == "ac_verification":
            stripped = raw.strip()
            if ":" in stripped:
                key, value = stripped.split(":", 1)
                result[f"ac_verification.{key.strip()}"] = (
                    value.strip().strip('"').strip("'")
                )
    return result


def verify_ac_release_eligible(args: list[str]) -> int:
    source = Path(args[0])
    tasks_dir = source / "tasks"
    paths: list[Path] = []
    if tasks_dir.exists():
        paths.extend(sorted(tasks_dir.glob("V*.md")))
        paths.extend(sorted(tasks_dir.glob("V*/index.md")))
        release_dir = tasks_dir / "pr-release"
        if release_dir.exists():
            paths.extend(sorted(release_dir.glob("V*.md")))
            paths.extend(sorted(release_dir.glob("V*/index.md")))
    if not paths:
        print("no V verification task found", file=sys.stderr)
        return 1
    eligible = False
    errors = []
    for path in paths:
        frontmatter = parse_frontmatter(path)
        status = frontmatter.get("ac_verification.status", "")
        disposition = frontmatter.get("ac_verification.human_disposition", "")
        summary = frontmatter.get("ac_verification.summary", "")
        if not status:
            errors.append(f"{path}: missing ac_verification")
        elif status == "PASS" and disposition == "passed":
            eligible = True
        elif status == "MANUAL_REQUIRED" and disposition == "passed" and summary:
            eligible = True
        elif status in {"FAIL", "UNCERTAIN", "BLOCKED_ENV", "IN_PROGRESS"}:
            errors.append(f"{path}: status {status} blocks release")
        else:
            errors.append(
                f"{path}: status={status or '<empty>'} human_disposition={disposition or '<empty>'} is not release-eligible"
            )
    if not eligible:
        print("; ".join(errors), file=sys.stderr)
        return 1
    return 0


def write_preflight(args: list[str]) -> int:
    path, task_id, head_sha, pr_url, pr_evidence, task_md = args
    payload = {
        "schema_version": 1,
        "writer": "framework-release-preflight.sh",
        "written_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "task_id": task_id,
        "head_sha": head_sha,
        "pr_url": pr_url,
        "task_md": task_md,
        "pr_create_evidence": pr_evidence,
        "verify_ac": "release_eligible",
        "clean_worktree": True,
    }
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(target)
    print(target)
    return 0


def match_parts(
    file_parts: list[str], file_index: int, pattern_parts: list[str], pattern_index: int
) -> bool:
    if file_index == len(file_parts) and pattern_index == len(pattern_parts):
        return True
    if pattern_index == len(pattern_parts):
        return False
    if file_index == len(file_parts):
        return all(part == "**" for part in pattern_parts[pattern_index:])
    segment = pattern_parts[pattern_index]
    if segment == "**":
        return match_parts(
            file_parts, file_index, pattern_parts, pattern_index + 1
        ) or match_parts(file_parts, file_index + 1, pattern_parts, pattern_index)
    return fnmatch.fnmatchcase(file_parts[file_index], segment) and match_parts(
        file_parts, file_index + 1, pattern_parts, pattern_index + 1
    )


def release_diff_intersection(args: list[str]) -> int:
    _task_md, release_commit, repo_root, parser_json = args
    data = json.loads(parser_json)
    patterns = []
    for entry in data.get("allowed_files") or []:
        value = entry.strip()
        if value.startswith("`") and value.endswith("`"):
            value = value[1:-1]
        if value:
            patterns.append(value)
    parent = subprocess.run(
        [
            "git",
            "-C",
            repo_root,
            "rev-parse",
            "--verify",
            "--quiet",
            release_commit + "^",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    command = (
        [
            "git",
            "-C",
            repo_root,
            "diff",
            "--name-only",
            release_commit + "^",
            release_commit,
        ]
        if parent.returncode == 0
        else ["git", "-C", repo_root, "ls-tree", "-r", "--name-only", release_commit]
    )
    process = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    count = 0
    for file_path in (
        line.strip() for line in process.stdout.splitlines() if line.strip()
    ):
        if any(
            file_path == pattern
            or match_parts(file_path.split("/"), 0, pattern.split("/"), 0)
            for pattern in patterns
        ):
            count += 1
    print(count)
    return 0


def task_frontmatter_field(args: list[str]) -> int:
    path, field = Path(args[0]), args[1]
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        print("")
        return 0
    try:
        end = lines[1:].index("---") + 1
    except ValueError:
        print("")
        return 0
    in_deliverable = False
    in_verification = False
    for raw in lines[1:end]:
        if raw == "deliverable:":
            in_deliverable = True
            in_verification = False
            continue
        if in_deliverable and raw and not raw.startswith((" ", "-")):
            in_deliverable = False
            in_verification = False
        if not in_deliverable:
            continue
        stripped = raw.strip()
        if stripped == "verification:":
            in_verification = True
            continue
        if in_verification and raw.startswith("  ") and not raw.startswith("    "):
            in_verification = False
        if (
            field == "deliverable_verification_status"
            and in_verification
            and raw.startswith("    status:")
        ):
            print(raw.split(":", 1)[1].strip())
            return 0
        if in_verification:
            continue
        key = {
            "deliverable_pr_url": "pr_url",
            "deliverable_pr_state": "pr_state",
            "deliverable_head_sha": "head_sha",
        }.get(field)
        if key and raw.startswith(f"  {key}:"):
            print(raw.split(":", 1)[1].strip())
            return 0
    print("")
    return 0


def package_field(args: list[str]) -> int:
    data = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    print(data[args[1]])
    return 0


def github_repo_from_remote(remote_url: str) -> str | None:
    """Return owner/repo for a github.com remote in common Git URL forms."""
    scp_match = re.fullmatch(r"git@github\.com:([^/]+)/(.+)", remote_url)
    if scp_match:
        owner, repo = scp_match.groups()
    else:
        parsed = urlsplit(remote_url)
        if (parsed.hostname or "").lower() != "github.com":
            return None
        parts = parsed.path.strip("/").split("/")
        if len(parts) != 2:
            return None
        owner, repo = parts
    if repo.endswith(".git"):
        repo = repo[:-4]
    if not owner or not repo or "/" in repo:
        return None
    return f"{owner}/{repo}"


def github_remote_repos(args: list[str]) -> int:
    repo_root = args[0]
    result = subprocess.run(
        ["git", "-C", repo_root, "remote", "-v"],
        check=False,
        capture_output=True,
        text=True,
    )
    repos = {
        repo
        for line in result.stdout.splitlines()
        if len(line.split()) >= 2
        for repo in [github_repo_from_remote(line.split()[1])]
        if repo is not None
    }
    for repo in sorted(repos):
        print(repo)
    return 0


def validate_changeset_packages(args: list[str]) -> int:
    changeset_dir, expected = Path(args[0]), args[1]
    mismatches = []
    if changeset_dir.exists():
        for path in sorted(changeset_dir.glob("*.md")):
            if path.name == "README.md":
                continue
            text = path.read_text(encoding="utf-8")
            if not text.startswith("---"):
                continue
            parts = text.split("---", 2)
            if len(parts) < 3:
                continue
            for line in parts[1].splitlines():
                match = re.match(
                    r"""\s*["']?([^"':]+)["']?\s*:\s*(major|minor|patch)\s*(?:#.*)?$""",
                    line,
                )
                if match and match.group(1).strip() != expected:
                    mismatches.append((path.name, match.group(1).strip()))
    if mismatches:
        print(
            "POLARIS_RELEASE_VERSION_CHANGESET_PACKAGE_MISMATCH: pending changeset package key does not match package.json name.",
            file=sys.stderr,
        )
        print(f"  expected: {expected}", file=sys.stderr)
        for filename, package in mismatches:
            print(f"  - {filename}: {package}", file=sys.stderr)
        return 1
    return 0


def collate_changelog(args: list[str]) -> int:
    path, version, release_date = Path(args[0]), args[1], args[2]
    section_order = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]
    lines = path.read_text(encoding="utf-8").split("\n")
    heading = re.compile(r"^## (?:\[)?" + re.escape(version) + r"(?:\])?(?:\s|$)")
    start = next(
        (index for index, line in enumerate(lines) if heading.match(line)), None
    )
    if start is None:
        print(
            f"POLARIS_RELEASE_VERSION_COLLATE_BLOCK_MISSING: no '## {version}' heading to collate",
            file=sys.stderr,
        )
        return 1
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].startswith("## ")
        ),
        len(lines),
    )
    buckets: dict[str, list[str]] = {name: [] for name in section_order}
    tag = re.compile(r"^- \[([A-Za-z]+)\]\s?(.*)$")
    count = 0
    current = None
    for raw in lines[start + 1 : end]:
        match = tag.match(raw)
        if match:
            section = match.group(1).capitalize()
            if section not in buckets:
                section = "Changed"
            current = section
            buckets[section].append("- " + match.group(2).rstrip())
            count += 1
        elif current is not None and (raw.startswith("  ") or not raw.strip()):
            if raw.strip():
                buckets[current].append(raw.rstrip())
            else:
                current = None
    if count == 0:
        return 0
    sections = [name for name in section_order if buckets[name]]
    if not sections:
        print(
            f"POLARIS_RELEASE_VERSION_COLLATE_EMPTY: {count} tagged line(s) in '## {version}' collated to zero Keep a Changelog sections",
            file=sys.stderr,
        )
        return 1
    block = [f"## [{version}] - {release_date}", ""]
    for section in sections:
        block.extend([f"### {section}", "", *buckets[section], ""])
    path.write_text("\n".join(lines[:start] + block + lines[end:]), encoding="utf-8")
    return 0


def resolve_surface(args: list[str]) -> int:
    fmt, field, task_json = args
    data = json.loads(task_json)
    frontmatter = data.get("frontmatter") or {}
    deliverable = frontmatter.get("deliverable")
    deliverable = deliverable if isinstance(deliverable, dict) else None
    deliverables = frontmatter.get("deliverables")
    deliverables = deliverables if isinstance(deliverables, dict) else {}
    changeset = deliverables.get("changeset")
    changeset = changeset if isinstance(changeset, dict) else None
    extension = frontmatter.get("extension_deliverable")
    extension = extension if isinstance(extension, dict) else None
    signals = []
    ambiguity = []
    if extension is not None:
        if extension.get("endpoint") == "local_extension":
            signals.append("local_extension")
        else:
            ambiguity.append("extension_deliverable_without_local_extension_endpoint")
    if changeset is not None and any(
        changeset.get(key) not in (None, "")
        for key in ("package_scope", "bump_level_default", "filename_slug")
    ):
        signals.append("package_release")
    if deliverable is not None:
        if deliverable.get("pr_url"):
            signals.append("developer_pr")
        else:
            ambiguity.append("deliverable_without_pr_url")
    if ambiguity:
        klass = "ambiguous"
    elif "local_extension" in signals:
        klass = "local_extension"
    elif "package_release" in signals:
        klass = "package_release"
    elif "developer_pr" in signals:
        klass = "developer_pr"
    else:
        klass = "none"
    payload = {
        "class": klass,
        "release_required": klass != "none",
        "surface_signals": signals,
        "ambiguity_reasons": ambiguity,
    }
    if fmt == "json":
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif fmt == "field":
        print_scalar(payload[field])
    else:
        print(
            f"SURFACE class={klass} release_required={'true' if payload['release_required'] else 'false'}"
        )
    return 0


COMMANDS = {
    "json-field": json_field,
    "emit-result": emit_result,
    "parent-verification-invalid": parent_verification_invalid,
    "render-closeout-drift": render_closeout_drift,
    "resolve-current-task": resolve_current_task,
    "source-container": source_container,
    "parent-file": parent_file,
    "update-status": update_status,
    "ac-verification-fields": ac_verification_fields,
    "attach-preflight": attach_preflight,
    "parse-pr-url": parse_pr_url,
    "repo-slug": repo_slug,
    "validate-pr-evidence": validate_pr_evidence,
    "verify-ac-release-eligible": verify_ac_release_eligible,
    "write-preflight": write_preflight,
    "release-diff-intersection": release_diff_intersection,
    "task-frontmatter-field": task_frontmatter_field,
    "package-field": package_field,
    "github-remote-repos": github_remote_repos,
    "validate-changeset-packages": validate_changeset_packages,
    "collate-changelog": collate_changelog,
    "resolve-surface": resolve_surface,
}


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in COMMANDS:
        print("usage: release_closeout_helpers.py <command> [args...]", file=sys.stderr)
        return 2
    return COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
