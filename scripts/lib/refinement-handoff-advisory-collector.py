#!/usr/bin/env python3
import importlib.util
import sys
from pathlib import Path

from refinement_common import load_json, refinement_paths


def load_release_surface_module():
    path = Path(__file__).with_name("refinement-release-surface-advisory.py")
    spec = importlib.util.spec_from_file_location("refinement_release_surface_advisory", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load advisory producer: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def durable_advisory_by_id(data):
    records = {}
    for item in data.get("handoff_advisories") or []:
        if not isinstance(item, dict):
            continue
        advisory_id = item.get("id")
        if isinstance(advisory_id, str) and advisory_id.strip():
            records[advisory_id.strip()] = item
    return records


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-handoff-advisory-collector.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    release_surface = load_release_surface_module()
    generated = release_surface.release_surface_advisories(data)
    durable = durable_advisory_by_id(data)

    blocked = False
    for advisory in generated:
        advisory_id = str(advisory.get("id") or "").strip()
        if not advisory_id:
            continue
        recorded = durable.get(advisory_id)
        if recorded is None:
            print(
                f"POLARIS_REFINEMENT_HANDOFF_ADVISORY_MISSING: {advisory_id}",
                file=sys.stderr,
            )
            blocked = True
            continue
        disposition = str(recorded.get("disposition") or "").strip()
        if disposition == "pending":
            print(
                f"POLARIS_REFINEMENT_HANDOFF_ADVISORY_PENDING: {advisory_id}",
                file=sys.stderr,
            )
            blocked = True

    return 1 if blocked else 0


if __name__ == "__main__":
    raise SystemExit(main())
