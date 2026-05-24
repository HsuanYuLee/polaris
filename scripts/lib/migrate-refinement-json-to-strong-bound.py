#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def migrate(path):
    p = Path(path)
    data = json.loads(p.read_text(encoding="utf-8"))
    data.setdefault("schema_version", 1)
    acs = data.get("acceptance_criteria") or []
    ac_ids = [str(ac.get("id")) for ac in acs if ac.get("id")]
    modules = data.get("modules") or []
    allowed = [str(m.get("path")) for m in modules if m.get("path")]
    if not data.get("tasks"):
        hints = ((data.get("downstream") or {}).get("breakdown_hints") or [])
        title = hints[0] if hints else "Strong-bound refinement contract implementation"
        data["tasks"] = [
            {
                "id": f"{(data.get('source') or {}).get('id', 'SOURCE')}-T1",
                "kind": "implementation",
                "title": title[:120],
                "scope": "Generated migration task; breakdown may resplit using this machine contract.",
                "allowed_files": allowed or ["N/A"],
                "modules": allowed or ["N/A"],
                "ac_ids": ac_ids[:],
                "dependencies": [],
                "estimate_points": 1,
                "verification": {
                    "method": "unit_test",
                    "detail": "Validate migrated strong-bound refinement.json schema.",
                },
            }
        ]
    if not data.get("adversarial_pass"):
        data["adversarial_pass"] = [
            {
                "ac_id": aid,
                "attack": "migration placeholder: no additional adversarial attack recorded",
                "enforce": "existing AC verification remains authoritative",
            }
            for aid in ac_ids
        ] or [
            {
                "ac_id": "AC1",
                "attack": "migration placeholder",
                "enforce": "no AC present before migration",
            }
        ]
    source_type = (data.get("source") or {}).get("type")
    for field in ("reproduction", "root_cause", "source_pr", "severity", "impact_scope", "regression"):
        if source_type != "bug":
            data.pop(field, None)
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        print("usage: migrate-refinement-json-to-strong-bound.py <refinement.json> [...]", file=sys.stderr)
        return 2
    for arg in sys.argv[1:]:
        migrate(arg)
        print(f"MIGRATED {arg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
