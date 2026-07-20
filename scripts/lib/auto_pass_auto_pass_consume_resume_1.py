import json
import sys
from pathlib import Path

ledger = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pause = ledger.get("pause")
if pause is None:
    print("__NO_PAUSE__")
elif not isinstance(pause, dict):
    print("__BAD_PAUSE__")
else:
    print(pause.get("kind") or "__NO_KIND__")
