import re
import sys

try:
    text = open(sys.argv[1], "r", encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)

matches = re.findall(r"evidence(?: written)?:\s*([^\s)]+)", text)
if matches:
    print(matches[-1])
