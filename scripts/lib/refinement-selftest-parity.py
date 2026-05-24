#!/usr/bin/env python3
import sys
from pathlib import Path

from refinement_common import load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-selftest-parity.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    modules = data.get("modules") or []
    listed = {str(m.get("path") or "") for m in modules}
    warnings = []
    for mod in modules:
        p = str(mod.get("path") or "")
        if mod.get("action") not in {"create", "modify"} or not p.startswith("scripts/") or "/selftests/" in p:
            continue
        if not p.endswith((".sh", ".py", ".mjs", ".js")):
            continue
        stem = Path(p).stem
        expected = f"scripts/selftests/{stem}-selftest.sh"
        if expected not in listed:
            warnings.append(p)
    for item in warnings:
        print(f"POLARIS_SELFTEST_PARITY_MISSING: {item}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
