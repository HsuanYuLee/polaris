#!/usr/bin/env python3
import json
import sys

from refinement_common import load_json, refinement_paths


def release_surface_advisories(data):
    paths = {str(m.get("path") or "") for m in data.get("modules") or []}
    framework_touch = any(p.startswith(".claude/") or p.startswith("scripts/") for p in paths)
    release_surface = {"VERSION", "CHANGELOG.md", "scripts/manifest.json", ".claude/hooks/pre-push-quality-gate.sh"}
    if not framework_touch or (paths & release_surface):
        return []
    return [
        {
            "id": "framework-release-surface-missing",
            "producer": "refinement-release-surface-advisory",
            "severity": "actionable",
            "recommended_action": (
                "Record how this framework-touching source accounts for release surface coverage, "
                "or bind the advisory to a task that owns the release-surface disposition."
            ),
            "disposition": "pending",
        }
    ]


def main():
    args = list(sys.argv[1:])
    emit_json = False
    if "--json" in args:
        emit_json = True
        args.remove("--json")
    if len(args) != 1:
        print("usage: refinement-release-surface-advisory.py [--json] <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(args[0])
    data = load_json(json_path)
    advisories = release_surface_advisories(data)
    if emit_json:
        print(json.dumps(advisories, ensure_ascii=False, indent=2))
    elif advisories:
        print("POLARIS_FRAMEWORK_RELEASE_SURFACE_MISSING", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
