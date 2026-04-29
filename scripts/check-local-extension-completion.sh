#!/usr/bin/env bash
set -euo pipefail

# check-local-extension-completion.sh
#
# Completion gate for engineering local_extension delivery. It validates the
# release metadata written by write-extension-deliverable.sh and checks that
# Layer A/B evidence still corresponds to the validated task head.
#
# Usage:
#   scripts/check-local-extension-completion.sh \
#     --repo <workspace-repo> \
#     --task-md specs/design-plans/DP-NNN-*/tasks/T1.md \
#     --task-id DP-NNN-T1 \
#     --extension-id <local-extension-id> \
#     [--template-repo <extension-owned-repo>]
#
# Exit: 0 = pass, 2 = block, 64 = usage error

PREFIX="[polaris local-extension-completion]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO_ROOT=""
TASK_MD=""
TASK_ID=""
EXTENSION_ID=""
TEMPLATE_REPO=""

usage() {
  sed -n '3,24p' "$0" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --task-id) TASK_ID="${2:-}"; shift 2 ;;
    --extension-id) EXTENSION_ID="${2:-}"; shift 2 ;;
    --template-repo) TEMPLATE_REPO="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$PREFIX unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ -n "$REPO_ROOT" && -n "$TASK_MD" && -n "$TASK_ID" && -n "$EXTENSION_ID" ]] || {
  echo "$PREFIX --repo, --task-md, --task-id, and --extension-id are required" >&2
  usage
  exit 64
}
[[ -d "$REPO_ROOT" ]] || { echo "$PREFIX repo not found: $REPO_ROOT" >&2; exit 64; }
[[ -f "$TASK_MD" ]] || { echo "$PREFIX task.md not found: $TASK_MD" >&2; exit 64; }
[[ -z "$TEMPLATE_REPO" || -d "$TEMPLATE_REPO" ]] || { echo "$PREFIX template repo not found: $TEMPLATE_REPO" >&2; exit 64; }

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
TASK_MD="$(cd "$(dirname "$TASK_MD")" && pwd)/$(basename "$TASK_MD")"
if [[ -n "$TEMPLATE_REPO" ]]; then
  TEMPLATE_REPO="$(cd "$TEMPLATE_REPO" && pwd)"
fi

declare endpoint="" ext_id="" task_head_sha="" workspace_commit="" template_commit="" version_tag="" release_url="" completed_at=""
declare ci_local_evidence="" verify_evidence="" vr_evidence=""

block() {
  echo "$PREFIX BLOCKED: $1" >&2
  exit 2
}

parser_json="$(bash "${SCRIPT_DIR}/parse-task-md.sh" "$TASK_MD" --no-resolve)" \
  || block "unable to parse task.md: $TASK_MD"

while IFS='=' read -r key value; do
  case "$key" in
    endpoint) endpoint="$value" ;;
    extension_id) ext_id="$value" ;;
    task_head_sha) task_head_sha="$value" ;;
    workspace_commit) workspace_commit="$value" ;;
    template_commit) template_commit="$value" ;;
    version_tag) version_tag="$value" ;;
    release_url) release_url="$value" ;;
    completed_at) completed_at="$value" ;;
    evidence.ci_local) ci_local_evidence="$value" ;;
    evidence.verify) verify_evidence="$value" ;;
    evidence.vr) vr_evidence="$value" ;;
  esac
done < <(printf '%s\n' "$parser_json" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
frontmatter = data.get("frontmatter") or {}
extension = frontmatter.get("extension_deliverable") or {}
evidence = extension.get("evidence") or {}

fields = [
    ("endpoint", extension.get("endpoint")),
    ("extension_id", extension.get("extension_id")),
    ("task_head_sha", extension.get("task_head_sha")),
    ("workspace_commit", extension.get("workspace_commit")),
    ("template_commit", extension.get("template_commit")),
    ("version_tag", extension.get("version_tag")),
    ("release_url", extension.get("release_url")),
    ("completed_at", extension.get("completed_at")),
    ("evidence.ci_local", evidence.get("ci_local")),
    ("evidence.verify", evidence.get("verify")),
    ("evidence.vr", evidence.get("vr")),
]
for key, value in fields:
    print("{}={}".format(key, value if value is not None else ""))
')

sha_like() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

sha_matches() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" || "$expected" == "$actual"* || "$actual" == "$expected"* ]]
}

[[ "$endpoint" == "local_extension" ]] || block "extension_deliverable.endpoint must be local_extension"
[[ "$ext_id" == "$EXTENSION_ID" ]] || block "extension_id mismatch: expected ${EXTENSION_ID}, got ${ext_id:-<empty>}"
sha_like "$task_head_sha" || block "task_head_sha missing or malformed"
sha_like "$workspace_commit" || block "workspace_commit missing or malformed"
sha_like "$template_commit" || block "template_commit missing or malformed"
[[ -n "$version_tag" ]] || block "version_tag missing"
[[ -n "$completed_at" ]] || block "completed_at missing"
printf '%s' "$completed_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' \
  || block "completed_at is not ISO-like: $completed_at"

if [[ "$version_tag" != "N/A" && ! "$version_tag" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
  block "version_tag must look like v1.2.3 or be N/A"
fi
if [[ -n "$release_url" && "$release_url" != "N/A" ]]; then
  printf '%s' "$release_url" | grep -qE '^https://github\.com/.+/releases/tag/.+$' \
    || block "release_url must be a GitHub release URL or N/A"
fi

git -C "$REPO_ROOT" cat-file -e "${task_head_sha}^{commit}" 2>/dev/null \
  || block "task_head_sha does not exist in workspace repo: $task_head_sha"
git -C "$REPO_ROOT" cat-file -e "${workspace_commit}^{commit}" 2>/dev/null \
  || block "workspace_commit does not exist in workspace repo: $workspace_commit"
git -C "$REPO_ROOT" merge-base --is-ancestor "$task_head_sha" "$workspace_commit" 2>/dev/null \
  || block "workspace_commit does not contain task_head_sha"

current_workspace_head="$(git -C "$REPO_ROOT" rev-parse HEAD)"
sha_matches "$workspace_commit" "$current_workspace_head" \
  || block "workspace_commit (${workspace_commit}) is stale; current HEAD is ${current_workspace_head}"

check_ci_evidence() {
  local evidence="$1"
  [[ -n "$evidence" && "$evidence" != "N/A" ]] || block "ci_local evidence path missing"
  [[ -f "$evidence" ]] || block "ci_local evidence file not found: $evidence"
  python3 - "$evidence" "$task_head_sha" <<'PY'
import json
import sys

path, expected_sha = sys.argv[1:3]
try:
    data = json.load(open(path, encoding="utf-8"))
    status = data.get("status")
    actual_sha = str(data.get("head_sha") or "")
    writer = data.get("writer")
    if status != "PASS":
        raise AssertionError(f"status must be PASS, got {status!r}")
    if writer != "ci-local.sh":
        raise AssertionError(f"writer must be ci-local.sh, got {writer!r}")
    if not (actual_sha == expected_sha or actual_sha.startswith(expected_sha) or expected_sha.startswith(actual_sha)):
        raise AssertionError(f"head_sha mismatch: evidence={actual_sha} expected={expected_sha}")
except Exception as exc:
    print(exc, file=sys.stderr)
    sys.exit(1)
PY
}

check_verify_evidence() {
  local evidence="$1"
  [[ -n "$evidence" && "$evidence" != "N/A" ]] || block "verify evidence path missing"
  [[ -f "$evidence" ]] || block "verify evidence file not found: $evidence"
  python3 - "$evidence" "$TASK_ID" "$task_head_sha" <<'PY'
import json
import sys

path, task_id, expected_sha = sys.argv[1:4]
try:
    data = json.load(open(path, encoding="utf-8"))
    actual_ticket = data.get("ticket")
    actual_sha = str(data.get("head_sha") or "")
    writer = data.get("writer", "polaris-write-evidence.sh")
    exit_code = data.get("exit_code")
    if actual_ticket != task_id:
        raise AssertionError(f"ticket mismatch: evidence={actual_ticket!r} expected={task_id!r}")
    if not (actual_sha == expected_sha or actual_sha.startswith(expected_sha) or expected_sha.startswith(actual_sha)):
        raise AssertionError(f"head_sha mismatch: evidence={actual_sha} expected={expected_sha}")
    if writer not in {"run-verify-command.sh", "polaris-write-evidence.sh"}:
        raise AssertionError(f"writer not allowed: {writer!r}")
    if int(exit_code) != 0:
        raise AssertionError(f"exit_code must be 0, got {exit_code!r}")
except Exception as exc:
    print(exc, file=sys.stderr)
    sys.exit(1)
PY
}

if ! check_ci_evidence "$ci_local_evidence"; then
  block "ci_local evidence is malformed or stale: $ci_local_evidence"
fi
if ! check_verify_evidence "$verify_evidence"; then
  block "verify evidence is malformed or stale: $verify_evidence"
fi

if [[ -n "$vr_evidence" && "$vr_evidence" != "N/A" ]]; then
  [[ -f "$vr_evidence" ]] || block "vr evidence file not found: $vr_evidence"
fi

if [[ -n "$TEMPLATE_REPO" ]]; then
  git -C "$TEMPLATE_REPO" cat-file -e "${template_commit}^{commit}" 2>/dev/null \
    || block "template_commit does not exist in template repo: $template_commit"
  current_template_head="$(git -C "$TEMPLATE_REPO" rev-parse HEAD)"
  sha_matches "$template_commit" "$current_template_head" \
    || block "template_commit (${template_commit}) is stale; template HEAD is ${current_template_head}"
  if [[ "$version_tag" != "N/A" ]]; then
    git -C "$TEMPLATE_REPO" rev-parse -q --verify "refs/tags/${version_tag}" >/dev/null \
      || block "template tag missing: $version_tag"
  fi
fi

echo "$PREFIX ✅ local extension completion satisfied for ${TASK_ID} @ ${workspace_commit}" >&2
