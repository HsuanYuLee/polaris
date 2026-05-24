#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

from refinement_common import load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-referrer-cascade.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, md_path, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    md_text = md_path.read_text(encoding="utf-8") if md_path.is_file() else ""
    explicit_zero = "referrer scan: 0 hits" in md_text
    for mod in data.get("modules") or []:
        if mod.get("action") not in {"delete", "rename"}:
            continue
        p = str(mod.get("path") or "")
        if not p:
            continue
        proc = subprocess.run(["rg", "-n", "--fixed-strings", p, ".claude", "scripts"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        hits = [line for line in proc.stdout.splitlines() if p not in line.split(":", 2)[0]]
        if hits or not explicit_zero:
            print(f"POLARIS_REFERRER_CASCADE_REVIEW: {p}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
