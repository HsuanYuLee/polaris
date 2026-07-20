"""Consume a session_handoff pause: null pause + set resumed_at (DP-339 T1).

Inputs: argv[1]=ledger path, argv[2]=resumed_at ISO8601 timestamp.
Atomic in-place rewrite (tempfile.mkstemp in the ledger dir + os.replace);
only `pause` and `resumed_at` mutate, every other key round-trips byte-for-byte.
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ledger_path = Path(sys.argv[1])
resumed_at = sys.argv[2]

ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
ledger["pause"] = None
ledger["resumed_at"] = resumed_at

fd, tmp_path = tempfile.mkstemp(
    dir=str(ledger_path.parent), prefix=".consume-resume-", suffix=".json"
)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(ledger, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(tmp_path, ledger_path)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise
