#!/usr/bin/env bash
# Purpose: 稽核受治理 script prose producer 是否遵從 workspace-config language。
#          會標出外部寫入 callsite 與硬編 prose 預設；producer 必須讀取 workspace
#          language、對具體 body 跑 language/external-write gate，或登錄 callsite 例外。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXCEPTIONS_PATH=""
MODE="repo"
QUIET=0
PATHS=()

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/validate-config-driven-authoring.sh [--root <repo>] [--exceptions <json>] [--quiet] [--path <file> ...]

稽核 framework scripts 中必須遵從 workspace language 的 external-write /
generated-prose callsite。每筆 finding 都需要相鄰 language gate、
workspace-config language read，或 callsite-level exception。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="${2:-}"; shift 2 ;;
    --exceptions) EXCEPTIONS_PATH="${2:-}"; shift 2 ;;
    --path) PATHS+=("${2:-}"); MODE="paths"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
if [[ -z "$EXCEPTIONS_PATH" ]]; then
  EXCEPTIONS_PATH="$ROOT_DIR/scripts/lib/config-driven-authoring-exceptions.json"
fi

python3 - "$ROOT_DIR" "$EXCEPTIONS_PATH" "$MODE" "$QUIET" "${PATHS[@]+"${PATHS[@]}"}" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
exceptions_path = Path(sys.argv[2])
mode = sys.argv[3]
quiet = sys.argv[4] == "1"
path_args = sys.argv[5:]

EXTERNAL_WRITE_PATTERNS = [
    (re.compile(r"\bgh\s+pr\s+(comment|create)\b"), "github-pr-write"),
    (re.compile(r"\bgh\s+release\s+(create|edit)\b"), "github-release-write"),
]

INLINE_PROSE_PATTERNS = [
    (re.compile(r"--(title|body)\s+(['\"])(?!\$)(?=[^'\"]*[A-Za-z])[^'\"]+\2"), "inline-external-prose"),
    (re.compile(r"released [^'\"]*(bundled into the release|orphan task PR cleaned)", re.I), "hardcoded-release-prose"),
    (re.compile(r"\[[^\]]+\]\s+framework release", re.I), "hardcoded-release-title"),
]

GUARD_PATTERNS = [
    re.compile(r"workspace-config\.yaml"),
    re.compile(r"validate-language-policy\.sh"),
    re.compile(r"polaris-external-write-gate\.sh"),
    re.compile(r"gate-pr-language\.sh"),
    re.compile(r"POLARIS_EXTERNAL_WRITE_WRITER"),
    re.compile(r"workspace language", re.I),
    re.compile(r"language-aware", re.I),
]


def rel(path: Path) -> str:
    return path.resolve().relative_to(root).as_posix()


def load_exceptions() -> list[dict]:
    if not exceptions_path.is_file():
        return []
    data = json.loads(exceptions_path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise SystemExit(f"FAIL: exceptions schema_version must be 1: {exceptions_path}")
    entries = data.get("exceptions")
    if not isinstance(entries, list):
        raise SystemExit(f"FAIL: exceptions must be a list: {exceptions_path}")
    out = []
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SystemExit(f"FAIL: exceptions[{idx}] must be an object")
        for key in ("path", "contains", "owner_dp", "reason"):
            if not isinstance(entry.get(key), str) or not entry[key].strip():
                raise SystemExit(f"FAIL: exceptions[{idx}].{key} must be a non-empty string")
        if entry["path"].endswith("/**") or entry["path"] in {"scripts/**", "scripts/"}:
            raise SystemExit(f"FAIL: exceptions[{idx}] broad path exception is forbidden: {entry['path']}")
        out.append(entry)
    return out


def target_files() -> list[Path]:
    if mode == "paths":
        return [root / p for p in path_args]
    return sorted(
        p for p in (root / "scripts").rglob("*")
        if p.is_file()
        and p.suffix in {".sh", ".py", ".mjs", ".ts"}
        and "/selftests/" not in p.as_posix()
        and not p.name.endswith("-selftest.sh")
    )


def has_file_guard(text: str) -> bool:
    return any(pattern.search(text) for pattern in GUARD_PATTERNS)


def exception_matches(exceptions: list[dict], rel_path: str, line: str) -> bool:
    for entry in exceptions:
        if entry["path"] == rel_path and entry["contains"] in line:
            return True
    return False


def is_comment_or_blank(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def line_risks(line: str) -> list[str]:
    if is_comment_or_blank(line):
        return []
    labels = [label for pattern, label in EXTERNAL_WRITE_PATTERNS if pattern.search(line)]
    writes_external_prose = bool(labels) and (
        "--title" in line or "--body" in line or "--notes" in line or "--message" in line
    )
    prose_labels = [label for pattern, label in INLINE_PROSE_PATTERNS if pattern.search(line)]
    if writes_external_prose:
        labels.extend(prose_labels)
        return labels
    return prose_labels


exceptions = load_exceptions()
findings = []
for path in target_files():
    if not path.is_file():
        findings.append(f"{path}: target file missing")
        continue
    try:
        rel_path = rel(path)
    except ValueError:
        findings.append(f"{path}: target file is outside repo root")
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    file_guarded = has_file_guard(text)
    for lineno, line in enumerate(text.splitlines(), start=1):
        matched = line_risks(line)
        if not matched:
            continue
        if file_guarded:
            continue
        if exception_matches(exceptions, rel_path, line):
            continue
        findings.append(
            f"{rel_path}:{lineno}: {','.join(matched)} lacks workspace language read, "
            "language/external-write gate, or callsite-level exception"
        )

if findings:
    print("FAIL: config-driven authoring audit", file=sys.stderr)
    for finding in findings:
        print(f"  - {finding}", file=sys.stderr)
    raise SystemExit(1)

if not quiet:
    print("PASS: config-driven authoring audit")
PY
