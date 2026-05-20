#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <spec-container|refinement.json>" >&2; exit 2; }
input="$1"
if [[ -d "$input" ]]; then
  container="$input"
else
  container="$(dirname "$input")"
fi

python3 - "$container" <<'PY'
import json
import re
import sys
from pathlib import Path

container = Path(sys.argv[1])
ref_json = container / "refinement.json"
ref_md = container / "refinement.md"
index_md = container / "index.md"
errors = []

for path in (ref_json, ref_md, index_md):
    if not path.is_file():
        errors.append(f"missing artifact: {path}")
if errors:
    print("FAIL: refinement artifact parity", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    raise SystemExit(1)

data = json.loads(ref_json.read_text(encoding="utf-8"))
ref_text = ref_md.read_text(encoding="utf-8")
index_text = index_md.read_text(encoding="utf-8")

json_modules = {(m.get("path"), m.get("action")) for m in data.get("modules", []) if m.get("path") and m.get("action")}
md_modules = set()
in_modules = False
for line in ref_text.splitlines():
    if line.strip() == "## Modules":
        in_modules = True
        continue
    if in_modules and line.startswith("## "):
        break
    if in_modules and line.startswith("| `"):
        cells = [c.strip() for c in line.split("|")]
        if len(cells) >= 4:
            md_modules.add((cells[1].strip("`"), cells[2]))
if json_modules != md_modules:
    errors.append(f"modules path/action drift: json={len(json_modules)} md={len(md_modules)}")

changed_files = set(data.get("changed_files") or [])
module_paths = {path for path, _action in json_modules}
if changed_files != module_paths:
    errors.append(f"changed_files drift: changed_files={len(changed_files)} module_paths={len(module_paths)}")

json_ac = {str(ac.get("id")) for ac in data.get("acceptance_criteria", []) if ac.get("id")}
ac_re = r"\bAC(?:-[A-Z0-9]+|[0-9]+)\b"
ref_ac = set(re.findall(ac_re, ref_text))
index_ac = set(re.findall(ac_re, index_text))
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
if first_number and not re.search(rf"\b{first_number.group(0)}\s*pt\b|\b{first_number.group(0)}pt\b", index_text):
    errors.append(f"downstream estimated_total_points not found in index.md: {points}")

if errors:
    print("FAIL: refinement artifact parity", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: refinement artifact parity ({container})")
PY
