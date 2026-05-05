#!/usr/bin/env bash
# scripts/run-visual-snapshot.sh — native visual regression evidence writer.
#
# Vertical slice contract:
#   run-visual-snapshot.sh --task-md PATH --mode baseline|compare|record [--repo PATH]
#
# Writes head_sha-bound Layer C evidence:
#   /tmp/polaris-vr-{ticket}-{head_sha}.json
#   {repo}/.polaris/evidence/vr/polaris-vr-{ticket}-{head_sha}.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"
TOOLCHAIN_DIR="$WORKSPACE_ROOT/tools/polaris-toolchain"

usage() {
  cat >&2 <<'EOF'
Usage:
  run-visual-snapshot.sh --task-md PATH --mode baseline|compare|record [--repo PATH] [--ticket KEY] [--source-container PATH] [--output-dir PATH] [--fixture-dir PATH]

Captures before/after screenshots for task.md verification.visual_regression
and writes /tmp/polaris-vr-{ticket}-{head_sha}.json evidence.

When --fixture-dir or Test Environment Fixtures is provided, baseline/compare
run against reviewed fixture-backed pages. Missing fixtures block as
BLOCKED_ENV; unreviewed fixtures block as MANUAL_REQUIRED.
EOF
}

TASK_MD=""
MODE=""
REPO_OVERRIDE=""
TICKET=""
SOURCE_CONTAINER=""
OUTPUT_DIR=""
FIXTURE_DIR_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --fixture-dir) FIXTURE_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "run-visual-snapshot: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TASK_MD" || -z "$MODE" ]]; then
  usage
  exit 2
fi
if [[ "$MODE" != "baseline" && "$MODE" != "compare" && "$MODE" != "record" ]]; then
  echo "run-visual-snapshot: --mode must be baseline, compare, or record (got: $MODE)" >&2
  exit 2
fi
if [[ ! -f "$TASK_MD" ]]; then
  echo "run-visual-snapshot: --task-md path not found: $TASK_MD" >&2
  exit 1
fi
if [[ ! -x "$PARSE_TASK_MD" ]]; then
  echo "run-visual-snapshot: parse-task-md.sh not executable at $PARSE_TASK_MD" >&2
  exit 1
fi

parse_field() {
  local field="$1"
  "$PARSE_TASK_MD" --field "$field" --no-resolve "$TASK_MD" 2>/dev/null || true
}

resolve_repo_path() {
  local override="$1"
  local repo_name="$2"
  local task_dir probe

  if [[ -n "$override" && -d "$override" ]]; then
    (cd "$override" && pwd)
    return 0
  fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi

  task_dir="$(cd "$(dirname "$TASK_MD")" && pwd)"
  while [[ "$task_dir" != "/" ]]; do
    probe="$task_dir/$repo_name"
    if [[ -d "$probe/.git" || -f "$probe/.git" ]]; then
      (cd "$probe" && pwd)
      return 0
    fi
    task_dir="$(dirname "$task_dir")"
  done
  return 1
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

abs_path_for_output() {
  local path_value="$1"
  if [[ "$path_value" = /* ]]; then
    printf '%s\n' "$path_value"
    return 0
  fi
  printf '%s/%s\n' "$PWD" "$path_value"
}

is_na_value() {
  local value="$1"
  [[ -z "$value" || "$value" == "N/A" || "$value" == "n/a" || "$value" == "NA" || "$value" == "na" || "$value" == "-" ]]
}

resolve_fixture_dir() {
  local raw="$1"
  local source_container="$2"
  local repo_path="$3"
  local task_dir

  if is_na_value "$raw"; then
    return 1
  fi
  if [[ "$raw" = /* ]]; then
    printf '%s\n' "$raw"
    return 0
  fi

  task_dir="$(cd "$(dirname "$TASK_MD")" && pwd)"
  if [[ -n "$source_container" && -d "$source_container/$raw" ]]; then
    (cd "$source_container/$raw" && pwd)
    return 0
  fi
  if [[ -d "$task_dir/$raw" ]]; then
    (cd "$task_dir/$raw" && pwd)
    return 0
  fi
  if [[ -d "$repo_path/$raw" ]]; then
    (cd "$repo_path/$raw" && pwd)
    return 0
  fi

  printf '%s/%s\n' "$source_container" "$raw"
}

write_evidence() {
  local status="$1"
  local triggered="$2"
  local result_json="${3:-}"
  local error_message="${4:-}"
  local evidence_file="$5"
  local durable_file="$6"

  mkdir -p "$(dirname "$evidence_file")" "$(dirname "$durable_file")"
  python3 - "$evidence_file" "$durable_file" "$status" "$triggered" "$result_json" "$error_message" <<'PY'
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

evidence_file, durable_file, status, triggered_raw, result_path, error_message = sys.argv[1:7]
triggered = triggered_raw == "true"

def env(name):
    value = os.environ.get(name)
    return value if value != "" else None

result = {}
if result_path and os.path.exists(result_path) and os.path.getsize(result_path) > 0:
    with open(result_path, "r", encoding="utf-8") as handle:
        result = json.load(handle)

payload = {
    "writer": "run-visual-snapshot.sh",
    "ticket": env("VR_TICKET"),
    "head_sha": env("VR_HEAD_SHA"),
    "mode": env("VR_MODE"),
    "triggered": triggered,
    "status": status,
    "expected": env("VR_EXPECTED"),
    "pages": result.get("pages", []),
    "artifacts": {
        "output_dir": env("VR_OUTPUT_DIR"),
        "result_json": result_path or None,
        "baseline_dir": result.get("baseline_dir"),
        "compare_dir": result.get("compare_dir"),
        "diff_dir": result.get("diff_dir"),
        "fixture_dir": env("VR_FIXTURE_DIR"),
        "fixture_manifest": result.get("fixture_manifest") or env("VR_FIXTURE_MANIFEST"),
    },
    "runtime_contract": {
        "level": env("VR_LEVEL"),
        "runtime_verify_target": env("VR_RUNTIME_VERIFY_TARGET"),
        "source_container": env("VR_SOURCE_CONTAINER"),
        "fixture_mode": env("VR_FIXTURE_MODE"),
    },
    "error": error_message or result.get("error"),
    "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}

with open(evidence_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
shutil.copyfile(evidence_file, durable_file)
PY
}

REPO_NAME="$(parse_field repo)"
REPO_PATH="$(resolve_repo_path "$REPO_OVERRIDE" "$REPO_NAME" || true)"
if [[ -z "$REPO_PATH" ]]; then
  echo "run-visual-snapshot: could not resolve repo path" >&2
  exit 1
fi

HEAD_SHA="$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || true)"
if [[ -z "$HEAD_SHA" ]]; then
  echo "run-visual-snapshot: git rev-parse HEAD failed in $REPO_PATH" >&2
  exit 1
fi

TASK_TICKET="$(parse_field task_jira_key)"
if [[ -z "$TICKET" ]]; then
  TICKET="$TASK_TICKET"
fi
if [[ -z "$TICKET" ]]; then
  echo "run-visual-snapshot: ticket not provided and not parseable from task.md" >&2
  exit 1
fi

SAFE_TICKET="$(safe_name "$TICKET")"
EXPECTED="$(parse_field verification_visual_regression_expected)"
PAGES_RAW="$(parse_field verification_visual_regression_pages)"
LEVEL="$(parse_field level)"
RUNTIME_VERIFY_TARGET="$(parse_field runtime_verify_target)"
FIXTURES_FIELD="$(parse_field fixtures)"

if [[ -z "$SOURCE_CONTAINER" ]]; then
  SOURCE_CONTAINER="$(cd "$(dirname "$TASK_MD")/.." && pwd 2>/dev/null || dirname "$TASK_MD")"
fi
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$REPO_PATH/.polaris/evidence/vr/artifacts/$SAFE_TICKET"
fi
OUTPUT_DIR="$(abs_path_for_output "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_DIR"

FIXTURE_DIR=""
if ! is_na_value "$FIXTURE_DIR_OVERRIDE"; then
  FIXTURE_DIR="$(resolve_fixture_dir "$FIXTURE_DIR_OVERRIDE" "$SOURCE_CONTAINER" "$REPO_PATH")"
elif ! is_na_value "$FIXTURES_FIELD"; then
  FIXTURE_DIR="$(resolve_fixture_dir "$FIXTURES_FIELD" "$SOURCE_CONTAINER" "$REPO_PATH")"
fi
FIXTURE_MANIFEST=""
FIXTURE_MODE="off"
if [[ -n "$FIXTURE_DIR" ]]; then
  FIXTURE_DIR="$(abs_path_for_output "$FIXTURE_DIR")"
  FIXTURE_MANIFEST="$FIXTURE_DIR/visual-fixtures.json"
  if [[ "$MODE" == "record" ]]; then
    FIXTURE_MODE="record"
  else
    FIXTURE_MODE="replay"
  fi
fi

EVIDENCE_FILE="/tmp/polaris-vr-${SAFE_TICKET}-${HEAD_SHA}.json"
DURABLE_FILE="$REPO_PATH/.polaris/evidence/vr/polaris-vr-${SAFE_TICKET}-${HEAD_SHA}.json"

export VR_TICKET="$TICKET"
export VR_HEAD_SHA="$HEAD_SHA"
export VR_MODE="$MODE"
export VR_EXPECTED="$EXPECTED"
export VR_LEVEL="$LEVEL"
export VR_RUNTIME_VERIFY_TARGET="$RUNTIME_VERIFY_TARGET"
export VR_SOURCE_CONTAINER="$SOURCE_CONTAINER"
export VR_OUTPUT_DIR="$OUTPUT_DIR"
export VR_FIXTURE_DIR="$FIXTURE_DIR"
export VR_FIXTURE_MANIFEST="$FIXTURE_MANIFEST"
export VR_FIXTURE_MODE="$FIXTURE_MODE"

if [[ -z "$EXPECTED" ]]; then
  write_evidence "SKIP" "false" "" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: SKIP — no verification.visual_regression declaration"
  echo "run-visual-snapshot: evidence at $EVIDENCE_FILE"
  exit 0
fi

if [[ "$LEVEL" != "runtime" ]]; then
  write_evidence "BLOCKED_ENV" "true" "" "visual_regression requires Test Environment Level=runtime" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BLOCKED_ENV — visual_regression requires Level=runtime" >&2
  exit 1
fi
if [[ -z "$RUNTIME_VERIFY_TARGET" ]]; then
  write_evidence "BLOCKED_ENV" "true" "" "runtime_verify_target is missing" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BLOCKED_ENV — runtime_verify_target is missing" >&2
  exit 1
fi
if [[ "$MODE" == "record" && -z "$FIXTURE_DIR" ]]; then
  write_evidence "BLOCKED_ENV" "true" "" "record mode requires --fixture-dir or Test Environment Fixtures" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BLOCKED_ENV — record mode requires fixture dir" >&2
  exit 1
fi
if ! (cd "$TOOLCHAIN_DIR" && pnpm exec node -e "const { createRequire } = require('module'); const r = createRequire(process.cwd() + '/package.json'); r('@playwright/test')" >/dev/null 2>&1); then
  write_evidence "BLOCKED_ENV" "true" "" "Playwright dependency is missing in tools/polaris-toolchain" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BLOCKED_ENV — Playwright dependency is missing" >&2
  exit 1
fi

PAGES_JSON="$(PAGES_RAW="$PAGES_RAW" RUNTIME_VERIFY_TARGET="$RUNTIME_VERIFY_TARGET" python3 - <<'PY'
import json
import os
from urllib.parse import urlparse, urlunparse

target = os.environ["RUNTIME_VERIFY_TARGET"]
raw = os.environ.get("PAGES_RAW", "")
parsed = urlparse(target)
origin = urlunparse((parsed.scheme, parsed.netloc, "", "", "", ""))
pages = [line.strip() for line in raw.splitlines() if line.strip()]
if not pages:
    pages = [parsed.path or "/"]

items = []
for page in pages:
    if page.startswith("http://") or page.startswith("https://"):
        url = page
        path = urlparse(page).path or "/"
    else:
        path = page if page.startswith("/") else "/" + page
        url = origin + path
    items.append({"path": path, "url": url})
print(json.dumps(items, ensure_ascii=False))
PY
)"

CAPTURE_PAGES_JSON="$PAGES_JSON"
if [[ "$FIXTURE_MODE" == "replay" ]]; then
  if [[ ! -f "$FIXTURE_MANIFEST" ]]; then
    write_evidence "BLOCKED_ENV" "true" "" "fixture replay requested but manifest is missing: $FIXTURE_MANIFEST" "$EVIDENCE_FILE" "$DURABLE_FILE"
    echo "run-visual-snapshot: BLOCKED_ENV — fixture manifest is missing" >&2
    exit 1
  fi
  REVIEWED="$(python3 - "$FIXTURE_MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print("true" if data.get("reviewed") is True else "false")
PY
)"
  if [[ "$REVIEWED" != "true" ]]; then
    write_evidence "MANUAL_REQUIRED" "true" "" "fixture manifest requires first-run human review: $FIXTURE_MANIFEST" "$EVIDENCE_FILE" "$DURABLE_FILE"
    echo "run-visual-snapshot: MANUAL_REQUIRED — fixture manifest requires review" >&2
    exit 1
  fi
  CAPTURE_PAGES_JSON="$(PAGES_JSON="$PAGES_JSON" FIXTURE_MANIFEST="$FIXTURE_MANIFEST" python3 - <<'PY'
import json
import os
import pathlib
import sys
from urllib.parse import urlparse

requested = json.loads(os.environ["PAGES_JSON"])
manifest_path = pathlib.Path(os.environ["FIXTURE_MANIFEST"])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
by_path = {item.get("path"): item for item in manifest.get("pages", [])}
items = []
missing = []
for page in requested:
    record = by_path.get(page["path"])
    if not record:
        missing.append(page["path"])
        continue
    fixture_file = manifest_path.parent / record["file"]
    if not fixture_file.exists():
        missing.append(page["path"])
        continue
    items.append({
        "path": page["path"],
        "url": record.get("url") or page["url"],
        "capture_url": fixture_file.resolve().as_uri(),
        "fixture_file": str(fixture_file),
    })
if missing:
    raise SystemExit("missing fixture page(s): " + ", ".join(missing))
print(json.dumps(items, ensure_ascii=False))
PY
)" || {
    write_evidence "BLOCKED_ENV" "true" "" "fixture replay requested but fixture pages are missing" "$EVIDENCE_FILE" "$DURABLE_FILE"
    echo "run-visual-snapshot: BLOCKED_ENV — fixture pages are missing" >&2
    exit 1
  }
elif [[ "$FIXTURE_MODE" == "record" ]]; then
  mkdir -p "$FIXTURE_DIR/pages"
fi

CAPTURE_TMP_DIR="$(mktemp -d -t polaris-vr-capture.XXXXXX)"
CAPTURE_SCRIPT="$CAPTURE_TMP_DIR/capture.mjs"
RESULT_JSON="$(mktemp -t polaris-vr-result.XXXXXX.json)"
trap 'rm -rf "$CAPTURE_TMP_DIR"; rm -f "$RESULT_JSON"' EXIT

cat >"$CAPTURE_SCRIPT" <<'NODE'
import { createHash } from 'crypto'
import { createRequire } from 'module'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs'
import path from 'path'

const require = createRequire(`${process.cwd()}/package.json`)
const { chromium } = require('@playwright/test')

const [mode, pagesJson, outputDir, resultPath, fixtureMode, fixtureDir, fixtureManifest] = process.argv.slice(2)
const pages = JSON.parse(pagesJson)
const baselineDir = path.join(outputDir, 'baseline')
const compareDir = path.join(outputDir, 'compare')
const diffDir = path.join(outputDir, 'diff')
mkdirSync(baselineDir, { recursive: true })
mkdirSync(compareDir, { recursive: true })
mkdirSync(diffDir, { recursive: true })

function slugFor(pagePath) {
  return pagePath.replace(/^\/+/, '').replace(/[^A-Za-z0-9._-]+/g, '-') || 'root'
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex')
}

function sha256Text(value) {
  return createHash('sha256').update(value).digest('hex')
}

const browser = await chromium.launch({ headless: true })
const context = await browser.newContext({
  viewport: { width: 1280, height: 720 },
  deviceScaleFactor: 1,
  ignoreHTTPSErrors: true,
  locale: 'zh-TW',
})

const results = []
const fixtureRecords = []
let blocked = false

try {
  for (const target of pages) {
    const slug = slugFor(target.path)
    const page = await context.newPage()
    const captureUrl = target.capture_url || target.url
    const response = await page.goto(captureUrl, { waitUntil: 'domcontentloaded', timeout: 45000 })
    await page.waitForLoadState('load', { timeout: 10000 }).catch(() => {})
    await page.waitForTimeout(1000)
    const httpStatus = response ? response.status() : null
    const bodyText = await page.evaluate(() => document.body?.innerText?.trim() || '')
    const pageBlocked = httpStatus === null || httpStatus >= 400 || bodyText.length === 0

    const baselinePath = path.join(baselineDir, `${slug}.png`)
    const comparePath = path.join(compareDir, `${slug}.png`)
    const diffPath = path.join(diffDir, `${slug}.json`)

    if (mode === 'record') {
      const html = await page.content()
      const relativeFile = `pages/${slug}.html`
      const fixturePath = path.join(fixtureDir, relativeFile)
      mkdirSync(path.dirname(fixturePath), { recursive: true })
      writeFileSync(fixturePath, html)
      if (pageBlocked) blocked = true
      const fixtureRecord = {
        path: target.path,
        url: target.url,
        file: relativeFile,
        sha256: sha256Text(html),
        http_status: httpStatus,
        text_length: bodyText.length,
      }
      fixtureRecords.push(fixtureRecord)
      results.push({
        path: target.path,
        url: target.url,
        http_status: httpStatus,
        text_length: bodyText.length,
        status: pageBlocked ? 'BLOCKED_ENV' : 'MANUAL_REQUIRED',
        error: pageBlocked ? 'page returned non-OK status or blank body' : 'fixture recorded; first-run review required',
        fixture_file: fixturePath,
        fixture_sha256: fixtureRecord.sha256,
        changed: false,
      })
    } else if (mode === 'baseline') {
      await page.screenshot({ path: baselinePath, fullPage: true })
      if (pageBlocked) blocked = true
      results.push({
        path: target.path,
        url: target.url,
        capture_url: captureUrl,
        http_status: httpStatus,
        text_length: bodyText.length,
        status: pageBlocked ? 'BLOCKED_ENV' : 'OK',
        error: pageBlocked ? 'page returned non-OK status or blank body' : undefined,
        baseline_screenshot: baselinePath,
        baseline_sha256: sha256(baselinePath),
        changed: false,
      })
    } else {
      if (!existsSync(baselinePath)) {
        blocked = true
        results.push({
          path: target.path,
          url: target.url,
          capture_url: captureUrl,
          http_status: httpStatus,
          text_length: bodyText.length,
          baseline_screenshot: baselinePath,
          status: 'BLOCKED_ENV',
          error: 'missing baseline screenshot',
        })
      } else {
        await page.screenshot({ path: comparePath, fullPage: true })
        if (pageBlocked) blocked = true
        const baselineSha = sha256(baselinePath)
        const compareSha = sha256(comparePath)
        const changed = baselineSha !== compareSha
        const diff = {
          path: target.path,
          url: target.url,
          capture_url: captureUrl,
          baseline_sha256: baselineSha,
          after_sha256: compareSha,
          changed,
        }
        writeFileSync(diffPath, JSON.stringify(diff, null, 2) + '\n')
        results.push({
          path: target.path,
          url: target.url,
          capture_url: captureUrl,
          http_status: httpStatus,
          text_length: bodyText.length,
          status: pageBlocked ? 'BLOCKED_ENV' : 'OK',
          error: pageBlocked ? 'page returned non-OK status or blank body' : undefined,
          baseline_screenshot: baselinePath,
          after_screenshot: comparePath,
          diff_artifact: diffPath,
          baseline_sha256: baselineSha,
          after_sha256: compareSha,
          changed,
        })
      }
    }
    await page.close()
  }
} finally {
  await browser.close()
}

if (mode === 'record') {
  mkdirSync(path.dirname(fixtureManifest), { recursive: true })
  writeFileSync(fixtureManifest, JSON.stringify({
    schema_version: 1,
    fixture_kind: 'polaris-visual-page-fixture',
    writer: 'run-visual-snapshot.sh',
    ticket: process.env.VR_TICKET,
    head_sha: process.env.VR_HEAD_SHA,
    runtime_verify_target: process.env.VR_RUNTIME_VERIFY_TARGET,
    reviewed: false,
    recorded_at: new Date().toISOString(),
    pages: fixtureRecords,
  }, null, 2) + '\n')
}

writeFileSync(resultPath, JSON.stringify({
  baseline_dir: baselineDir,
  compare_dir: compareDir,
  diff_dir: diffDir,
  fixture_dir: fixtureDir || undefined,
  fixture_manifest: fixtureManifest || undefined,
  fixture_mode: fixtureMode,
  review_required: mode === 'record',
  blocked,
  changed_count: results.filter((item) => item.changed).length,
  pages: results,
}, null, 2) + '\n')
NODE

set +e
(cd "$TOOLCHAIN_DIR" && pnpm exec node "$CAPTURE_SCRIPT" "$MODE" "$CAPTURE_PAGES_JSON" "$OUTPUT_DIR" "$RESULT_JSON" "$FIXTURE_MODE" "$FIXTURE_DIR" "$FIXTURE_MANIFEST")
CAPTURE_RC=$?
set -e

if [[ "$CAPTURE_RC" -ne 0 ]]; then
  write_evidence "BLOCKED_ENV" "true" "$RESULT_JSON" "Playwright capture failed with exit $CAPTURE_RC" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BLOCKED_ENV — Playwright capture failed" >&2
  exit 1
fi

if [[ "$MODE" == "record" ]]; then
  RECORD_STATUS="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("BLOCKED_ENV" if data.get("blocked") else "MANUAL_REQUIRED")
PY
)"
  if [[ "$RECORD_STATUS" == "BLOCKED_ENV" ]]; then
    write_evidence "BLOCKED_ENV" "true" "$RESULT_JSON" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
    echo "run-visual-snapshot: BLOCKED_ENV — fixture record target was not valid" >&2
    exit 1
  fi
  write_evidence "MANUAL_REQUIRED" "true" "$RESULT_JSON" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: MANUAL_REQUIRED — fixture recorded; review required at $FIXTURE_MANIFEST" >&2
  exit 1
fi

if [[ "$MODE" == "baseline" ]]; then
  BASELINE_STATUS="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("BLOCKED_ENV" if data.get("blocked") else "BASELINE_CAPTURED")
PY
)"
  if [[ "$BASELINE_STATUS" == "BLOCKED_ENV" ]]; then
    write_evidence "BLOCKED_ENV" "true" "$RESULT_JSON" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
    echo "run-visual-snapshot: BLOCKED_ENV — baseline capture target was not valid" >&2
    exit 1
  fi
  write_evidence "BASELINE_CAPTURED" "true" "$RESULT_JSON" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
  echo "run-visual-snapshot: BASELINE_CAPTURED — evidence at $EVIDENCE_FILE"
  exit 0
fi

STATUS="$(EXPECTED="$EXPECTED" python3 - "$RESULT_JSON" <<'PY'
import json
import os
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
expected = os.environ["EXPECTED"]
if data.get("blocked"):
    print("BLOCKED_ENV")
elif data.get("changed_count", 0) > 0 and expected != "update_baseline":
    print("BLOCK")
else:
    print("PASS")
PY
)"

write_evidence "$STATUS" "true" "$RESULT_JSON" "" "$EVIDENCE_FILE" "$DURABLE_FILE"
echo "run-visual-snapshot: $STATUS — evidence at $EVIDENCE_FILE"

case "$STATUS" in
  PASS) exit 0 ;;
  *) exit 1 ;;
esac
