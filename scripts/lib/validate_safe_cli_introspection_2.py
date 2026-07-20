"""Structured validator authority extracted from scripts/validate-safe-cli-introspection.sh."""

import hashlib
import os
import subprocess
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()

# A framework source snapshot is the git-owned source surface: tracked files
# plus non-ignored untracked files.  Local runtime state (for example
# node_modules, .polaris evidence, and linked worktrees) is deliberately outside
# that surface.  Reading every byte below the checkout made a single --help
# fixture scan unrelated ignored state twice and turned release re-verification
# into an unbounded workspace-size operation.
try:
    listed = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        check=True,
        capture_output=True,
    ).stdout
    paths = [
        root / raw.decode("utf-8", "surrogateescape")
        for raw in listed.split(b"\0")
        if raw
    ]
except (FileNotFoundError, subprocess.CalledProcessError):
    # Hermetic non-git fixtures retain the original complete-tree behavior.
    paths = [
        path for path in root.rglob("*") if ".git" not in path.relative_to(root).parts
    ]

for path in sorted(paths, key=lambda item: item.as_posix()):
    if not path.exists() and not path.is_symlink():
        # A path may disappear between enumeration and hashing.  Encode the
        # disappearance so the before/after digest still differs deterministically.
        digest.update(f"{path.relative_to(root).as_posix()}\0missing\0".encode())
        continue
    relative = path.relative_to(root).as_posix()
    mode = stat.S_IMODE(path.lstat().st_mode)
    digest.update(f"{relative}\0{mode:o}\0".encode())
    if path.is_symlink():
        digest.update(os.readlink(path).encode())
    elif path.is_file():
        digest.update(path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
