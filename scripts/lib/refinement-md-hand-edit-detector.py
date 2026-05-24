#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-md-hand-edit-detector.py <refinement.json>", file=sys.stderr)
        return 2
    script = Path(__file__).resolve().parents[1] / "render-refinement-md.sh"
    proc = subprocess.run(["bash", str(script), sys.argv[1], "--check"], text=True)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
