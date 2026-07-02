#!/usr/bin/env bash
# Purpose: validate framework script structure rules that sit above header and categorization gates.
set -euo pipefail

PREFIX="[validate-framework-script-structure]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="diff"
BASE="HEAD"
FILES=()

usage() {
  cat >&2 <<'USAGE'
Usage:
  validate-framework-script-structure.sh [--mode diff|audit] [--base <ref>] [--root <dir>] [--file <path>]...

Checks changed framework shell/Python scripts and script-governance handbook text
for structure rules that reduce hard-coded, hard-to-review script growth.
USAGE
}

fail() {
  echo "$PREFIX FAIL: $*" >&2
  exit 1
}

note_violation() {
  local path="$1"
  local reason="$2"
  printf '%s\t%s\n' "$path" "$reason"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#--mode=}"; shift ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; shift ;;
    --root) ROOT_DIR="${2:-}"; shift 2 ;;
    --root=*) ROOT_DIR="${1#--root=}"; shift ;;
    --file) FILES+=("${2:-}"); shift 2 ;;
    --file=*) FILES+=("${1#--file=}"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

case "$MODE" in
  diff|audit) ;;
  *) echo "$PREFIX invalid --mode: $MODE" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"

is_target_file() {
  case "$1" in
    *.sh|*.py|script-governance.md|*/script-governance.md) return 0 ;;
    *) return 1 ;;
  esac
}

discover_files() {
  if [[ ${#FILES[@]} -gt 0 ]]; then
    printf '%s\n' "${FILES[@]}"
    return 0
  fi

  if [[ "$MODE" == "audit" ]]; then
    git -C "$ROOT_DIR" ls-files \
      'scripts/*.sh' 'scripts/*.py' 'scripts/**/*.sh' 'scripts/**/*.py' \
      '.claude/**/*.sh' '.claude/**/*.py' \
      '.claude/rules/handbook/framework/script-governance.md'
    return 0
  fi

  {
    git -C "$ROOT_DIR" diff --name-only --diff-filter=ACMRT "$BASE"...HEAD -- \
      'scripts/*.sh' 'scripts/*.py' 'scripts/**/*.sh' 'scripts/**/*.py' \
      '.claude/**/*.sh' '.claude/**/*.py' \
      '.claude/rules/handbook/framework/script-governance.md' 2>/dev/null || true
    git -C "$ROOT_DIR" ls-files --others --exclude-standard -- \
      'scripts/*.sh' 'scripts/*.py' 'scripts/**/*.sh' 'scripts/**/*.py' \
      '.claude/**/*.sh' '.claude/**/*.py' \
      '.claude/rules/handbook/framework/script-governance.md' 2>/dev/null || true
  } | sort -u
}

check_shellcheck_suppression() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
bad = []
for index, line in enumerate(lines):
    if not line.lstrip().startswith("# shellcheck disable="):
        continue
    window = lines[max(0, index - 2): index + 1]
    if not any("POLARIS_SHELLCHECK_JUSTIFICATION:" in item for item in window):
        bad.append(index + 1)
if bad:
    print(",".join(str(item) for item in bad))
    raise SystemExit(1)
PY
}

check_python_cli() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
is_cli = (
    "if __name__ == \"__main__\"" in text
    or "if __name__ == '__main__'" in text
    or "sys.argv" in text
)
if not is_cli:
    raise SystemExit(0)
if "argparse.ArgumentParser" not in text:
    print("missing argparse.ArgumentParser")
    raise SystemExit(1)
if "allow_abbrev=False" not in text:
    print("missing allow_abbrev=False")
    raise SystemExit(1)
PY
}

check_handbook() {
  local path="$1"
  local missing=()
  local token
  local tokens=(
    "Google Shell Style Guide"
    "ShellCheck"
    "PEP 8"
    "argparse"
    "table-driven"
    "shared source"
    "suppression"
    "wrapper"
    "validate-framework-script-structure.sh"
  )

  for token in "${tokens[@]}"; do
    if ! grep -Fq "$token" "$path"; then
      missing+=("$token")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s\n' "${missing[*]}"
    return 1
  fi
}

violations_tmp="$(mktemp -t framework-script-structure.XXXXXX)"
trap 'rm -f "$violations_tmp"' EXIT

while IFS= read -r raw_path; do
  [[ -n "$raw_path" ]] || continue
  if [[ "$raw_path" = /* ]]; then
    abs_path="$raw_path"
    rel_path="$(python3 - "$ROOT_DIR" "$abs_path" <<'PY'
from pathlib import Path
import os
import sys
root = Path(sys.argv[1]).resolve()
path = Path(sys.argv[2]).resolve()
try:
    print(path.relative_to(root))
except ValueError:
    print(path.name)
PY
)"
  else
    rel_path="$raw_path"
    abs_path="$ROOT_DIR/$raw_path"
  fi
  [[ -f "$abs_path" ]] || continue
  is_target_file "$rel_path" || continue

  case "$rel_path" in
    *.sh)
      if ! out="$(check_shellcheck_suppression "$abs_path" 2>&1)"; then
        note_violation "$rel_path" "ShellCheck suppression missing POLARIS_SHELLCHECK_JUSTIFICATION near line(s): $out" >>"$violations_tmp"
      fi
      ;;
    *.py)
      if ! out="$(check_python_cli "$abs_path" 2>&1)"; then
        note_violation "$rel_path" "Python CLI must use argparse.ArgumentParser(... allow_abbrev=False): $out" >>"$violations_tmp"
      fi
      ;;
  esac

  if [[ "$(basename "$rel_path")" == "script-governance.md" ]]; then
    if ! out="$(check_handbook "$abs_path" 2>&1)"; then
      note_violation "$rel_path" "handbook missing required structure terms: $out" >>"$violations_tmp"
    fi
  fi
done < <(discover_files)

if [[ "$MODE" == "audit" ]]; then
  python3 - "$violations_tmp" "$ROOT_DIR" <<'PY'
import json
from pathlib import Path
import sys

violations_file = Path(sys.argv[1])
root = sys.argv[2]
items = []
if violations_file.exists():
    for raw in violations_file.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        path, _, reason = raw.partition("\t")
        items.append({"path": path, "reason": reason})
print(json.dumps({
    "schema_version": 1,
    "mode": "audit",
    "root": root,
    "violation_count": len(items),
    "violations": items,
}, ensure_ascii=False, indent=2))
PY
  exit 0
fi

if [[ -s "$violations_tmp" ]]; then
  cat "$violations_tmp" >&2
  fail "framework script structure violations"
fi

echo "PASS: validate-framework-script-structure"
