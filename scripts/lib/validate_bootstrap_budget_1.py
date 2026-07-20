"""Structured validator authority extracted from scripts/validate-bootstrap-budget.sh."""

import json
import os
import sys

threshold = int(sys.argv[1])
mode = sys.argv[2]
data = json.loads(os.environ["JSON_OUTPUT"])
tokens = int(data["shared_polaris_estimated_tokens"])
status = "PASS" if tokens <= threshold else ("WARN" if mode == "advisory" else "FAIL")

print(f"bootstrap_budget_status={status}")
print(f"shared_polaris_estimated_tokens={tokens}")
print(f"threshold={threshold}")
print(f"mode={mode}")
print(f"estimator={data.get('estimator', '')}")

if status == "FAIL":
    sys.exit(1)
