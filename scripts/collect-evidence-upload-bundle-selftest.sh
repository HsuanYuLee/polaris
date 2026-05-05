#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR" "$CI_EVIDENCE"' EXIT

REPO="$WORKDIR/repo"
SOURCE="$WORKDIR/specs/EPIC-999"
TICKET="TASK-9999"
HEAD_SHA="abcdef1234567890abcdef1234567890abcdef12"
CI_EVIDENCE="/tmp/polaris-ci-local-task-${TICKET}-${HEAD_SHA:0:12}-selftest.json"

mkdir -p \
  "$REPO/.polaris/evidence/verify" \
  "$REPO/.polaris/evidence/vr/artifacts/$TICKET/baseline" \
  "$REPO/.polaris/evidence/vr/artifacts/$TICKET/compare" \
  "$REPO/.polaris/evidence/playwright/$TICKET" \
  "$REPO/.polaris/evidence/behavior/$TICKET/compare-abc123" \
  "$SOURCE"

printf '{"writer":"run-verify-command.sh","head_sha":"%s","status":"PASS"}\n' "$HEAD_SHA" \
  >"$REPO/.polaris/evidence/verify/polaris-verified-${TICKET}-${HEAD_SHA}.json"
printf '{"writer":"run-visual-snapshot.sh","head_sha":"%s","status":"PASS","mode":"compare"}\n' "$HEAD_SHA" \
  >"$REPO/.polaris/evidence/vr/polaris-vr-${TICKET}-${HEAD_SHA}.json"
printf 'baseline-image\n' >"$REPO/.polaris/evidence/vr/artifacts/$TICKET/baseline/zh-tw-product-12156.png"
printf 'compare-image\n' >"$REPO/.polaris/evidence/vr/artifacts/$TICKET/compare/zh-tw-product-12156.png"
printf 'webm-video\n' >"$REPO/.polaris/evidence/playwright/$TICKET/media-lightbox.webm"
printf 'behavior-png\n' >"$REPO/.polaris/evidence/behavior/$TICKET/compare-abc123/behavior-screen.png"
printf 'behavior-webm\n' >"$REPO/.polaris/evidence/behavior/$TICKET/compare-abc123/behavior-video.webm"
cat >"$REPO/.polaris/evidence/playwright/$TICKET/playwright-behavior-video.json" <<JSON
{
  "ticket": "$TICKET",
  "head_sha": "$HEAD_SHA",
  "video": "media-lightbox.webm"
}
JSON
cat >"$REPO/.polaris/evidence/behavior/$TICKET/polaris-behavior-${TICKET}-${HEAD_SHA}-abc123.json" <<JSON
{
  "ticket": "$TICKET",
  "head_sha": "$HEAD_SHA",
  "writer": "run-behavior-contract.sh",
  "mode": "compare",
  "behavior_mode": "pm_flow",
  "status": "PASS",
  "at": "2026-05-05T00:00:00Z",
  "context_hash": "abc123",
  "screenshots": ["$REPO/.polaris/evidence/behavior/$TICKET/compare-abc123/behavior-screen.png"],
  "videos": ["$REPO/.polaris/evidence/behavior/$TICKET/compare-abc123/behavior-video.webm"]
}
JSON
printf '{"writer":"ci-local.sh","head_sha":"%s","status":"PASS"}\n' "$HEAD_SHA" >"$CI_EVIDENCE"

output="$(bash "$ROOT/scripts/collect-evidence-upload-bundle.sh" \
  --repo "$REPO" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --source-container "$SOURCE" \
  --target pr)"

bundle_dir="$(python3 - "$output" <<'PY'
import json
import sys
print(json.loads(sys.argv[1])["output_dir"])
PY
)"

[[ -f "$bundle_dir/README.md" ]] || { echo "missing README.md" >&2; exit 1; }
[[ -f "$bundle_dir/manifest.json" ]] || { echo "missing manifest.json" >&2; exit 1; }
grep -q "required publication files" "$bundle_dir/README.md"

python3 - "$bundle_dir/manifest.json" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
items = manifest["items"]
bundle_paths = [item["bundle_path"] for item in items]
assert len(bundle_paths) == len(set(bundle_paths)), "bundle filenames must be unique"
assert any(item["kind"] == "playwright_video" and item["requires_publication"] for item in items)
assert any(item["kind"] == "behavior" and item["requires_publication"] for item in items)
assert any(item["kind"] == "behavior_media" and item["requires_publication"] for item in items)
assert any(item["kind"] == "ci_local" and not item["requires_publication"] for item in items)
vr_pngs = [item for item in items if item["kind"] == "vr_artifact" and item["bundle_path"].endswith("zh-tw-product-12156.png")]
assert len(vr_pngs) == 2, f"expected two collision-prone VR pngs, got {len(vr_pngs)}"
required = [item for item in items if item["requires_publication"]]
assert len(required) >= 7, f"expected required publication evidence, got {len(required)}"
PY

echo "PASS: collect-evidence-upload-bundle selftest"
