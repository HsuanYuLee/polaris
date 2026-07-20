"""Structured validator authority extracted from scripts/validate-artifact-contract-conformance.sh."""

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

registry_path = Path(sys.argv[1])
scan_root = Path(sys.argv[2]).resolve()
ledger_dir = Path(sys.argv[3])
class_filter = sys.argv[4]
mode = sys.argv[5]  # "check" | "seed"


def usage(msg: str) -> None:
    print(f"POLARIS_ARTIFACT_CONTRACT_USAGE: {msg}", file=sys.stderr)
    raise SystemExit(2)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


try:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
except Exception as exc:  # noqa: BLE001 - surfaced as usage error
    usage(f"invalid registry JSON: {exc}")

classes = registry.get("artifact_classes") or []
if class_filter:
    classes = [c for c in classes if c.get("class") == class_filter]
    if not classes:
        usage(f"no artifact class named {class_filter!r} in registry")


def resolve_delegate(rel: str) -> Path:
    p = Path(rel)
    return p if p.is_absolute() else (scan_root / p)


def field_present(data, field: str) -> bool:
    return isinstance(data, dict) and field in data and data.get(field) is not None


def ledger_file_for(name: str) -> Path:
    return ledger_dir / f"{name}.json"


def load_enrolled(name: str):
    """Return (enrolled_set, existing_record | None) for a class's draining ledger."""
    lf = ledger_file_for(name)
    if not lf.is_file():
        return set(), None
    try:
        rec = json.loads(lf.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001 - a corrupt ledger enrolls nothing (fail-closed on all)
        return set(), None
    return set(rec.get("enrolled_artifacts") or []), rec


def rel(artifact: Path) -> str:
    try:
        return str(artifact.relative_to(scan_root))
    except ValueError:
        return str(artifact)


def scan_non_conformant(cls):
    """Enumerate a class's existing artifacts and return {relpath: reason} for non-conformant ones."""
    glob = cls.get("enumerate_glob")
    field = cls.get("required_field")
    since = cls.get("required_since")
    delegate = cls.get("delegate_validator")
    if not glob or not field or not delegate:
        usage(
            f"class {cls.get('class')!r} missing enumerate_glob/required_field/delegate_validator"
        )
    delegate_path = resolve_delegate(delegate)

    non_conformant = {}
    for artifact in sorted(scan_root.glob(glob)):
        if not artifact.is_file():
            continue
        reason = None
        try:
            data = json.loads(artifact.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            data = None
            reason = f"unreadable JSON: {exc}"

        if reason is None:
            if not field_present(data, field):
                reason = f"missing required field '{field}' (required since {since})"
            else:
                # Delegate the SHAPE check to the EXISTING per-contract validator named by the
                # registry. The gate does not re-implement that validator's semantics.
                proc = subprocess.run(
                    ["bash", str(delegate_path), str(artifact)],
                    capture_output=True,
                    text=True,
                )
                if proc.returncode != 0:
                    tail = (proc.stderr or proc.stdout or "").strip().splitlines()
                    detail = tail[-1] if tail else f"delegate exit {proc.returncode}"
                    reason = f"shape drift per {delegate} ({detail})"

        if reason is not None:
            non_conformant[rel(artifact)] = reason
    return non_conformant


def write_ledger(cls, enrolled_sorted, existing_record):
    """Write / update a class's draining migration ledger (drain target = 0)."""
    name = cls.get("class")
    ledger_dir.mkdir(parents=True, exist_ok=True)
    seeded_at = (existing_record or {}).get("baseline_seeded_at") or now_iso()
    record = {
        "class": name,
        "required_field": cls.get("required_field"),
        "required_since": cls.get("required_since"),
        "delegate_validator": cls.get("delegate_validator"),
        "migration_owner": cls.get("migration_owner") or "unassigned",
        "draining": True,
        "waiver": False,
        "target_remaining": 0,
        "remaining": len(enrolled_sorted),
        "enrolled_artifacts": enrolled_sorted,
        "baseline_seeded_at": seeded_at,
        "generated_at": now_iso(),
    }
    ledger_file_for(name).write_text(
        json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return record


# ---------------------------------------------------------------------------------------------
# Seed mode: enroll EVERY currently-non-conformant artifact (any namespace) as pre-existing debt.
# This is the migration-time baseline capture and the ONLY mode that adds enrollments. Exit 0.
# ---------------------------------------------------------------------------------------------
if mode == "seed":
    total = 0
    for cls in classes:
        name = cls.get("class") or "<unnamed>"
        non_conformant = scan_non_conformant(cls)
        enrolled_sorted = sorted(non_conformant.keys())
        _, existing = load_enrolled(name)
        write_ledger(cls, enrolled_sorted, existing)
        total += len(enrolled_sorted)
        print(
            f"artifact-contract-conformance: seeded baseline for class '{name}' "
            f"(enrolled={len(enrolled_sorted)}, migration_owner={cls.get('migration_owner') or 'unassigned'}) "
            f"into draining ledger {ledger_file_for(name)}",
            file=sys.stderr,
        )
    print(
        f"artifact-contract-conformance: baseline seeded ({len(classes)} class(es); "
        f"{total} pre-existing non-conformant artifact(s) enrolled as draining debt)"
    )
    raise SystemExit(0)

# ---------------------------------------------------------------------------------------------
# Steady-state gate: fail-closed on NEW (unenrolled) non-conformant; enrolled debt passes; drain
# conformant entries out of an existing ledger. NEW violations are never written to the ledger.
# ---------------------------------------------------------------------------------------------
new_violations = []  # list of (class, relpath, reason) — unenrolled == NEW
draining_total = 0  # count of enrolled non-conformant artifacts still draining

for cls in classes:
    name = cls.get("class") or "<unnamed>"
    non_conformant = scan_non_conformant(cls)
    enrolled, existing = load_enrolled(name)

    still_draining = sorted(p for p in non_conformant if p in enrolled)
    draining_total += len(still_draining)

    for relpath in sorted(p for p in non_conformant if p not in enrolled):
        new_violations.append((name, relpath, non_conformant[relpath]))

    # Drain: shrink an EXISTING ledger to only the artifacts that are still non-conformant. This
    # removes entries that became conformant (remaining -> 0) and NEVER adds NEW violations. The
    # gate does not CREATE a ledger in steady-state mode — absent a baseline seed, every
    # non-conformant artifact is NEW and fail-closes.
    if existing is not None and set(still_draining) != enrolled:
        write_ledger(cls, still_draining, existing)

if new_violations:
    print(
        f"POLARIS_ARTIFACT_CONTRACT_NON_CONFORMANT: {len(new_violations)} new/unenrolled "
        f"non-conformant artifact(s)",
        file=sys.stderr,
    )
    for name, artifact, reason in new_violations:
        print(f"  - [{name}] {artifact}: {reason}", file=sys.stderr)
    raise SystemExit(2)

print(
    f"artifact-contract-conformance: PASS ({len(classes)} class(es) checked; "
    f"0 new/unenrolled non-conformant; {draining_total} enrolled artifact(s) draining toward 0)"
)
