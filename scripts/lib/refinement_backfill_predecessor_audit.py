#!/usr/bin/env python3
"""Backfill or report refinement predecessor_audit fields."""
from __future__ import annotations

import os
import sys
from pathlib import Path

USAGE = """Usage:
  backfill-refinement-predecessor-audit.sh --root <workspace_root> [--mode report|apply|check] [--format summary|json]

Modes:
  report  Print classification output only.
  apply   Backfill predecessor_audit: [] for safe_empty artifacts.
  check   Exit non-zero when safe_empty / needs_review / schema_error remains.
"""

def fail_usage(message: str | None = None, code: int = 64) -> None:
    if message:
        print(message, file=sys.stderr)
    print(USAGE, end="", file=sys.stderr)
    raise SystemExit(code)

args=sys.argv[1:]
root_arg=""
mode="report"
fmt="summary"
i=0
while i < len(args):
    arg=args[i]
    if arg in {"--root", "--mode", "--format"}:
        value=args[i+1] if i+1 < len(args) else ""
        if arg == "--root": root_arg=value
        elif arg == "--mode": mode=value
        else: fmt=value
        i += 2
    elif arg in {"-h", "--help"}:
        print(USAGE, end="", file=sys.stderr)
        raise SystemExit(0)
    else:
        fail_usage(f"unknown argument: {arg}")
if not root_arg or not Path(root_arg).is_dir():
    print("--root is required and must exist", file=sys.stderr)
    raise SystemExit(64)
if mode not in {"report", "apply", "check"}:
    print("--mode must be one of: report, apply, check", file=sys.stderr)
    raise SystemExit(64)
if fmt not in {"summary", "json"}:
    print("--format must be one of: summary, json", file=sys.stderr)
    raise SystemExit(64)
root_arg=str(Path(root_arg).resolve())
validator=Path(__file__).resolve().parents[1] / "validate-refinement-json.sh"
sys.argv=[sys.argv[0], root_arg, mode, fmt, str(validator)]

import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
mode = sys.argv[2]
fmt = sys.argv[3]
validator = Path(sys.argv[4])
specs_root = root / "docs-manager" / "src" / "content" / "docs" / "specs"

if not validator.is_file():
    print(f"validator not found: {validator}", file=sys.stderr)
    raise SystemExit(64)

missing_pred_msg = "missing required field 'predecessor_audit' (expected array; use [] if none)"
status_order = ["already_ok", "safe_empty", "needs_review", "schema_error"]
strong_terms = (
    "predecessor",
    "supersed",
    "absorb",
    "carry forward",
    "carry-forward",
    "承接",
    "沿用",
    "延續",
    "繼承",
    "吸收",
    "沿襲",
    "前身",
)
id_pattern = re.compile(r"\b(?:DP-\d{3}|[A-Z][A-Z0-9]+-\d+)\b")


def canonical_paths() -> list[Path]:
    if specs_root.is_dir():
        search_root = specs_root
    else:
        search_root = root
    results: list[Path] = []
    for path in sorted(search_root.rglob("refinement.json")):
        if "archive" in path.parts:
            continue
        results.append(path)
    return results


def validate(path: Path) -> tuple[int, list[str], str]:
    proc = subprocess.run(
        [str(validator), str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    errors = []
    for line in proc.stderr.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            errors.append(stripped[2:])
    return proc.returncode, errors, proc.stderr.strip()


def current_spec_id(data: dict) -> str | None:
    source = data.get("source")
    if isinstance(source, dict):
        source_id = source.get("id")
        if isinstance(source_id, str) and source_id.strip():
            return source_id.strip()
    epic = data.get("epic")
    if isinstance(epic, str) and epic.strip():
        return epic.strip()
    return None


def hint_entries(data: object, current_id: str | None, path: str = "") -> list[dict]:
    hints: list[dict] = []
    if isinstance(data, dict):
        for key, value in data.items():
            child_path = f"{path}.{key}" if path else key
            hints.extend(hint_entries(value, current_id, child_path))
        return hints
    if isinstance(data, list):
        for index, value in enumerate(data):
            child_path = f"{path}[{index}]"
            hints.extend(hint_entries(value, current_id, child_path))
        return hints
    if not isinstance(data, str):
        return hints

    lower = data.lower()
    if not any(term in lower for term in strong_terms):
        return hints

    ids = sorted({match.group(0) for match in id_pattern.finditer(data)})
    other_ids = [item for item in ids if item != current_id]
    if not other_ids:
        return hints

    hints.append(
        {
            "field": path,
            "related_spec_ids": other_ids,
            "excerpt": data.strip(),
        }
    )
    return hints


def classify(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - exercised in selftest via invalid fixture
        return {
            "path": str(path),
            "status": "schema_error",
            "errors": [f"json_load_error: {exc}"],
        }

    if not isinstance(data, dict):
        return {
            "path": str(path),
            "status": "schema_error",
            "errors": ["refinement.json root must be an object"],
        }

    rc, errors, raw_error = validate(path)
    if rc == 0:
        return {
            "path": str(path),
            "status": "already_ok",
            "errors": [],
            "hints": [],
        }

    if rc != 1:
        detail = errors or [raw_error or f"validator_exit={rc}"]
        return {
            "path": str(path),
            "status": "schema_error",
            "errors": detail,
        }

    only_missing_predecessor = errors == [missing_pred_msg]
    if not only_missing_predecessor:
        return {
            "path": str(path),
            "status": "schema_error",
            "errors": errors,
        }

    current_id = current_spec_id(data)
    hints = hint_entries(data, current_id)
    if hints:
        return {
            "path": str(path),
            "status": "needs_review",
            "errors": errors,
            "hints": hints,
        }

    return {
        "path": str(path),
        "status": "safe_empty",
        "errors": errors,
        "hints": [],
    }


def apply_backfill(path: Path) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    if "predecessor_audit" in data:
        return False
    data["predecessor_audit"] = []
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return True


records = [classify(path) for path in canonical_paths()]
applied_paths: list[str] = []

if mode == "apply":
    for record in records:
        if record["status"] != "safe_empty":
            continue
        if apply_backfill(Path(record["path"])):
            applied_paths.append(record["path"])
    records = [classify(path) for path in canonical_paths()]

summary = {
    "root": str(root),
    "scan_scope": "canonical_non_archive_refinement",
    "mode": mode,
    "format": fmt,
    "total": len(records),
    "already_ok": sum(1 for item in records if item["status"] == "already_ok"),
    "safe_empty": sum(1 for item in records if item["status"] == "safe_empty"),
    "needs_review": sum(1 for item in records if item["status"] == "needs_review"),
    "schema_error": sum(1 for item in records if item["status"] == "schema_error"),
    "applied": len(applied_paths),
}

payload = {
    "summary": summary,
    "records": records,
    "applied_paths": applied_paths,
}

if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    print(f"root={summary['root']}")
    print(f"scan_scope={summary['scan_scope']}")
    print(f"mode={summary['mode']}")
    print(f"total={summary['total']}")
    print(f"already_ok={summary['already_ok']}")
    print(f"safe_empty={summary['safe_empty']}")
    print(f"needs_review={summary['needs_review']}")
    print(f"schema_error={summary['schema_error']}")
    print(f"applied={summary['applied']}")
    for status in status_order:
        print(f"[{status}]")
        for record in records:
            if record["status"] != status:
                continue
            print(record["path"])
            for hint in record.get("hints", []):
                related = ", ".join(hint["related_spec_ids"])
                print(f"  hint: {hint['field']} -> {related} :: {hint['excerpt']}")
            for error in record.get("errors", []):
                print(f"  error: {error}")

if mode == "check" and any(summary[key] > 0 for key in ("safe_empty", "needs_review", "schema_error")):
    raise SystemExit(1)
