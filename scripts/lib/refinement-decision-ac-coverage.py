#!/usr/bin/env python3
import re
import sys
from pathlib import Path

from refinement_common import ac_blob, load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-decision-ac-coverage.py <container|refinement.json>", file=sys.stderr)
        return 2
    container, md_path, json_path = refinement_paths(sys.argv[1])
    text = md_path.read_text(encoding="utf-8")
    data = load_json(json_path)
    blob = ac_blob(data).lower()
    missing = []
    for match in re.finditer(r"\*\*(D[0-9]+)[：:][^*]+", text):
        did = match.group(1)
        noun = re.sub(r"[^A-Za-z0-9\u4e00-\u9fff]+", " ", match.group(0)).strip().lower()
        if did.lower() not in blob and noun[:16] not in blob:
            missing.append(did)
    if missing:
        print(f"POLARIS_DECISION_AC_COVERAGE_MISSING: {','.join(sorted(set(missing)))}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
