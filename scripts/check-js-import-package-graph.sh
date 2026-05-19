#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF=""
PATHS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/check-js-import-package-graph.sh [--root <repo>] [--base <ref>] [--path <file>]... [--self-test]

Fails when changed JS files import packages that are absent from the owning
package.json dependency graph.
USAGE
}

run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  mkdir -p "$tmp/scripts"
  cp "$0" "$tmp/scripts/check-js-import-package-graph.sh"
  cat >"$tmp/package.json" <<'JSON'
{"type":"module","dependencies":{"left-pad":"1.3.0"}}
JSON
  cat >"$tmp/ok.mjs" <<'JS'
import leftPad from 'left-pad';
import { readFileSync } from 'node:fs';
console.log(leftPad(readFileSync, 2));
JS
  cat >"$tmp/bad.mjs" <<'JS'
import chalk from 'chalk';
console.log(chalk.green('x'));
JS
  bash "$tmp/scripts/check-js-import-package-graph.sh" --root "$tmp" >/dev/null
  bash "$tmp/scripts/check-js-import-package-graph.sh" --root "$tmp" --path ok.mjs >/dev/null
  if bash "$tmp/scripts/check-js-import-package-graph.sh" --root "$tmp" --path bad.mjs >/tmp/check-js-import-package-graph.out 2>&1; then
    echo "expected undeclared JS package import to fail" >&2
    exit 1
  fi
  grep -q "package 'chalk' is not declared" /tmp/check-js-import-package-graph.out
  echo "PASS: check-js-import-package-graph selftest"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="$2"; shift 2 ;;
    --base) BASE_REF="$2"; shift 2 ;;
    --path) PATHS+=("$2"); shift 2 ;;
    --self-test) run_self_test; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "check-js-import-package-graph: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

PY_ARGS=("$ROOT_DIR" "$BASE_REF")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
base = sys.argv[2]
explicit = [Path(p) for p in sys.argv[3:]]
node_builtins = {
    "assert", "buffer", "child_process", "crypto", "events", "fs", "http",
    "https", "module", "os", "path", "process", "stream", "url", "util",
}

def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root))
    except ValueError:
        return str(path)

def changed_files() -> list[Path]:
    if explicit:
        return [(root / p if not p.is_absolute() else p) for p in explicit]
    ref = base or "origin/main"
    names: set[str] = set()
    for cmd in (
        ["git", "-C", str(root), "diff", "--name-only", f"{ref}..HEAD"],
        ["git", "-C", str(root), "diff", "--name-only"],
        ["git", "-C", str(root), "diff", "--cached", "--name-only"],
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            continue
        names.update(line.strip() for line in out.splitlines() if line.strip())
    return [root / name for name in sorted(names)]

def nearest_package_json(path: Path) -> Path | None:
    current = path.parent
    while True:
        candidate = current / "package.json"
        if candidate.is_file():
            return candidate
        if current == root:
            return None
        if current.parent == current:
            return None
        current = current.parent

def deps(package_json: Path | None) -> set[str]:
    if not package_json:
        return set()
    data = json.loads(package_json.read_text(encoding="utf-8"))
    result: set[str] = set()
    for key in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        value = data.get(key)
        if isinstance(value, dict):
            result.update(value)
    return result

def package_name(spec: str) -> str:
    return "/".join(spec.split("/")[:2]) if spec.startswith("@") else spec.split("/", 1)[0]

errors: list[str] = []
for path in changed_files():
    if path.suffix not in {".js", ".mjs", ".cjs"} or not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    specs = re.findall(r"(?:import\s+(?:[^'\"]+\s+from\s+)?|require\()\s*['\"]([^'\"]+)['\"]", text)
    declared = deps(nearest_package_json(path))
    for spec in specs:
        if spec.startswith((".", "/", "node:")):
            continue
        pkg = package_name(spec)
        if pkg in node_builtins:
            continue
        if pkg not in declared:
            errors.append(f"{rel(path)}: package {pkg!r} is not declared in owning package.json")

for error in errors:
    print(error, file=sys.stderr)
if errors:
    print(f"FAIL: JS import package graph ({len(errors)} issue(s))", file=sys.stderr)
    sys.exit(1)
print("PASS: JS import package graph")
PY
