#!/usr/bin/env bash
# Selftest for build-review-prompt.sh.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
builder="$script_dir/build-review-prompt.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

workspace="$tmp/workspace"
base_dir="$tmp/repos"
out_with_handbook="$tmp/prompts-with-handbook"
out_without_handbook="$tmp/prompts-without-handbook"
manifest_with_handbook="$tmp/review-prompt-manifest.json"
mkdir -p "$base_dir/acme-web" "$base_dir/acme-api"

# 補充住在提供它的那支 skill 自己的目錄裡，由那支 skill 宣告出來（DP-484）。所以「有補充」
# 這條路要拿真的宣告去驗——假造一個目錄驗的是一條已經不存在的路。
#
# 哪一家不寫死：這支 selftest 會跟著 skill 樹被帶到別的 repo，而那裡的公司叫什麼名字
# 這裡不知道。掃宣告拿第一個；一支公司 skill 都沒有的樹（例如剛複製出去的 template）
# 就跳過這一半，並且說出來——安靜跳過會被下一個人讀成「這條路驗過了」。
notes_company="$(grep -rhoE '<!--[[:space:]]*[A-Za-z0-9_-]*REPO-NOTES-[a-z0-9-]+:' \
  "$script_dir/../.." --include='SKILL.md' 2>/dev/null \
  | sed -E 's/.*REPO-NOTES-([a-z0-9-]+):.*/\1/' | head -1 || true)"
if [[ -z "$notes_company" ]]; then
  echo "build-review-prompt-selftest: 這棵樹裡沒有任何公司 skill 宣告補充來源，"\
       "「有補充」那一半不驗（另一半照跑）。"
  exit 0
fi
notes_resolver="$(grep -rhoE "<!--[[:space:]]*[A-Za-z0-9_-]*REPO-NOTES-${notes_company}:[^>]+-->" \
  "$script_dir/../.." --include='SKILL.md' 2>/dev/null \
  | sed -E "s/.*REPO-NOTES-${notes_company}:[[:space:]]*//; s/[[:space:]]*-->$//" | head -1)"
notes_project="$( (cd "$script_dir/../../../.." && eval "$notes_resolver" --list) \
  | head -1 | tr -d '[:space:]')"
notes_handbook_marker="repo-notes/references/handbook/${notes_project}/"

candidates="$tmp/candidates.json"
cat > "$candidates" <<'JSON'
[
  {
    "repo": "acme-web",
    "number": 101,
    "title": "APP-3900 web change",
    "url": "https://github.com/acme/acme-web/pull/101",
    "author": "alice",
    "review_status": "needs_first_review",
    "review_detail": "first review",
    "model_tier": "standard_coding",
    "model_tier_reason": "cluster lead",
    "cluster_role": "cluster_lead",
    "cluster_key": "1776130982.981829:APP-3900",
    "cluster_size": 2,
    "cluster_lead_url": "https://github.com/acme/acme-web/pull/101",
    "ticket_key": "APP-3901",
    "root_ticket_key": "APP-3900",
    "slack_thread_ts": "1776130982.981829"
  },
  {
    "repo": "acme-api",
    "number": 102,
    "title": "APP-3900 api change",
    "url": "https://github.com/acme/acme-api/pull/102",
    "author": "bob",
    "review_status": "needs_re_approve",
    "review_detail": "new push after approve",
    "model_tier": "small_fast",
    "model_tier_reason": "sibling PR diff/sanity mode",
    "cluster_role": "cluster_sibling",
    "cluster_key": "1776130982.981829:APP-3900",
    "cluster_size": 2,
    "cluster_lead_url": "https://github.com/acme/acme-web/pull/101",
    "cluster_lead_summary": "lead has no findings",
    "ticket_key": "APP-3902",
    "root_ticket_key": "APP-3900",
    "slack_thread_ts": "1776130982.981829"
  }
]
JSON

"$builder" \
  --my-user reviewer \
  --base-dir "$base_dir" \
  --workspace "$workspace" \
  --company "$notes_company" \
  --project "$notes_project" \
  --out-dir "$out_with_handbook" \
  --manifest "$manifest_with_handbook" \
  < "$candidates" >/tmp/build-review-prompt-selftest.out

python3 - "$out_with_handbook" "$manifest_with_handbook" "$notes_handbook_marker" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
manifest = json.loads(Path(sys.argv[2]).read_text())
handbook_marker = sys.argv[3]
if len(manifest) != 2:
    raise SystemExit(f"unexpected manifest length: {len(manifest)}")
if manifest[0]["model_tier"] != "standard_coding":
    raise SystemExit(f"missing standard model tier in manifest: {manifest[0]}")
if manifest[1]["model_tier"] != "small_fast":
    raise SystemExit(f"missing small model tier in manifest: {manifest[1]}")
if manifest[0]["root_ticket_key"] != "APP-3900":
    raise SystemExit(f"missing root ticket in manifest: {manifest[0]}")
prompt = (out_dir / "review-prompt-acme-web-101.txt").read_text()
api_prompt = (out_dir / "review-prompt-acme-api-102.txt").read_text()
required = [
    "Inline Dispatch Context",
    "Review Flow",
    "Severity And Write Rules",
    "Submit Action",
    "Completion Envelope",
    "Verified project handbook paths:",
    handbook_marker,
    "gh pr diff https://github.com/acme/acme-web/pull/101 --name-only",
    "單 PR 累積上限為 100 行",
    "FAILURE / ERROR checks",
    "PASS checks must be omitted",
    "inspect-pr-section.sh",
    "Existing comments metadata-only",
    "(.body // \"\")[:80]",
    "sampled diff",
    "Model class hint: standard_coding",
    "Cluster role: cluster_lead",
    "Cluster / Model Tier Rules",
    "Ticket key: APP-3901",
    "Root ticket key: APP-3900",
    "Slack thread_ts: 1776130982.981829",
    "Runtime adapter policy: Do not dispatch this packet through a general-purpose sub-agent.",
    "Code Reviewer review packet",
]
for item in required:
    if item not in prompt:
        raise SystemExit(f"missing prompt content: {item}")
for item in [
    "Model class hint: small_fast",
    "Cluster role: cluster_sibling",
    "Sibling-diff mode",
    "lead has no findings",
    "needs_standard_review",
]:
    if item not in api_prompt:
        raise SystemExit(f"missing sibling prompt content: {item}")
for forbidden in [
    "review-pr/SKILL.md",
    "review-pr-entry-fetch-flow.md",
    "review-pr-analysis-flow.md",
    "review-pr-submit-flow.md",
    "repo-handbook.md",
]:
    if forbidden in prompt:
        raise SystemExit(f"forbidden reference leaked into prompt: {forbidden}")
PY

"$builder" \
  --my-user reviewer \
  --base-dir "$base_dir" \
  --workspace "$workspace" \
  --company acme \
  --project no-handbook \
  --out-dir "$out_without_handbook" \
  < "$candidates" >/tmp/build-review-prompt-selftest-empty.out

rg -q "No project handbook" "$out_without_handbook/review-prompt-acme-web-101.txt"

out_show_all="$tmp/prompts-show-all"
"$builder" \
  --my-user reviewer \
  --base-dir "$base_dir" \
  --workspace "$workspace" \
  --company acme \
  --project acme-web \
  --show-all-checks \
  --out-dir "$out_show_all" \
  < "$candidates" >/tmp/build-review-prompt-selftest-show-all.out

rg -q -- "--show-all-checks override is enabled" "$out_show_all/review-prompt-acme-web-101.txt"

echo "build-review-prompt selftest: PASS"
