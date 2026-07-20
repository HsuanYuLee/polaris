#!/usr/bin/env python3
"""Backfill or report refinement verification_strategy fields."""
from __future__ import annotations

import sys
from pathlib import Path

USAGE = """Usage:
  backfill-refinement-verification-strategy.sh --root <workspace_root> [--mode report|apply|check] [--format summary|json]

Modes:
  report  Print classification output only (no writes).
  apply   Backfill verification_strategy for delegate-valid inferences (source_level_v_required /
          per_task_self_verify), then reclassify.
  check   Exit non-zero when needs_review / schema_error remains.
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
delegate=Path(__file__).resolve().parents[1] / "validate-verification-strategy.sh"
if not delegate.is_file():
    print(f"POLARIS_TOOL_MISSING:validate-verification-strategy.sh not found: {delegate}", file=sys.stderr)
    raise SystemExit(2)
sys.argv=[sys.argv[0], root_arg, mode, fmt, str(delegate)]

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
mode = sys.argv[2]
fmt = sys.argv[3]
delegate = Path(sys.argv[4])
specs_root = root / "docs-manager" / "src" / "content" / "docs" / "specs"

# Provenance carried inside the written verification_strategy object (AC-NEG2). Technical
# identifiers stay in their original form; prose is the workspace language (zh-TW).
BACKFILLED_BY = "DP-421"
AUTHORITY = "DP-421 verification_strategy corpus backfill：由 tasks[] V-presence deterministic 推斷"
REASON_V = "backfill：tasks[] 含 V 驗收任務（kind ∈ {verification, V} 或 id 前綴 V），推斷 source-level V 驗收"
REASON_SELF = "backfill：tasks[] 無 V 驗收任務，推斷每張交付單自驗（per-task verify_command）"

STATUS_ORDER = ["already_ok", "applied", "needs_review", "schema_error"]
_short_id_bare = re.compile(r"[TV][0-9]+[a-z]?")
_short_id_composite = re.compile(r"[A-Z][A-Z0-9]*-[0-9]+-([TV][0-9]+[a-z]?)")


def all_refinement_paths() -> list[Path]:
    """Every refinement.json under the specs corpus, active AND archive (sorted, stable)."""
    if not specs_root.is_dir():
        return []
    return sorted(specs_root.rglob("refinement.json"))


def short_task_id(task: dict) -> str:
    raw = str(task.get("id") or "").strip()
    if _short_id_bare.fullmatch(raw):
        return raw
    m = _short_id_composite.fullmatch(raw)
    return m.group(1) if m else raw


def is_v_task(task: dict) -> bool:
    """A task denotes source-level verification when its id normalizes to V* or kind is V."""
    if short_task_id(task).startswith("V"):
        return True
    kind = str(task.get("kind") or "").strip().lower()
    return kind in ("verification", "v")


def infer_strategy(data: dict) -> dict:
    tasks = [t for t in (data.get("tasks") or []) if isinstance(t, dict)]
    if any(is_v_task(t) for t in tasks):
        return {
            "mode": "source_level_v_required",
            "reason": REASON_V,
            "authority": AUTHORITY,
            "backfilled_by": BACKFILLED_BY,
        }
    return {
        "mode": "per_task_self_verify",
        "reason": REASON_SELF,
        "authority": AUTHORITY,
        "backfilled_by": BACKFILLED_BY,
    }


def delegate_accepts(data: dict, strategy: dict) -> tuple[bool, str]:
    """Run the CANONICAL validate-verification-strategy.sh on data+strategy; reuse it as the single
    shape authority instead of re-implementing its semantics."""
    candidate = dict(data)
    candidate["verification_strategy"] = strategy
    with tempfile.NamedTemporaryFile(
        "w", suffix=".json", delete=False, encoding="utf-8"
    ) as fh:
        json.dump(candidate, fh, ensure_ascii=False)
        tmp = Path(fh.name)
    try:
        proc = subprocess.run(
            [str(delegate), str(tmp)], capture_output=True, text=True, check=False
        )
    finally:
        tmp.unlink(missing_ok=True)
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    return proc.returncode == 0, (detail[-1] if detail else f"delegate exit {proc.returncode}")


def classify(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - exercised via invalid fixture
        return {"path": str(path), "status": "schema_error", "detail": f"json_load_error: {exc}"}

    if not isinstance(data, dict):
        return {"path": str(path), "status": "schema_error", "detail": "root must be an object"}

    if data.get("verification_strategy") is not None:
        return {"path": str(path), "status": "already_ok", "detail": ""}

    strategy = infer_strategy(data)
    accepted, detail = delegate_accepts(data, strategy)
    if accepted:
        return {
            "path": str(path),
            "status": "inferred",
            "mode": strategy["mode"],
            "strategy": strategy,
            "detail": "",
        }
    return {
        "path": str(path),
        "status": "needs_review",
        "mode": strategy["mode"],
        "detail": detail,
    }


def apply_backfill(path: Path, strategy: dict) -> bool:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("verification_strategy") is not None:
        return False
    # Single-key addition: append verification_strategy last so every other key keeps its order and
    # value (AC-NEG2: jq 'del(.verification_strategy)' equals on both sides).
    data["verification_strategy"] = strategy
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return True


records = [classify(p) for p in all_refinement_paths()]
applied_paths: list[str] = []

if mode == "apply":
    for record in records:
        if record["status"] != "inferred":
            continue
        if apply_backfill(Path(record["path"]), record["strategy"]):
            applied_paths.append(record["path"])
    records = [classify(p) for p in all_refinement_paths()]


def status_of(record: dict) -> str:
    # In report/check, an "inferred" record is one that WOULD be applied; label it "applied" so the
    # summary reads the same before and after apply for spot-checking.
    return "applied" if record["status"] == "inferred" else record["status"]


summary = {
    "root": str(root),
    "scan_scope": "all_refinement_active_and_archive",
    "mode": mode,
    "format": fmt,
    "total": len(records),
    "already_ok": sum(1 for r in records if status_of(r) == "already_ok"),
    "applied": sum(1 for r in records if status_of(r) == "applied"),
    "needs_review": sum(1 for r in records if status_of(r) == "needs_review"),
    "schema_error": sum(1 for r in records if status_of(r) == "schema_error"),
    "written": len(applied_paths),
}

payload = {"summary": summary, "records": records, "applied_paths": applied_paths}

if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
else:
    for key in ("root", "scan_scope", "mode", "total", "already_ok", "applied", "needs_review",
                "schema_error", "written"):
        print(f"{key}={summary[key]}")
    for status in STATUS_ORDER:
        print(f"[{status}]")
        for record in records:
            if status_of(record) != status:
                continue
            line = record["path"]
            if record.get("mode"):
                line += f"  mode={record['mode']}"
            print(line)
            if record.get("detail"):
                print(f"  detail: {record['detail']}")

if mode == "check" and any(summary[key] > 0 for key in ("needs_review", "schema_error")):
    raise SystemExit(1)
