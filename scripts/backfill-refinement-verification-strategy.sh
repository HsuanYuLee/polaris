#!/usr/bin/env bash
# Purpose: DP-421 T2 — backfill the source-level verification_strategy field onto every
#   refinement.json that predates the DP-364 requirement (active + archive corpus). This is the
#   first migration application of the T1 registry-driven artifact-contract-conformance gate
#   (scripts/validate-artifact-contract-conformance.sh, class refinement-json-verification-strategy).
#   Mirrors scripts/backfill-refinement-predecessor-audit.sh: a bash CLI wrapper around an embedded
#   python classifier with report / apply / check modes.
#
#   Deterministic inference (per DP-421 AC2), reusing the CANONICAL shape validator so that every
#   written strategy is conformant by construction (no second classifier;
#   canonical-contract-governance.md § No special writer paths / Canonical shape first):
#     - tasks[] has a V task (id prefix V, or kind in {verification, V}) => source_level_v_required
#     - otherwise                                                         => per_task_self_verify
#   The inferred verification_strategy is then validated against the EXISTING
#   scripts/validate-verification-strategy.sh (the same delegate the T1 conformance gate uses). Only
#   inferences the delegate ACCEPTS are written; an inference the delegate rejects (e.g. a T-only
#   source whose T tasks predate the per-task verify_command requirement, so per_task_self_verify is
#   not delegate-valid, and there is no V task for source_level_v_required) is classified
#   needs_review and left untouched — the migration never writes a strategy that would fail the
#   conformance gate.
#   Its tasks[] `task` accessor is registered in scripts/refinement-consumer-registry.json;
#   W12 fails closed if the id/kind reads drift outside the canonical schema.
#
#   Only the single top-level verification_strategy key is added; all other keys keep their value
#   (single-key addition, AC-NEG2). Backfilled provenance is carried inside the object
#   (authority + backfilled_by=DP-421).
#
# Inputs:
#   --root <workspace_root>          (required; specs corpus is <root>/docs-manager/src/content/docs/specs)
#   --mode report|apply|check        (default report)
#   --format summary|json            (default summary)
#
# Outputs:
#   report : classification counts + per-status file lists on stdout (exit 0).
#   apply  : backfill verification_strategy for delegate-valid inferences, then reclassify (exit 0).
#   check  : exit 1 when any needs_review / schema_error remains (migration not fully drained).
#   Exit 64 on bad arguments.
set -euo pipefail

ROOT=""
MODE="report"
FORMAT="summary"

usage() {
  cat >&2 <<'EOF'
Usage:
  backfill-refinement-verification-strategy.sh --root <workspace_root> [--mode report|apply|check] [--format summary|json]

Modes:
  report  Print classification output only (no writes).
  apply   Backfill verification_strategy for delegate-valid inferences (source_level_v_required /
          per_task_self_verify), then reclassify.
  check   Exit non-zero when needs_review / schema_error remains.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "--root is required and must exist" >&2
  exit 64
fi

if [[ "$MODE" != "report" && "$MODE" != "apply" && "$MODE" != "check" ]]; then
  echo "--mode must be one of: report, apply, check" >&2
  exit 64
fi

if [[ "$FORMAT" != "summary" && "$FORMAT" != "json" ]]; then
  echo "--format must be one of: summary, json" >&2
  exit 64
fi

ROOT="$(cd "$ROOT" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DELEGATE="${SCRIPT_DIR}/validate-verification-strategy.sh"

if [[ ! -f "$DELEGATE" ]]; then
  echo "POLARIS_TOOL_MISSING:validate-verification-strategy.sh not found: $DELEGATE" >&2
  exit 2
fi

python3 - "$ROOT" "$MODE" "$FORMAT" "$DELEGATE" <<'PY'
from __future__ import annotations

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
PY
