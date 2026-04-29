#!/usr/bin/env bash
set -uo pipefail

# write-extension-deliverable.sh
#
# Atomically writes local-extension release metadata into task.md frontmatter.
# This is the local_extension counterpart to write-deliverable.sh; it records
# a real release deliverable without inventing a PR URL.
#
# Usage:
#   scripts/write-extension-deliverable.sh <task-md-path> \
#     --extension-id <local-extension-id> \
#     --task-head-sha <sha> \
#     --workspace-commit <sha> \
#     --template-commit <sha> \
#     --version-tag <tag|N/A> \
#     --ci-local-evidence <path> \
#     --verify-evidence <path> \
#     [--vr-evidence <path|N/A>] \
#     [--release-url <url|N/A>] \
#     [--completed-at <iso8601>]
#
# Exit codes:
#   0 — success
#   1 — inconsistent write after retries; caller must halt
#   2 — invalid input

MAX_RETRIES=3

die() {
  printf '[write-extension-deliverable] ERROR: %s\n' "$1" >&2
  exit 2
}

fail_inconsistent() {
  printf '\n' >&2
  printf '====================================================================\n' >&2
  printf 'HARD STOP — local extension deliverable write failed\n' >&2
  printf '====================================================================\n' >&2
  printf 'task.md: %s\n' "$TASK_MD" >&2
  printf 'cause  : %s\n' "$1" >&2
  printf 'Task release metadata may be inconsistent. Manual recovery required.\n' >&2
  printf '====================================================================\n' >&2
  exit 1
}

usage() {
  sed -n '3,33p' "$0" >&2
}

is_sha() {
  printf '%s' "$1" | grep -qE '^[0-9a-fA-F]{7,40}$'
}

TASK_MD="${1:-}"
[[ -n "$TASK_MD" ]] || { usage; exit 2; }
shift || true

EXTENSION_ID=""
TASK_HEAD_SHA=""
WORKSPACE_COMMIT=""
TEMPLATE_COMMIT=""
VERSION_TAG=""
RELEASE_URL="N/A"
CI_LOCAL_EVIDENCE=""
VERIFY_EVIDENCE=""
VR_EVIDENCE="N/A"
COMPLETED_AT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --extension-id) EXTENSION_ID="${2:-}"; shift 2 ;;
    --task-head-sha) TASK_HEAD_SHA="${2:-}"; shift 2 ;;
    --workspace-commit) WORKSPACE_COMMIT="${2:-}"; shift 2 ;;
    --template-commit) TEMPLATE_COMMIT="${2:-}"; shift 2 ;;
    --version-tag) VERSION_TAG="${2:-}"; shift 2 ;;
    --release-url) RELEASE_URL="${2:-}"; shift 2 ;;
    --ci-local-evidence) CI_LOCAL_EVIDENCE="${2:-}"; shift 2 ;;
    --verify-evidence) VERIFY_EVIDENCE="${2:-}"; shift 2 ;;
    --vr-evidence) VR_EVIDENCE="${2:-}"; shift 2 ;;
    --completed-at) COMPLETED_AT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -f "$TASK_MD" ]] || die "task.md not found: $TASK_MD"
[[ -n "$EXTENSION_ID" ]] || die "--extension-id is required"
[[ "$EXTENSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "--extension-id contains unsupported characters"
[[ -n "$TASK_HEAD_SHA" ]] || die "--task-head-sha is required"
[[ -n "$WORKSPACE_COMMIT" ]] || die "--workspace-commit is required"
[[ -n "$TEMPLATE_COMMIT" ]] || die "--template-commit is required"
[[ -n "$VERSION_TAG" ]] || die "--version-tag is required"
[[ -n "$CI_LOCAL_EVIDENCE" ]] || die "--ci-local-evidence is required"
[[ -n "$VERIFY_EVIDENCE" ]] || die "--verify-evidence is required"

is_sha "$TASK_HEAD_SHA" || die "--task-head-sha must be a 7-40 char hex SHA"
is_sha "$WORKSPACE_COMMIT" || die "--workspace-commit must be a 7-40 char hex SHA"
is_sha "$TEMPLATE_COMMIT" || die "--template-commit must be a 7-40 char hex SHA"

if [[ "$VERSION_TAG" != "N/A" && ! "$VERSION_TAG" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
  die "--version-tag must look like v1.2.3 or be N/A"
fi

if [[ -n "$RELEASE_URL" && "$RELEASE_URL" != "N/A" ]]; then
  printf '%s' "$RELEASE_URL" | grep -qE '^https://github\.com/.+/releases/tag/.+$' \
    || die "--release-url must be a GitHub release URL or N/A"
fi

if [[ -z "$COMPLETED_AT" ]]; then
  COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
printf '%s' "$COMPLETED_AT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:?[0-9]{2})$' \
  || die "--completed-at must be ISO 8601"

TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
TASK_DIR="$(dirname "$TASK_MD")"

attempt=0
last_error=""

while [[ "$attempt" -lt "$MAX_RETRIES" ]]; do
  attempt=$((attempt + 1))
  tmp_file="$(mktemp "${TASK_DIR}/.extension-deliverable.XXXXXX")" || die "failed to create temp file"

  if ! write_error=$(python3 - "$TASK_MD" "$tmp_file" "$EXTENSION_ID" "$TASK_HEAD_SHA" "$WORKSPACE_COMMIT" "$TEMPLATE_COMMIT" "$VERSION_TAG" "$RELEASE_URL" "$CI_LOCAL_EVIDENCE" "$VERIFY_EVIDENCE" "$VR_EVIDENCE" "$COMPLETED_AT" <<'PY' 2>&1
import re
import sys
from pathlib import Path

(
    task_path,
    tmp_path,
    extension_id,
    task_head_sha,
    workspace_commit,
    template_commit,
    version_tag,
    release_url,
    ci_local_evidence,
    verify_evidence,
    vr_evidence,
    completed_at,
) = sys.argv[1:13]

path = Path(task_path)
content = path.read_text(encoding="utf-8")

block = (
    "extension_deliverable:\n"
    "  endpoint: local_extension\n"
    f"  extension_id: {extension_id}\n"
    f"  task_head_sha: {task_head_sha}\n"
    f"  workspace_commit: {workspace_commit}\n"
    f"  template_commit: {template_commit}\n"
    f"  version_tag: {version_tag}\n"
    f"  release_url: {release_url}\n"
    f"  completed_at: {completed_at}\n"
    "  evidence:\n"
    f"    ci_local: {ci_local_evidence}\n"
    f"    verify: {verify_evidence}\n"
    f"    vr: {vr_evidence}\n"
)

fm_pattern = re.compile(r"^---\n(.*?)^---\n", re.DOTALL | re.MULTILINE)
match = fm_pattern.match(content)

if not match:
    new_content = "---\n" + block + "---\n" + content
else:
    fm_body = match.group(1)
    cleaned = re.sub(
        r"^extension_deliverable:(?:\n(?:[ \t]+[^\n]*))*\n?",
        "",
        fm_body,
        flags=re.MULTILINE,
    )
    if cleaned and not cleaned.endswith("\n"):
        cleaned += "\n"
    new_content = "---\n" + cleaned + block + "---\n" + content[match.end():]

Path(tmp_path).write_text(new_content, encoding="utf-8")
PY
  ); then
    last_error="python writer failed: ${write_error}"
    rm -f "$tmp_file"
  elif ! mv_error=$(mv "$tmp_file" "$TASK_MD" 2>&1); then
    last_error="atomic mv failed: ${mv_error}"
    rm -f "$tmp_file" 2>/dev/null || true
  else
    verify_result=$(python3 - "$TASK_MD" "$EXTENSION_ID" "$WORKSPACE_COMMIT" <<'PY' 2>&1
import sys
from pathlib import Path

path, expected_extension, expected_workspace = sys.argv[1:4]
text = Path(path).read_text(encoding="utf-8")
if not text.startswith("---\n") or "\n---\n" not in text[4:]:
    print("NO_FRONTMATTER")
    sys.exit(1)
fm = text[4:text.find("\n---\n", 4)].splitlines()
in_block = False
found_extension = ""
found_workspace = ""
for raw in fm:
    if raw == "extension_deliverable:":
        in_block = True
        continue
    if in_block and raw and not raw[0].isspace():
        break
    if not in_block:
        continue
    stripped = raw.strip()
    if stripped.startswith("extension_id:"):
        found_extension = stripped.split(":", 1)[1].strip()
    if stripped.startswith("workspace_commit:"):
        found_workspace = stripped.split(":", 1)[1].strip()

if found_extension != expected_extension:
    print(f"EXTENSION_MISMATCH:{found_extension}")
    sys.exit(1)
if found_workspace != expected_workspace:
    print(f"WORKSPACE_MISMATCH:{found_workspace}")
    sys.exit(1)
print("OK")
PY
    ) || true
    if [[ "$verify_result" == "OK" ]]; then
      echo "[write-extension-deliverable] OK: wrote extension_deliverable to $TASK_MD" >&2
      exit 0
    fi
    last_error="read-back verification failed: ${verify_result}"
  fi

  sleep "$attempt"
done

fail_inconsistent "$last_error"
