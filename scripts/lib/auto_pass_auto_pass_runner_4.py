import json
import sys

try:
    payload = json.loads(sys.argv[1])
    errors = payload.get("errors") or []
    print(errors[0] if errors else "current-head gap ledger validation failed")
except Exception:
    print("current-head gap ledger validation failed")
