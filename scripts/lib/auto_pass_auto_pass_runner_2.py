import json
import sys

source_id, stage, evidence_path, reason = sys.argv[1:5]
print(
    json.dumps(
        {
            "schema_version": 1,
            "source_id": source_id,
            "stage": stage,
            "status": "FAIL",
            "terminal_status": "blocked_by_gate_failure",
            "next_action": "blocked",
            "next_skill": None,
            "next_work_item_id": None,
            "evidence_path": evidence_path,
            "delegation_authority": None,
            "reason": reason,
        },
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    )
)
