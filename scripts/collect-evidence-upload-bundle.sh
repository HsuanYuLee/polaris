#!/usr/bin/env bash
set -euo pipefail

# collect-evidence-upload-bundle.sh — Collect local delivery evidence into a
# human-upload bundle under specs/{source}/artifacts/.
#
# This helper does not create or alter gate evidence. It copies already-written
# evidence files and media into a stable folder that a human can drag into a PR
# comment or Jira attachment surface.

PREFIX="[polaris evidence-upload-bundle]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT=""
TICKET=""
HEAD_SHA=""
SOURCE_CONTAINER=""
TARGET="pr"
OUTPUT_DIR=""
CLEAN="1"

usage() {
  cat >&2 <<'USAGE'
Usage:
  collect-evidence-upload-bundle.sh --repo <path> --ticket <KEY> --head-sha <sha> --source-container <spec-container> [--target pr|jira|both] [--output-dir <path>] [--no-clean]

Options:
  --repo <path>               Product or framework repo that produced local evidence.
  --ticket <KEY>              Work item id, Jira ticket key, or DP pseudo-task id.
  --head-sha <sha>            Delivery head sha.
  --source-container <path>   Spec container that owns artifacts/ (for example specs/.../EPIC-123).
  --target <target>           pr, jira, or both. Default: pr.
  --output-dir <path>         Override bundle output directory.
  --no-clean                  Keep existing files in the output directory.
USAGE
}

safe_slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --source-container) SOURCE_CONTAINER="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --no-clean) CLEAN="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

case "$TARGET" in
  pr|jira|both) ;;
  *) echo "$PREFIX invalid --target: $TARGET" >&2; exit 64 ;;
esac

if [[ -z "$REPO_ROOT" || -z "$TICKET" || -z "$HEAD_SHA" || -z "$SOURCE_CONTAINER" ]]; then
  echo "$PREFIX --repo, --ticket, --head-sha, and --source-container are required" >&2
  usage
  exit 64
fi
if [[ ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX repo not found: $REPO_ROOT" >&2
  exit 64
fi
if [[ ! -d "$SOURCE_CONTAINER" ]]; then
  echo "$PREFIX source container not found: $SOURCE_CONTAINER" >&2
  exit 64
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
SOURCE_CONTAINER="$(cd "$SOURCE_CONTAINER" && pwd)"
SAFE_TICKET="$(safe_slug "$TICKET")"

if [[ -z "$OUTPUT_DIR" ]]; then
  case "$TARGET" in
    pr) OUTPUT_DIR="${SOURCE_CONTAINER}/artifacts/${SAFE_TICKET}-pr-upload" ;;
    jira) OUTPUT_DIR="${SOURCE_CONTAINER}/artifacts/${SAFE_TICKET}-jira-upload" ;;
    both) OUTPUT_DIR="${SOURCE_CONTAINER}/artifacts/${SAFE_TICKET}-evidence-upload" ;;
  esac
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
if [[ "$CLEAN" == "1" ]]; then
  case "$OUTPUT_DIR" in
    /|/tmp|/private/tmp|"${HOME:-/}")
      echo "$PREFIX refusing to clean unsafe output directory: $OUTPUT_DIR" >&2
      exit 64
      ;;
  esac
  find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

publication_manifest="$(mktemp -t polaris-publication-manifest.XXXXXX.json)"
trap 'rm -f "$publication_manifest"' EXIT

bash "$SCRIPT_DIR/publish-delivery-evidence.sh" \
  --mode collect \
  --repo "$REPO_ROOT" \
  --ticket "$TICKET" \
  --head-sha "$HEAD_SHA" \
  --manifest-file "$publication_manifest" >/dev/null

python3 - "$publication_manifest" "$REPO_ROOT" "$TICKET" "$HEAD_SHA" "$TARGET" "$OUTPUT_DIR" <<'PY'
from __future__ import annotations

import datetime as dt
import hashlib
import json
import shutil
from pathlib import Path
import sys

publication_manifest_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
ticket = sys.argv[3]
head_sha = sys.argv[4]
target = sys.argv[5]
output_dir = Path(sys.argv[6])

publication = json.loads(publication_manifest_path.read_text(encoding="utf-8"))
items: list[dict] = []
seen_sources: set[Path] = set()
used_names: set[str] = set()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def slug(value: str) -> str:
    chars = []
    for char in value:
        if char.isalnum() or char in "._-":
            chars.append(char)
        else:
            chars.append("-")
    result = "".join(chars).strip("-")
    return result or "item"


def relative_display(path: Path) -> str:
    for root in (repo_root, Path("/tmp")):
        try:
            if root == Path("/tmp"):
                return "/tmp/" + str(path.relative_to(root))
            return str(path.relative_to(root))
        except ValueError:
            pass
    return str(path)


def destination_name(kind: str, source: Path) -> str:
    parent = source.parent.name
    stem = f"{slug(kind)}-{slug(parent)}-{source.name}"
    candidate = stem
    if candidate not in used_names:
        used_names.add(candidate)
        return candidate
    digest = hashlib.sha256(str(source).encode("utf-8")).hexdigest()[:8]
    candidate = f"{source.stem}-{digest}{source.suffix}"
    while candidate in used_names:
        digest = hashlib.sha256((candidate + str(source)).encode("utf-8")).hexdigest()[:8]
        candidate = f"{source.stem}-{digest}{source.suffix}"
    used_names.add(candidate)
    return candidate


def add_source(kind: str, source: Path, *, required_publication: bool, note: str = "") -> None:
    try:
        source = source.expanduser().resolve()
    except OSError:
        return
    if source in seen_sources or not source.is_file():
        return
    seen_sources.add(source)
    dest = output_dir / destination_name(kind, source)
    shutil.copy2(source, dest)
    items.append(
        {
            "kind": kind,
            "source_path": str(source),
            "display_path": relative_display(source),
            "bundle_path": dest.name,
            "size": dest.stat().st_size,
            "sha256": sha256_file(dest),
            "requires_publication": required_publication,
            "note": note,
        }
    )


for item in publication.get("items", []):
    absolute = item.get("absolute_path")
    if absolute:
        add_source(
            str(item.get("kind", "evidence")),
            Path(absolute),
            required_publication=bool(item.get("requires_publication")),
        )

    if item.get("kind") == "playwright_behavior":
        behavior_path = Path(absolute) if absolute else None
        bases = [repo_root]
        if behavior_path:
            bases.insert(0, behavior_path.parent)
        for ref in item.get("metadata", {}).get("video_refs", []) or []:
            ref_path = Path(str(ref))
            candidates = [ref_path] if ref_path.is_absolute() else [base / ref_path for base in bases]
            for candidate in candidates:
                if candidate.is_file():
                    add_source(
                        "playwright_video",
                        candidate,
                        required_publication=True,
                        note="video reference from playwright behavior evidence",
                    )
                    break

short_head = head_sha[:12]
ci_candidates = []
for pattern in (f"/tmp/polaris-ci-local-*{head_sha}*.json", f"/tmp/polaris-ci-local-*{short_head}*.json"):
    ci_candidates.extend(Path("/").glob(pattern.lstrip("/")))
for candidate in sorted(set(ci_candidates)):
    matches_head = head_sha in candidate.name or short_head in candidate.name
    try:
        data = json.loads(candidate.read_text(encoding="utf-8"))
        candidate_head = str(data.get("head_sha", ""))
        matches_head = matches_head or candidate_head == head_sha or candidate_head.startswith(short_head)
    except Exception:
        pass
    if matches_head:
        add_source("ci_local", candidate, required_publication=False)

manifest = {
    "schema_version": 1,
    "kind": "polaris-evidence-upload-bundle",
    "ticket": ticket,
    "head_sha": head_sha,
    "target": target,
    "repo": str(repo_root),
    "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "publication_manifest_sha256": sha256_file(publication_manifest_path),
    "items": items,
    "warnings": publication.get("errors", []),
}
manifest_path = output_dir / "manifest.json"
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

required = [item for item in items if item.get("requires_publication")]
lines = [
    f"# Evidence upload bundle - {ticket}",
    "",
    f"- Ticket: `{ticket}`",
    f"- Head SHA: `{head_sha}`",
    f"- Target: `{target}`",
    f"- Repo: `{repo_root}`",
    "",
    "## Upload",
    "",
]
if required:
    lines.extend(
        [
            "請把下列 required publication files 拖曳到 PR/Jira comment UI，然後把產生的遠端 comment 或 attachment URL 保留在 delivery evidence marker。",
            "",
            "| File | Kind | Source | SHA-256 |",
            "|------|------|--------|---------|",
        ]
    )
    for item in required:
        lines.append(
            f"| `{item['bundle_path']}` | `{item['kind']}` | `{item['display_path']}` | `{item['sha256']}` |"
        )
else:
    lines.append("目前沒有 screenshot、video 或 VR artifact 需要人工發布。")

supporting = [item for item in items if not item.get("requires_publication")]
if supporting:
    lines.extend(["", "## Supporting Local Evidence", "", "| File | Kind | Source | SHA-256 |", "|------|------|--------|---------|"])
    for item in supporting:
        lines.append(
            f"| `{item['bundle_path']}` | `{item['kind']}` | `{item['display_path']}` | `{item['sha256']}` |"
        )

if publication.get("errors"):
    lines.extend(["", "## Warnings", ""])
    for warning in publication.get("errors", []):
        lines.append(f"- {warning}")

lines.extend(
    [
        "",
        "## Safety",
        "",
        "上傳前請先檢查 screenshots 與 videos。若檔案暴露 secrets、private customer data 或無關個資，不可發布。",
        "",
        "`manifest.json` 記錄所有 copied files、source paths、sizes 與 SHA-256 hashes。",
    ]
)
(output_dir / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"output_dir": str(output_dir), "items": len(items), "required_publication": len(required)}, ensure_ascii=False))
PY
