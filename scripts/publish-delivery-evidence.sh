#!/usr/bin/env bash
set -euo pipefail

# publish-delivery-evidence.sh — PR-visible evidence publication helper.
#
# Modes:
#   collect  Build a JSON manifest for local visual / behavior evidence.
#   check    Require a PR-visible publication marker when publishable evidence exists.
#   comment  Publish the manifest as a GitHub PR comment.

PREFIX="[polaris evidence-publication]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODE="check"
REPO_ROOT=""
TICKET=""
HEAD_SHA=""
PR_URL=""
MANIFEST_FILE=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  publish-delivery-evidence.sh --mode collect|check|comment --repo <path> --ticket <KEY> --head-sha <sha> [--pr-url <url>] [--manifest-file <path>]

Options:
  --mode <mode>        collect, check, or comment. Default: check.
  --repo <path>        Target repo root.
  --ticket <KEY>       Task ticket key or DP pseudo-task id.
  --head-sha <sha>     Delivery head sha.
  --pr-url <url>       GitHub PR URL. Required for check/comment.
  --manifest-file      Optional output path for collect/comment manifest JSON.
USAGE
}

parse_github_pr_url() {
  local pr_url="$1"
  python3 - "$pr_url" <<'PY'
import re
import sys

value = sys.argv[1].strip()
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", value)
if not match:
    sys.exit(1)
owner, repo, number = match.groups()
print(f"{owner}/{repo}\t{number}")
PY
}

safe_ticket() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --pr-url) PR_URL="${2:-}"; shift 2 ;;
    --manifest-file) MANIFEST_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

case "$MODE" in
  collect|check|comment) ;;
  *) echo "$PREFIX invalid --mode: $MODE" >&2; exit 64 ;;
esac

if [[ -z "$REPO_ROOT" || -z "$TICKET" || -z "$HEAD_SHA" ]]; then
  echo "$PREFIX --repo, --ticket, and --head-sha are required" >&2
  usage
  exit 64
fi
if [[ ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX repo not found: $REPO_ROOT" >&2
  exit 64
fi
if [[ "$MODE" != "collect" && -z "$PR_URL" ]]; then
  echo "$PREFIX --pr-url is required for mode=$MODE" >&2
  exit 64
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
SAFE_TICKET="$(safe_ticket "$TICKET")"

manifest_tmp="$(mktemp -t polaris-evidence-manifest.XXXXXX.json)"
comment_tmp=""
comments_tmp=""
cleanup() {
  rm -f "$manifest_tmp" "${comment_tmp:-}" "${comments_tmp:-}"
}
trap cleanup EXIT

python3 - "$REPO_ROOT" "$TICKET" "$SAFE_TICKET" "$HEAD_SHA" "$manifest_tmp" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

repo_root = Path(sys.argv[1])
ticket = sys.argv[2]
safe_ticket = sys.argv[3]
head_sha = sys.argv[4]
output = Path(sys.argv[5])

evidence_root = repo_root / ".polaris" / "evidence"
items = []
errors = []

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def add_item(kind: str, path: Path, required: bool = True, metadata=None):
    if not path.exists() or not path.is_file():
        return
    rel = path
    try:
        rel = path.relative_to(repo_root)
    except ValueError:
        pass
    items.append({
        "kind": kind,
        "path": str(rel),
        "absolute_path": str(path),
        "size": path.stat().st_size,
        "sha256": sha256_file(path),
        "requires_publication": required,
        "metadata": metadata or {},
    })

def has_video_reference(value):
    refs = []
    def walk(obj):
        if isinstance(obj, dict):
            for key, val in obj.items():
                normalized = str(key).lower().replace("-", "_")
                if normalized in {"video", "video_path", "videos"}:
                    if isinstance(val, list):
                        refs.extend(str(item) for item in val if str(item).strip())
                    elif str(val).strip():
                        refs.append(str(val))
                walk(val)
        elif isinstance(obj, list):
            for item in obj:
                walk(item)
    walk(value)
    return refs

verify_tmp = Path("/tmp") / f"polaris-verified-{ticket}-{head_sha}.json"
verify_durable = evidence_root / "verify" / f"polaris-verified-{ticket}-{head_sha}.json"
add_item("verify", verify_tmp, required=False)
add_item("verify", verify_durable, required=False)

vr_tmp = Path("/tmp") / f"polaris-vr-{safe_ticket}-{head_sha}.json"
vr_durable = evidence_root / "vr" / f"polaris-vr-{safe_ticket}-{head_sha}.json"
add_item("vr", vr_tmp, required=True)
add_item("vr", vr_durable, required=True)

vr_artifact_dir = evidence_root / "vr" / "artifacts" / safe_ticket
if vr_artifact_dir.is_dir():
    for path in sorted(vr_artifact_dir.rglob("*")):
        if path.is_file():
            add_item("vr_artifact", path, required=True)

behavior_file = evidence_root / "playwright" / ticket / "playwright-behavior-video.json"
if behavior_file.is_file():
    video_refs = []
    try:
        data = json.loads(behavior_file.read_text(encoding="utf-8"))
        video_refs = has_video_reference(data)
    except Exception as exc:
        errors.append(f"Playwright behavior evidence is not valid JSON: {behavior_file}: {exc}")
    if not video_refs:
        errors.append(f"Playwright behavior evidence requires video reference: {behavior_file}")
    add_item("playwright_behavior", behavior_file, required=True, metadata={"video_refs": video_refs})

requires_publication = any(item.get("requires_publication") for item in items)
manifest = {
    "schema_version": 1,
    "ticket": ticket,
    "head_sha": head_sha,
    "repo": str(repo_root),
    "requires_publication": requires_publication,
    "items": items,
    "errors": errors,
}
canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True).encode("utf-8")
manifest["manifest_sha256"] = hashlib.sha256(canonical).hexdigest()
output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if [[ -n "$MANIFEST_FILE" ]]; then
  mkdir -p "$(dirname "$MANIFEST_FILE")"
  cp "$manifest_tmp" "$MANIFEST_FILE"
fi

if [[ "$MODE" == "collect" ]]; then
  cat "$manifest_tmp"
  exit 0
fi

manifest_errors="$(python3 - "$manifest_tmp" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for error in data.get("errors", []):
    print(error)
PY
)"
if [[ -n "$manifest_errors" ]]; then
  echo "$PREFIX BLOCKED: evidence manifest is not publishable" >&2
  printf '%s\n' "$manifest_errors" >&2
  exit 2
fi

requires_publication="$(python3 - "$manifest_tmp" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("true" if data.get("requires_publication") else "false")
PY
)"
if [[ "$requires_publication" != "true" ]]; then
  echo "$PREFIX no visual or behavior evidence requires PR publication for ${TICKET}@${HEAD_SHA}" >&2
  exit 0
fi

parsed="$(parse_github_pr_url "$PR_URL" || true)"
if [[ -z "$parsed" ]]; then
  echo "$PREFIX invalid GitHub PR URL: $PR_URL" >&2
  exit 64
fi
GH_REPO="${parsed%%$'\t'*}"
PR_NUMBER="${parsed##*$'\t'}"

marker="polaris-evidence-publication:v1 ticket=${TICKET} head=${HEAD_SHA}"

if [[ "$MODE" == "check" ]]; then
  command -v gh >/dev/null 2>&1 || {
    echo "$PREFIX BLOCKED: gh CLI is required to inspect PR evidence publication comments" >&2
    exit 2
  }

  comments_tmp="$(mktemp -t polaris-evidence-comments.XXXXXX.json)"
  if ! gh api "repos/${GH_REPO}/issues/${PR_NUMBER}/comments" --paginate >"$comments_tmp"; then
    echo "$PREFIX BLOCKED: unable to read PR comments for evidence publication: $PR_URL" >&2
    exit 2
  fi

  if python3 - "$comments_tmp" "$marker" <<'PY'
import json
import sys

path, marker = sys.argv[1:3]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception:
    raise SystemExit(1)
if isinstance(data, dict):
    data = [data]
for item in data:
    body = str(item.get("body", ""))
    if marker in body:
        raise SystemExit(0)
raise SystemExit(1)
PY
  then
    echo "$PREFIX PR-visible evidence publication marker found for ${TICKET}@${HEAD_SHA}" >&2
    exit 0
  fi

  echo "$PREFIX BLOCKED: No PR-visible evidence publication marker for ${TICKET}@${HEAD_SHA}" >&2
  echo "$PREFIX Run: bash scripts/publish-delivery-evidence.sh --mode comment --repo '$REPO_ROOT' --ticket '$TICKET' --head-sha '$HEAD_SHA' --pr-url '$PR_URL'" >&2
  exit 2
fi

comment_tmp="$(mktemp -t polaris-evidence-comment.XXXXXX.md)"
python3 - "$manifest_tmp" "$comment_tmp" "$marker" <<'PY'
import json
from pathlib import Path
import sys

manifest_path, comment_path, marker = sys.argv[1:4]
data = json.load(open(manifest_path, encoding="utf-8"))
lines = [
    f"<!-- {marker} manifest_sha256={data.get('manifest_sha256', '')} -->",
    "## Polaris evidence publication",
    "",
    f"- Ticket: `{data['ticket']}`",
    f"- Head SHA: `{data['head_sha']}`",
    f"- Manifest SHA-256: `{data.get('manifest_sha256', '')}`",
    "",
    "## Evidence manifest",
    "",
    "| 類型 | 路徑 | 大小 | SHA-256 |",
    "|------|------|------|---------|",
]
for item in data.get("items", []):
    if not item.get("requires_publication"):
        continue
    lines.append(
        f"| `{item['kind']}` | `{item['path']}` | {item['size']} | `{item['sha256']}` |"
    )
video_refs = []
for item in data.get("items", []):
    video_refs.extend(item.get("metadata", {}).get("video_refs", []) or [])
if video_refs:
    lines.extend(["", "## Video references", ""])
    for ref in video_refs:
        lines.append(f"- `{ref}`")
Path(comment_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

if ! bash "$SCRIPT_DIR/validate-language-policy.sh" --blocking --mode artifact --workspace-root "$REPO_ROOT" "$comment_tmp"; then
  echo "$PREFIX BLOCKED: generated evidence publication comment violates language policy" >&2
  exit 2
fi

command -v gh >/dev/null 2>&1 || {
  echo "$PREFIX BLOCKED: gh CLI is required to publish evidence comment" >&2
  exit 2
}
gh pr comment "$PR_NUMBER" --repo "$GH_REPO" --body-file "$comment_tmp"
echo "$PREFIX published PR-visible evidence manifest for ${TICKET}@${HEAD_SHA}" >&2
