#!/usr/bin/env bash
# Purpose: classify a set of changed file paths (a diff) into product-owned vs
#          framework-owned by artifact-role ownership, and fail closed when a
#          product PR silently bundles framework-owned flow-repair paths (mixed diff).
# Inputs:  changed paths via CLI args and/or newline-separated stdin.
#          POLARIS_FRAMEWORK_OWNED_PATHS_JSON overrides the owned-glob registry
#          (default scripts/lib/framework-source-owned-paths.json — the single
#          canonical framework-owned glob set, shared with
#          validate-framework-source-write.sh; this validator does NOT invent a
#          second ownership list).
# Outputs: stdout PASS line with the resolved artifact-role (empty|product|framework);
#          exit 0 for empty or homogeneous diffs; exit 2 + POLARIS_MIXED_ARTIFACT_ROLE_DIFF
#          on a mixed diff (framework owner paths listed on stderr); exit 3 usage/IO error.
set -euo pipefail

PREFIX="[artifact-role-ownership]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OWNED_JSON="${POLARIS_FRAMEWORK_OWNED_PATHS_JSON:-$ROOT_DIR/scripts/lib/framework-source-owned-paths.json}"

usage() {
  sed -n '2,12p' "$0" >&2
  cat >&2 <<'USAGE'
Usage:
  classify-artifact-role-ownership.sh [--] <path> [<path> ...]
  <cmd producing paths> | classify-artifact-role-ownership.sh
USAGE
}

PATHS=()
END_OPTS=0
while [[ $# -gt 0 ]]; do
  if [[ "$END_OPTS" -eq 1 ]]; then
    PATHS+=("$1"); shift; continue
  fi
  case "$1" in
    --) END_OPTS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$PREFIX POLARIS_ARTIFACT_ROLE_USAGE: unknown option: $1" >&2; usage; exit 3 ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

# Also accept newline-separated paths on stdin (parity with `git diff --name-only | ...`).
if [[ ! -t 0 ]]; then
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && PATHS+=("$_line")
  done
fi

if [[ ! -f "$OWNED_JSON" ]]; then
  echo "$PREFIX POLARIS_ARTIFACT_ROLE_IO: owned-path registry not found: $OWNED_JSON" >&2
  exit 3
fi

PATHS_BLOB=""
if [[ ${#PATHS[@]} -gt 0 ]]; then
  PATHS_BLOB="$(printf '%s\n' "${PATHS[@]}")"
fi
export POLARIS_ARTIFACT_ROLE_PATHS="$PATHS_BLOB"
export POLARIS_ARTIFACT_ROLE_OWNED_JSON="$OWNED_JSON"
export POLARIS_ARTIFACT_ROLE_PREFIX="$PREFIX"

python3 - <<'PY'
import fnmatch
import json
import os
import sys
from pathlib import Path

owned_json = Path(os.environ["POLARIS_ARTIFACT_ROLE_OWNED_JSON"])
prefix = os.environ["POLARIS_ARTIFACT_ROLE_PREFIX"]
raw_paths = os.environ.get("POLARIS_ARTIFACT_ROLE_PATHS", "")

try:
    cfg = json.loads(owned_json.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"{prefix} POLARIS_ARTIFACT_ROLE_IO: cannot parse {owned_json}: {exc}", file=sys.stderr)
    sys.exit(3)

owned_globs = cfg.get("owned_path_globs") or []
if not owned_globs:
    print(f"{prefix} POLARIS_ARTIFACT_ROLE_IO: owned_path_globs empty in {owned_json}", file=sys.stderr)
    sys.exit(3)


def normalise(raw: str) -> str:
    """Strip surrounding quotes / whitespace / leading ./ from a changed path."""
    text = raw.strip().strip("'\"")
    while text.startswith("./"):
        text = text[2:]
    return text


def matches_one(path: str, pattern: str) -> bool:
    """Match a repo-relative path against one owned glob.

    A `prefix/**` pattern is treated as a directory subtree (matches the dir
    itself and anything beneath it); other patterns fall back to fnmatch.
    """
    if pattern.endswith("/**"):
        base = pattern[:-3].rstrip("/")
        return path == base or path.startswith(base + "/")
    return fnmatch.fnmatchcase(path, pattern)


def is_framework(path: str) -> bool:
    """True when the path is owned by the framework per the canonical glob set."""
    return any(matches_one(path, glob) for glob in owned_globs)


paths = sorted({normalise(p) for p in raw_paths.splitlines() if normalise(p)})
framework = [p for p in paths if is_framework(p)]
product = [p for p in paths if not is_framework(p)]

if not paths:
    print(f"{prefix} PASS: artifact-role=empty (0 path(s))")
    sys.exit(0)

if framework and product:
    print(
        f"{prefix} POLARIS_MIXED_ARTIFACT_ROLE_DIFF: product PR bundles "
        f"{len(framework)} framework-owned path(s); split the framework-owned "
        "flow repair into its own DP-backed framework PR:",
        file=sys.stderr,
    )
    for p in framework:
        print(f"  framework-owned: {p}", file=sys.stderr)
    for p in product:
        print(f"  product-owned:   {p}", file=sys.stderr)
    sys.exit(2)

if framework:
    print(f"{prefix} PASS: artifact-role=framework ({len(framework)} path(s))")
else:
    print(f"{prefix} PASS: artifact-role=product ({len(product)} path(s))")
sys.exit(0)
PY
