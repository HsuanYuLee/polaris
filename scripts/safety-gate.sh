#!/usr/bin/env bash
# safety-gate.sh — PreToolUse hook for Polaris sub-agents
# Reads Claude Code hook JSON from stdin, blocks dangerous operations.
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

if [[ "${1:-}" == "evidence-publication" ]]; then
  shift
  python3 - "$@" <<'PY'
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
from pathlib import Path

ALLOWED_REMOTE_EXTENSIONS = {
    ".png": "image",
    ".jpg": "image",
    ".jpeg": "image",
    ".webp": "image",
    ".gif": "image",
    ".svg": "image",
    ".webm": "video",
    ".mp4": "video",
    ".mov": "video",
    ".m4v": "video",
    ".json": "raw",
}

SECRET_PATTERNS = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key material"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"), "GitHub token"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"), "Slack token"),
    (re.compile(r"\bJIRA_API_TOKEN\b"), "Jira API token variable"),
    (re.compile(r"(?i)['\"]?\b(password|secret|token)\b['\"]?\s*[:=]\s*['\"]?[^'\"\s,}]{8,}"), "credential-like assignment"),
]

TEXT_EXTENSIONS = {".json", ".svg"}

def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="safety-gate.sh evidence-publication",
        description="Classify evidence artifacts before remote publication.",
    )
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--links")
    parser.add_argument("--output")
    return parser.parse_args(argv)

def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)

def is_true(value):
    return value is True or str(value).lower() == "true"

def link_index(links):
    items = links.get("items") if isinstance(links, dict) else []
    by_id = {}
    by_filename = {}
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        if item.get("id"):
            by_id[str(item["id"])] = item
        for key in ("asset_path", "relative_link"):
            value = item.get(key)
            if value:
                by_filename[Path(str(value)).name] = item
    return by_id, by_filename

def resolve_path(artifact, link_item, manifest_dir):
    candidates = []
    if link_item:
        candidates.extend([link_item.get("asset_path"), link_item.get("source_path")])
    candidates.extend([
        artifact.get("asset_path"),
        artifact.get("source_path"),
        artifact.get("local_path"),
    ])
    for relative_key in ("local_link", "relative_link"):
        value = artifact.get(relative_key)
        if value:
            candidates.append(str(manifest_dir / value))
    filename = artifact.get("filename")
    if filename:
        candidates.append(str(manifest_dir / filename))

    for candidate in candidates:
        if not candidate:
            continue
        path = Path(str(candidate))
        if not path.is_absolute():
            path = manifest_dir / path
        path = path.resolve()
        if path.is_file():
            return path
    return None

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def scan_secrets(path):
    if path.suffix.lower() not in TEXT_EXTENSIONS:
        return None
    try:
        content = path.read_text(encoding="utf-8", errors="ignore")[:1024 * 1024]
    except OSError:
        return "unreadable text artifact"
    for pattern, reason in SECRET_PATTERNS:
        if pattern.search(content):
            return reason
    return None

def artifact_requires_publication(artifact, link_item):
    values = [
        artifact.get("requires_publication"),
        artifact.get("publication_required"),
    ]
    if isinstance(link_item, dict):
        values.append(link_item.get("remote_publication_required"))
    return any(is_true(value) for value in values)

def artifact_publishable(artifact, link_item):
    values = [
        artifact.get("publishable"),
        artifact.get("publication_safety", {}).get("publishable") if isinstance(artifact.get("publication_safety"), dict) else None,
    ]
    if isinstance(link_item, dict):
        values.append(link_item.get("publishable"))
    return any(is_true(value) for value in values)

def classify(artifact, link_item, manifest_dir):
    filename = str(artifact.get("filename") or (Path(str(link_item.get("asset_path"))).name if link_item and link_item.get("asset_path") else artifact.get("id") or "artifact"))
    required = artifact_requires_publication(artifact, link_item)
    declared_publishable = artifact_publishable(artifact, link_item)
    local_path = resolve_path(artifact, link_item, manifest_dir)
    extension = Path(filename).suffix.lower()
    if local_path:
        extension = local_path.suffix.lower()

    result = {
        "id": artifact.get("id") or (link_item or {}).get("id") or filename,
        "filename": filename,
        "kind": artifact.get("kind") or (link_item or {}).get("kind") or ALLOWED_REMOTE_EXTENSIONS.get(extension, "unknown"),
        "path": str(local_path) if local_path else None,
        "requires_publication": required,
        "publishable": False,
        "status": "skipped",
        "reason": "remote publication not required",
    }

    if not required:
        return result

    if not declared_publishable:
        result.update(status="blocked", reason="required artifact is not explicitly publishable")
        return result
    if not local_path:
        result.update(status="blocked", reason="required artifact source file not found")
        return result
    if extension not in ALLOWED_REMOTE_EXTENSIONS:
        result.update(status="blocked", reason=f"unsupported remote publication extension: {extension or 'none'}")
        return result

    secret_reason = scan_secrets(local_path)
    if secret_reason:
        result.update(status="blocked", reason=f"secret-bearing artifact: {secret_reason}")
        return result

    result.update(
        kind=ALLOWED_REMOTE_EXTENSIONS[extension],
        publishable=True,
        status="publishable",
        reason="explicitly publishable and passed deterministic safety checks",
        sha256=sha256(local_path),
        size=local_path.stat().st_size,
    )
    return result

def main(argv):
    args = parse_args(argv)
    manifest_path = Path(args.manifest).resolve()
    manifest = load_json(manifest_path)
    manifest_dir = manifest_path.parent
    links = load_json(Path(args.links).resolve()) if args.links else {}
    by_id, by_filename = link_index(links)

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        artifacts = []

    classified = []
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            continue
        link_item = by_id.get(str(artifact.get("id"))) if artifact.get("id") else None
        if not link_item and artifact.get("filename"):
            link_item = by_filename.get(str(artifact["filename"]))
        classified.append(classify(artifact, link_item, manifest_dir))

    blocked = [item for item in classified if item["status"] == "blocked"]
    output = {
        "schema_version": 1,
        "kind": "polaris-evidence-publication-safety",
        "manifest": str(manifest_path),
        "status": "blocked" if blocked else "pass",
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "summary": {
            "total": len(classified),
            "publishable": sum(1 for item in classified if item["status"] == "publishable"),
            "blocked": len(blocked),
            "skipped": sum(1 for item in classified if item["status"] == "skipped"),
        },
        "artifacts": classified,
    }
    rendered = json.dumps(output, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 2 if blocked else 0

raise SystemExit(main(sys.argv[1:]))
PY
  exit $?
fi

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

# --- Edit / Write: enforce directory allowlist ---
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  if [[ -n "${POLARIS_SAFE_DIRS:-}" ]]; then
    file_path=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)

    if [[ -n "$file_path" ]]; then
      allowed=false
      IFS=':' read -ra dirs <<< "$POLARIS_SAFE_DIRS"
      for dir in "${dirs[@]}"; do
        # Normalize: strip trailing slash
        dir="${dir%/}"
        if [[ "$file_path" == "$dir" || "$file_path" == "$dir/"* ]]; then
          allowed=true
          break
        fi
      done

      if [[ "$allowed" == "false" ]]; then
        echo "[safety-gate] BLOCKED $tool_name: '$file_path' is outside allowed directories." >&2
        echo "Allowed: $POLARIS_SAFE_DIRS" >&2
        exit 2
      fi
    fi
  fi
  exit 0
fi

# --- Bash: block dangerous command patterns ---
if [[ "$tool_name" == "Bash" ]]; then
  command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

  check() {
    local pattern="$1"
    local reason="$2"
    if printf '%s' "$command" | grep -qiE "$pattern"; then
      echo "[safety-gate] BLOCKED Bash: $reason" >&2
      echo "Command: $command" >&2
      exit 2
    fi
  }

  check 'rm[[:space:]]+-rf[[:space:]]+(/|~|/\*)' 'recursive delete of root or home'
  check 'git[[:space:]]+push[[:space:]]+.*--force[[:space:]]+.*(main|master)|git[[:space:]]+push[[:space:]]+.*-f[[:space:]]+.*(main|master)' 'force-push to main/master'
  check 'DROP[[:space:]]+(TABLE|DATABASE)' 'destructive SQL operation'
  check 'chmod[[:space:]]+777' 'overly permissive chmod 777'
  check '>[[:space:]]*/dev/sd[a-z]' 'write to block device'
  check '/dev/tcp/' 'reverse shell via /dev/tcp'
  check 'mkfifo[[:space:]]+/tmp/' 'reverse shell via named pipe'
  check '(nc|ncat|netcat)[[:space:]]+(-e|-c|--exec)' 'reverse shell via netcat'
  check 'curl[[:space:]]+.*\|[[:space:]]*(bash|sh|zsh)' 'pipe-to-shell execution'
  check 'wget[[:space:]]+.*-O[[:space:]]*-[[:space:]]*\|[[:space:]]*(bash|sh)' 'pipe-to-shell execution'
  check 'crontab[[:space:]]+' 'cron modification'

  exit 0
fi

# All other tools: allow
exit 0
