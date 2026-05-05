#!/usr/bin/env bash
set -euo pipefail

PREFIX="[polaris behavior-backfill]"
ROOT=""
QUEUE=""
MODE="dry-run"

usage() {
  cat >&2 <<'USAGE'
Usage:
  backfill-behavior-contracts.sh --root <specs-root> [--write|--check] [--queue <path>]

Default mode is dry-run. --write modifies high-confidence task.md files and writes
the planner decision queue. --check passes only when every missing contract is
either backfilled or listed in the decision queue.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --queue) QUEUE="${2:-}"; shift 2 ;;
    --write) MODE="write"; shift ;;
    --check) MODE="check"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "$PREFIX --root is required and must exist" >&2
  exit 64
fi

ROOT="$(cd "$ROOT" && pwd)"
if [[ -z "$QUEUE" ]]; then
  QUEUE="$ROOT/design-plans/DP-109-behavior-contract-before-after-gate/artifacts/behavior-contract-backfill-queue.md"
fi

python3 - "$ROOT" "$QUEUE" "$MODE" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
queue_path = Path(sys.argv[2])
mode = sys.argv[3]

def has_behavior_contract(text: str) -> bool:
    return "behavior_contract:" in text

def is_archive(path: Path) -> bool:
    return "archive" in path.parts

def task_files() -> list[Path]:
    results = []
    for path in root.rglob("*.md"):
        if is_archive(path):
            continue
        parts = path.parts
        if "tasks" not in parts:
            continue
        results.append(path)
    return sorted(results)

def frontmatter_bounds(lines: list[str]) -> tuple[int, int] | None:
    if not lines or lines[0].strip() != "---":
        return None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            return (0, idx)
    return None

def scalar_from_header(text: str, key: str) -> str:
    pattern = re.compile(rf"\|\s*{re.escape(key)}\s*\|\s*([^|]+?)\s*\|")
    match = pattern.search(text)
    return match.group(1).strip() if match else ""

def heading(text: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return ""

def classify(path: Path, text: str) -> dict:
    lower = text.lower()
    filename = path.name
    repo = scalar_from_header(text, "Repo")
    level = ""
    level_match = re.search(r"\*\*Level\*\*:\s*([^\n]+)", text)
    if level_match:
        level = level_match.group(1).strip().lower()

    if filename.startswith("V"):
        return {
            "action": "backfill",
            "contract": {"applies": False, "reason": "verification task；使用者行為意圖由 AC 驗收步驟承載"},
            "confidence": "high",
        }
    if repo == "polaris-framework" or "framework work order" in lower or "polaris-framework" in lower:
        return {
            "action": "backfill",
            "contract": {"applies": False, "reason": "framework/static work order；不涉及產品 runtime 行為"},
            "confidence": "high",
        }
    if level in {"static", "build"} and re.search(r"\b(schema|validator|reference|docs|script|release|metadata|selftest)\b", lower):
        return {
            "action": "backfill",
            "contract": {"applies": False, "reason": "static/build task；不涉及使用者可見 runtime 行為"},
            "confidence": "high",
        }

    summary = heading(text)
    if re.search(r"figma|design target|visual target|設計稿", lower):
        return {
            "action": "backfill",
            "contract": {
                "applies": True,
                "mode": "visual_target",
                "source_of_truth": "figma",
                "fixture_policy": "mockoon_required",
                "baseline_ref": "develop",
                "flow": summary or path.stem,
                "assertions": ["after screen matches declared visual target"],
                "allowed_differences": [],
            },
            "confidence": "medium",
        }
    if re.search(r"pm flow|pm-provided|operation flow|操作流程", lower):
        return {
            "action": "backfill",
            "contract": {
                "applies": True,
                "mode": "pm_flow",
                "source_of_truth": "pm_flow",
                "fixture_policy": "mockoon_required",
                "baseline_ref": "none",
                "flow": summary or path.stem,
                "assertions": ["PM flow assertions pass"],
                "allowed_differences": [],
            },
            "confidence": "medium",
        }
    if re.search(r"replacement|replace|migration|migrate|refactor|remove legacy|替換|重構|移除 legacy|改造", lower):
        return {
            "action": "backfill",
            "contract": {
                "applies": True,
                "mode": "parity",
                "source_of_truth": "existing_behavior",
                "fixture_policy": "mockoon_required",
                "baseline_ref": "develop",
                "flow": summary or path.stem,
                "assertions": ["existing user-visible behavior remains stable"],
                "allowed_differences": [],
            },
            "confidence": "medium",
        }

    return {
        "action": "queue",
        "reason": "現有 task.md 無法高信心判斷是否有使用者可見 runtime 行為",
        "confidence": "low",
    }

def yaml_scalar(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value == []:
        return "[]"
    text = str(value).replace('"', '\\"')
    return f'"{text}"'

def contract_block(contract: dict, indent: str = "") -> list[str]:
    lines = [f"{indent}verification:", f"{indent}  behavior_contract:"]
    for key, value in contract.items():
        if isinstance(value, list):
            if not value:
                lines.append(f"{indent}    {key}: []")
            else:
                lines.append(f"{indent}    {key}:")
                for item in value:
                    lines.append(f"{indent}      - {yaml_scalar(item)}")
        else:
            lines.append(f"{indent}    {key}: {yaml_scalar(value)}")
    return lines

def insert_contract(path: Path, text: str, contract: dict) -> str:
    lines = text.splitlines()
    bounds = frontmatter_bounds(lines)
    if bounds is None:
        raise ValueError(f"missing frontmatter: {path}")
    _, end = bounds
    block = contract_block(contract)
    new_lines = lines[:end] + block + lines[end:]
    return "\n".join(new_lines) + "\n"

items = []
for path in task_files():
    text = path.read_text(encoding="utf-8")
    rel = str(path.relative_to(root))
    if has_behavior_contract(text):
        items.append({"path": rel, "status": "present"})
        continue
    classification = classify(path, text)
    record = {"path": rel, **classification}
    items.append(record)
    if mode == "write" and classification["action"] == "backfill":
        path.write_text(insert_contract(path, text, classification["contract"]), encoding="utf-8")

queued = [item for item in items if item.get("action") == "queue"]
backfills = [item for item in items if item.get("action") == "backfill"]
present = [item for item in items if item.get("status") == "present"]

def write_queue() -> None:
    queue_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Behavior Contract Backfill Decision Queue",
        "",
        f"- Generated at: `{dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')}`",
        f"- Root: `{root}`",
        f"- Queued items: `{len(queued)}`",
        "",
    ]
    if queued:
        lines.extend(["## Planner Decisions Required", "", "| Task | Reason |", "|------|--------|"])
        for item in queued:
            lines.append(f"| `{item['path']}` | {item['reason']} |")
    else:
        lines.append("No planner decisions required.")
    queue_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

if mode == "write":
    write_queue()

if mode == "check":
    queue_text = queue_path.read_text(encoding="utf-8") if queue_path.exists() else ""
    missing_from_queue = [item for item in queued if f"`{item['path']}`" not in queue_text]
    if missing_from_queue:
        print(json.dumps({"status": "FAIL", "missing_from_queue": missing_from_queue}, ensure_ascii=False, indent=2))
        raise SystemExit(1)

summary = {
    "mode": mode,
    "root": str(root),
    "queue": str(queue_path),
    "total": len(items),
    "present": len(present),
    "backfill_candidates": len(backfills),
    "queued": len(queued),
}
print(json.dumps(summary, ensure_ascii=False, indent=2))
PY
