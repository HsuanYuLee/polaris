"""Structured validator authority extracted from scripts/validate-script-header-comment.sh."""

import os
import subprocess
import sys
from pathlib import Path

mode = sys.argv[1]
base_ref = sys.argv[2]
root = Path(sys.argv[3]).resolve()
explicit = [Path(p) for p in sys.argv[4:]]

HOT_PATH_EXTS = {".sh", ".py", ".mjs", ".ts"}
HEADER_WINDOW = 20

# Exclusion globs — generated targets must never be checked (AC-NEG2),
# nor fixtures whose intent is to demonstrate the violation itself, nor
# vendored / build outputs.
EXCLUDE_GLOBS = [
    # Generated runtime targets (manifest-driven). They are .md, so are not
    # in HOT_PATH_EXTS, but we still record the contract intent explicitly.
    "CLAUDE.md",
    "AGENTS.md",
    ".codex/AGENTS.md",
    ".github/copilot-instructions.md",
    # Fixtures whose purpose is to exercise the validator itself.
    "scripts/fixtures/script-header-comment/**",
    # Other fixture trees that may contain intentionally minimal scripts.
    "scripts/fixtures/**/missing-*",
    # Build / vendored output.
    "docs-manager/dist/**",
    "docs-manager/node_modules/**",
    "node_modules/**",
    ".worktrees/**",
    ".polaris/**",
]


def excluded(rel: Path) -> bool:
    s = rel.as_posix()
    for pat in EXCLUDE_GLOBS:
        if Path(s).match(pat):
            return True
        # fnmatch via Path.match does not handle ** well across segments for
        # all patterns; do a manual prefix check for trailing ** patterns.
        if pat.endswith("/**"):
            prefix = pat[:-3]
            if s == prefix.rstrip("/") or s.startswith(prefix):
                return True
    return False


def has_header(path: Path) -> bool:
    # Check first HEADER_WINDOW lines for a meaningful purpose comment.
    #
    # Rules:
    #   .sh / .mjs / .ts: at least one non-empty hash/slash-style comment
    #     line that is NOT just the shebang.
    #   .py: at least one non-empty hash comment line OR a module
    #     docstring (triple-quoted at module top).
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return True  # cannot read → don't block
    lines = text.splitlines()[:HEADER_WINDOW]
    ext = path.suffix
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#!"):
            continue
        if ext == ".py":
            # Module docstring detection — first non-shebang, non-blank line.
            if stripped.startswith('"""') or stripped.startswith("'''"):
                # Must contain actual content (not just the opening quotes
                # immediately followed by closing on the same line with
                # nothing inside).
                quote = '"""' if stripped.startswith('"""') else "'''"
                inner = stripped[len(quote) :]
                if inner.endswith(quote):
                    inner = inner[: -len(quote)]
                if inner.strip():
                    return True
                # Multi-line docstring: assume content follows.
                return True
            if stripped.startswith("#"):
                body = stripped.lstrip("#").strip()
                if body:
                    return True
        elif ext in {".sh"}:
            if stripped.startswith("#"):
                body = stripped.lstrip("#").strip()
                if body:
                    return True
        elif ext in {".mjs", ".ts"}:
            if stripped.startswith("//"):
                body = stripped.lstrip("/").strip()
                if body:
                    return True
            if stripped.startswith("/*"):
                return True
            if stripped.startswith("#"):
                # shebang already filtered above; treat other # as comment.
                body = stripped.lstrip("#").strip()
                if body:
                    return True
        # If we hit code-like content first, keep scanning until window ends.
    return False


def git_diff_files(base: str) -> list[Path]:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "diff", "--name-only", "--diff-filter=AM", base],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        sys.stderr.write(
            f"error: git diff failed against base {base!r}: {exc.stderr}\n"
        )
        sys.exit(2)
    paths = []
    for line in out.stdout.splitlines():
        rel = line.strip()
        if not rel:
            continue
        p = root / rel
        if p.exists():
            paths.append(p)
    return paths


def walk_repo() -> list[Path]:
    paths = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune obvious heavy dirs early.
        dirnames[:] = [
            d
            for d in dirnames
            if d not in {".git", "node_modules", "dist", ".worktrees", ".polaris"}
        ]
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix not in HOT_PATH_EXTS:
                continue
            paths.append(p)
    return paths


def collect_candidates() -> list[Path]:
    if explicit:
        return [p if p.is_absolute() else (root / p) for p in explicit]
    if mode == "diff":
        return git_diff_files(base_ref)
    return walk_repo()


def in_scope(path: Path) -> bool:
    if path.suffix not in HOT_PATH_EXTS:
        return False
    try:
        rel = path.resolve().relative_to(root)
    except ValueError:
        return False
    if excluded(rel):
        return False
    return True


violations: list[Path] = []
checked = 0
for candidate in collect_candidates():
    if not candidate.exists():
        continue
    if not in_scope(candidate):
        continue
    checked += 1
    if not has_header(candidate):
        violations.append(candidate)

if mode == "diff":
    if violations:
        for v in violations:
            try:
                rel = v.resolve().relative_to(root)
            except ValueError:
                rel = v
            sys.stdout.write(f"POLARIS_SCRIPT_HEADER_MISSING:{rel}\n")
        sys.stdout.write(
            f"FAIL: {len(violations)} script(s) missing header comment "
            f"(checked {checked})\n"
        )
        sys.exit(2)
    sys.stdout.write(f"PASS: validate-script-header-comment (checked {checked})\n")
    sys.exit(0)
else:  # audit
    sys.stdout.write(
        f"AUDIT: validate-script-header-comment scanned {checked} script(s); "
        f"{len(violations)} missing header\n"
    )
    for v in violations:
        try:
            rel = v.resolve().relative_to(root)
        except ValueError:
            rel = v
        sys.stdout.write(f"  legacy-debt: {rel}\n")
    sys.exit(0)
