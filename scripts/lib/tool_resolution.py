"""Python-callable mise-aware tool resolution helpers (DP-230 D38).

Mirror of ``scripts/lib/tool-resolution.sh`` for callers running inside Python.

Resolution strategy (deterministic, no shell fallthrough):

1. POSIX baseline whitelist (``bash``, ``python3``, ``cp``, ``mv``, ``rm`` …) ->
   ``shutil.which`` PATH lookup. Framework infrastructure must not be locked to
   mise-managed versions (AC-NEG15).
2. ``mise where <tool>`` from the workspace root -> first emitted absolute path
   plus the tool basename.
3. ``~/.local/share/mise/shims/<tool>`` (or ``POLARIS_MISE_SHIMS_DIR``) when the
   shim is executable (EC12 fallback).
4. ``shutil.which(<tool>)`` last-resort PATH lookup with stderr advisory so the
   call still succeeds when mise is not initialised (CI minimal container).

The resolver raises :class:`ToolResolutionError` when none of the above produce
an executable path; callers can ``except ToolResolutionError`` to map this to a
``POLARIS_TOOL_MISSING`` exit. Resolved paths are memoised per process to keep
``resolve_tool()`` overhead inside the AC-NFR5 budget (≤ 50 ms median).
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

__all__ = [
    "ToolResolutionError",
    "POSIX_BASELINE",
    "resolve_tool",
    "clear_cache",
]


class ToolResolutionError(RuntimeError):
    """Raised when no resolution layer can locate the requested tool."""


# Framework infra tools that are part of the POSIX baseline (AC-NEG15).
# These must succeed via PATH lookup even when mise is not initialised so that
# framework infrastructure cannot be silently pinned to a mise-managed version.
POSIX_BASELINE = frozenset(
    {
        "bash",
        "sh",
        "python3",
        "cp",
        "mv",
        "rm",
        "ln",
        "mkdir",
        "rmdir",
        "test",
        "true",
        "false",
        "env",
        "printf",
        "echo",
        "cat",
        "tr",
        "tee",
        "sed",
        "awk",
        "grep",
        "find",
        "xargs",
        "sort",
        "uniq",
        "head",
        "tail",
        "wc",
        "cut",
        "date",
        "basename",
        "dirname",
        "readlink",
        "uname",
        "chmod",
        "git",
    }
)


# Memoised resolution cache: tool -> absolute path.
_CACHE: dict[str, str] = {}


def clear_cache() -> None:
    """Reset the memoisation cache (intended for tests)."""

    _CACHE.clear()


def _workspace_root() -> Path:
    override = os.environ.get("POLARIS_WORKSPACE_ROOT")
    if override:
        candidate = Path(override)
        if candidate.is_dir():
            return candidate.resolve()
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip()).resolve()
    except FileNotFoundError:
        pass
    return Path.cwd().resolve()


def _find_mise() -> Optional[str]:
    explicit = os.environ.get("POLARIS_MISE_BIN")
    if explicit and os.access(explicit, os.X_OK):
        return explicit
    via_path = shutil.which("mise")
    if via_path:
        return via_path
    candidates = [
        Path.home() / ".local" / "bin" / "mise",
        Path.home() / ".local" / "share" / "mise" / "bin" / "mise",
        Path("/opt/homebrew/bin/mise"),
        Path("/usr/local/bin/mise"),
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _mise_where(tool: str) -> Optional[str]:
    mise_bin = _find_mise()
    if not mise_bin:
        return None
    root = _workspace_root()
    try:
        proc = subprocess.run(
            [mise_bin, "where", tool],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    if proc.returncode != 0:
        return None
    for line in proc.stdout.splitlines():
        candidate = line.strip()
        if not candidate:
            continue
        # ``mise where`` returns the install prefix; the executable lives under
        # ``<prefix>/bin/<tool>``. Some tools install at the prefix root, so
        # fall back to the prefix itself when the bin variant is missing.
        bin_candidate = Path(candidate) / "bin" / tool
        if bin_candidate.is_file() and os.access(bin_candidate, os.X_OK):
            return str(bin_candidate)
        flat_candidate = Path(candidate) / tool
        if flat_candidate.is_file() and os.access(flat_candidate, os.X_OK):
            return str(flat_candidate)
    return None


def _mise_shim(tool: str) -> Optional[str]:
    shims_dir = os.environ.get("POLARIS_MISE_SHIMS_DIR")
    if shims_dir:
        candidate = Path(shims_dir) / tool
    else:
        candidate = Path.home() / ".local" / "share" / "mise" / "shims" / tool
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


def _path_lookup(tool: str) -> Optional[str]:
    return shutil.which(tool)


def resolve_tool(tool: str) -> str:
    """Resolve ``tool`` to an absolute executable path.

    See module docstring for resolution layering. Raises
    :class:`ToolResolutionError` when no layer can locate the tool.
    """

    if not tool or not isinstance(tool, str):
        raise ToolResolutionError("resolve_tool() requires a non-empty tool name")

    cached = _CACHE.get(tool)
    if cached is not None:
        return cached

    if tool in POSIX_BASELINE:
        path = _path_lookup(tool)
        if path:
            _CACHE[tool] = path
            return path
        # POSIX baseline must not fall through to mise; missing here is fatal.
        raise ToolResolutionError(
            f"POLARIS_TOOL_MISSING tool={tool} layer=posix_baseline_path"
        )

    path = _mise_where(tool)
    if path:
        _CACHE[tool] = path
        return path

    path = _mise_shim(tool)
    if path:
        _CACHE[tool] = path
        return path

    path = _path_lookup(tool)
    if path:
        # Last-layer fallback is permitted but should be observable so operators
        # can detect when their environment is bypassing mise (EC12 advisory).
        print(
            f"POLARIS_TOOL_RESOLUTION_ADVISORY tool={tool} layer=path_lookup "
            "hint=mise where/shims unavailable; consider running through mise",
            file=sys.stderr,
        )
        _CACHE[tool] = path
        return path

    raise ToolResolutionError(
        f"POLARIS_TOOL_MISSING tool={tool} layer=exhausted "
        "hint=run mise install or expose the tool on PATH"
    )
