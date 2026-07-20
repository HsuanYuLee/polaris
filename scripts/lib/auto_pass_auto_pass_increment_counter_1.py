import json
import sys
from pathlib import Path

ledger_path = Path(sys.argv[1])
transition = sys.argv[2]
evidence_id = sys.argv[3]

try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    sys.exit(f"ERROR: ledger invalid JSON: {exc}")

if not isinstance(ledger, dict):
    sys.exit("ERROR: ledger root must be an object")

counters = ledger.get("loop_counters")
if counters is None:
    counters = {}
    ledger["loop_counters"] = counters
elif not isinstance(counters, dict):
    sys.exit("ERROR: ledger.loop_counters must be an object")

# Migrate legacy integer shape to new {count, evidence_ids[]} shape.
# Backwards compat: if the value is a plain int, treat it as count=N, evidence_ids=[].
existing = counters.get(transition)
if existing is None:
    entry = {"count": 0, "evidence_ids": []}
elif isinstance(existing, int):
    # Legacy integer format — migrate to new shape, preserving count.
    entry = {"count": existing, "evidence_ids": []}
elif isinstance(existing, dict):
    entry = existing
    if "count" not in entry:
        entry["count"] = 0
    if "evidence_ids" not in entry:
        entry["evidence_ids"] = []
else:
    sys.exit(f"ERROR: loop_counters.{transition} has unexpected type: {type(existing)}")

# DP-246 AC2: duplicate evidence_id -> silent exit 0 (idempotent no-op).
if evidence_id in entry["evidence_ids"]:
    print("DUPLICATE")
    sys.exit(0)

previous = entry["count"]
current = previous + 1
entry["count"] = current
entry["evidence_ids"].append(evidence_id)
counters[transition] = entry

tmp = ledger_path.with_suffix(ledger_path.suffix + ".tmp")
tmp.write_text(
    json.dumps(ledger, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
)
tmp.replace(ledger_path)

# Emit "1" only on the 1 -> 2 transition (counter became 2). This is the
# canonical "stage retry" friction trigger; subsequent increments are tracked
# by the counter itself but do not append additional friction entries (cap is
# enforced upstream in auto-pass-probe.sh ledger_terminal()).
print("1" if previous == 1 else "0")
