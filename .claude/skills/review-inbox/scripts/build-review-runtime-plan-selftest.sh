#!/usr/bin/env bash
# Selftest for build-review-runtime-plan.py.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
planner="$script_dir/build-review-runtime-plan.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

candidates="$tmp/candidates.json"
manifest="$tmp/manifest.json"
plan="$tmp/runtime-plan.json"

cat > "$candidates" <<'JSON'
[
  {
    "repo": "demo-web",
    "number": 10,
    "title": "APP-3900 lead",
    "url": "https://github.com/demo/demo-web/pull/10",
    "review_status": "needs_first_review",
    "model_tier": "standard_coding",
    "cluster_role": "cluster_lead",
    "cluster_key": "1776130982.981829:APP-3900",
    "cluster_size": 3,
    "cluster_lead_url": "https://github.com/demo/demo-web/pull/10",
    "ticket_key": "APP-3901",
    "root_ticket_key": "APP-3900"
  },
  {
    "repo": "demo-api",
    "number": 20,
    "title": "APP-3900 sibling api",
    "url": "https://github.com/demo/demo-api/pull/20",
    "review_status": "needs_first_review",
    "model_tier": "small_fast",
    "cluster_role": "cluster_sibling",
    "cluster_key": "1776130982.981829:APP-3900",
    "cluster_size": 3,
    "cluster_lead_url": "https://github.com/demo/demo-web/pull/10",
    "ticket_key": "APP-3902",
    "root_ticket_key": "APP-3900"
  },
  {
    "repo": "demo-web",
    "number": 21,
    "title": "APP-3900 sibling web",
    "url": "https://github.com/demo/demo-web/pull/21",
    "review_status": "needs_first_review",
    "model_tier": "small_fast",
    "cluster_role": "cluster_sibling",
    "cluster_key": "1776130982.981829:APP-3900",
    "cluster_size": 3,
    "cluster_lead_url": "https://github.com/demo/demo-web/pull/10",
    "ticket_key": "APP-3903",
    "root_ticket_key": "APP-3900"
  },
  {
    "repo": "demo-web",
    "number": 30,
    "title": "APP-4000 standalone",
    "url": "https://github.com/demo/demo-web/pull/30",
    "review_status": "needs_first_review",
    "model_tier": "standard_coding",
    "cluster_role": "standalone",
    "cluster_key": "1776130999.000000:APP-4000",
    "cluster_size": 1,
    "ticket_key": "APP-4000"
  }
]
JSON

cat > "$manifest" <<'JSON'
[
  {"pr_url": "https://github.com/demo/demo-web/pull/10", "file": "/tmp/prompts/review-prompt-demo-web-10.txt"},
  {"pr_url": "https://github.com/demo/demo-api/pull/20", "file": "/tmp/prompts/review-prompt-demo-api-20.txt"},
  {"pr_url": "https://github.com/demo/demo-web/pull/21", "file": "/tmp/prompts/review-prompt-demo-web-21.txt"},
  {"pr_url": "https://github.com/demo/demo-web/pull/30", "file": "/tmp/prompts/review-prompt-demo-web-30.txt"}
]
JSON

"$planner" --manifest "$manifest" --out "$plan" < "$candidates"

python3 - "$plan" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text())
if plan["schema"] != "review-inbox-runtime-plan.v1":
    raise SystemExit("schema mismatch")
policy = plan["adapter_policy"]
if policy["general_purpose_subagent_allowed"] is not False:
    raise SystemExit("general-purpose subagent must be disabled")
if policy["fallback"] != "main_session_sequential":
    raise SystemExit(f"unexpected fallback: {policy}")

steps = plan["steps"]
if [step["phase"] for step in steps[:3]] != ["cluster_lead", "cluster_sibling", "cluster_sibling"]:
    raise SystemExit(f"cluster lead/sibling order mismatch: {steps}")
if steps[0]["requires_lead_summary"]:
    raise SystemExit("lead must not require lead summary")
if not all(step["requires_lead_summary"] for step in steps[1:3]):
    raise SystemExit("siblings must require lead summary")
if steps[1]["lead_summary_path"] != steps[0]["lead_summary_path"]:
    raise SystemExit("cluster members must share lead summary path")
if steps[1]["prompt_file"] != "/tmp/prompts/review-prompt-demo-api-20.txt":
    raise SystemExit("manifest prompt file not attached")
if steps[3]["phase"] != "standalone":
    raise SystemExit("standalone step missing")
if steps[3]["general_purpose_subagent_allowed"] is not False:
    raise SystemExit("standalone also must disable general-purpose subagent")
PY

echo "build-review-runtime-plan selftest: PASS"
