#!/usr/bin/env python3
import re
import sys

from refinement_common import load_json, refinement_paths


PATTERN = re.compile(r"^AC(?:[0-9]+|-[A-Z0-9]+)$")


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-ac-id-shape.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    invalid = [str(ac.get("id")) for ac in data.get("acceptance_criteria") or [] if not PATTERN.match(str(ac.get("id") or ""))]
    if invalid:
        print(f"POLARIS_AC_ID_SHAPE_INVALID: {', '.join(invalid)} (expected ^AC[0-9]+$ or ^AC-[A-Z0-9]+$)", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
