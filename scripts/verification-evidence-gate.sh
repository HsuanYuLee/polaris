#!/usr/bin/env bash
# verification-evidence-gate.sh — PreToolUse hook (Dimension A only)
# Blocks `gh pr create` and `git push` (to task/fix branches on product repos)
# unless runtime/build verification evidence exists for the ticket.
#
# Intercepts:
#   - `gh pr create` — all cases (original DP-029 behavior)
#   - `git push` — only task/* and fix/* branches on repos with a workspace-owned
#     polaris-config generated ci-local script.
#
# Evidence file:
#   /tmp/polaris-verified-{TICKET}-{HEAD_SHA}.json
#     - written by run-verify-command.sh
#     - head_sha-bound (auto-stale on rebase; no 4h age check needed)
#     - schema: { ticket, head_sha, writer, exit_code, at, level, ... }
#
# Writer whitelist: evidence `writer` field is resolved from
# scripts/lib/evidence-producers.json for marker_kind=verify.
#
# Dimension B (ci-local mirror evidence) is enforced separately by ci-local-gate.sh
# (DP-032 D12-c). The two hooks both register on `gh pr create` + `git push` and
# share the same task/* + workspace-owned ci-local filter for product-repo gating.
#
# Env:
#   POLARIS_SKIP_EVIDENCE=1  — bypass (for non-ticket PRs like framework changes)
#
# Exit 0 = allow, Exit 2 = block

set -euo pipefail

# Single source of truth for the workspace-owned ci-local.sh path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"
# shellcheck source=lib/verification-evidence.sh
. "$SCRIPT_DIR/lib/verification-evidence.sh"
if [[ -f "$SCRIPT_DIR/lib/main-checkout.sh" ]]; then
  # shellcheck source=lib/main-checkout.sh
  . "$SCRIPT_DIR/lib/main-checkout.sh"
fi

input=$(cat)

tool_name=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || true)

[[ "$tool_name" == "Bash" ]] || exit 0

command=$(printf '%s' "$input" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Determine which command we're intercepting
MODE=""
if printf '%s' "$command" | grep -qiE '^gh[[:space:]]+pr[[:space:]]+create\b'; then
  MODE="pr-create"
elif printf '%s' "$command" | grep -qiE '^git[[:space:]]+((-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push|push)\b'; then
  MODE="push"
fi

[[ -n "$MODE" ]] || exit 0

# --- Push-specific filters: only block task/fix branches on product repos ---
if [[ "$MODE" == "push" ]]; then
  # Extract repo path from git -C <path> push, or use current dir
  push_repo=$(printf '%s' "$command" | grep -oE 'git -C [^ ]+' | head -1 | sed 's/git -C //' || true)
  push_repo="${push_repo:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"

  # Only intercept task/* and fix/* branches (skip wip/*, feat/*, main, develop)
  push_branch=$(git -C "${push_repo:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  case "$push_branch" in
    task/*|fix/*) ;; # continue checking
    *) exit 0 ;;     # not a delivery branch, allow
  esac

  # Only intercept repos with workspace-owned ci-local.sh.
  if [[ ! -f "$(ci_local_path_for_repo "${push_repo:-.}")" ]]; then
    exit 0  # No ci-local.sh — repo not onboarded to D12 mirror, allow
  fi

  # Skip destructive/tag pushes
  if printf '%s' "$command" | grep -qE '\-\-delete|\-\-tags'; then
    exit 0
  fi
fi

# Bypass for non-ticket PRs (framework, docs, etc.)
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  exit 0
fi

# Extract ticket key from current branch name
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# For push mode, use the repo we already resolved
if [[ "$MODE" == "push" ]]; then
  branch="$push_branch"
fi
ticket=""

# Match patterns: task/TASK-1234-desc, feat/EPIC-521-desc, fix/TASK-1234
# Project keys may contain digits (e.g., KB2CW), so [A-Z][A-Z0-9]+ not [A-Z]+
if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
  ticket="${BASH_REMATCH[1]}"
fi

if [[ -z "$ticket" ]]; then
  # No ticket in branch name — likely a framework/docs PR, allow
  exit 0
fi

# Resolve repo root for head_sha lookup. For push mode, $push_repo is already set;
# otherwise use cwd. Best-effort — failure leaves head_sha empty and we fall back.
HEAD_SHA=""
gate_repo="${push_repo:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [[ -n "$gate_repo" ]] && [[ -d "$gate_repo/.git" || -f "$gate_repo/.git" ]]; then
  HEAD_SHA="$(git -C "$gate_repo" rev-parse HEAD 2>/dev/null || true)"
fi

tmp_evidence="$(verification_evidence_tmp_path "$ticket" "$HEAD_SHA")"
durable_evidence="$(verification_evidence_durable_path "$gate_repo" "$ticket" "$HEAD_SHA" 2>/dev/null || true)"
EVIDENCE_FILE="$(verification_evidence_resolve_existing_path "$gate_repo" "$ticket" "$HEAD_SHA" 2>/dev/null || true)"
if [[ -z "$EVIDENCE_FILE" ]]; then
  echo "BLOCKED: No verification evidence for ${ticket}" >&2
  echo "" >&2
  echo "Expected:" >&2
  echo "  ${tmp_evidence}      (DP-032 Wave β D15 — head_sha-bound, written by run-verify-command.sh)" >&2
  echo "  ${durable_evidence}      (durable mirror, written by run-verify-command.sh)" >&2
  echo "" >&2
  echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${ticket}] to produce evidence." >&2
  echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
  exit 2
fi

# D15 schema: ticket, head_sha, writer, exit_code, at
# No 4h stale check — head_sha self-binds freshness (rebase invalidates filename)
if ! valid="$(verification_evidence_validate_file "$EVIDENCE_FILE" "$ticket" "$HEAD_SHA" 2>/dev/null)"; then
  valid="${valid:-invalid: parse error}"
fi
if [[ "$valid" != "valid" ]]; then
  echo "BLOCKED: head_sha-bound evidence file is malformed for ${ticket}" >&2
  echo "  ${EVIDENCE_FILE}: ${valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, head_sha, writer from scripts/lib/evidence-producers.json marker_kind=verify, exit_code, at." >&2
  echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${ticket}" >&2
  exit 2
fi

# exit_code must be 0 — verify command must have passed
if ! pass_result="$(verification_evidence_is_pass "$EVIDENCE_FILE" 2>/dev/null)"; then
  pass_result="${pass_result:-exit_code != 0}"
fi
if [[ "$pass_result" != "pass" ]]; then
  echo "BLOCKED: Verification evidence shows verify command FAIL for ${ticket}" >&2
  echo "  ${EVIDENCE_FILE}: ${pass_result}" >&2
  echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
  exit 2
fi

evidence_root="$(verification_evidence_root_for_repo "$gate_repo" 2>/dev/null || true)"
publication_tmp="/tmp/polaris-publication-${ticket}-${HEAD_SHA}.json"
publication_durable=""
if [[ -n "$HEAD_SHA" ]]; then
  publication_durable="${evidence_root}/publication/polaris-publication-${ticket}-${HEAD_SHA}.json"
fi

PUBLICATION_FILE=""
if [[ -n "$HEAD_SHA" && -f "$publication_tmp" ]]; then
  PUBLICATION_FILE="$publication_tmp"
elif [[ -n "$HEAD_SHA" && -f "$publication_durable" ]]; then
  PUBLICATION_FILE="$publication_durable"
fi

if [[ -n "$PUBLICATION_FILE" ]]; then
  if ! publication_valid=$(python3 - "$PUBLICATION_FILE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid JSON: {exc}")
    raise SystemExit(1)

remote = data.get("remote_publication") if isinstance(data.get("remote_publication"), dict) else {}
status = str(remote.get("status") or data.get("status") or "local_only")
if status in {"blocked", "failed"}:
    print(f"blocked publication status: {status}")
    raise SystemExit(1)

def is_required(artifact):
    return any(bool(artifact.get(key)) for key in ("requires_publication", "publication_required", "remote_publication_required"))

def sha256_file(file):
    digest = hashlib.sha256()
    with open(file, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

artifacts = data.get("artifacts") if isinstance(data.get("artifacts"), list) else []
errors = []
for artifact in artifacts:
    if not isinstance(artifact, dict):
        continue
    public_path = artifact.get("public_path")
    if public_path:
        candidate = Path(str(public_path))
        if not candidate.is_file():
            errors.append(f"missing static mirror: {public_path}")
        elif artifact.get("sha256") and sha256_file(candidate) != artifact.get("sha256"):
            errors.append(f"static mirror sha256 mismatch: {public_path}")
    if status in {"uploaded", "jira_uploaded"} and is_required(artifact):
        jira_attachment = artifact.get("jira_attachment") if isinstance(artifact.get("jira_attachment"), dict) else {}
        if not jira_attachment.get("url") or jira_attachment.get("status") != "uploaded":
            errors.append(f"missing Jira attachment URL for required artifact: {artifact.get('id') or artifact.get('filename')}")

if errors:
    print("; ".join(errors))
    raise SystemExit(1)
print("valid")
PY
  ); then
    publication_valid="${publication_valid:-invalid publication manifest}"
  fi
  if [[ "$publication_valid" != "valid" ]]; then
    echo "BLOCKED: publication manifest is not valid for ${ticket}" >&2
    echo "  ${PUBLICATION_FILE}: ${publication_valid}" >&2
    exit 2
  fi
fi

# Dimension B (ci-local mirror evidence) is handled by ci-local-gate.sh — DP-032 D12-c

exit 0
