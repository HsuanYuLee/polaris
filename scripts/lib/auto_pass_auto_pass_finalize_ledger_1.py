"""Purpose: finalize the auto-pass ledger terminal_status to complete (DP-311 T2).

Inputs: argv[1]=ledger path, argv[2]=source container, argv[3]=expected source id ('' to skip).
Outputs: FINALIZED / NOOP on stdout; POLARIS_LEDGER_FINALIZE_* marker on stderr + exit 2
on contract violation. Atomic in-place rewrite (tmp + os.replace) on the write path only.
"""

import json
import os
import sys
import tempfile
from pathlib import Path

ledger_path = Path(sys.argv[1])
container = sys.argv[2]
expected_source_id = sys.argv[3]

# AC-NEG4: non-complete terminal 一律保留，不得被 closeout chain 改寫成 complete。
# legacy / 未知字串值同樣視為「非 complete 的既有 terminal」保留（不 migrate，AC-NEG5）。
try:
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"POLARIS_LEDGER_FINALIZE_INVALID_JSON:{ledger_path}: {exc}", file=sys.stderr)
    raise SystemExit(2)

source = ledger.get("source") or {}
ledger_container = source.get("container")
if (
    not ledger_container
    or Path(ledger_container).resolve() != Path(container).resolve()
):
    print(
        f"POLARIS_LEDGER_FINALIZE_CONTAINER_MISMATCH:{ledger_path}: "
        f"ledger source.container={ledger_container!r} != --source-container={container!r}",
        file=sys.stderr,
    )
    raise SystemExit(2)

if expected_source_id and source.get("id") != expected_source_id:
    print(
        f"POLARIS_LEDGER_FINALIZE_SOURCE_ID_MISMATCH:{ledger_path}: "
        f"ledger source.id={source.get('id')!r} != --source-id={expected_source_id!r}",
        file=sys.stderr,
    )
    raise SystemExit(2)

terminal = ledger.get("terminal_status")
if terminal == "complete":
    print(f"NOOP: ledger already complete ({ledger_path})")
    raise SystemExit(0)
if terminal not in (None, ""):
    print(f"NOOP: non-complete terminal '{terminal}' preserved ({ledger_path})")
    raise SystemExit(0)
if ledger.get("pause"):
    pause_kind = (ledger.get("pause") or {}).get("kind")
    print(f"NOOP: unresolved pause '{pause_kind}' — not finalized ({ledger_path})")
    raise SystemExit(0)

ledger["terminal_status"] = "complete"

fd, tmp_path = tempfile.mkstemp(
    dir=str(ledger_path.parent), prefix=".finalize-", suffix=".json"
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

print(f"FINALIZED: terminal_status=complete ({ledger_path})")
