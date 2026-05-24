#!/usr/bin/env python3
import re
import subprocess
import sys
from pathlib import Path

from refinement_common import ac_blob, load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-script-help-advisory.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    blob = ac_blob(data)
    scripts = sorted(set(re.findall(r"(scripts/[A-Za-z0-9_./-]+\.sh)", blob)))
    for script in scripts:
        path = Path(script)
        if not path.is_file():
            continue
        proc = subprocess.run(["bash", script, "--help"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if proc.returncode != 0:
            continue
        flags = sorted(set(re.findall(r"--[A-Za-z0-9][A-Za-z0-9_-]*", proc.stdout + proc.stderr)))
        if flags:
            print(f"POLARIS_SCRIPT_HELP_ADVISORY: {script} flags={','.join(flags)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
