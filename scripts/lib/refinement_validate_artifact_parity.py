"""驗證 refinement JSON、衍生 Markdown 與 primary doc 的語意一致性。"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        cli = os.environ.get("POLARIS_COMPAT_CLI", "validate-refinement-artifact-parity.sh")
        print(f"usage: {cli} <spec-container|refinement.json>", file=sys.stderr)
        return 2
    supplied = Path(args[0])
    if str(supplied).startswith("-"):
        dirname = subprocess.run(["dirname", str(supplied)], capture_output=True, text=True)
        if dirname.returncode:
            sys.stderr.write(dirname.stderr)
            return dirname.returncode
    container = supplied if supplied.is_dir() else supplied.parent
    ref_json = container / "refinement.json"
    ref_md = container / "refinement.md"
    index_md = container / "index.md"
    errors = [f"missing artifact: {path}" for path in (ref_json, ref_md, index_md) if not path.is_file()]
    if errors:
        return report(errors)

    data = json.loads(ref_json.read_text(encoding="utf-8"))
    ref_text = ref_md.read_text(encoding="utf-8")
    index_text = index_md.read_text(encoding="utf-8")
    json_modules = {
        (module.get("path"), module.get("action"))
        for module in data.get("modules", [])
        if module.get("path") and module.get("action")
    }
    md_modules: set[tuple[str, str]] = set()
    in_modules = False
    for line in ref_text.splitlines():
        if line.strip() == "## Modules":
            in_modules = True
            continue
        if in_modules and line.startswith("## "):
            break
        if in_modules and line.startswith("| `"):
            cells = [cell.strip() for cell in line.split("|")]
            if len(cells) >= 4:
                md_modules.add((cells[1].strip("`"), cells[2]))
    if json_modules != md_modules:
        errors.append(f"modules path/action drift: json={len(json_modules)} md={len(md_modules)}")

    changed_files = set(data.get("changed_files") or [])
    module_paths = {path for path, _action in json_modules}
    if changed_files != module_paths:
        errors.append(
            f"changed_files drift: changed_files={len(changed_files)} module_paths={len(module_paths)}"
        )
    json_ac = {str(ac.get("id")) for ac in data.get("acceptance_criteria", []) if ac.get("id")}
    ac_pattern = r"\bAC(?:-[A-Z0-9]+|[0-9]+)\b"
    ref_ac = set(re.findall(ac_pattern, ref_text))
    index_ac = set(re.findall(ac_pattern, index_text))
    if not json_ac.issubset(ref_ac):
        errors.append(f"AC ids missing from refinement.md: {sorted(json_ac - ref_ac)}")
    if not json_ac.issubset(index_ac):
        errors.append(f"AC ids missing from index.md: {sorted(json_ac - index_ac)}")

    downstream = data.get("downstream") or {}
    count = str(downstream.get("suggested_subtask_count", ""))
    points = str(downstream.get("estimated_total_points", ""))
    if count and not re.search(rf"\b{re.escape(count)}\b", index_text):
        errors.append(f"downstream suggested_subtask_count not found in index.md: {count}")
    first_number = re.search(r"\d+", points)
    if first_number and not re.search(
        rf"\b{first_number.group(0)}\s*pt\b|\b{first_number.group(0)}pt\b", index_text
    ):
        errors.append(f"downstream estimated_total_points not found in index.md: {points}")
    if errors:
        return report(errors)
    print(f"PASS: refinement artifact parity ({container})")
    return 0


def report(errors: list[str]) -> int:
    print("FAIL: refinement artifact parity", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
