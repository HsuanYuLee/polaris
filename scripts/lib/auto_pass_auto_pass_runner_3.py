import json
import sys

try:
    value = json.loads(sys.argv[1]).get("container")
except Exception:
    value = None
print(value if isinstance(value, str) else "")
