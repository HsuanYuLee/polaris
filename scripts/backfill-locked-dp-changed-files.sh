#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage:
  scripts/backfill-locked-dp-changed-files.sh [--root PATH] [--mode report|check|apply] [--format summary|json]

Scans LOCKED DP refinement.json files and backfills missing changed_files from modules[].path.
USAGE
  exit 2
}

ROOT="$(pwd)"
MODE="report"
FORMAT="summary"

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
    --help|-h)
      usage
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      ;;
  esac
done

case "$MODE" in
  report|check|apply) ;;
  *) echo "ERROR: --mode must be report, check, or apply" >&2; usage ;;
esac

case "$FORMAT" in
  summary|json) ;;
  *) echo "ERROR: --format must be summary or json" >&2; usage ;;
esac

python3 - "$ROOT" "$MODE" "$FORMAT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
mode = sys.argv[2]
fmt = sys.argv[3]

design_plans = root / "docs-manager/src/content/docs/specs/design-plans"


def frontmatter_status(path: Path) -> str | None:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    for raw in text[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        if key.strip() == "status":
            return value.strip().strip('"').strip("'")
    return None


def infer_changed_files(data: dict) -> list[str]:
    paths: list[str] = []
    for module in data.get("modules") or []:
        if not isinstance(module, dict):
            continue
        path = module.get("path")
        if isinstance(path, str) and path.strip() and path not in paths:
            paths.append(path)
    return paths


def has_changed_files(data: dict) -> bool:
    value = data.get("changed_files", None)
    return isinstance(value, list) and bool(value)


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


records = []
if design_plans.is_dir():
    for refinement_path in sorted(design_plans.glob("DP-*/refinement.json")):
        container = refinement_path.parent
        status = frontmatter_status(container / "index.md") or frontmatter_status(container / "plan.md")
        if status != "LOCKED":
            continue
        try:
            data = json.loads(refinement_path.read_text(encoding="utf-8"))
        except Exception as exc:
            records.append({
                "path": str(refinement_path.relative_to(root)),
                "status": "invalid_json",
                "error": str(exc),
                "changed_files_count": 0,
                "inferred_count": 0,
                "applied": False,
            })
            continue
        changed_files_present = has_changed_files(data)
        inferred = infer_changed_files(data)
        record = {
            "path": str(refinement_path.relative_to(root)),
            "status": "ok" if changed_files_present else "missing_changed_files",
            "changed_files_count": len(data.get("changed_files") or []) if isinstance(data.get("changed_files"), list) else 0,
            "inferred_count": len(inferred),
            "applied": False,
        }
        if not changed_files_present and inferred and mode == "apply":
            data["changed_files"] = inferred
            write_json(refinement_path, data)
            record["status"] = "backfilled"
            record["changed_files_count"] = len(inferred)
            record["applied"] = True
        records.append(record)

missing = [record for record in records if record["status"] in {"missing_changed_files", "invalid_json"}]
applied = [record for record in records if record["applied"]]
summary = {
    "mode": mode,
    "root": str(root),
    "locked_dp_count": len(records),
    "missing_count": len(missing),
    "applied_count": len(applied),
}

if fmt == "json":
    print(json.dumps({"summary": summary, "records": records}, ensure_ascii=False, indent=2))
else:
    print(
        "locked_dp_count={locked_dp_count} missing_count={missing_count} applied_count={applied_count}".format(
            **summary
        )
    )
    for record in records:
        if record["status"] != "ok":
            print(f"{record['status']}: {record['path']} inferred_count={record['inferred_count']}")

if mode == "check" and missing:
    raise SystemExit(1)
PY
