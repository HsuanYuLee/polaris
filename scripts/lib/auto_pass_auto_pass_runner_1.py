import json
import sys

try:
    value = json.load(open(sys.argv[1], encoding="utf-8")).get("source_id")
except Exception:
    value = None
print(value if isinstance(value, str) else "")
