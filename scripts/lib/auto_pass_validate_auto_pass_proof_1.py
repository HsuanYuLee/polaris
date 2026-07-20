import fnmatch
import json
import sys
from pathlib import Path

producer_map = Path(sys.argv[1])
args = sys.argv[2:]

VALID_STATUSES = {
    "PASS",
    "FAIL",
    "BLOCKED",
    "ROUTE_BACK",
    "MANUAL_REQUIRED",
    "UNCERTAIN",
    "BLOCKED_ENV",
    "IN_PROGRESS",
}


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"{path}: invalid JSON: {exc}") from exc


def load_map():
    data = load_json(producer_map)
    errors = []
    if data.get("schema_version") != 1:
        errors.append("producer map schema_version must be 1")
    producers = data.get("producers")
    if not isinstance(producers, list) or not producers:
        errors.append("producer map producers must be a non-empty array")
    seen = set()
    for idx, producer in enumerate(producers or []):
        for field in ("owning_skill", "writer", "marker_kinds", "path_globs"):
            if field not in producer:
                errors.append(f"producer[{idx}] missing {field}")
        marker_kinds = producer.get("marker_kinds")
        path_globs = producer.get("path_globs")
        writer_scripts = producer.get("writer_scripts", [])
        required_frontmatter = producer.get("required_frontmatter", [])
        if not isinstance(marker_kinds, list) or not marker_kinds:
            errors.append(f"producer[{idx}].marker_kinds must be a non-empty array")
        if not isinstance(path_globs, list) or not path_globs:
            errors.append(f"producer[{idx}].path_globs must be a non-empty array")
        if "writer_scripts" in producer and (
            not isinstance(writer_scripts, list) or not writer_scripts
        ):
            errors.append(
                f"producer[{idx}].writer_scripts must be a non-empty array when present"
            )
        for script in writer_scripts:
            if not isinstance(script, str) or not script:
                errors.append(
                    f"producer[{idx}].writer_scripts entries must be non-empty strings"
                )
        if "required_frontmatter" in producer and not isinstance(
            required_frontmatter, list
        ):
            errors.append(
                f"producer[{idx}].required_frontmatter must be an array when present"
            )
        for kind in marker_kinds or []:
            if kind in seen:
                errors.append(f"duplicate marker_kind in producer map: {kind}")
            seen.add(kind)
    if errors:
        raise ValueError("\n".join(errors))
    return data


def rel_path(path: Path):
    try:
        return path.resolve().relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def producer_for(data, marker_kind, writer, owning_skill, path):
    rel = rel_path(path)
    for producer in data["producers"]:
        if marker_kind not in producer.get("marker_kinds", []):
            continue
        if writer != producer.get("writer"):
            continue
        if owning_skill != producer.get("owning_skill"):
            continue
        if any(
            fnmatch.fnmatch(rel, glob) or fnmatch.fnmatch("./" + rel, glob)
            for glob in producer.get("path_globs", [])
        ):
            return producer
    return None


def validate_marker(data, path, producer_map_data):
    errors = []
    required = [
        "schema_version",
        "marker_kind",
        "writer",
        "owning_skill",
        "source_id",
        "work_item_id",
        "status",
        "freshness",
    ]
    for field in required:
        if field not in data:
            errors.append(f"missing {field}")
    if data.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    marker_kind = data.get("marker_kind")
    writer = data.get("writer")
    owning_skill = data.get("owning_skill")
    if data.get("status") not in VALID_STATUSES:
        errors.append(f"invalid status: {data.get('status')}")
    if not isinstance(data.get("freshness"), dict) or not data.get("freshness"):
        errors.append("freshness must be a non-empty object")
    else:
        freshness = data["freshness"]
        if not any(
            key in freshness
            for key in (
                "head_sha",
                "source_artifact",
                "task_artifact_sha256",
                "pr_head_sha",
            )
        ):
            errors.append(
                "freshness must include head_sha, source_artifact, task_artifact_sha256, or pr_head_sha"
            )
    if str(path).startswith("/tmp/") and data.get("status") == "PASS":
        errors.append("PASS marker cannot be /tmp only")
    if marker_kind == "audit_closure":
        rows = data.get("disposition_rows")
        if not isinstance(rows, list) or len(rows) < 12:
            errors.append("audit_closure requires at least 12 disposition_rows")
    if marker_kind == "dp198_handoff":
        if data.get("dp_198_t3_unblocked") is not True:
            errors.append("dp198_handoff requires dp_198_t3_unblocked=true")
        if not isinstance(data.get("evidence_paths"), list) or not data.get(
            "evidence_paths"
        ):
            errors.append("dp198_handoff requires non-empty evidence_paths")
        if not isinstance(data.get("audit_closure_summary"), dict):
            errors.append("dp198_handoff requires audit_closure_summary object")
    if (
        marker_kind
        and writer
        and owning_skill
        and producer_for(producer_map_data, marker_kind, writer, owning_skill, path)
        is None
    ):
        errors.append(
            f"no producer mapping for marker_kind={marker_kind} writer={writer} owning_skill={owning_skill} path={rel_path(path)}"
        )
    producer = (
        producer_for(producer_map_data, marker_kind, writer, owning_skill, path)
        if marker_kind and writer and owning_skill
        else None
    )
    if producer is not None and not producer.get("writer_scripts"):
        errors.append(
            f"producer mapping for marker_kind={marker_kind} must declare writer_scripts"
        )
    return errors


try:
    producer_map_data = load_map()
    if args == ["--producer-map"]:
        print(f"PASS: producer map {producer_map}")
        raise SystemExit(0)
    failures = []
    for raw in args:
        path = Path(raw)
        if not path.is_file():
            failures.append(f"{raw}: file not found")
            continue
        marker = load_json(path)
        errors = validate_marker(marker, path, producer_map_data)
        if errors:
            failures.append(f"{raw}:\n  - " + "\n  - ".join(errors))
    if failures:
        print("FAIL: auto-pass proof validation", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        raise SystemExit(1)
    print(f"PASS: auto-pass proof validation ({len(args)} file(s))")
except ValueError as exc:
    print(f"FAIL: {exc}", file=sys.stderr)
    raise SystemExit(1)
