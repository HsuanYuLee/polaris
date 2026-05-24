#!/usr/bin/env python3
import re
import sys

from refinement_common import load_json, md_table_rows, refinement_paths, section


def count_bullets(block, prefix):
    return len(re.findall(rf"^\s*-\s*\*\*{re.escape(prefix)}", block, re.M))


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-intra-dp-consistency.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, md_path, json_path = refinement_paths(sys.argv[1])
    text = md_path.read_text(encoding="utf-8")
    data = load_json(json_path)
    json_modules = {str(m.get("path")): str(m.get("action")) for m in data.get("modules") or []}
    md_modules = {}
    for row in md_table_rows(section(text, "Modules")):
        if len(row) >= 2 and row[0] not in {"Path", "檔案"}:
            md_modules[row[0]] = row[1]
    drift = [p for p, action in md_modules.items() if p in json_modules and json_modules[p] != action]
    if drift:
        print(f"POLARIS_INTRA_DP_MODULE_DRIFT: {', '.join(drift)}", file=sys.stderr)
        return 2
    risks_md = count_bullets(section(text, "Risks"), "R")
    risks_json = len(((data.get("gaps") or {}).get("rd_risks") or []))
    if risks_md and risks_md != risks_json:
        print(f"POLARIS_INTRA_DP_RISKS_COUNT_DRIFT: md={risks_md} json={risks_json}", file=sys.stderr)
        return 2
    edges_md = count_bullets(section(text, "Edge Cases"), "EC")
    edges_json = len(data.get("edge_cases") or [])
    if edges_md and edges_md != edges_json:
        print(f"POLARIS_INTRA_DP_EDGE_CASES_COUNT_DRIFT: md={edges_md} json={edges_json}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
