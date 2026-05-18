#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT_DIR/scripts/tool-direct-call-inventory.txt"
CHECK=false

usage() {
  cat <<'USAGE'
Usage: bash scripts/tool-direct-call-inventory.sh [--check] [--output <path>]

Scans Tier A Polaris scripts for direct tool calls and emits a TSV baseline:
path, line, tool, owner, install_authority, runtime_profile, goes_to_mise.
USAGE
}

OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "tool-direct-call-inventory: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

export PYTHON_BIN="${PYTHON_BIN:-$(command -v python3)}"
# shellcheck source=lib/tool-attribution.sh
source "$ROOT_DIR/scripts/lib/tool-attribution.sh"

field() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import json
import sys
value = json.loads(sys.argv[1]).get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

emit_inventory() {
  "$PYTHON_BIN" - "$ROOT_DIR" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
files = [
    "scripts/polaris-bootstrap.sh",
    "scripts/polaris-doctor.sh",
    "scripts/doctor-mise-check.sh",
    "scripts/polaris-pr-create.sh",
    "scripts/run-governed-script-tests.sh",
]
tools = {"mise", "gh", "node", "pnpm", "jq", "rg", "python3"}
allowed_commands = {
    ".", ":", "[", "bash", "break", "case", "cd", "command", "continue", "do",
    "done", "echo", "elif", "else", "esac", "exit", "export", "false", "fi",
    "for", "function", "if", "local", "printf", "pwd", "read", "return", "set",
    "shift", "source", "then", "true", "while",
    "polaris_require_delivery_tool", "polaris_require_mise_tool",
    "polaris_with_runtime_tools",
}

def classify(tool: str) -> dict:
    raw = subprocess.check_output(
        ["bash", "-lc", f"source {root}/scripts/lib/tool-attribution.sh; polaris_classify_tool {tool}"],
        text=True,
    )
    return json.loads(raw)

def shell_functions(text: str) -> set[str]:
    names = set()
    for line in text.splitlines():
        match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", line)
        if match:
            names.add(match.group(1))
    return names

print("path\tline\ttool\towner\tinstall_authority\truntime_profile\tgoes_to_mise")
for rel_path in files:
    path = root / rel_path
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")
    functions = shell_functions(text)
    heredoc_until = None
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if heredoc_until:
            if raw.strip() == heredoc_until:
                heredoc_until = None
            continue
        heredoc = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", raw)
        if heredoc:
            heredoc_until = heredoc.group(1)
            continue
        line = raw.split("#", 1)[0].strip()
        if not line or line.endswith("() {") or line in {"}", "do", "then", "else"}:
            continue
        if "=" in line and re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\+)?=", line):
            continue
        token = re.sub(r"^(if|then|elif|while|until|do|else)\s+", "", line).lstrip("! (")
        token = re.split(r"\s+", token, maxsplit=1)[0].split("=", 1)[0].strip("\"'")
        if not token or token in allowed_commands or token in functions:
            continue
        if token not in tools:
            continue
        attr = classify(token)
        print(
            f"{rel_path}\t{lineno}\t{token}\t{attr.get('owner', '')}\t"
            f"{attr.get('install_authority', '')}\t{attr.get('runtime_profile', '')}\t"
            f"{str(attr.get('goes_to_mise', '')).lower()}"
        )
PY
}

if [[ -n "$OUTPUT" ]]; then
  emit_inventory > "$OUTPUT"
  exit 0
fi

if [[ "$CHECK" == true ]]; then
  tmp="$(mktemp -t polaris-tool-inventory-XXXXXX)"
  trap 'rm -f "$tmp"' EXIT
  emit_inventory > "$tmp"
  if ! cmp -s "$tmp" "$BASELINE"; then
    echo "tool-direct-call-inventory: baseline drift detected" >&2
    diff -u "$BASELINE" "$tmp" >&2 || true
    exit 1
  fi
  echo "tool-direct-call-inventory PASS"
  exit 0
fi

emit_inventory
