#!/usr/bin/env python3
"""Purpose: flag dangling referrers when a refinement module is deleted/renamed.

Inputs:  argv[1] = container dir or refinement.json path.
Outputs: exit 0; emits POLARIS_REFERRER_CASCADE_REVIEW on stderr for each
         delete/rename path that still has referrers (or lacks an explicit
         "referrer scan: 0 hits" note). exit 2 when rg is unavailable.
"""
import subprocess
import sys

from refinement_common import load_json, refinement_paths
from tool_resolution import ToolResolutionError, resolve_tool


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-referrer-cascade.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, md_path, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    md_text = md_path.read_text(encoding="utf-8") if md_path.is_file() else ""
    explicit_zero = "referrer scan: 0 hits" in md_text
    try:
        rg_path = resolve_tool("rg")
    except ToolResolutionError as exc:
        print(f"POLARIS_TOOL_MISSING resolve_tool('rg') failed: {exc}", file=sys.stderr)
        return 2
    for mod in data.get("modules") or []:
        if mod.get("action") not in {"delete", "rename"}:
            continue
        p = str(mod.get("path") or "")
        if not p:
            continue
        proc = subprocess.run([rg_path, "-n", "--fixed-strings", p, ".claude", "scripts"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        hits = [line for line in proc.stdout.splitlines() if p not in line.split(":", 2)[0]]
        if hits or not explicit_zero:
            print(f"POLARIS_REFERRER_CASCADE_REVIEW: {p}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
