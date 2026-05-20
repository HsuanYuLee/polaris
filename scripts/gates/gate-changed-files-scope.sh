#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/gates/gate-changed-files-scope.sh --repo PATH --refinement PATH [--base REF] [--head REF]

Fails when git changed files are outside refinement.json changed_files.
USAGE
  exit 2
}

REPO=""
REFINEMENT=""
BASE="HEAD~1"
HEAD="HEAD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --refinement) REFINEMENT="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --head) HEAD="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$REPO" && -n "$REFINEMENT" ]] || usage

python3 - "$REPO" "$REFINEMENT" "$BASE" "$HEAD" <<'PY'
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
refinement_path = Path(sys.argv[2]).resolve()
base = sys.argv[3]
head = sys.argv[4]


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(2)


if not repo.is_dir():
    fail(f"repo not found: {repo}")
if not refinement_path.is_file():
    fail(f"refinement.json not found: {refinement_path}")

try:
    refinement = json.loads(refinement_path.read_text(encoding="utf-8"))
except Exception as exc:
    fail(f"refinement.json invalid JSON: {exc}")

allowed = refinement.get("changed_files")
if not isinstance(allowed, list) or not allowed:
    fail("refinement.json changed_files is required and must be a non-empty array")

proc = subprocess.run(
    ["git", "-C", str(repo), "diff", "--name-only", f"{base}..{head}"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if proc.returncode != 0:
    fail(proc.stderr.strip() or "git diff failed")

changed = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
extra = []
for path in changed:
    if not any(fnmatch.fnmatch(path, pattern) for pattern in allowed if isinstance(pattern, str)):
        extra.append(path)

if extra:
    print("FAIL: changed files exceed refinement.json changed_files", file=sys.stderr)
    for path in extra:
        print(f"  - {path}", file=sys.stderr)
    print("Route back to refinement to update changed_files or narrow implementation scope.", file=sys.stderr)
    raise SystemExit(2)

print(f"PASS: changed files scope ({len(changed)} changed file(s))")
PY
