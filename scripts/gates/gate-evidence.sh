#!/usr/bin/env bash
set -euo pipefail

# gate-evidence.sh — Portable git-hook gate (DP-032 Wave δ)
# Extracted from scripts/verification-evidence-gate.sh for cross-LLM portability.
# Can be called from: git pre-commit/pre-push hooks, polaris-pr-create.sh, or directly.
#
# Usage:
#   bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>] [--task-md <path>]
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_EVIDENCE=1

PREFIX="[polaris gate-evidence]"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
TICKET=""
TASK_MD=""

MAIN_CHECKOUT_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib/main-checkout.sh"
if [[ -f "$MAIN_CHECKOUT_LIB" ]]; then
  # shellcheck source=../lib/main-checkout.sh
  . "$MAIN_CHECKOUT_LIB"
fi

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="$2"; shift 2 ;;
    --ticket) TICKET="$2"; shift 2 ;;
    --task-md) TASK_MD="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-evidence.sh [--repo <path>] [--ticket <KEY>] [--task-md <path>]"
      echo "  --repo <path>     Target repo (default: git rev-parse --show-toplevel)"
      echo "  --ticket <KEY>    JIRA ticket key (default: extract from branch name)"
      echo "  --task-md <path>  Work order path for conditional Layer C VR evidence"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Default repo
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

# Bypass
if [[ "${POLARIS_SKIP_EVIDENCE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_EVIDENCE=1 — bypassing." >&2
  exit 0
fi

extract_task_key_from_branch() {
  local branch="$1"
  local key=""
  key="$(printf '%s' "$branch" | grep -oE 'DP-[0-9]{3}-T[0-9]+[a-z]*' | head -n 1 || true)"
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1 || true
}

resolve_task_md_for_branch() {
  local repo_root="$1"
  local script_root=""
  local current_branch=""
  local main_checkout=""

  script_root="$(cd "$SCRIPT_DIR/.." && pwd)"
  [[ -x "$script_root/resolve-task-md.sh" ]] || return 1
  current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$current_branch" ]] || return 1

  if declare -F resolve_main_checkout >/dev/null 2>&1; then
    main_checkout="$(resolve_main_checkout "$repo_root" 2>/dev/null || true)"
  fi
  [[ -n "$main_checkout" ]] || main_checkout="$repo_root"

  bash "$script_root/resolve-task-md.sh" --scan-root "$main_checkout" --current 2>/dev/null | head -n 1
}

# Extract ticket/task identity from branch if not provided.
if [[ -z "$TICKET" ]]; then
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  TICKET="$(extract_task_key_from_branch "$branch")"
fi

# No ticket → framework/docs PR, allow
if [[ -z "$TICKET" ]]; then
  exit 0
fi

# Resolve HEAD SHA
HEAD_SHA=""
if [[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]]; then
  HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
fi

# --- Resolve head_sha-bound evidence file ---
EVIDENCE_FILE=""

new_evidence="/tmp/polaris-verified-${TICKET}-${HEAD_SHA}.json"
durable_evidence=""
if [[ -n "$HEAD_SHA" ]]; then
  evidence_root="${POLARIS_EVIDENCE_ROOT:-}"
  if [[ -z "$evidence_root" ]]; then
    main_checkout=""
    if declare -F resolve_main_checkout >/dev/null 2>&1; then
      main_checkout="$(resolve_main_checkout "$REPO_ROOT" 2>/dev/null || true)"
    fi
    if [[ -z "$main_checkout" ]]; then
      main_checkout="$REPO_ROOT"
    fi
    evidence_root="${main_checkout}/.polaris/evidence"
  fi
  durable_evidence="${evidence_root}/verify/polaris-verified-${TICKET}-${HEAD_SHA}.json"
fi

if [[ -n "$HEAD_SHA" && -f "$new_evidence" ]]; then
  EVIDENCE_FILE="$new_evidence"
elif [[ -n "$HEAD_SHA" && -f "$durable_evidence" ]]; then
  EVIDENCE_FILE="$durable_evidence"
else
  echo "$PREFIX BLOCKED: No verification evidence for ${TICKET}" >&2
  echo "" >&2
  echo "Expected:" >&2
  echo "  ${new_evidence}  (D15 — head_sha-bound, written by run-verify-command.sh)" >&2
  echo "  ${durable_evidence}  (durable mirror, written by run-verify-command.sh)" >&2
  echo "" >&2
  echo "Run scripts/run-verify-command.sh --task-md <path> [--ticket ${TICKET}] to produce evidence." >&2
  echo "If this is a non-ticket PR, set POLARIS_SKIP_EVIDENCE=1" >&2
  exit 2
fi

# D15 schema: ticket, head_sha, writer (whitelisted), exit_code, at
valid=$(python3 -c "
import json
WHITELIST = {'run-verify-command.sh'}
try:
    with open('${EVIDENCE_FILE}') as f:
        d = json.load(f)
    assert d.get('ticket') == '${TICKET}', 'ticket mismatch'
    assert d.get('head_sha') == '${HEAD_SHA}', 'head_sha mismatch'
    writer = d.get('writer')
    assert writer in WHITELIST, f'writer not in whitelist: {writer!r}'
    assert 'exit_code' in d, 'missing exit_code'
    assert isinstance(d['exit_code'], int), 'exit_code must be int'
    assert d.get('at'), 'missing at'
    print('valid')
except Exception as e:
    print(f'invalid: {e}')
" 2>/dev/null || echo "invalid: parse error")

if [[ "$valid" != "valid" ]]; then
  echo "$PREFIX BLOCKED: head_sha-bound evidence file is malformed for ${TICKET}" >&2
  echo "  ${EVIDENCE_FILE}: ${valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, head_sha, writer=run-verify-command.sh, exit_code, at." >&2
  echo "Re-run: scripts/run-verify-command.sh --task-md <path> --ticket ${TICKET}" >&2
  exit 2
fi

# exit_code must be 0
exit_code_pass=$(python3 -c "
import json
with open('${EVIDENCE_FILE}') as f:
    d = json.load(f)
print('pass' if int(d.get('exit_code', -1)) == 0 else 'fail')
" 2>/dev/null || echo "fail")

if [[ "$exit_code_pass" != "pass" ]]; then
  echo "$PREFIX BLOCKED: Verification evidence shows FAIL for ${TICKET}" >&2
  echo "  ${EVIDENCE_FILE}: exit_code != 0" >&2
  echo "  Fix the underlying issue and re-run scripts/run-verify-command.sh." >&2
  exit 2
fi

echo "$PREFIX ✅ D15 evidence valid for ${TICKET} @ ${HEAD_SHA}." >&2

# Layer C: conditional native visual regression evidence. Only tasks that
# declare verification.visual_regression require this gate.
if [[ -z "$TASK_MD" ]]; then
  TASK_MD="$(resolve_task_md_for_branch "$REPO_ROOT" || true)"
fi

if [[ -z "$TASK_MD" || ! -f "$TASK_MD" ]]; then
  echo "$PREFIX Layer C VR skip: task.md not resolved." >&2
  exit 0
fi

PARSE_TASK_MD="$(cd "$SCRIPT_DIR/.." && pwd)/parse-task-md.sh"
VR_EXPECTED=""
if [[ -x "$PARSE_TASK_MD" ]]; then
  VR_EXPECTED="$(bash "$PARSE_TASK_MD" --field verification_visual_regression_expected --no-resolve "$TASK_MD" 2>/dev/null || true)"
fi

if [[ -z "$VR_EXPECTED" ]]; then
  echo "$PREFIX Layer C VR skip: task.md has no verification.visual_regression." >&2
  exit 0
fi

vr_tmp="/tmp/polaris-vr-${TICKET}-${HEAD_SHA}.json"
vr_durable=""
if [[ -n "$HEAD_SHA" ]]; then
  vr_durable="${evidence_root}/vr/polaris-vr-${TICKET}-${HEAD_SHA}.json"
fi

VR_EVIDENCE_FILE=""
if [[ -n "$HEAD_SHA" && -f "$vr_tmp" ]]; then
  VR_EVIDENCE_FILE="$vr_tmp"
elif [[ -n "$HEAD_SHA" && -f "$vr_durable" ]]; then
  VR_EVIDENCE_FILE="$vr_durable"
fi

if [[ -z "$VR_EVIDENCE_FILE" ]]; then
  stale_match="$(
    {
      find /tmp -maxdepth 1 -type f -name "polaris-vr-${TICKET}-*.json" 2>/dev/null
      find /private/tmp -maxdepth 1 -type f -name "polaris-vr-${TICKET}-*.json" 2>/dev/null
      if [[ -d "${evidence_root}/vr" ]]; then
        find "${evidence_root}/vr" -maxdepth 1 -type f -name "polaris-vr-${TICKET}-*.json" 2>/dev/null
      fi
    } | while IFS= read -r path; do
      if [[ "$path" != *-"$HEAD_SHA".json ]]; then
        printf '%s\n' "$path"
        break
      fi
    done || true
  )"
  if [[ -n "$stale_match" ]]; then
    echo "$PREFIX BLOCKED: stale Layer C VR evidence for ${TICKET}; no evidence matches HEAD ${HEAD_SHA}" >&2
  else
    echo "$PREFIX BLOCKED: No Layer C VR evidence for ${TICKET}" >&2
  fi
  echo "" >&2
  echo "Expected:" >&2
  echo "  ${vr_tmp}  (Layer C — head_sha-bound, written by run-visual-snapshot.sh)" >&2
  echo "  ${vr_durable}  (durable mirror, written by run-visual-snapshot.sh)" >&2
  echo "" >&2
  echo "Run scripts/run-visual-snapshot.sh --task-md <path> --mode baseline, then --mode compare." >&2
  exit 2
fi

vr_valid=$(python3 - "$VR_EVIDENCE_FILE" "$TICKET" "$HEAD_SHA" <<'PY'
import json
import sys

path, ticket, head_sha = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    assert data.get("writer") == "run-visual-snapshot.sh", "writer mismatch"
    assert data.get("ticket") == ticket, "ticket mismatch"
    assert data.get("head_sha") == head_sha, "head_sha mismatch"
    assert data.get("mode") == "compare", "mode must be compare"
    assert data.get("status") == "PASS", f"status must be PASS, got {data.get('status')!r}"
    assert data.get("at"), "missing at"
    print("valid")
except Exception as exc:
    print(f"invalid: {exc}")
PY
)

if [[ "$vr_valid" != "valid" ]]; then
  echo "$PREFIX BLOCKED: Layer C VR evidence is malformed or not passing for ${TICKET}" >&2
  echo "  ${VR_EVIDENCE_FILE}: ${vr_valid}" >&2
  echo "" >&2
  echo "Evidence must contain: ticket, head_sha, writer=run-visual-snapshot.sh, mode=compare, status=PASS, at." >&2
  exit 2
fi

echo "$PREFIX ✅ Layer C VR evidence valid for ${TICKET} @ ${HEAD_SHA}." >&2
exit 0
