"""Structured validator authority extracted from scripts/validate-dp-metadata.sh."""

import re
import sys
from pathlib import Path

inputs = [Path(p) for p in sys.argv[1:]]

VALID_STATUSES = {
    "SEEDED",
    "DISCUSSION",
    "LOCKED",
    "IMPLEMENTING",
    "IMPLEMENTED",
    "ABANDONED",
    "SUPERSEDED",
}
VALID_PRIORITIES = {"P0", "P1", "P2", "P3", "P4"}
VALID_VARIANTS = {"note", "tip", "caution", "danger", "success"}
VALID_SUPERSESSION_STATES = {"none", "partial", "full"}


def primary_doc_files(path: Path):
    if not path.exists():
        print(f"error: path not found: {path}", file=sys.stderr)
        sys.exit(2)
    if path.is_file():
        if path.name in {"index.md", "plan.md"}:
            yield path
        return
    if path.is_dir() and re.match(r"DP-\d+", path.name):
        index_doc = path / "index.md"
        plan_doc = path / "plan.md"
        if index_doc.is_file():
            yield index_doc
            return
        if plan_doc.is_file():
            yield plan_doc
            return
    candidates = []
    for container in sorted(path.rglob("DP-*")):
        if not container.is_dir():
            continue
        parts = container.parts
        if "design-plans" not in parts:
            continue
        index_doc = container / "index.md"
        plan_doc = container / "plan.md"
        if index_doc.is_file():
            candidates.append(index_doc)
        elif plan_doc.is_file():
            candidates.append(plan_doc)
    for file in candidates:
        yield file


def strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_scalar(value: str):
    value = strip_quotes(value)
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [strip_quotes(part.strip()) for part in body.split(",") if part.strip()]
    return value


def parse_nested_block(lines, start_idx):
    block = {}
    idx = start_idx
    while idx < len(lines):
        current = lines[idx]
        if not current.startswith("  "):
            break
        if not current.strip():
            idx += 1
            continue
        stripped = current.strip()
        if ":" not in stripped:
            idx += 1
            continue
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip()
        if value:
            block[key] = parse_scalar(value)
            idx += 1
            continue

        nested_map = {}
        list_items = []
        probe = idx + 1
        while probe < len(lines):
            candidate = lines[probe]
            if not candidate.startswith("    "):
                break
            stripped_candidate = candidate.strip()
            if stripped_candidate.startswith("- "):
                list_items.append(parse_scalar(stripped_candidate[2:].strip()))
            elif ":" in stripped_candidate:
                nested_key, nested_value = stripped_candidate.split(":", 1)
                nested_map[nested_key.strip()] = parse_scalar(nested_value.strip())
            probe += 1
        if nested_map:
            block[key] = nested_map
            idx = probe
            continue
        if list_items:
            block[key] = list_items
            idx = probe
            continue

        block[key] = None
        idx += 1

    return block, idx


def parse_frontmatter(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None, ["missing frontmatter"]
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is None:
        return None, ["unterminated frontmatter"]

    data = {}
    errors = []
    idx = 1
    while idx < end:
        line = lines[idx]
        if ":" in line and not line.startswith((" ", "\t")):
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            if not value:
                nested, consumed = parse_nested_block(lines, idx + 1)
                data[key] = nested
                idx = consumed
                continue
            data[key] = strip_quotes(value)
            idx += 1
            continue
        idx += 1

    return data, errors


def dp_number(path: Path):
    for part in reversed(path.parts):
        match = re.match(r"DP-(\d+)", part)
        if match:
            return int(match.group(1))
    return None


def add(rows, path, issue, detail):
    rows.append((str(path), issue, detail))


def validate_supersession(rows, file, status, supersession):
    if status == "SUPERSEDED" and not supersession:
        add(
            rows,
            file,
            "missing-supersession",
            "status SUPERSEDED requires supersession summary metadata",
        )
        return
    if not supersession:
        return
    if not isinstance(supersession, dict):
        add(rows, file, "invalid-supersession", "supersession must be a YAML object")
        return

    state = supersession.get("state")
    successor_ids = supersession.get("successor_ids")
    last_event_at = supersession.get("last_event_at")
    residual_open = supersession.get("residual_open")

    if state not in VALID_SUPERSESSION_STATES:
        add(rows, file, "invalid-supersession-state", f"got {state!r}")
    if not isinstance(successor_ids, list):
        add(
            rows,
            file,
            "invalid-supersession-successor-ids",
            "successor_ids must be a YAML list or bracket list",
        )
    elif not all(isinstance(item, str) and item.strip() for item in successor_ids):
        add(
            rows,
            file,
            "invalid-supersession-successor-ids",
            "successor_ids must contain non-empty strings",
        )
    if not isinstance(last_event_at, str) or not last_event_at.strip():
        add(
            rows,
            file,
            "invalid-supersession-last-event",
            "last_event_at must be a non-empty string",
        )
    if not isinstance(residual_open, bool):
        add(
            rows,
            file,
            "invalid-supersession-residual-open",
            "residual_open must be true or false",
        )

    if (
        state == "partial"
        and isinstance(successor_ids, list)
        and len(successor_ids) == 0
    ):
        add(
            rows,
            file,
            "partial-supersession-missing-successor",
            "partial supersession requires at least one successor id",
        )
    if status == "SUPERSEDED":
        if state != "full":
            add(
                rows,
                file,
                "superseded-state-mismatch",
                "status SUPERSEDED requires supersession.state=full",
            )
        if residual_open is not False:
            add(
                rows,
                file,
                "superseded-residual-open",
                "status SUPERSEDED requires residual_open=false",
            )
        if isinstance(successor_ids, list) and len(successor_ids) == 0:
            add(
                rows,
                file,
                "superseded-missing-successor",
                "status SUPERSEDED requires at least one successor id",
            )


files = []
seen = set()
for input_path in inputs:
    for file in primary_doc_files(input_path):
        resolved = file.resolve()
        if resolved not in seen:
            seen.add(resolved)
            files.append(file)

if not files:
    print("error: no Design Plan primary docs found", file=sys.stderr)
    sys.exit(2)

rows = []
for file in files:
    data, parse_errors = parse_frontmatter(file)
    for error in parse_errors:
        add(
            rows,
            file,
            error,
            "run sync-spec-sidebar-metadata.sh after fixing frontmatter",
        )
    if data is None:
        continue

    status = data.get("status", "")
    priority = data.get("priority", "")
    sidebar = data.get("sidebar", {})
    supersession = data.get("supersession")
    badge = sidebar.get("badge", {}) if isinstance(sidebar, dict) else {}
    order = sidebar.get("order") if isinstance(sidebar, dict) else None
    expected_order = dp_number(file)

    if status == "SEED":
        add(rows, file, "legacy-status", "use SEEDED instead of SEED")
    elif status not in VALID_STATUSES:
        add(rows, file, "invalid-status", f"got {status!r}")

    if priority not in VALID_PRIORITIES:
        add(rows, file, "invalid-priority", f"got {priority!r}")

    validate_supersession(rows, file, status, supersession)

    if not sidebar:
        add(rows, file, "missing-sidebar", "frontmatter must include sidebar metadata")
    else:
        if not sidebar.get("label"):
            add(rows, file, "missing-sidebar-label", "sidebar.label is required")
        if order is None:
            add(rows, file, "missing-sidebar-order", "sidebar.order is required")
        elif expected_order is not None and str(order) != str(expected_order):
            add(
                rows,
                file,
                "wrong-sidebar-order",
                f"expected {expected_order}, got {order}",
            )
        text = badge.get("text")
        variant = badge.get("variant")
        if not text:
            add(
                rows,
                file,
                "missing-sidebar-badge-text",
                "sidebar.badge.text is required",
            )
        elif status and priority and text != f"{status} / {priority}":
            add(
                rows,
                file,
                "wrong-sidebar-badge-text",
                f"expected {status} / {priority}, got {text}",
            )
        if variant not in VALID_VARIANTS:
            add(rows, file, "invalid-sidebar-badge-variant", f"got {variant!r}")

if rows:
    print("path\tissue\tdetail", file=sys.stderr)
    for row in rows:
        print("\t".join(row), file=sys.stderr)
    sys.exit(1)

print(f"PASS: DP metadata validation ({len(files)} file(s))")
