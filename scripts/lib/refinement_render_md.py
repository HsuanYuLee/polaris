"""產生 refinement.md derived view，並支援 byte parity check。"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


CHECKSUM = re.compile(r"\n<!-- checksum: sha256:[0-9a-f]+ -->\n\Z")


def stamp(payload: str) -> str:
    normalized = payload.rstrip() + "\n"
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    return normalized + f"\n<!-- checksum: sha256:{digest} -->\n"


def add_advisories(text: str, data: dict) -> str:
    advisories = data.get("handoff_advisories") or []
    if not advisories or "## Handoff Advisories" in text:
        return text
    text = CHECKSUM.sub("\n", text)
    rows = [
        "| ID | Producer | Severity | Disposition | Task IDs | Recommended Action |",
        "|----|----------|----------|-------------|----------|--------------------|",
    ]
    for advisory in advisories:
        task_ids = advisory.get("task_ids") or []
        task_text = ", ".join(map(str, task_ids)) if isinstance(task_ids, list) else str(task_ids)
        cells = [
            advisory.get("id"), advisory.get("producer"), advisory.get("severity"),
            advisory.get("disposition"), task_text, advisory.get("recommended_action"),
        ]
        rows.append("| " + " | ".join(str(value or "").replace("|", "/") for value in cells) + " |")
    return insert_before_hardened_ac(text, "\n".join(["## Handoff Advisories", "", *rows, ""]))


def add_bug_fields(text: str, data: dict) -> str:
    if (data.get("source") or {}).get("type") != "bug" or "## Bug-specific Fields" in text:
        return text
    text = CHECKSUM.sub("\n", text)
    rows = [
        ("Reproduction steps", "; ".join(str(step) for step in data.get("reproduction_steps") or [])),
        ("Root cause", data.get("root_cause")), ("Source PR", data.get("source_pr")),
        ("Severity", data.get("severity")), ("Impact scope", data.get("impact_scope")),
        ("Regression", data.get("regression")),
    ]
    section = "\n".join(["## Bug-specific Fields", "", *[f"- **{label}**: {value}" for label, value in rows], ""])
    return insert_before_hardened_ac(text, section)


def insert_before_hardened_ac(text: str, section: str) -> str:
    anchor = "\n## Hardened AC\n"
    if anchor not in text:
        raise SystemExit("render-refinement-md: missing Hardened AC anchor")
    return stamp(text.replace(anchor, f"\n{section}{anchor}", 1))


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    cli = os.environ.get("POLARIS_COMPAT_CLI", "render-refinement-md.sh")
    if not args:
        print(f"usage: {cli} <refinement.json> [--check]", file=sys.stderr)
        return 2
    json_path = Path(args.pop(0))
    if str(json_path).startswith("-"):
        dirname = subprocess.run(["dirname", str(json_path)], capture_output=True, text=True)
        if dirname.returncode:
            sys.stderr.write(dirname.stderr)
            return dirname.returncode
    check = False
    while args:
        if args.pop(0) == "--check":
            check = True
        else:
            print(f"usage: {cli} <refinement.json> [--check]", file=sys.stderr)
            return 2
    output_path = json_path.parent / "refinement.md"
    generator = Path(__file__).with_name("refinement-md-generator.py")
    generated = subprocess.run(
        [sys.executable, str(generator), str(json_path)], capture_output=True, text=True, check=False
    )
    if generated.returncode != 0:
        sys.stderr.write(generated.stderr)
        return generated.returncode
    data = json.loads(json_path.read_text(encoding="utf-8"))
    text = add_bug_fields(add_advisories(generated.stdout, data), data)
    if check:
        if not output_path.is_file() or output_path.read_text(encoding="utf-8") != text:
            print("POLARIS_REFINEMENT_MD_HAND_EDIT_DETECTED", file=sys.stderr)
            return 2
        return 0
    output_path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
