#!/usr/bin/env bash
# ci-local-run.sh — Canonical entry point for running ci-local against current PWD.
#
# DP-079 follow-up. Resolves the canonical ci-local.sh from workspace-owned
# polaris-config (works correctly from inside a worktree) and invokes it with
# --repo $PWD.
#
# Usage:
#   bash {polaris}/scripts/ci-local-run.sh                   # validates $PWD
#   bash {polaris}/scripts/ci-local-run.sh --repo <path>     # validates <path>
#   bash {polaris}/scripts/ci-local-run.sh --repo <path> --base-branch <branch>
#
# Behavior:
#   - Resolves main checkout via `git rev-parse --git-common-dir`
#   - If workspace-owned polaris-config has no generated ci-local.sh, legacy
#     repo-local `.claude/scripts/ci-local.sh` is a migration error unless
#     POLARIS_ALLOW_CI_LOCAL_LEGACY=1 is set explicitly.
#   - Otherwise: bash <company>/polaris-config/<project>/generated-scripts/ci-local.sh --repo <target>
#   - BLOCKED_ENV is retried once in the same context, then surfaced as a
#     runtime-neutral RETRY_WITH_ESCALATION payload for Codex/Claude/human shell
#     adapters to handle. The wrapper never performs elevated execution itself.
#   - If no --base-branch is provided, attempts to resolve the task.md base
#     from the current branch so stacked PR local Codecov checks match CI.
#
# Exit codes: forwarded from ci-local.sh (0 PASS, 1 FAIL/BLOCKED_ENV, 2 invalid usage).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/main-checkout.sh
. "$SCRIPT_DIR/lib/main-checkout.sh"
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"

TARGET_REPO=""
BASE_BRANCH=""
EVENT=""
SOURCE_BRANCH=""
REF=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) TARGET_REPO="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --source-branch) SOURCE_BRANCH="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,/^set -uo pipefail$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[ci-local-run] Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$TARGET_REPO" ]] && TARGET_REPO="$(pwd)"
TARGET_REPO="$(cd "$TARGET_REPO" 2>/dev/null && pwd)" || {
  echo "[ci-local-run] ERROR: target path not accessible: $TARGET_REPO" >&2
  exit 2
}

main_checkout="$(resolve_main_checkout "$TARGET_REPO")" || {
  echo "[ci-local-run] ERROR: not inside a git repo (target: $TARGET_REPO)" >&2
  exit 2
}

canonical_script="$(ci_local_path_for_repo "$TARGET_REPO")"
legacy_script="$(ci_local_legacy_path_for_repo "$TARGET_REPO")"
if [[ ! -f "$canonical_script" ]]; then
  if [[ -f "$legacy_script" ]]; then
    if [[ "${POLARIS_ALLOW_CI_LOCAL_LEGACY:-0}" == "1" ]]; then
      canonical_script="$legacy_script"
      echo "[ci-local-run] using repo-local fallback reason=$CI_LOCAL_LEGACY_REASON path=$legacy_script" >&2
    else
      echo "[ci-local-run] ERROR: repo-local legacy ci-local exists but canonical workspace-owned script is missing." >&2
      echo "[ci-local-run] canonical: $canonical_script" >&2
      echo "[ci-local-run] legacy:    $legacy_script" >&2
      echo "[ci-local-run] fix: migrate with ci-local-generate.sh --repo '$TARGET_REPO' --force, then remove repo-local legacy script." >&2
      exit 2
    fi
  else
    echo "[ci-local-run] NO_CI_LOCAL_CONFIGURED canonical=$canonical_script" >&2
    exit 0
  fi
fi

if [[ -z "$BASE_BRANCH" ]]; then
  task_md="$(cd "$TARGET_REPO" && bash "$SCRIPT_DIR/resolve-task-md-by-branch.sh" --current 2>/dev/null | head -1 || true)"
  if [[ -n "$task_md" && -x "$SCRIPT_DIR/resolve-task-base.sh" ]]; then
    BASE_BRANCH="$(bash "$SCRIPT_DIR/resolve-task-base.sh" "$task_md" 2>/dev/null || true)"
  fi
fi

args=(--repo "$TARGET_REPO")
[[ -n "$EVENT" ]] && args+=(--event "$EVENT")
[[ -n "$BASE_BRANCH" ]] && args+=(--base-branch "$BASE_BRANCH")
[[ -n "$SOURCE_BRANCH" ]] && args+=(--source-branch "$SOURCE_BRANCH")
[[ -n "$REF" ]] && args+=(--ref "$REF")

wrapper_command=(bash "$SCRIPT_DIR/ci-local-run.sh" --repo "$TARGET_REPO")
[[ -n "$EVENT" ]] && wrapper_command+=(--event "$EVENT")
[[ -n "$BASE_BRANCH" ]] && wrapper_command+=(--base-branch "$BASE_BRANCH")
[[ -n "$SOURCE_BRANCH" ]] && wrapper_command+=(--source-branch "$SOURCE_BRANCH")
[[ -n "$REF" ]] && wrapper_command+=(--ref "$REF")

run_ci_local_capture() {
  local log_path="$1"
  shift
  : > "$log_path"
  bash "$canonical_script" "$@" 2>&1 | tee -a "$log_path"
  return "${PIPESTATUS[0]}"
}

latest_evidence_from_log() {
  python3 - "$1" <<'PY'
import re
import sys

try:
    text = open(sys.argv[1], "r", encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)

matches = re.findall(r"evidence(?: written)?:\s*([^\s)]+)", text)
if matches:
    print(matches[-1])
PY
}

evidence_status() {
  python3 - "$1" <<'PY'
import json
import sys

try:
    print(json.load(open(sys.argv[1], "r", encoding="utf-8")).get("status", ""))
except Exception:
    print("")
PY
}

evidence_identity() {
  python3 - "$1" <<'PY'
import hashlib
import json
import sys

try:
    data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
except Exception:
    sys.exit(0)

context = data.get("context") or {}
raw = "|".join(str(context.get(k) or "") for k in ("event", "base_branch", "source_branch", "ref"))
context_hash = hashlib.sha1(raw.encode()).hexdigest()[:12]
print("|".join([
    str(data.get("branch") or ""),
    str(data.get("head_sha") or ""),
    context_hash,
]))
PY
}

emit_blocked_env_payload() {
  local evidence_path="$1"
  shift
  python3 - "$evidence_path" "$@" <<'PY'
import hashlib
import json
import shlex
import sys

evidence_path = sys.argv[1]
command = sys.argv[2:]

try:
    data = json.load(open(evidence_path, "r", encoding="utf-8"))
except Exception as exc:
    print(f"[ci-local-run] BLOCKED_ENV evidence could not be read: {exc}", file=sys.stderr)
    sys.exit(0)

blocked = data.get("blocked_env") or {}
context = data.get("context") or {}
raw_context = "|".join(str(context.get(k) or "") for k in ("event", "base_branch", "source_branch", "ref"))
context_hash = hashlib.sha1(raw_context.encode()).hexdigest()[:12]
reason = blocked.get("reason") or "unknown"
host = blocked.get("host") or ""
manual_remediation = "Connect the required VPN/private network or run the same command from an unsandboxed shell, then rerun the exact command."

payload = {
    "action": "RETRY_WITH_ESCALATION",
    "status": "BLOCKED_ENV",
    "reason": reason,
    "host": host,
    "stage": blocked.get("stage") or "",
    "package_manager": blocked.get("package_manager") or "",
    "context_hash": context_hash,
    "head_sha": data.get("head_sha") or "",
    "evidence": evidence_path,
    "command": " ".join(shlex.quote(part) for part in command),
    "manual_remediation": manual_remediation,
}

print(f"[ci-local-run] BLOCKED_ENV still present after same-context retry: reason={reason} host={host or 'unknown'}", file=sys.stderr)
print(json.dumps(payload, indent=2, sort_keys=True), file=sys.stderr)
PY
}

first_log="$(mktemp)"
second_log="$(mktemp)"
trap 'rm -f "$first_log" "$second_log"' EXIT

run_ci_local_capture "$first_log" "${args[@]}"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  exit 0
fi

first_evidence="$(latest_evidence_from_log "$first_log")"
first_status=""
if [[ -n "$first_evidence" && -f "$first_evidence" ]]; then
  first_status="$(evidence_status "$first_evidence")"
fi

if [[ "$first_status" != "BLOCKED_ENV" ]]; then
  exit "$rc"
fi

if [[ "${CI_LOCAL_ENV_RETRY_ONCE_DONE:-}" != "1" ]]; then
  echo "[ci-local-run] BLOCKED_ENV detected; retrying once with the same ci-local context." >&2
  CI_LOCAL_ENV_RETRY_ONCE_DONE=1 run_ci_local_capture "$second_log" "${args[@]}"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    exit 0
  fi

  second_evidence="$(latest_evidence_from_log "$second_log")"
  second_status=""
  if [[ -n "$second_evidence" && -f "$second_evidence" ]]; then
    second_status="$(evidence_status "$second_evidence")"
  fi

  if [[ "$second_status" == "BLOCKED_ENV" ]]; then
    first_identity="$(evidence_identity "$first_evidence")"
    second_identity="$(evidence_identity "$second_evidence")"
    if [[ -z "$first_identity" || -z "$second_identity" || "$first_identity" != "$second_identity" ]]; then
      echo "[ci-local-run] ERROR: BLOCKED_ENV retry context changed; refusing escalation payload." >&2
      echo "[ci-local-run] first=${first_identity:-unreadable} second=${second_identity:-unreadable}" >&2
      exit 2
    fi
    emit_blocked_env_payload "$second_evidence" "${wrapper_command[@]}"
  fi
  exit "$rc"
fi

emit_blocked_env_payload "$first_evidence" "${wrapper_command[@]}"
exit "$rc"
