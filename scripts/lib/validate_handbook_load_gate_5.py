"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

import json
import os
import sys

try:
    data = json.loads(sys.argv[1])
except Exception as exc:
    print(f"invalid resolver JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)
required = ("config_path", "index_path", "scope_root", "scope_id")
if any(not isinstance(data.get(key), str) or not data[key] for key in required):
    print("resolver payload missing required path identity", file=sys.stderr)
    raise SystemExit(1)
if (
    os.path.realpath(data["scope_root"]) != os.path.realpath(sys.argv[2])
    or data["scope_id"] != sys.argv[3]
):
    print("resolver payload identity mismatch", file=sys.stderr)
    raise SystemExit(1)
if os.path.realpath(data["config_path"]) != os.path.realpath(sys.argv[4]):
    print("resolver config path is outside canonical project mapping", file=sys.stderr)
    raise SystemExit(1)
if os.path.realpath(data["index_path"]) != os.path.realpath(sys.argv[5]):
    print("resolver index path is outside canonical project mapping", file=sys.stderr)
    raise SystemExit(1)
if not os.path.isfile(data["config_path"]) or not os.path.isfile(data["index_path"]):
    print("resolver payload paths do not exist", file=sys.stderr)
    raise SystemExit(1)
print(data["index_path"])
