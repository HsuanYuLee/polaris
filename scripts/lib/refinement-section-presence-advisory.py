#!/usr/bin/env python3
import re
import sys

from refinement_common import load_json, refinement_paths, section


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in {"--mode"}:
        print("usage: refinement-section-presence-advisory.py --mode predecessor|adversarial <container|refinement.json>", file=sys.stderr)
        return 2
    mode = sys.argv[2]
    target = sys.argv[3]
    _, md_path, json_path = refinement_paths(target)
    text = md_path.read_text(encoding="utf-8")
    if mode == "predecessor":
        block = section(text, "Predecessor Scan")
        if "keyword" not in block.lower() or "hit" not in block.lower():
            print("POLARIS_PREDECESSOR_SCAN_MISSING", file=sys.stderr)
            return 2
        return 0
    if mode == "adversarial":
        block = section(text, "Adversarial Pass")
        if "attack" not in block.lower() or "enforce" not in block.lower():
            print("POLARIS_ADVERSARIAL_PASS_MISSING", file=sys.stderr)
            return 0
        data = load_json(json_path)
        covered = set(re.findall(r"AC(?:[0-9]+|-[A-Z0-9]+)", block))
        required = {str(ac.get("id")) for ac in data.get("acceptance_criteria") or [] if ac.get("category") in {"functional", "negative"}}
        missing = sorted(required - covered)
        if missing:
            print(f"POLARIS_ADVERSARIAL_PASS_INCOMPLETE: {','.join(missing)}", file=sys.stderr)
        return 0
    print(f"unknown mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
