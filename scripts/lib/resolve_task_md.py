"""Resolve one canonical task.md from a path, source identity, JIRA key, PR, or branch."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = SCRIPT_DIR.parent
PARSE_TASK_MD = SCRIPT_DIR / "parse-task-md.sh"
BY_BRANCH = SCRIPT_DIR / "resolve-task-md-by-branch.sh"


class ResolverError(Exception):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def usage() -> int:
    print(
        "usage: resolve-task-md.sh <path|jira-key|pr-url|pr-number>\n"
        "       resolve-task-md.sh --current\n"
        "       resolve-task-md.sh --specs-source <path> <path|jira-key|pr-url|pr-number>\n"
        "       resolve-task-md.sh --include-archive <path|jira-key|pr-url|pr-number>\n"
        "       resolve-task-md.sh --clear-lock\n"
        "       resolve-task-md.sh --write-lock <path|jira-key|pr-url|pr-number>\n"
        "       resolve-task-md.sh --write-lock --current\n"
        "       resolve-task-md.sh --write-lock --from-input \"<raw user message>\"\n"
        "       resolve-task-md.sh --from-input \"<raw user message>\"\n"
        "       resolve-task-md.sh --scan-root <path> <path|jira-key|pr-url|pr-number>\n"
        "       resolve-task-md.sh --scan-root <path> --current\n"
        "       resolve-task-md.sh --scan-root <path> --from-input \"<raw user message>\"\n\n"
        "stdout: absolute path to exactly one task.md\n"
        "exit: 0 = resolved\n"
        "      1 = not found / ambiguous / dependency missing\n"
        "      2 = usage error",
        file=sys.stderr,
    )
    return 2


def absolute(path: str | Path) -> Path:
    return Path(os.path.abspath(os.fspath(Path(path).expanduser())))


def git_output(*args: str, cwd: Path | None = None) -> str:
    command = ["git"]
    if cwd:
        command.extend(["-C", str(cwd)])
    command.extend(args)
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def main_checkout(start: Path) -> Path | None:
    common = git_output("rev-parse", "--git-common-dir", cwd=start)
    if not common:
        return None
    common_path = Path(common)
    if not common_path.is_absolute():
        common_path = (start / common_path).resolve()
    return common_path.parent if common_path.is_dir() else None


def highest_workspace_config(start: Path) -> Path | None:
    override = os.environ.get("POLARIS_WORKSPACE_CONFIG_ROOT", "")
    if override:
        candidate = absolute(override)
        if candidate.is_file() and candidate.name == "workspace-config.yaml":
            candidate = candidate.parent
        return candidate if (candidate / "workspace-config.yaml").is_file() else None
    candidate = start if start.is_dir() else start.parent
    matches = [parent for parent in [candidate, *candidate.parents] if (parent / "workspace-config.yaml").is_file()]
    return matches[-1] if matches else None


def detect_root(explicit: str) -> Path:
    if explicit:
        root = absolute(explicit)
        if not root.is_dir():
            raise ResolverError(f"error: --scan-root not a directory: {explicit}", 2)
        return root
    cwd = Path.cwd().resolve()
    configured = highest_workspace_config(cwd)
    if configured:
        return configured
    git_root = git_output("rev-parse", "--show-toplevel", cwd=cwd)
    if git_root:
        return absolute(git_root)
    raise ResolverError("error: could not locate workspace root")


def require_specs(path: Path, label: str) -> Path:
    if path.is_symlink():
        raise ResolverError(f"resolve-specs-root: symlink primary path is not allowed for {label}: {path}")
    if not path.is_dir():
        raise ResolverError(
            f"resolve-specs-root: missing {label}: {path}; pass --specs-source or run from the main checkout with canonical specs available"
        )
    return absolute(path)


def resolve_specs_root(root: Path, explicit: str = "") -> Path:
    configured = explicit or os.environ.get("POLARIS_SPECS_ROOT", "")
    if configured:
        return require_specs(absolute(configured), "explicit specs source")
    local = root / "docs-manager/src/content/docs/specs"
    if local.is_symlink():
        raise ResolverError(f"resolve-specs-root: symlink primary path is not allowed for workspace specs root: {local}")
    if local.is_dir():
        return absolute(local)
    overlay = main_checkout(root)
    if overlay and overlay != root:
        candidate = overlay / "docs-manager/src/content/docs/specs"
        if candidate.is_symlink():
            raise ResolverError(f"resolve-specs-root: symlink primary path is not allowed for workspace overlay specs root: {candidate}")
        if candidate.is_dir():
            return absolute(candidate)
    return require_specs(local, "workspace specs root")


def canonical_task(path: Path) -> bool:
    parts = path.parts
    if "specs" not in parts or "tasks" not in parts:
        return False
    if path.name == "index.md":
        return bool(re.fullmatch(r"[TV][0-9]+[a-z]*", path.parent.name))
    return bool(re.fullmatch(r"[TV][0-9]+[a-z]*\.md", path.name))


def task_name(path: Path) -> str:
    return path.parent.name if path.name == "index.md" else path.stem


def task_files(specs: Path, include_archive: bool, t_only: bool = False) -> list[Path]:
    result: list[Path] = []
    for path in specs.rglob("*.md"):
        parts = path.parts
        if any(part in {".git", ".worktrees", "node_modules"} for part in parts):
            continue
        if not include_archive and "archive" in parts:
            continue
        if not canonical_task(path):
            continue
        if t_only and not task_name(path).startswith("T"):
            continue
        result.append(absolute(path))
    return sorted(set(result))


def unique(label: str, matches: list[Path]) -> Path:
    matches = sorted(set(absolute(path) for path in matches))
    if not matches:
        raise ResolverError("")
    if len(matches) > 1:
        detail = "\n".join(f"  {path}" for path in matches)
        raise ResolverError(f"error: {label} resolved to multiple work orders:\n{detail}")
    return matches[0]


def direct_path(value: str) -> Path | None:
    path = absolute(value)
    return path if path.is_file() and canonical_task(path) else None


def resolve_source_task(specs: Path, source_task: str, include_archive: bool, dp_only: bool = False) -> Path:
    match = re.fullmatch(r"([A-Z][A-Z0-9]*-[0-9]+)-([TV][0-9]+[a-z]*)", source_task)
    if not match:
        raise ResolverError("")
    source_id, wanted_task = match.groups()
    matches: list[Path] = []
    for path in task_files(specs, include_archive):
        if task_name(path) != wanted_task:
            continue
        ancestors = {parent.name for parent in path.parents}
        if source_id not in ancestors and not any(name.startswith(source_id + "-") for name in ancestors):
            continue
        if dp_only and "design-plans" not in path.parts:
            continue
        matches.append(path)
    label = f"DP task {source_task}" if dp_only else f"JIRA Epic task {source_task}"
    try:
        return unique(label, matches)
    except ResolverError as error:
        if str(error):
            raise
        kind = "DP task.md" if dp_only else "JIRA Epic task.md"
        raise ResolverError(f"error: no {kind} found for {source_task}") from None


def parsed_jira(path: Path) -> str:
    if PARSE_TASK_MD.is_file():
        result = subprocess.run(
            ["bash", str(PARSE_TASK_MD), str(path), "--no-resolve", "--field", "jira_key"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"^>.*\bJIRA:\s*([A-Z][A-Z0-9]+-[0-9]+)\b", text, re.MULTILINE)
    return match.group(1) if match else ""


def resolve_jira(specs: Path, jira: str, include_archive: bool) -> Path:
    matches = [path for path in task_files(specs, include_archive, t_only=True) if parsed_jira(path) == jira]
    try:
        return unique(f"JIRA {jira}", matches)
    except ResolverError as error:
        if str(error):
            raise
        raise ResolverError(f"error: no task.md found for JIRA {jira}") from None


def resolve_series(specs: Path, epic: str, series: str, ordinal: str, include_archive: bool) -> Path:
    candidates = [
        path
        for path in task_files(specs, include_archive, t_only=True)
        if task_name(path).lower().startswith(series.lower()) and epic in {parent.name for parent in path.parents}
    ]
    if not candidates:
        raise ResolverError(f"error: no {series} series task.md found for {epic}")

    def sort_key(path: Path) -> tuple[int, int, str, str]:
        match = re.fullmatch(r"T([0-9]+)([a-z]*)", task_name(path), re.IGNORECASE)
        canonical = 0 if "companies" in path.parts else 1
        return (canonical, int(match.group(1)) if match else 999999, match.group(2).lower() if match else "zzzz", str(path))

    candidates.sort(key=sort_key)
    normalized = ordinal.strip().lower()
    if normalized in {"first", "1", "1st", "one", "第一", "第1", "首張", "第一張"}:
        return candidates[0]
    if normalized in {"second", "2", "2nd", "two", "第二", "第2", "第二張"}:
        if len(candidates) < 2:
            raise ResolverError(f"error: ordinal {ordinal or '<none>'} is out of range for {epic} {series} series")
        return candidates[1]
    if len(candidates) == 1:
        return candidates[0]
    detail = "\n".join(f"  {path}" for path in candidates)
    raise ResolverError(
        f"error: {epic} {series} series resolved to multiple work orders; provide an ordinal or exact task id:\n{detail}"
    )


def resolve_branch(root: Path, branch: str) -> Path:
    if not BY_BRANCH.is_file():
        raise ResolverError(f"error: missing dependency: {BY_BRANCH}")
    result = subprocess.run(
        ["bash", str(BY_BRANCH), "--scan-root", str(root), branch],
        capture_output=True,
        text=True,
        check=False,
    )
    line = next((line for line in result.stdout.splitlines() if line.strip()), "")
    if result.returncode or not line:
        raise ResolverError(result.stderr.strip() or f"error: branch did not resolve to a work order: {branch}")
    return absolute(line)


def resolve_pr(root: Path, reference: str) -> Path:
    if shutil.which("gh") is None:
        raise ResolverError(f"error: gh is required to resolve PR input: {reference}")
    result = subprocess.run(
        ["gh", "pr", "view", reference, "--json", "headRefName", "--jq", ".headRefName"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    branch = result.stdout.strip()
    if result.returncode or not branch or branch == "null":
        raise ResolverError(f"error: failed to resolve PR head branch from: {reference}")
    return resolve_branch(root, branch)


def resolve_input(root: Path, specs: Path, raw: str, include_archive: bool) -> Path:
    if not raw.strip():
        raise ResolverError("error: --from-input requires non-empty text", 2)
    direct = direct_path(raw)
    if direct:
        return direct
    if not re.search(r"\b[A-Z][A-Z0-9]+-\d+-[TV]\d+[a-z]*\b", raw, re.IGNORECASE):
        epic = re.search(r"\b([A-Z][A-Z0-9]+-\d+)\b", raw)
        series = re.search(r"\b(T\d+)\s*(?:系列|series)?\b", raw, re.IGNORECASE)
        if epic and series:
            lower = raw.lower()
            ordinal = "first" if re.search(r"(第一張|第一|第\s*1|首張|\bfirst\b|\b1st\b)", lower) else ""
            if re.search(r"(第二張|第二|第\s*2|\bsecond\b|\b2nd\b)", lower):
                ordinal = "second"
            return resolve_series(specs, epic.group(1), series.group(1).upper(), ordinal, include_archive)
    patterns = [
        ("source_task", r"\b([A-Z][A-Z0-9]*-\d+-[TV]\d+[a-z]*)\b"),
        ("path", r"((?:\.\.?/|~/|/)?[^\s'\"]+\.md)\b"),
        ("pr_url", r"(https?://github\.com/[^/\s]+/[^/\s]+/pull/\d+)"),
        ("jira", r"\b([A-Z][A-Z0-9]+-\d+)\b"),
    ]
    for kind, pattern in patterns:
        match = re.search(pattern, raw)
        if not match:
            continue
        value = match.group(1)
        if kind == "source_task":
            return resolve_source_task(specs, value, include_archive, dp_only=value.startswith("DP-"))
        if kind == "path":
            candidate = absolute(value)
            if candidate.is_file():
                return candidate
            git_root = git_output("rev-parse", "--show-toplevel", cwd=Path.cwd())
            candidate = absolute(Path(git_root or Path.cwd()) / value)
            if candidate.is_file():
                return candidate
            raise ResolverError(f"error: markdown path mentioned in input does not exist: {value}")
        if kind == "pr_url":
            return resolve_pr(root, value)
        return resolve_jira(specs, value, include_archive)
    number = re.fullmatch(r"\s*#?([0-9]+)\s*", raw)
    if number:
        return resolve_pr(root, number.group(1))
    raise ResolverError("error: could not resolve work order from raw input")


def lock_path(root: Path) -> Path:
    directory = Path(os.environ.get("POLARIS_WORK_ORDER_LOCK_DIR", "/tmp"))
    digest = hashlib.sha1(str(root).encode("utf-8")).hexdigest()[:12]
    return directory / f"polaris-work-order-lock-{digest}.json"


def write_lock(root: Path, resolved: Path, mode: str, value: str) -> None:
    path = lock_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "root": str(root),
        "resolved_path": str(resolved),
        "mode": mode,
        "input": value,
        "writer": "resolve-task-md.sh",
        "at": datetime.now(timezone.utc).isoformat(),
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def run_selftest() -> int:
    env = os.environ.copy()
    env.pop("RESOLVE_TASK_MD_SELFTEST", None)
    result = subprocess.run(
        ["mise", "exec", "--", "pytest", "tests/test_resolve_task_md.py", "-q", "-k", "not embedded_resolve_task_md_selftest"],
        cwd=REPO_ROOT,
        env=env,
        check=False,
    )
    return result.returncode


def main(argv: list[str]) -> int:
    if os.environ.get("RESOLVE_TASK_MD_SELFTEST") == "1":
        return run_selftest()
    parser = argparse.ArgumentParser(add_help=False, allow_abbrev=False)
    parser.add_argument("value", nargs="?")
    parser.add_argument("--scan-root", default="")
    parser.add_argument("--specs-source", default="")
    parser.add_argument("--from-input", default="")
    parser.add_argument("--include-archive", action="store_true")
    parser.add_argument("--write-lock", action="store_true")
    parser.add_argument("--print-lock-path", action="store_true")
    parser.add_argument("--clear-lock", action="store_true")
    parser.add_argument("--current", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    parsed = parser.parse_args(argv)
    if parsed.help:
        return usage()

    mode_flags = sum(bool(item) for item in (parsed.from_input, parsed.clear_lock, parsed.current))
    if mode_flags > 1 or (parsed.value and mode_flags):
        return usage()
    if parsed.from_input:
        mode, value = "from-input", parsed.from_input
    elif parsed.clear_lock:
        mode, value = "clear-lock", ""
    elif parsed.current:
        mode, value = "current", ""
    elif parsed.value:
        mode, value = "direct", parsed.value
    else:
        return usage()

    scan_root = parsed.scan_root
    specs_source = parsed.specs_source
    write_lock_flag = parsed.write_lock
    print_lock = parsed.print_lock_path
    include_archive = parsed.include_archive
    try:
        root = detect_root(scan_root)
        specs = resolve_specs_root(root, specs_source)
        if mode == "clear-lock":
            lock_path(root).unlink(missing_ok=True)
            return 0
        if print_lock:
            print(lock_path(root))
            return 0
        if mode == "current":
            branch = git_output("rev-parse", "--abbrev-ref", "HEAD", cwd=Path.cwd())
            if not branch or branch == "HEAD":
                raise ResolverError("error: --current: could not resolve current branch")
            resolved = resolve_branch(root, branch)
        elif mode == "from-input":
            resolved = resolve_input(root, specs, value, include_archive)
        else:
            direct = direct_path(value)
            if direct:
                resolved = direct
            elif re.fullmatch(r"DP-[0-9]{3}-[TV][0-9]+[a-z]*", value):
                resolved = resolve_source_task(specs, value, include_archive, dp_only=True)
            elif re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-[TV][0-9]+[a-z]*", value):
                resolved = resolve_source_task(specs, value, include_archive)
            elif re.fullmatch(r"[A-Z][A-Z0-9]+-[0-9]+", value):
                resolved = resolve_jira(specs, value, include_archive)
            elif re.fullmatch(r"https?://github\.com/.+/pull/[0-9]+", value) or re.fullmatch(r"#?[0-9]+", value):
                resolved = resolve_pr(root, value.lstrip("#"))
            else:
                raise ResolverError(
                    f"error: unsupported input: {value}\n"
                    "supported: path, JIRA key, PR URL, PR number, --current, --from-input"
                )
        if write_lock_flag:
            write_lock(root, resolved, mode, value)
        print(resolved)
        return 0
    except ResolverError as error:
        if str(error):
            print(error, file=sys.stderr)
        return error.code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
