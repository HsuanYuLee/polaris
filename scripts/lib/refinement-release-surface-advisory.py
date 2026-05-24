#!/usr/bin/env python3
import sys

from refinement_common import load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-release-surface-advisory.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    paths = {str(m.get("path") or "") for m in data.get("modules") or []}
    framework_touch = any(p.startswith(".claude/") or p.startswith("scripts/") for p in paths)
    release_surface = {"VERSION", "CHANGELOG.md", "scripts/manifest.json", ".claude/hooks/pre-push-quality-gate.sh"}
    if framework_touch and not (paths & release_surface):
        print("POLARIS_FRAMEWORK_RELEASE_SURFACE_MISSING", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
