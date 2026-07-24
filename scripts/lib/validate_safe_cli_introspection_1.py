"""Validate safe CLI prefixes and execute introspection with process containment.

Purpose: provide one importable authority for classifying Verify Command scripts,
checking the DP-422 literal help prefix, and terminating a timed-out process group.
"""

from __future__ import annotations

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Mapping, Sequence

BEGIN_MARKER = "# POLARIS_SAFE_CLI_INTROSPECTION_BEGIN"
END_MARKER = "# POLARIS_SAFE_CLI_INTROSPECTION_END"
EXPECTED_IF = 'if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then'
LITERAL_PRINTF = re.compile(r"  command printf '%s\\n' '[^']*'")
TEST_PATH_PARTS = {"test", "tests", "selftest", "selftests"}
TEST_NAME_SUFFIXES = ("-selftest.sh", "_selftest.sh", "-test.sh", "_test.sh")


class UnsafePrefixError(ValueError):
    """Describe why a script is not eligible for dynamic help introspection."""


class UnsafeScriptPathError(ValueError):
    """Describe a script path that cannot be classified inside its repo."""


@dataclass(frozen=True)
class BoundedCommandResult:
    """Captured result from a process-group-contained command."""

    returncode: int
    stdout: str
    stderr: str
    timed_out: bool


def validate_safe_cli_prefix(path: Path) -> None:
    """Raise UnsafePrefixError unless path has the canonical literal help prefix."""

    lines = path.read_text(encoding="utf-8").splitlines()
    if lines.count(BEGIN_MARKER) != 1 or lines.count(END_MARKER) != 1:
        raise UnsafePrefixError("canonical markers must each appear exactly once")
    begin = lines.index(BEGIN_MARKER)
    end = lines.index(END_MARKER)
    if end <= begin:
        raise UnsafePrefixError("end marker must follow begin marker")
    if not lines or lines[0] != "#!/usr/bin/env bash":
        raise UnsafePrefixError("first line must be the canonical bash shebang")

    executable_prefix = [
        line.strip()
        for line in lines[1:begin]
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if executable_prefix != ["set -euo pipefail"]:
        raise UnsafePrefixError(
            "only set -euo pipefail may execute before the canonical help block"
        )

    block = lines[begin + 1 : end]
    if len(block) < 4 or block[0] != EXPECTED_IF or block[-2:] != ["  exit 0", "fi"]:
        raise UnsafePrefixError("help block must use the canonical condition and terminal exit 0")
    printf_lines = block[1:-2]
    if not printf_lines:
        raise UnsafePrefixError("help block must emit at least one literal line")
    for line in printf_lines:
        if not LITERAL_PRINTF.fullmatch(line):
            raise UnsafePrefixError(f"non-literal or side-effecting help statement: {line}")


def classify_script_for_introspection(
    path: Path,
    repo_relative: str,
    repo_root: Path,
) -> str:
    """Return test, safe_cli, or non_cli without executing the script."""

    lexical = PurePosixPath(repo_relative)
    if lexical.is_absolute():
        raise UnsafeScriptPathError("script token must be repo-relative")
    try:
        canonical_root = repo_root.resolve(strict=True)
        canonical_path = path.resolve(strict=True)
        relative_path = canonical_path.relative_to(canonical_root)
    except (OSError, RuntimeError, ValueError) as exc:
        raise UnsafeScriptPathError(
            f"script does not resolve to a file inside the repo: {repo_relative}"
        ) from exc
    relative = PurePosixPath(relative_path.as_posix())
    if any(part.lower() in TEST_PATH_PARTS for part in relative.parts[:-1]):
        return "test"
    if relative.name.lower().endswith(TEST_NAME_SUFFIXES):
        return "test"
    try:
        validate_safe_cli_prefix(path)
    except (OSError, UnicodeError, UnsafePrefixError):
        return "non_cli"
    return "safe_cli"


def _process_group_exists(pgid: int) -> bool:
    """Return whether pgid still has at least one process."""

    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _terminate_process_group(proc: subprocess.Popen[str]) -> None:
    """Terminate a dedicated session, escalating when descendants ignore TERM."""

    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 0.25
    while _process_group_exists(proc.pid) and time.monotonic() < deadline:
        proc.poll()
        time.sleep(0.01)
    if _process_group_exists(proc.pid):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        proc.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()


def run_bounded_command(
    argv: Sequence[str],
    *,
    cwd: Path,
    timeout_seconds: float = 5.0,
    env: Mapping[str, str] | None = None,
) -> BoundedCommandResult:
    """Run argv in a new session and kill/reap its process group on timeout."""

    proc = subprocess.Popen(
        list(argv),
        cwd=cwd,
        env=dict(env) if env is not None else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout_seconds)
        returncode = proc.returncode
        if _process_group_exists(proc.pid):
            _terminate_process_group(proc)
        return BoundedCommandResult(returncode, stdout, stderr, False)
    except subprocess.TimeoutExpired:
        _terminate_process_group(proc)
        stdout, stderr = proc.communicate()
        return BoundedCommandResult(proc.returncode, stdout, stderr, True)


def _fail_prefix(path: Path, detail: str) -> None:
    print(
        f"POLARIS_SAFE_CLI_INTROSPECTION_UNSAFE_PREFIX:{path.name}:{detail}",
        file=sys.stderr,
    )
    raise SystemExit(2)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--run-bounded", action="store_true")
    parser.add_argument("--cwd", default="")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--output", default="")
    parser.add_argument("--clear-env", action="store_true")
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    return parser.parse_args()


def main() -> int:
    """Expose legacy prefix validation and the bounded runner to shell callers."""

    args = _parse_args()
    arguments = list(args.arguments)
    if arguments and arguments[0] == "--":
        arguments.pop(0)

    if not args.run_bounded:
        if len(arguments) != 1:
            print("expected exactly one script path", file=sys.stderr)
            return 2
        path = Path(arguments[0])
        try:
            validate_safe_cli_prefix(path)
        except (OSError, UnicodeError, UnsafePrefixError) as exc:
            _fail_prefix(path, str(exc))
        return 0

    if not args.cwd or not args.output or not arguments:
        print("--run-bounded requires --cwd, --output, and a command", file=sys.stderr)
        return 2
    child_env = {} if args.clear_env else dict(os.environ)
    for item in args.env:
        if "=" not in item:
            print(f"--env must use KEY=VALUE form: {item}", file=sys.stderr)
            return 2
        key, value = item.split("=", 1)
        if not key:
            print("--env key must not be empty", file=sys.stderr)
            return 2
        child_env[key] = value
    try:
        result = run_bounded_command(
            arguments,
            cwd=Path(args.cwd),
            timeout_seconds=args.timeout,
            env=child_env,
        )
    except OSError as exc:
        print(f"POLARIS_SAFE_CLI_INTROSPECTION_EXEC_FAILED:{exc}", file=sys.stderr)
        return 2
    Path(args.output).write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.timed_out:
        print("POLARIS_SAFE_CLI_INTROSPECTION_TIMEOUT", file=sys.stderr)
        return 124
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
