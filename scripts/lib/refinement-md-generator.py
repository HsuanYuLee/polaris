#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-md-generator.py <refinement.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    data = json.loads(path.read_text(encoding="utf-8"))
    title = f"{(data.get('source') or {}).get('id', 'Source')} Refinement"
    lines = [
        "---",
        f'title: "{title}"',
        'description: "Generated refinement derived view."',
        "---",
        "",
        "<!-- generated-by: render-refinement-md.sh; do-not-hand-edit -->",
        "",
        "# Derived View",
        "",
        "## Predecessor Scan",
        "- keyword: refinement contract",
        "- hits: generated derived view preserves source artifact linkage",
        "",
        "## Scope",
    ]
    for task in data.get("tasks") or []:
        lines.append(f"- **{task.get('id')}**: {task.get('title')} — {task.get('scope')}")
    lines += ["", "## Hardened AC", "", "| ID | Statement | 驗證方式 |", "|----|-----------|----------|"]
    for ac in data.get("acceptance_criteria") or []:
        ver = ac.get("verification") or {}
        lines.append(f"| {ac.get('id')} | {str(ac.get('text','')).replace('|','/')} | {ver.get('method')} |")
    lines += ["", "## Adversarial Pass"]
    for item in data.get("adversarial_pass") or []:
        lines.append(f"- **{item.get('ac_id')}** attack: {item.get('attack')}; enforce: {item.get('enforce')}")
    lines += ["", "## Edge Cases"]
    for i, ec in enumerate(data.get("edge_cases") or [], 1):
        lines.append(f"- **EC{i}**: {ec.get('scenario')} — {ec.get('handling')}")
    lines += ["", "## Risks"]
    for i, risk in enumerate(((data.get("gaps") or {}).get("rd_risks") or []), 1):
        lines.append(f"- **R{i}**: {risk.get('risk')} — {risk.get('mitigation')}")
    lines += ["", "## Modules", "", "| Path | Action |", "|------|--------|"]
    for mod in data.get("modules") or []:
        lines.append(f"| `{mod.get('path')}` | {mod.get('action')} |")
    payload = "\n".join(lines).rstrip() + "\n"
    checksum = hashlib.sha256(payload.encode("utf-8")).hexdigest()
    sys.stdout.write(payload + f"\n<!-- checksum: sha256:{checksum} -->\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
