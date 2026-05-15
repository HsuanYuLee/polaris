#!/usr/bin/env bash
# Validate framework script dependencies against Polaris-managed contracts.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="diff"
BASE_BRANCH=""
PATHS=()

usage() {
  cat <<'EOF'
Usage:
  scripts/validate-script-dependencies.sh [--mode diff|audit] [--base <ref>] [--path <script>]...

Checks framework scripts for unmanaged third-party dependencies.

Modes:
  diff   blocking mode for changed scripts
  audit  advisory mode for a wider scan; reports issues but exits 0

Baseline / allowlist entries must use the shared DP-184 D8 schema:
  owner, reason, remediation_task, expiry, scope
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --base)
      BASE_BRANCH="${2:-}"
      shift 2
      ;;
    --path)
      PATHS+=("${2:-}")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$MODE" in
  diff|audit) ;;
  *) echo "invalid --mode: $MODE" >&2; exit 2 ;;
esac

PY_ARGS=("$ROOT_DIR" "$MODE" "$BASE_BRANCH")
if [[ "${#PATHS[@]}" -gt 0 ]]; then
  PY_ARGS+=("${PATHS[@]}")
fi

python3 - "${PY_ARGS[@]}" <<'PY'
from __future__ import annotations

import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
mode = sys.argv[2]
base = sys.argv[3]
explicit_paths = [Path(p) for p in sys.argv[4:] if p]

errors: list[str] = []
warnings: list[str] = []

SHELL_ALLOWED = {
    ".", ":", "[", "alias", "awk", "basename", "bash", "break", "cat", "cd",
    "chmod", "command", "continue", "cp", "curl", "cut", "date", "dirname",
    "done", "echo", "env", "eval", "exec", "exit", "export", "false", "fi", "find", "for",
    "gh", "git", "grep", "head", "if", "jq", "kill", "local", "lsof", "mkdir",
    "mise", "mv", "node", "nohup", "open", "pnpm", "printf", "pwd", "python",
    "python3", "read", "readonly", "return", "rg", "rm", "screen", "sed", "set",
    "shift", "shopt", "sleep", "sort", "source", "tail", "tee", "test", "tr",
    "trap", "true", "umask", "uniq", "wc", "while", "xargs",
}
NODE_BUILTINS = {
    "assert", "buffer", "child_process", "crypto", "events", "fs", "http",
    "https", "module", "os", "path", "process", "stream", "url", "util",
}


def rel(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root))
    except Exception:
        return str(path)


def record(path: Path, message: str) -> None:
    target = warnings if mode == "audit" else errors
    target.append(f"{rel(path)}: {message}")


def git_changed_files() -> list[Path]:
    if explicit_paths:
        return [(root / p if not p.is_absolute() else p) for p in explicit_paths]
    if not base:
        try:
            base_ref = subprocess.check_output(
                ["git", "-C", str(root), "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            base_ref = "origin/main"
    else:
        base_ref = base
    commands = [
        ["git", "-C", str(root), "diff", "--name-only", f"{base_ref}..HEAD"],
        ["git", "-C", str(root), "diff", "--name-only"],
        ["git", "-C", str(root), "diff", "--cached", "--name-only"],
        ["git", "-C", str(root), "ls-files", "--others", "--exclude-standard"],
    ]
    files: set[str] = set()
    for cmd in commands:
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        except Exception:
            continue
        files.update(line.strip() for line in out.splitlines() if line.strip())
    return [root / f for f in sorted(files)]


def audit_files() -> list[Path]:
    return sorted(
        p for p in root.glob("scripts/**/*")
        if p.is_file() and p.suffix in {".sh", ".py", ".mjs", ".js", ".cjs"}
    )


def target_files() -> list[Path]:
    candidates = audit_files() if mode == "audit" and not explicit_paths else git_changed_files()
    return [
        p for p in candidates
        if p.is_file()
        and rel(p).startswith("scripts/")
        and p.suffix in {".sh", ".py", ".mjs", ".js", ".cjs"}
    ]


def shell_functions(text: str) -> set[str]:
    names: set[str] = set()
    for line in text.splitlines():
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", line)
        if m:
            names.add(m.group(1))
    return names


def scan_shell(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    functions = shell_functions(text)
    heredoc_until: str | None = None
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if heredoc_until:
            if raw.strip() == heredoc_until:
                heredoc_until = None
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
        if heredoc:
            heredoc_until = heredoc.group(1)
        line = raw.split("#", 1)[0].strip()
        if not line or line.endswith("() {") or line in {"}", "do", "then", "else"}:
            continue
        if "=" in line and re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\+)?=", line):
            continue
        line = re.sub(r"^(if|then|elif|while|until|do|else)\s+", "", line)
        line = line.lstrip("! (")
        token = re.split(r"\s+", line, maxsplit=1)[0]
        token = token.split("=", 1)[0]
        token = token.strip("\"'")
        if not token or token in functions or token in SHELL_ALLOWED:
            continue
        if token in {"case", "esac", ";;"} or token.endswith(")") or token.endswith(";;"):
            continue
        if token.startswith("$") or token.startswith("[[") or token.startswith("(("):
            continue
        record(path, f"line {lineno}: unmanaged shell command {token!r}")


def scan_python(path: Path) -> None:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    stdlib = getattr(sys, "stdlib_module_names", set())
    for node in ast.walk(tree):
        names: list[str] = []
        if isinstance(node, ast.Import):
            names = [alias.name.split(".", 1)[0] for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names = [node.module.split(".", 1)[0]]
        for name in names:
            if name not in stdlib:
                record(path, f"third-party Python import {name!r} is not declared")


def nearest_package_json(path: Path) -> Path | None:
    cur = path.parent
    while cur != root.parent:
        candidate = cur / "package.json"
        if candidate.is_file():
            return candidate
        if cur == root:
            break
        cur = cur.parent
    return None


def package_deps(pkg_path: Path | None) -> set[str]:
    if not pkg_path:
        return set()
    data = json.loads(pkg_path.read_text(encoding="utf-8"))
    deps: set[str] = set()
    for key in ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies"):
        value = data.get(key)
        if isinstance(value, dict):
            deps.update(value)
    return deps


def node_package_name(spec: str) -> str:
    if spec.startswith("@"):
        return "/".join(spec.split("/")[:2])
    return spec.split("/", 1)[0]


def scan_node(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    specs = re.findall(r"(?:import\s+(?:[^'\"]+\s+from\s+)?|require\()\s*['\"]([^'\"]+)['\"]", text)
    deps = package_deps(nearest_package_json(path))
    for spec in specs:
        if spec.startswith((".", "/", "node:")):
            continue
        pkg = node_package_name(spec)
        if pkg in NODE_BUILTINS:
            continue
        if pkg not in deps:
            record(path, f"Node package import {pkg!r} is not declared in owning package.json")


for script in target_files():
    try:
        if script.suffix == ".sh":
            scan_shell(script)
        elif script.suffix == ".py":
            scan_python(script)
        elif script.suffix in {".mjs", ".js", ".cjs"}:
            scan_node(script)
    except Exception as exc:
        record(script, f"scan failed: {exc}")

for item in warnings:
    print(f"ADVISORY: {item}", file=sys.stderr)
for item in errors:
    print(f"ERROR: {item}", file=sys.stderr)

if errors:
    print(f"FAIL: script dependency governance ({len(errors)} issue(s))", file=sys.stderr)
    sys.exit(1)

print("PASS: script dependency governance")
PY
