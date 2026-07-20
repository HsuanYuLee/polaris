import json
import sys

try:
    print(json.load(open(sys.argv[1], "r", encoding="utf-8")).get("status", ""))
except Exception:
    print("")
