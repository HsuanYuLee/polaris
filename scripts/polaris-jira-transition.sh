#!/bin/bash
# polaris-jira-transition.sh — Unified JIRA status transition (D25, DP-032 Wave α)
#
# Cross-LLM entry point for transitioning a JIRA issue to a target status.
# Replaces scattered MCP `transitionJiraIssue` calls in engineering / verify-AC /
# bug-triage / start-dev so non-Claude runtimes (Codex, Cursor, Gemini CLI) can
# share the same primitive.
#
# Aggressive soft-fail strategy (per DP-032 D25):
#   - JIRA transition is a nice-to-have display layer; task.md + PR are the
#     authoritative delivery record. A failed transition must NEVER block the
#     delivery flow.
#   - Any non-usage failure (missing config, no credentials, API error, ticket
#     already past target, transition unreachable) → stderr message + exit 0.
#   - No retries, no Slack/PR notifications, no follow-up.
#   - Idempotent: ticket already at target status → skip + exit 0.
#
# Hard failures (exit 1) reserved for caller bugs only:
#   - Wrong number of arguments
#   - Malformed ticket key
#
# Usage:
#   polaris-jira-transition.sh <ticket> <target_status_slug>
#
# Examples:
#   polaris-jira-transition.sh KB2CW-3900 in_development
#   polaris-jira-transition.sh GT-478 code_review
#   polaris-jira-transition.sh KB2CW-3653 done
#
# Status slugs (built-in default mapping; override via workspace-config):
#   in_development → "In Development"
#   code_review    → "Code Review"
#   done           → "Done"
#   waiting_qa     → "Waiting QA"
#   qa_pass        → "QA Pass"
#   blocked        → "Blocked"
#
# Override mapping in workspace-config.yaml (per company JIRA workflow):
#   jira:
#     transitions:
#       code_review: "Ready for Review"   # custom display name
#
# Env:
#   JIRA_EMAIL          Atlassian account email (from .env.secrets)
#   JIRA_API_TOKEN      Atlassian API token (from .env.secrets)
#   JIRA_SITE           Override jira.instance (e.g. mycompany.atlassian.net)
#   POLARIS_COMPANY_DIR Pin company config dir; bypasses walk-up search
#
# Secrets file auto-detection (mirrors jira-upload-attachment.sh):
#   POLARIS_COMPANY_DIR/.env.secrets → ../kkday/.env.secrets → ~/work/kkday/.env.secrets

# NOTE: deliberately no `set -e`. Every error path is handled with explicit
# soft-fail so a missed exit-code propagation cannot break delivery flow.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

soft_info() { echo "polaris-jira-transition: $*" >&2; }
soft_warn() { echo "polaris-jira-transition: WARN: $*" >&2; }

usage() {
  cat >&2 <<'EOF'
Usage: polaris-jira-transition.sh <ticket> <target_status_slug>

  ticket               JIRA issue key (e.g. KB2CW-3900, GT-478)
  target_status_slug   in_development | code_review | done | waiting_qa |
                       qa_pass | blocked
                       (or any slug declared under jira.transitions in
                        workspace-config.yaml)

Aggressive soft-fail: API/config failures never block delivery; only
usage errors exit non-zero.
EOF
}

# ── Find workspace-config.yaml carrying jira.instance ──
# Search order:
#   1) $POLARIS_COMPANY_DIR/workspace-config.yaml (explicit pin)
#   2) Walk up from PWD; if any workspace-config has jira.instance, use it.
#   3) Worktree case: walk up from `git rev-parse --git-common-dir` parent.
#   4) Outermost workspace-config (root) with `companies[]` → first
#      company whose own workspace-config defines jira.instance.
find_company_config() {
  if [[ -n "${POLARIS_COMPANY_DIR:-}" ]] && [[ -f "$POLARIS_COMPANY_DIR/workspace-config.yaml" ]]; then
    echo "$POLARIS_COMPANY_DIR/workspace-config.yaml"
    return 0
  fi

  local seen=() probe gc gc_abs p2
  probe="$(pwd)"
  while [[ "$probe" != "/" && -n "$probe" ]]; do
    if [[ -f "$probe/workspace-config.yaml" ]]; then
      seen+=("$probe/workspace-config.yaml")
    fi
    probe="$(dirname "$probe")"
  done

  if command -v git >/dev/null 2>&1; then
    gc="$(git rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -n "$gc" ]]; then
      [[ "$gc" = /* ]] || gc="$(pwd)/$gc"
      gc_abs="$(cd "$gc" 2>/dev/null && pwd || true)"
      if [[ -n "$gc_abs" ]]; then
        p2="$(dirname "$gc_abs")"
        while [[ "$p2" != "/" && -n "$p2" ]]; do
          if [[ -f "$p2/workspace-config.yaml" ]]; then
            seen+=("$p2/workspace-config.yaml")
          fi
          p2="$(dirname "$p2")"
        done
      fi
    fi
  fi

  local cfg
  for cfg in "${seen[@]:-}"; do
    [[ -z "$cfg" ]] && continue
    if has_jira_instance "$cfg"; then
      echo "$cfg"
      return 0
    fi
  done

  for cfg in "${seen[@]:-}"; do
    [[ -z "$cfg" ]] && continue
    local company_cfg
    company_cfg=$(python3 - "$cfg" <<'PY' 2>/dev/null
import os, sys, yaml
cfg_path = sys.argv[1]
try:
    with open(cfg_path) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
for comp in data.get('companies') or []:
    base = (comp.get('base_dir') or '').strip()
    if not base:
        continue
    base = os.path.expanduser(base)
    cand = os.path.join(base, 'workspace-config.yaml')
    if not os.path.isfile(cand):
        continue
    try:
        with open(cand) as f:
            cd = yaml.safe_load(f) or {}
    except Exception:
        continue
    if (cd.get('jira') or {}).get('instance'):
        print(cand)
        sys.exit(0)
PY
)
    if [[ -n "$company_cfg" ]]; then
      echo "$company_cfg"
      return 0
    fi
  done

  return 1
}

has_jira_instance() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, yaml
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(1)
sys.exit(0 if (data.get('jira') or {}).get('instance') else 1)
PY
}

# Read jira.instance + resolve transition target name (config → default).
# Stdout (3 lines): instance, target_name, source ("config"|"default"|"")
read_jira_config() {
  local cfg="$1" slug="$2"
  python3 - "$cfg" "$slug" <<'PY'
import sys, yaml
cfg_path, slug = sys.argv[1], sys.argv[2]
try:
    with open(cfg_path) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print('')
    print('')
    print('')
    sys.exit(0)
jira = data.get('jira') or {}
print((jira.get('instance') or '').strip())

transitions = jira.get('transitions') or {}
configured = (transitions.get(slug) or '').strip()

defaults = {
    'in_development': 'In Development',
    'code_review':    'Code Review',
    'done':           'Done',
    'waiting_qa':     'Waiting QA',
    'qa_pass':        'QA Pass',
    'blocked':        'Blocked',
}

if configured:
    print(configured)
    print('config')
elif slug in defaults:
    print(defaults[slug])
    print('default')
else:
    print('')
    print('')
PY
}

# ── Credentials (mirror jira-upload-attachment.sh) ──
load_credentials() {
  if [[ -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then return 0; fi

  local search_dirs=(
    "${POLARIS_COMPANY_DIR:-}"
    "$SCRIPT_DIR/../kkday"
    "$HOME/work/kkday"
  )

  local dir secrets
  for dir in "${search_dirs[@]}"; do
    [[ -z "$dir" ]] && continue
    secrets="$dir/.env.secrets"
    if [[ -f "$secrets" ]]; then
      set +u
      # shellcheck disable=SC1090
      source "$secrets"
      set -u
      [[ -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]] && return 0
    fi
  done

  return 1
}

# ── REST API helpers (curl + python parsing) ──

# Returns current status name (stdout). Lines starting "::ERROR::" indicate
# fetch/parse failure (caller treats as soft-fail).
get_current_status() {
  local site="$1" ticket="$2"
  curl -s --max-time 30 \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "https://$site/rest/api/2/issue/$ticket?fields=status" 2>/dev/null \
  | python3 -c "
import json, sys
raw = sys.stdin.read()
if not raw.strip():
    print('::ERROR::empty response')
    sys.exit(0)
try:
    d = json.loads(raw)
except Exception as e:
    print('::ERROR::parse failure: ' + str(e))
    sys.exit(0)
err = d.get('errorMessages')
if err:
    print('::ERROR::' + ' '.join(err))
    sys.exit(0)
name = (((d.get('fields') or {}).get('status') or {}).get('name') or '').strip()
if not name:
    print('::ERROR::status name missing')
    sys.exit(0)
print(name)
"
}

# Print "<id>\t<to.name>" per line for each available transition.
# On failure prints nothing and returns 1.
get_available_transitions() {
  local site="$1" ticket="$2"
  local body
  body=$(curl -s --max-time 30 \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "https://$site/rest/api/2/issue/$ticket/transitions" 2>/dev/null) || return 1
  [[ -z "$body" ]] && return 1
  echo "$body" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
if d.get('errorMessages'):
    sys.exit(1)
for t in d.get('transitions') or []:
    tid = (t.get('id') or '').strip()
    to_name = ((t.get('to') or {}).get('name') or '').strip()
    if tid and to_name:
        print(tid + '\t' + to_name)
"
}

# Execute transition. Return 0 on 2xx, 1 otherwise (with stderr detail).
post_transition() {
  local site="$1" ticket="$2" tid="$3"
  local response http_code body
  response=$(curl -s --max-time 30 -w "\n%{http_code}" \
    -X POST \
    -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"transition\":{\"id\":\"$tid\"}}" \
    "https://$site/rest/api/2/issue/$ticket/transitions" 2>/dev/null) || return 1
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  fi
  echo "HTTP $http_code: $body" >&2
  return 1
}

# Lowercase a string (bash 3.2 compatible).
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# ── Main ──
main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  if [[ $# -ne 2 ]]; then
    usage
    exit 1
  fi

  local ticket="$1" slug="$2"

  if ! [[ "$ticket" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
    soft_warn "ticket key looks malformed: '$ticket' (expected PROJECT-123) — skipping"
    exit 0
  fi

  if [[ -z "$slug" ]]; then
    soft_warn "empty status slug — skipping"
    exit 0
  fi

  local cfg
  if ! cfg=$(find_company_config); then
    soft_warn "no workspace-config.yaml with jira.instance found from $(pwd) — skipping transition"
    exit 0
  fi

  local cfg_data instance target_name source
  cfg_data=$(read_jira_config "$cfg" "$slug")
  instance=$(echo "$cfg_data" | sed -n '1p')
  target_name=$(echo "$cfg_data" | sed -n '2p')
  source=$(echo "$cfg_data" | sed -n '3p')

  # JIRA_SITE env override beats config.
  if [[ -n "${JIRA_SITE:-}" ]]; then
    instance="$JIRA_SITE"
  fi

  if [[ -z "$instance" ]]; then
    soft_warn "jira.instance missing in $cfg (and JIRA_SITE not set) — skipping transition"
    exit 0
  fi

  if [[ -z "$target_name" ]]; then
    soft_warn "unknown status slug '$slug' (no built-in default; not declared in jira.transitions) — skipping transition"
    exit 0
  fi

  if [[ "$source" == "default" ]]; then
    soft_info "using built-in default mapping: $slug → '$target_name' (declare jira.transitions.$slug in $cfg to override; default mapping is migration-period only and will be removed by DP-035)"
  fi

  if ! load_credentials; then
    soft_warn "JIRA credentials unavailable (set JIRA_EMAIL + JIRA_API_TOKEN, or provide .env.secrets in POLARIS_COMPANY_DIR / ~/work/kkday/) — skipping transition"
    exit 0
  fi

  local current
  current=$(get_current_status "$instance" "$ticket")
  if [[ "$current" == ::ERROR::* ]]; then
    soft_warn "fetch status failed for $ticket: ${current#::ERROR::} — skipping"
    exit 0
  fi

  if [[ "$(lower "$current")" == "$(lower "$target_name")" ]]; then
    soft_info "$ticket already at '$current' — idempotent skip"
    exit 0
  fi

  local transitions tid="" matched_to=""
  if ! transitions=$(get_available_transitions "$instance" "$ticket"); then
    soft_warn "fetch transitions failed for $ticket — skipping"
    exit 0
  fi

  local id to_name
  while IFS=$'\t' read -r id to_name; do
    [[ -z "$id" || -z "$to_name" ]] && continue
    if [[ "$(lower "$to_name")" == "$(lower "$target_name")" ]]; then
      tid="$id"
      matched_to="$to_name"
      break
    fi
  done <<< "$transitions"

  if [[ -z "$tid" ]]; then
    soft_warn "transition to '$target_name' not reachable from current status '$current' for $ticket (workflow may have no direct edge, or ticket has moved past) — skipping"
    exit 0
  fi

  if post_transition "$instance" "$ticket" "$tid"; then
    soft_info "$ticket: '$current' → '$matched_to'"
    exit 0
  fi

  soft_warn "transition POST failed for $ticket — skipping"
  exit 0
}

main "$@"
