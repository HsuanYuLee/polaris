#!/usr/bin/env bash
# validate-breakdown-ready.sh
#
# Breakdown-to-engineering readiness gate. It runs after task.md schema
# validation and before breakdown hands work to engineering.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: validate-breakdown-ready.sh <task.md|tasks_dir>
       validate-breakdown-ready.sh --self-test

Validates task.md readiness before breakdown hands work to engineering:
- task.md schema passes
- task folder dependency gate passes
- Allowed Files are machine-matchable path/glob tokens
- Gate Closure Matrix is present and names scope/test/verify/ci-local gates
- Gate rows expose pass conditions and ownership/decisions
EOF
}

run_self_test() {
  local tasks valid invalid invalid_matrix
  SELFTEST_TMP="$(mktemp -d -t validate-breakdown-ready.XXXXXX)"
  trap 'rm -rf "${SELFTEST_TMP:-}"' EXIT
  tasks="$SELFTEST_TMP/tasks"
  mkdir -p "$tasks"
  valid="$tasks/T1.md"
  invalid="$tasks/T2.md"
  invalid_matrix="$tasks/T3.md"

  cat > "$valid" <<'MD'
---
title: "T1: 建立 breakdown readiness gate (2 pt)"
---

# T1: 建立 breakdown readiness gate (2 pt)

> Source: DP-082 | Task: DP-082-T1 | JIRA: N/A | Repo: work

## Operational Context

| 欄位 | 值 |
|------|-----|
| Source type | dp |
| Source ID | DP-082 |
| Task ID | DP-082-T1 |
| JIRA key | N/A |
| Test sub-tasks | N/A - framework work order |
| AC 驗收單 | N/A - framework work order |
| Base branch | main |
| Task branch | task/DP-082-T1-breakdown-readiness-gate |
| References to load | - `.claude/skills/references/task-md-schema.md` |

## Verification Handoff

AC 驗證不在本 task 範圍。

## 目標

新增 breakdown readiness gate。

## 改動範圍

| 檔案 | 動作 | 說明 |
|------|------|------|
| `scripts/validate-breakdown-ready.sh` | create | readiness gate |

## Allowed Files

- `scripts/validate-breakdown-ready.sh`
- `scripts/validate-breakdown-ready-selftest.sh`
- `VERSION`

## Gate Closure Matrix

| Gate | Applies | Pass condition | Owner / decision |
|------|---------|----------------|------------------|
| scope | yes | Allowed Files 全為 path/glob | breakdown |
| test | yes | selftest pass | breakdown |
| verify | yes | smoke pass | breakdown |
| ci-local | no | N/A | no repo CI required |

## 估點理由

2 pt，單一 validator 與 selftest。

## 測試計畫（code-level）

- selftest covers valid and invalid task.md。

## Test Command

```bash
echo test
```

## Test Environment

- **Level**: static
- **Dev env config**: `workspace-config.yaml` → `projects[work].dev_environment`
- **Fixtures**: N/A
- **Runtime verify target**: N/A
- **Env bootstrap command**: N/A

## Verify Command

```bash
echo verify
```
MD

  sed 's/`scripts\/validate-breakdown-ready.sh`/上述檔案的 test 檔/' "$valid" > "$invalid"
  sed 's/| verify | yes | smoke pass | breakdown |/| verify | yes |  |  |/' "$valid" > "$invalid_matrix"

  bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$valid" >/dev/null || {
    echo "self-test failed: valid task did not pass" >&2
    return 1
  }
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$invalid" >/dev/null 2>&1; then
    echo "self-test failed: natural-language Allowed Files entry passed" >&2
    return 1
  fi
  if bash "$SCRIPT_DIR/validate-breakdown-ready.sh" "$invalid_matrix" >/dev/null 2>&1; then
    echo "self-test failed: incomplete Gate Closure Matrix row passed" >&2
    return 1
  fi
  echo "validate-breakdown-ready self-test PASS"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

python3 - "$SCRIPT_DIR" "$1" <<'PY'
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

script_dir = Path(sys.argv[1])
target = Path(sys.argv[2])
parse_task_md = script_dir / "parse-task-md.sh"
validate_task_md = script_dir / "validate-task-md.sh"
validate_task_md_deps = script_dir / "validate-task-md-deps.sh"


def section(text: str, heading: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    in_section = False
    for line in lines:
        if line == heading:
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            out.append(line)
    return "\n".join(out)


def path_token(raw: str) -> bool:
    value = raw.strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    if not value:
        return False
    if any(ch.isspace() for ch in value):
        return False
    if re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", value):
        return False
    if value.startswith("-"):
        return False
    if value in {".", ".."} or "/../" in f"/{value}/":
        return False
    if value.startswith(("http://", "https://")):
        return False
    return bool(re.match(r"^[^\s`'\"]+$", value))


def parse_allowed(file: Path) -> list[str]:
    proc = subprocess.run(
        [str(parse_task_md), "--field", "allowed_files", str(file)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return []
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def task_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(path.glob("T*.md"))
    raise FileNotFoundError(path)


def table_rows(markdown: str) -> list[list[str]]:
    rows: list[list[str]] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or "|" not in stripped[1:]:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if cells and all(re.match(r"^:?-{3,}:?$", cell.replace(" ", "")) for cell in cells):
            continue
        rows.append(cells)
    return rows


def gate_rows(markdown: str) -> dict[str, list[str]]:
    rows = table_rows(markdown)
    if not rows:
        return {}
    header = [cell.lower() for cell in rows[0]]
    gate_idx = next((idx for idx, cell in enumerate(header) if "gate" in cell), 0)
    out: dict[str, list[str]] = {}
    for row in rows[1:]:
        if gate_idx >= len(row):
            continue
        gate = row[gate_idx].strip().lower()
        for required in ("scope", "test", "verify", "ci-local"):
            if gate == required or gate.startswith(f"{required} "):
                out[required] = row
    return out


def has_meaningful_cell(row: list[str], idx: int) -> bool:
    if idx >= len(row):
        return False
    value = row[idx].strip()
    return bool(value and value not in {"-", "--"})


def validate_one(file: Path) -> list[str]:
    errors: list[str] = []
    normalized = str(file)
    if "/tasks/pr-release/" in normalized or "/archive/" in normalized:
        return errors
    if not re.match(r"^T[0-9]+[a-z]*\.md$", file.name):
        return errors

    schema = subprocess.run(
        [str(validate_task_md), str(file)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if schema.returncode != 0:
        errors.append(f"{file}: validate-task-md.sh failed; fix schema before readiness handoff")

    allowed = parse_allowed(file)
    if not allowed:
        errors.append(f"{file}: Allowed Files has no entries")
    for entry in allowed:
        if not path_token(entry):
            errors.append(f"{file}: Allowed Files entry is not a machine-matchable path/glob token: {entry}")

    text = file.read_text(encoding="utf-8")
    matrix = section(text, "## Gate Closure Matrix")
    if not matrix.strip():
        errors.append(f"{file}: missing non-empty ## Gate Closure Matrix")
    else:
        lower = matrix.lower()
        rows = table_rows(matrix)
        header = [cell.lower() for cell in rows[0]] if rows else []
        pass_idx = next((idx for idx, cell in enumerate(header) if "pass condition" in cell or "通過條件" in cell), 2)
        owner_idx = next((idx for idx, cell in enumerate(header) if "owner" in cell or "decision" in cell or "歸屬" in cell or "決策" in cell), 3)
        gates = gate_rows(matrix)
        for gate in ("scope", "test", "verify", "ci-local"):
            row = gates.get(gate)
            if row is None:
                errors.append(f"{file}: Gate Closure Matrix must mention '{gate}' gate")
                continue
            if not has_meaningful_cell(row, pass_idx):
                errors.append(f"{file}: Gate Closure Matrix '{gate}' row must include a pass condition")
            if not has_meaningful_cell(row, owner_idx):
                errors.append(f"{file}: Gate Closure Matrix '{gate}' row must include owner/decision")
        if "n/a" in lower and not re.search(r"n/a.{3,}", lower):
            errors.append(f"{file}: Gate Closure Matrix N/A entries must include a reason")

    return errors


if not target.exists():
    print(f"validate-breakdown-ready: path not found: {target}", file=sys.stderr)
    raise SystemExit(2)

all_errors: list[str] = []
for file in task_files(target):
    all_errors.extend(validate_one(file))

if target.is_dir() and validate_task_md_deps.exists():
    deps = subprocess.run(
        [str(validate_task_md_deps), str(target)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if deps.returncode != 0:
        all_errors.append(f"{target}: validate-task-md-deps.sh failed; fix dependency closure before readiness handoff")

if all_errors:
    print("validate-breakdown-ready.sh FAIL", file=sys.stderr)
    for error in all_errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"validate-breakdown-ready.sh PASS - {target}")
PY
