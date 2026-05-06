#!/usr/bin/env bash
set -euo pipefail

# write-task-verify-report.sh — Generate a task-bound human-readable
# verify-report.md from local Polaris evidence.
#
# Usage:
#   bash scripts/write-task-verify-report.sh --repo <path> --ticket <KEY> --task-md <path> [--head-sha <sha>] [--status <status>] [--output <path>]

PREFIX="[polaris task-verify-report]"

REPO_ROOT=""
TICKET=""
TASK_MD=""
HEAD_SHA=""
STATUS="PASS"
OUTPUT=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  write-task-verify-report.sh --repo <path> --ticket <KEY> --task-md <path> [--head-sha <sha>] [--status <status>] [--output <path>]

Options:
  --repo <path>       Repo/worktree that produced local evidence.
  --ticket <KEY>      Task ticket key or DP pseudo-task id.
  --task-md <path>    Canonical task markdown path.
  --head-sha <sha>    Delivery head SHA. Defaults to git HEAD in --repo.
  --status <status>   Report status. Defaults to PASS.
  --output <path>     Override output report path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --head-sha) HEAD_SHA="${2:-}"; shift 2 ;;
    --status) STATUS="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

if [[ -z "$REPO_ROOT" || -z "$TICKET" || -z "$TASK_MD" ]]; then
  echo "$PREFIX --repo, --ticket, and --task-md are required" >&2
  usage
  exit 64
fi
if [[ ! -d "$REPO_ROOT" ]]; then
  echo "$PREFIX repo not found: $REPO_ROOT" >&2
  exit 64
fi
if [[ ! -f "$TASK_MD" ]]; then
  echo "$PREFIX task.md not found: $TASK_MD" >&2
  exit 64
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi
if [[ -z "$HEAD_SHA" ]]; then
  echo "$PREFIX unable to resolve delivery head SHA" >&2
  exit 64
fi

python3 - "$REPO_ROOT" "$TICKET" "$TASK_MD" "$HEAD_SHA" "$STATUS" "$OUTPUT" <<'PY'
from __future__ import annotations

import datetime as dt
import glob
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
ticket = sys.argv[2]
task_md = Path(sys.argv[3]).resolve()
head_sha = sys.argv[4]
status = sys.argv[5]
output_arg = sys.argv[6]


def slug(value: str) -> str:
    chars = []
    for char in value:
        if char.isalnum() or char in "._-":
            chars.append(char)
        else:
            chars.append("-")
    return "".join(chars).strip("-") or "item"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def task_container_for(path: Path) -> Path:
    if path.name == "index.md":
        return path.parent
    return path.with_suffix("")


report_path = Path(output_arg).resolve() if output_arg else task_container_for(task_md) / "verify-report.md"
report_dir = report_path.parent
raw_dir = report_dir / "assets" / "raw"
raw_dir.mkdir(parents=True, exist_ok=True)

safe_ticket = slug(ticket)
short_head = head_sha[:12]
evidence_root = repo_root / ".polaris" / "evidence"

candidate_paths: list[tuple[str, Path]] = []


def add_candidate(kind: str, path: Path) -> None:
    candidate_paths.append((kind, path))


add_candidate("verify", Path("/tmp") / f"polaris-verified-{ticket}-{head_sha}.json")
add_candidate("verify", evidence_root / "verify" / f"polaris-verified-{ticket}-{head_sha}.json")
add_candidate("review_thread_disposition", evidence_root / "review-thread-disposition" / f"polaris-review-thread-disposition-{ticket}-{head_sha}.json")
add_candidate("review_thread_disposition", evidence_root / "review-threads" / f"polaris-review-thread-disposition-{ticket}-{head_sha}.json")
add_candidate("vr", Path("/tmp") / f"polaris-vr-{safe_ticket}-{head_sha}.json")
add_candidate("vr", evidence_root / "vr" / f"polaris-vr-{safe_ticket}-{head_sha}.json")
add_candidate("playwright_behavior", evidence_root / "playwright" / ticket / "playwright-behavior-video.json")

for pattern in (
    f"/tmp/polaris-ci-local-*{head_sha}*.json",
    f"/tmp/polaris-ci-local-*{short_head}*.json",
):
    for path in sorted(glob.glob(pattern)):
        add_candidate("ci_local", Path(path))

behavior_dir = evidence_root / "behavior" / safe_ticket
if behavior_dir.is_dir():
    for path in sorted(behavior_dir.glob(f"polaris-behavior-{safe_ticket}-{head_sha}-*.json")):
        add_candidate("behavior", path)

seen_sources: set[Path] = set()
used_names: set[str] = set()
items: list[dict] = []
verify_records: list[dict] = []
review_records: list[dict] = []


def unique_name(kind: str, source: Path) -> str:
    base = f"{slug(kind)}-{slug(source.name)}"
    candidate = base
    if candidate not in used_names:
        used_names.add(candidate)
        return candidate
    digest = hashlib.sha256(str(source).encode("utf-8")).hexdigest()[:8]
    candidate = f"{slug(kind)}-{source.stem}-{digest}{source.suffix}"
    while candidate in used_names:
        digest = hashlib.sha256((candidate + str(source)).encode("utf-8")).hexdigest()[:8]
        candidate = f"{slug(kind)}-{source.stem}-{digest}{source.suffix}"
    used_names.add(candidate)
    return candidate


def relative_link(path: Path) -> str:
    rel = os.path.relpath(Path(path).resolve(), report_dir).replace("\\", "/")
    return rel if rel.startswith(".") else f"./{rel}"


for kind, source in candidate_paths:
    try:
        source = source.expanduser().resolve()
    except OSError:
        continue
    if source in seen_sources or not source.is_file():
        continue
    seen_sources.add(source)

    destination = raw_dir / unique_name(kind, source)
    if source != destination.resolve():
        shutil.copy2(source, destination)
    digest = sha256_file(destination)
    item = {
        "kind": kind,
        "source_path": str(source),
        "asset_path": str(destination),
        "relative_link": relative_link(destination),
        "size": destination.stat().st_size,
        "sha256": digest,
    }
    items.append(item)

    if kind == "verify":
        try:
            data = json.loads(destination.read_text(encoding="utf-8"))
            verify_records.append({
                "command": data.get("effective_command") or data.get("command") or "",
                "exit_code": data.get("exit_code"),
                "mode": data.get("verification_mode") or "primary",
                "at": data.get("at") or "",
                "file": destination.name,
            })
        except Exception:
            pass
    if kind == "review_thread_disposition":
        try:
            data = json.loads(destination.read_text(encoding="utf-8"))
            review_records.append({
                "threads": len(data.get("threads", [])) if isinstance(data.get("threads"), list) else 0,
                "file": destination.name,
            })
        except Exception:
            pass

generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
links = {
    "schema_version": 1,
    "kind": "polaris-task-verify-report-links",
    "ticket": ticket,
    "head_sha": head_sha,
    "status": status,
    "task_md": str(task_md),
    "report": str(report_path),
    "generated_at": generated_at,
    "items": items,
}
(report_dir / "links.json").write_text(json.dumps(links, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(report_dir / "publication-manifest.json").write_text(json.dumps({
    "schema_version": 1,
    "kind": "polaris-task-verify-report-publication",
    "ticket": ticket,
    "head_sha": head_sha,
    "status": "local_only",
    "generated_at": generated_at,
    "artifacts": [],
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = [
    "---",
    f"title: {json.dumps(f'Verify Report - {ticket}', ensure_ascii=False)}",
    f"description: {json.dumps(f'Task-bound verification report for {ticket} at {head_sha}.', ensure_ascii=False)}",
    "---",
    "",
    "## Summary",
    "",
    f"- Ticket: `{ticket}`",
    f"- Head SHA: `{head_sha}`",
    f"- Status: `{status}`",
    f"- Generated at: `{generated_at}`",
    f"- Task: [{task_md.name}]({relative_link(task_md)})",
    f"- Repo: `{repo_root}`",
    f"- Links manifest: [links.json](./links.json)",
    f"- Publication manifest: [publication-manifest.json](./publication-manifest.json)",
    "",
    "## Verification Commands",
    "",
]

if verify_records:
    lines.extend(["| Command | Exit | Mode | At | Evidence |", "|---------|------|------|----|----------|"])
    for record in verify_records:
        command = str(record.get("command") or "N/A").replace("\n", "<br>")
        exit_code = record.get("exit_code")
        at = record.get("at") or "N/A"
        mode = record.get("mode") or "N/A"
        file = record.get("file") or ""
        lines.append(f"| `{command}` | `{exit_code}` | `{mode}` | `{at}` | [{file}](./assets/raw/{file}) |")
    lines.append("")
else:
    lines.extend([
        "No `run-verify-command.sh` evidence was collected for this head. See Supporting Evidence for other local proof.",
        "",
    ])

lines.extend(["## Review Thread Disposition", ""])
if review_records:
    lines.extend(["| Threads | Evidence |", "|---------|----------|"])
    for record in review_records:
        file = record.get("file") or ""
        lines.append(f"| `{record.get('threads', 0)}` | [{file}](./assets/raw/{file}) |")
    lines.append("")
else:
    lines.extend(["No review-thread disposition manifest was collected for this head.", ""])

lines.extend(["## Supporting Evidence", ""])
if items:
    lines.extend(["| File | Kind | SHA-256 |", "|------|------|---------|"])
    for item in items:
        path = Path(item["asset_path"])
        lines.append(f"| [{path.name}]({item['relative_link']}) | `{item['kind']}` | `{item['sha256']}` |")
    lines.append("")
else:
    lines.extend(["No local supporting evidence files were collected.", ""])

report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(json.dumps({"report": str(report_path), "items": len(items)}, ensure_ascii=False))
PY
