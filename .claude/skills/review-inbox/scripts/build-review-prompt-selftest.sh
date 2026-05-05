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
mkdir -p "$workspace/acme/polaris-config/acme-web/handbook" "$base_dir/acme-web" "$base_dir/acme-api"
printf '# Handbook\n' > "$workspace/acme/polaris-config/acme-web/handbook/index.md"

candidates="$tmp/candidates.json"
cat > "$candidates" <<'JSON'
[
  {
    "repo": "acme-web",
    "number": 101,
    "title": "web change",
    "url": "https://github.com/acme/acme-web/pull/101",
    "author": "alice",
    "review_status": "needs_first_review",
    "review_detail": "first review"
  },
  {
    "repo": "acme-api",
    "number": 102,
    "title": "api change",
    "url": "https://github.com/acme/acme-api/pull/102",
    "author": "bob",
    "review_status": "needs_re_approve",
    "review_detail": "new push after approve"
  }
]
JSON

"$builder" \
  --my-user reviewer \
  --base-dir "$base_dir" \
  --workspace "$workspace" \
  --company acme \
  --project acme-web \
  --out-dir "$out_with_handbook" \
  < "$candidates" >/tmp/build-review-prompt-selftest.out

python3 - "$out_with_handbook" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
manifest = json.loads(Path("/tmp/review-prompt-manifest.json").read_text())
if len(manifest) != 2:
    raise SystemExit(f"unexpected manifest length: {len(manifest)}")
prompt = (out_dir / "review-prompt-acme-web-101.txt").read_text()
required = [
    "Inline Dispatch Context",
    "Review Flow",
    "Severity And Write Rules",
    "Submit Action",
    "Completion Envelope",
    "Verified project handbook paths:",
    "acme/polaris-config/acme-web/handbook/index.md",
    "gh pr diff https://github.com/acme/acme-web/pull/101 --name-only",
    "Existing comments metadata-only",
    "(.body // \"\")[:80]",
    "sampled diff",
]
for item in required:
    if item not in prompt:
        raise SystemExit(f"missing prompt content: {item}")
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

echo "build-review-prompt selftest: PASS"
