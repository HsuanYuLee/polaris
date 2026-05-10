#!/usr/bin/env bash
# check-sunset-broken-refs.sh — verify cleanup removal did not leave dead refs.

set -euo pipefail

root="."
base_ref="origin/main"
skip_runtime_compile=0

usage() {
  cat >&2 <<'EOF'
usage: check-sunset-broken-refs.sh [--root <repo>] [--base-ref <ref>] [--skip-runtime-compile]

Checks cleanup removals for:
- active callsites that still mention deleted paths or basenames;
- .claude/skills/references/INDEX.md links that point to missing references;
- runtime instruction graph drift via compile-runtime-instructions.sh --check.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;;
    --base-ref) base_ref="${2:-}"; shift 2 ;;
    --skip-runtime-compile) skip_runtime_compile=1; shift ;;
    -h|--help) usage ;;
    *) echo "error: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$root" || ! -d "$root" ]]; then
  echo "error: repo root not found: $root" >&2
  exit 2
fi

root="$(cd "$root" && pwd)"

python3 - "$root" "$base_ref" <<'PY'
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
base_ref = sys.argv[2]
errors: list[str] = []

ACTIVE_SEARCH_DIRS = [
    ".claude/skills",
    ".claude/rules",
    "scripts",
    "docs-manager/src/content/docs/specs/design-plans",
]

EXCLUDED_ACTIVE_FILES = {
    "CHANGELOG.md",
}


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def deleted_paths() -> list[str]:
    proc = run(["git", "diff", "--name-only", "--diff-filter=D", f"{base_ref}..HEAD"])
    if proc.returncode != 0:
        errors.append(f"unable to diff against {base_ref}: {proc.stderr.strip()}")
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def active_files() -> list[Path]:
    out: list[Path] = []
    for rel_dir in ACTIVE_SEARCH_DIRS:
        base = root / rel_dir
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            if "/archive/" in rel or "/node_modules/" in rel or "/.astro/" in rel:
                continue
            if rel in EXCLUDED_ACTIVE_FILES:
                continue
            out.append(path)
    return out


def find_mentions(target: str, files: list[Path]) -> list[str]:
    basename = Path(target).name
    mentions: list[str] = []
    for path in files:
        rel = path.relative_to(root).as_posix()
        if rel == target:
            continue
        try:
            text = path.read_text(errors="ignore")
        except Exception:
            continue
        if target in text or basename in text:
            mentions.append(rel)
    return sorted(set(mentions))


def check_deleted_references() -> None:
    files = active_files()
    for target in deleted_paths():
        mentions = find_mentions(target, files)
        if mentions:
            errors.append(
                f"deleted target still referenced: {target} -> {', '.join(mentions[:10])}"
            )


def check_reference_index_links() -> None:
    index = root / ".claude/skills/references/INDEX.md"
    if not index.exists():
        return
    text = index.read_text(errors="ignore")
    for match in re.finditer(r"\[[^\]]+\]\(([^)]+\.md)\)", text):
        href = match.group(1).strip()
        if href.startswith(("http://", "https://", "/")):
            continue
        target = (index.parent / href).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            errors.append(f"reference index link escapes repo: {href}")
            continue
        if not target.exists():
            errors.append(f"reference index dead link: {href}")


check_deleted_references()
check_reference_index_links()

if errors:
    print("FAIL: sunset broken-reference check failed", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: no deleted-target active references or reference-index dead links")
PY

if [[ "$skip_runtime_compile" -eq 0 && -x "$root/scripts/compile-runtime-instructions.sh" ]]; then
  bash "$root/scripts/compile-runtime-instructions.sh" --target agents --check >/dev/null
fi

echo "PASS: sunset broken-reference check"
