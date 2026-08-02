#!/usr/bin/env bash
# resolve-pr-pickup-input.sh — Normalize pr-pickup intake into a deterministic artifact.
#
# Responsibilities:
# - Parse direct GitHub PR URLs from user input
# - Parse Slack thread context from Slack archive URLs or explicit context flags
# - Optionally extract PR URLs from Slack thread content via extract-pr-urls.py
# - Emit one machine-readable intake artifact for pr-pickup to consume

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: resolve-pr-pickup-input.sh --input "<text>" [options]

Options:
  --input TEXT             Original user input or composed intake text.
  --org ORG                GitHub org for Slack thread PR extraction.
  --slack-thread-file PATH Raw Slack thread export for PR extraction.
  --slack-channel-id ID    Explicit Slack channel override.
  --slack-thread-ts TS     Explicit Slack thread_ts override.
  --allow-empty-prs        Allow zero PR URLs; used for pre-read context parsing.
  --format FORMAT          json (default) or field.
  --field NAME             Field name when --format field.

Field names:
  source_type
  slack_source
  slack_channel_id
  slack_thread_ts
  pr_count
  pr_urls_json
  needs_slack_thread_read
EOF
  exit 2
}

input_text=""
github_org=""
slack_thread_file=""
slack_channel_id=""
slack_thread_ts=""
allow_empty_prs=0
format="json"
field_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      input_text="${2:-}"
      shift 2
      ;;
    --org)
      github_org="${2:-}"
      shift 2
      ;;
    --slack-thread-file)
      slack_thread_file="${2:-}"
      shift 2
      ;;
    --slack-channel-id)
      slack_channel_id="${2:-}"
      shift 2
      ;;
    --slack-thread-ts)
      slack_thread_ts="${2:-}"
      shift 2
      ;;
    --allow-empty-prs)
      allow_empty_prs=1
      shift
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    --field)
      field_name="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$input_text" ]]; then
  echo "error: --input is required" >&2
  usage
fi

if [[ "$format" != "json" && "$format" != "field" ]]; then
  echo "error: --format must be json or field" >&2
  exit 2
fi

if [[ "$format" == "field" && -z "$field_name" ]]; then
  echo "error: --field is required when --format field" >&2
  exit 2
fi

initial_json="$(python3 - "$input_text" "$slack_channel_id" "$slack_thread_ts" "$allow_empty_prs" <<'PY'
import json
import re
import sys

text = sys.argv[1]
channel_override = sys.argv[2]
thread_override = sys.argv[3]
allow_empty = sys.argv[4] == "1"

slack_url_re = re.compile(r'https://[A-Za-z0-9.-]+\.slack\.com/archives/([A-Z0-9]+)/p(\d{16,})')
pr_url_re = re.compile(r'https://github\.com/[^/\s|>]+/[^/\s|>]+/pull/\d+')

def p_to_ts(raw):
    if len(raw) <= 6:
        return None
    return f"{raw[:-6]}.{raw[-6:]}"

slack_match = slack_url_re.search(text)
slack_source = bool(slack_match or (channel_override and thread_override))
channel_id = channel_override or (slack_match.group(1) if slack_match else "")
thread_ts = thread_override or (p_to_ts(slack_match.group(2)) if slack_match else "")

seen = set()
pr_urls = []
for match in pr_url_re.findall(text):
    url = re.sub(r'#.*$', '', match)
    if url in seen:
        continue
    seen.add(url)
    pr_urls.append(url)

needs_slack_thread_read = bool(slack_source and not pr_urls)
source_type = "direct_pr_url"
if slack_source and pr_urls:
    source_type = "direct_pr_with_slack_context"
elif slack_source:
    source_type = "slack_context_only"

artifact = {
    "source_type": source_type,
    "slack_source": slack_source,
    "slack_channel_id": channel_id,
    "slack_thread_ts": thread_ts,
    "pr_urls": pr_urls,
    "pr_count": len(pr_urls),
    "needs_slack_thread_read": needs_slack_thread_read,
}

if not allow_empty and not pr_urls:
    print(json.dumps(artifact))
    sys.exit(7)

print(json.dumps(artifact))
PY
)" || initial_status=$?

initial_status="${initial_status:-0}"

if [[ "$initial_status" -ne 0 && "$initial_status" -ne 7 ]]; then
  echo "error: failed to parse input" >&2
  exit "$initial_status"
fi

final_json="$initial_json"

if [[ -n "$slack_thread_file" ]]; then
  if [[ ! -f "$slack_thread_file" ]]; then
    echo "error: slack thread file not found: $slack_thread_file" >&2
    exit 1
  fi
  if [[ -z "$github_org" ]]; then
    echo "error: --org is required when --slack-thread-file is provided" >&2
    exit 1
  fi

  resolved_thread_ts="$(printf '%s' "$initial_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("slack_thread_ts",""))')"
  if [[ -z "$resolved_thread_ts" ]]; then
    echo "error: slack thread context missing; provide Slack URL or explicit --slack-thread-ts" >&2
    exit 1
  fi

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  extractor="$script_dir/../../review-inbox/scripts/extract-pr-urls.py"
  if [[ ! -f "$extractor" ]]; then
    echo "error: extractor script missing: $extractor" >&2
    exit 1
  fi

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  mapping_file="$tmp_dir/mapping.json"
  urls_file="$tmp_dir/urls.txt"

  python3 "$extractor" --org "$github_org" --thread-ts "$resolved_thread_ts" --mapping "$mapping_file" \
    < "$slack_thread_file" > "$urls_file"

  final_json="$(python3 - "$initial_json" "$urls_file" "$mapping_file" <<'PY'
import json
import sys
from pathlib import Path

artifact = json.loads(sys.argv[1])
urls = [line.strip() for line in Path(sys.argv[2]).read_text().splitlines() if line.strip()]
mapping = json.loads(Path(sys.argv[3]).read_text())

seen = set()
merged = []
for url in artifact.get("pr_urls", []) + urls:
    if url in seen:
        continue
    seen.add(url)
    merged.append(url)

artifact["pr_urls"] = merged
artifact["pr_count"] = len(merged)
artifact["needs_slack_thread_read"] = False

if artifact.get("slack_source"):
    if merged:
        artifact["source_type"] = "slack_thread_url"
    else:
        artifact["source_type"] = "slack_thread_url"

if mapping:
    first_url = merged[0] if merged else None
    if first_url and isinstance(mapping.get(first_url), dict):
      mapped = mapping[first_url]
      if not artifact.get("slack_thread_ts") and mapped.get("thread_ts"):
          artifact["slack_thread_ts"] = str(mapped["thread_ts"])

print(json.dumps(artifact))
PY
)"
fi

final_pr_count="$(printf '%s' "$final_json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["pr_count"])')"
final_needs_thread="$(printf '%s' "$final_json" | python3 -c 'import sys,json; print("true" if json.load(sys.stdin)["needs_slack_thread_read"] else "false")')"

if [[ "$allow_empty_prs" -ne 1 && "$final_pr_count" -eq 0 ]]; then
  if [[ "$final_needs_thread" == "true" ]]; then
    echo "error: no PR URL resolved yet; Slack thread content must be read first" >&2
  else
    echo "error: no PR URL found in input" >&2
  fi
  exit 1
fi

if [[ "$format" == "json" ]]; then
  printf '%s\n' "$final_json"
  exit 0
fi

python3 - "$final_json" "$field_name" <<'PY'
import json
import sys

artifact = json.loads(sys.argv[1])
field = sys.argv[2]

if field == "pr_urls_json":
    print(json.dumps(artifact.get("pr_urls", [])))
    sys.exit(0)

if field not in artifact:
    print(f"error: unknown field: {field}", file=sys.stderr)
    sys.exit(1)

value = artifact[field]
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (list, dict)):
    print(json.dumps(value))
else:
    print("" if value is None else value)
PY
