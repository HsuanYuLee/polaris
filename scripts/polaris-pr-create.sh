#!/usr/bin/env bash
set -euo pipefail

# polaris-pr-create.sh — PR creation wrapper with pre-flight gates (DP-032 Wave δ)
# Replaces bare `gh pr create` in Polaris engineering flows.
# Runs base-check + evidence + ci-local + PR metadata gates before PR creation.
#
# Usage:
#   bash scripts/polaris-pr-create.sh [--repo <path>] [--task-md <path>] [--skip-gates] [--dry-run] [--aggregate-release] -- <gh pr create args...>
#   bash scripts/polaris-pr-create.sh --base develop --title "feat: X" --body "..."
#
# All unrecognized flags are passed through to `gh pr create`.
# Gates that fail with exit 2 abort PR creation.
#
# `--skip-gates` may skip non-source gates only. The work-source gate is
# mandatory in Polaris-governed repos and has no emergency bypass.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATES_DIR="$SCRIPT_DIR/gates"
REVIEW_LABEL_LIB="$SCRIPT_DIR/lib/pr-review-label.sh"
SPECS_ROOT_LIB="$SCRIPT_DIR/lib/specs-root.sh"
GITHUB_REST_LIB="$SCRIPT_DIR/lib/github-rest.sh"

PREFIX="[polaris-pr-create]"
REPO_PATH=""
TASK_MD_PATH=""
SKIP_GATES="${POLARIS_SKIP_PR_GATES:-0}"
AGGREGATE_RELEASE=0
AGG_SOURCE=""
AGG_VERSION=""
AGG_BUNDLED_TASKS=""
DRY_RUN=0
GH_ARGS=()
CREATED_PR_URL=""

if [[ -f "$REVIEW_LABEL_LIB" ]]; then
  # shellcheck source=lib/pr-review-label.sh
  . "$REVIEW_LABEL_LIB"
fi
if [[ -f "$SPECS_ROOT_LIB" ]]; then
  # shellcheck source=lib/specs-root.sh
  . "$SPECS_ROOT_LIB"
fi
if [[ -f "$GITHUB_REST_LIB" ]]; then
  # shellcheck source=lib/github-rest.sh
  . "$GITHUB_REST_LIB"
fi

usage() {
  cat <<EOF
Usage: polaris-pr-create.sh [--repo <path>] [--task-md <path>] [--skip-gates] [--dry-run]
                            [--aggregate-release --source DP-NNN --version vX.Y.Z --bundled-tasks T1,T2,...]
                            [--] <gh pr create args...>

Wrapper for 'gh pr create' that runs pre-flight gates before PR creation.

Options:
  --repo <path>     Repository path (default: cwd)
  --task-md <path>  Explicit Polaris task.md work source for gates
  --skip-gates      Skip non-source gates only; work-source gate still runs
  --dry-run         Run gates but do not create the PR
  --aggregate-release
                     Treat this as an explicit framework aggregate release PR.
                     Inserts a "Bundle Identity" block (bundle_branch_alias /
                     bundled_tasks / source / version) into the PR body so the
                     downstream scope gate can union merged-task Allowed Files.
  --source <DP-NNN>      DP source ID (required with --aggregate-release).
  --version <vX.Y.Z>     Release version (required with --aggregate-release).
  --bundled-tasks T1,T2  Comma-separated bundled task IDs (required with --aggregate-release).
  -h, --help        Show this help

All other arguments are passed verbatim to 'gh pr create'.
EOF
  exit 0
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage ;;
    --repo)          REPO_PATH="$2"; shift 2 ;;
    --repo=*)        REPO_PATH="${1#--repo=}"; shift ;;
    --task-md)       TASK_MD_PATH="$2"; shift 2 ;;
    --task-md=*)     TASK_MD_PATH="${1#--task-md=}"; shift ;;
    --skip-gates)    SKIP_GATES=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --aggregate-release) AGGREGATE_RELEASE=1; shift ;;
    --source)        AGG_SOURCE="$2"; shift 2 ;;
    --source=*)      AGG_SOURCE="${1#--source=}"; shift ;;
    --version)       AGG_VERSION="$2"; shift 2 ;;
    --version=*)     AGG_VERSION="${1#--version=}"; shift ;;
    --bundled-tasks) AGG_BUNDLED_TASKS="$2"; shift 2 ;;
    --bundled-tasks=*) AGG_BUNDLED_TASKS="${1#--bundled-tasks=}"; shift ;;
    --)              shift; GH_ARGS+=("$@"); break ;;
    *)               GH_ARGS+=("$1"); shift ;;
  esac
done

# DP-230 D37: aggregate-release identity validation. The bundle identity block
# is the deterministic carrier for `bundle_branch_alias` + `bundled_tasks` that
# the downstream scope gate (check-pr-scope.sh) consumes; require complete inputs.
if [[ "$AGGREGATE_RELEASE" -eq 1 ]]; then
  if [[ -z "$AGG_SOURCE" || -z "$AGG_VERSION" || -z "$AGG_BUNDLED_TASKS" ]]; then
    echo "$PREFIX ✗ BLOCKED: --aggregate-release requires --source, --version, and --bundled-tasks." >&2
    exit 2
  fi
  if [[ ! "$AGG_SOURCE" =~ ^DP-[0-9]+$ ]]; then
    echo "$PREFIX ✗ BLOCKED: --source must look like DP-NNN (got: $AGG_SOURCE)" >&2
    exit 2
  fi
  if [[ ! "$AGG_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "$PREFIX ✗ BLOCKED: --version must look like vX.Y.Z (got: $AGG_VERSION)" >&2
    exit 2
  fi
fi

REPO_PATH="${REPO_PATH:-$(pwd)}"

# --- Extract --base from GH_ARGS ---
BASE_BRANCH=""
PR_TITLE=""
PR_BODY=""
PR_BODY_FILE=""
PR_BODY_SOURCE=""
for (( i=0; i<${#GH_ARGS[@]}; i++ )); do
  case "${GH_ARGS[$i]}" in
    --base=*) BASE_BRANCH="${GH_ARGS[$i]#--base=}" ;;
    --title=*) PR_TITLE="${GH_ARGS[$i]#--title=}" ;;
    --body=*) PR_BODY="${GH_ARGS[$i]#--body=}"; PR_BODY_SOURCE="body" ;;
    --body-file=*) PR_BODY_FILE="${GH_ARGS[$i]#--body-file=}"; PR_BODY_SOURCE="file" ;;
    --base)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        BASE_BRANCH="${GH_ARGS[$(( i + 1 ))]}"
      fi
      ;;
    --title)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_TITLE="${GH_ARGS[$(( i + 1 ))]}"
      fi
      ;;
    --body)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_BODY="${GH_ARGS[$(( i + 1 ))]}"
        PR_BODY_SOURCE="body"
      fi
      ;;
    --body-file)
      if [[ $(( i + 1 )) -lt ${#GH_ARGS[@]} ]]; then
        PR_BODY_FILE="${GH_ARGS[$(( i + 1 ))]}"
        PR_BODY_SOURCE="file"
      fi
      ;;
  esac
done

# DP-230 D37: inject aggregate-release bundle identity block into the PR body.
# The block is deterministic key-value lines (parsed by scripts/check-pr-scope.sh)
# wrapped in a "Bundle Identity" markdown section. We materialize the augmented
# body in a tmpfile and rewrite GH_ARGS so `gh pr create` consumes --body-file.
inject_bundle_identity_block() {
  local body_text=""
  if [[ "$PR_BODY_SOURCE" == "file" && -n "$PR_BODY_FILE" && -f "$PR_BODY_FILE" ]]; then
    body_text="$(cat "$PR_BODY_FILE")"
  elif [[ "$PR_BODY_SOURCE" == "body" ]]; then
    body_text="$PR_BODY"
  else
    body_text=""
  fi

  # Detect existing branch name (alias for bundle_branch_alias).
  local branch_alias=""
  branch_alias="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$branch_alias" && "$branch_alias" != "HEAD" ]] \
    || branch_alias="bundle-${AGG_SOURCE}-${AGG_VERSION}"

  # Build identity block. Render bundled_tasks as JSON-like list for
  # downstream parsers; keep the literal section heading "Bundle Identity"
  # because gate-pr-body-template depends on stable markdown anchors.
  local bundled_tasks_list=""
  bundled_tasks_list="$(printf '%s' "$AGG_BUNDLED_TASKS" \
    | python3 -c '
import sys
raw = sys.stdin.read().strip()
items = [t.strip() for t in raw.split(",") if t.strip()]
print("[" + ", ".join(items) + "]")
')"

  local block
  block="$(cat <<EOF

## Bundle Identity

bundle_branch_alias: ${branch_alias}
bundled_tasks: ${bundled_tasks_list}
source: ${AGG_SOURCE}
version: ${AGG_VERSION}
EOF
)"

  # Replace an empty "(reserved for bundle metadata)" placeholder if present,
  # otherwise append. Either way the body now carries the deterministic
  # key-value lines `bundle_branch_alias:` / `bundled_tasks:`.
  local merged_body=""
  if printf '%s' "$body_text" | grep -q "^## Bundle Identity"; then
    local body_tmp
    body_tmp="$(mktemp -t polaris-pr-create-body.XXXXXX)"
    printf '%s' "$body_text" > "$body_tmp"
    merged_body="$(python3 -c '
import re
import sys

body_path, source, version, tasks_list, branch_alias = sys.argv[1:6]
with open(body_path, "r", encoding="utf-8") as fh:
    body = fh.read()
block = (
    "## Bundle Identity\n\n"
    f"bundle_branch_alias: {branch_alias}\n"
    f"bundled_tasks: {tasks_list}\n"
    f"source: {source}\n"
    f"version: {version}\n"
)
pattern = re.compile(r"## Bundle Identity\n(.*?)(?=\n## |\Z)", re.DOTALL)
new_body = pattern.sub(block, body, count=1)
sys.stdout.write(new_body)
' "$body_tmp" "$AGG_SOURCE" "$AGG_VERSION" "$bundled_tasks_list" "$branch_alias")"
    rm -f "$body_tmp"
  else
    merged_body="${body_text}${block}"$'\n'
  fi

  local injected_file
  injected_file="$(mktemp -t polaris-pr-create-bundle.XXXXXX)"
  printf '%s' "$merged_body" > "$injected_file"

  # Rewrite GH_ARGS: drop any --body / --body-file (with or without `=`), then
  # append --body-file <injected_file>. This is the only deterministic carrier
  # that survives gh's own arg validation.
  local new_args=()
  local i=0
  while [[ $i -lt ${#GH_ARGS[@]} ]]; do
    case "${GH_ARGS[$i]}" in
      --body|--body-file)
        i=$((i + 2))
        ;;
      --body=*|--body-file=*)
        i=$((i + 1))
        ;;
      *)
        new_args+=("${GH_ARGS[$i]}")
        i=$((i + 1))
        ;;
    esac
  done
  new_args+=("--body-file" "$injected_file")
  GH_ARGS=("${new_args[@]}")
  PR_BODY=""
  PR_BODY_FILE="$injected_file"
  PR_BODY_SOURCE="file"
}

if [[ "$AGGREGATE_RELEASE" -eq 1 ]]; then
  inject_bundle_identity_block
fi

read_pr_assignee_policy() {
  local repo_root="$1"
  python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import sys

start = Path(sys.argv[1]).resolve()
for root in [start, *start.parents]:
    cfg = root / "workspace-config.yaml"
    if not cfg.exists():
        continue
    text = cfg.read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r"\s*pr_assignee_policy\s*:\s*([^#]+)", line)
        if m:
            print(m.group(1).strip().strip('"').strip("'"))
            raise SystemExit(0)
print("required")
PY
}

resolve_pr_assignee() {
  local repo_root="$1"
  local config_user=""

  config_user="$(python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import sys

start = Path(sys.argv[1]).resolve()
for root in [start, *start.parents]:
    cfg = root / "workspace-config.yaml"
    if not cfg.exists():
        continue
    in_user = False
    for line in cfg.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if re.match(r"^[A-Za-z0-9_-]+:", line):
            in_user = stripped.startswith("user:")
            continue
        if in_user:
            m = re.match(r"\s*github_username\s*:\s*([^#]+)", line)
            if m:
                print(m.group(1).strip().strip('"').strip("'"))
                raise SystemExit(0)
PY
)"

  if [[ -n "$config_user" ]]; then
    printf '%s\n' "$config_user"
    return 0
  fi

  if declare -F polaris_github_current_login >/dev/null 2>&1; then
    polaris_github_current_login
  fi
}

parse_github_pr_url() {
  local pr_url="$1"

  python3 - "$pr_url" <<'PY'
import re
import sys

value = sys.argv[1].strip()
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", value)
if not match:
    raise SystemExit(1)

owner, repo, number = match.groups()
print(f"{owner}/{repo}\t{number}")
PY
}

verify_final_pr_assignee() {
  local pr_ref="$1"
  local policy="$2"
  local parsed=""
  local gh_repo=""
  local pr_number=""
  local gate="$GATES_DIR/gate-pr-assignee.sh"

  if [[ "$policy" == "off" || "$policy" == "optional" ]]; then
    return 0
  fi
  if [[ -z "$pr_ref" ]]; then
    echo "$PREFIX ✗ BLOCKED: PR was created but its URL could not be parsed; cannot verify required assignee metadata." >&2
    exit 2
  fi
  if ! parsed="$(parse_github_pr_url "$pr_ref")"; then
    echo "$PREFIX ✗ BLOCKED: PR URL is not a GitHub PR URL; cannot verify required assignee metadata: $pr_ref" >&2
    exit 2
  fi
  if [[ ! -x "$gate" ]]; then
    echo "$PREFIX ✗ BLOCKED: assignee verification gate is missing or not executable: $gate" >&2
    exit 2
  fi

  gh_repo="${parsed%%$'\t'*}"
  pr_number="${parsed##*$'\t'}"
  bash "$gate" --repo "$REPO_PATH" --gh-repo "$gh_repo" --pr-number "$pr_number"
}

auto_assign_pr() {
  local pr_ref="$1"
  local policy="$2"
  local assignee="$3"

  case "$policy" in
    off)
      echo "$PREFIX PR assignee policy=off — skipping auto-assign."
      return 0
      ;;
    optional|required|"")
      ;;
    *)
      echo "$PREFIX invalid pr_assignee_policy '$policy'; treating as required."
      policy="required"
      ;;
  esac

  if [[ -z "$assignee" ]]; then
    if [[ "$policy" == "optional" ]]; then
      echo "$PREFIX WARN: cannot resolve PR assignee; continuing because policy=optional."
      return 0
    fi
    echo "$PREFIX ✗ BLOCKED: cannot resolve PR assignee from workspace-config.yaml user.github_username or gh auth."
    return 2
  fi

  if [[ -n "$pr_ref" ]]; then
    local parsed=""
    local gh_repo=""
    local pr_number=""
    if declare -F polaris_github_pr_add_assignee_rest >/dev/null 2>&1 && parsed="$(parse_github_pr_url "$pr_ref")"; then
      gh_repo="${parsed%%$'\t'*}"
      pr_number="${parsed##*$'\t'}"
      polaris_github_pr_add_assignee_rest "$gh_repo" "$pr_number" "$assignee"
    elif declare -F polaris_github_pr_add_assignee_cli_fallback >/dev/null 2>&1; then
      polaris_github_pr_add_assignee_cli_fallback "$pr_ref" "$assignee"
    else
      echo "$PREFIX ✗ BLOCKED: GitHub assignee helper is unavailable." >&2
      return 2
    fi
  else
    if declare -F polaris_github_pr_add_assignee_cli_fallback >/dev/null 2>&1; then
      polaris_github_pr_add_assignee_cli_fallback "" "$assignee"
    else
      echo "$PREFIX ✗ BLOCKED: GitHub assignee helper is unavailable." >&2
      return 2
    fi
  fi
  echo "$PREFIX ✓ PR assigned to $assignee"
}

create_pr_and_assign() {
  local output_file=""
  local pr_ref=""
  local policy=""
  local assignee=""
  local rc=0

  policy="$(read_pr_assignee_policy "$REPO_PATH")"
  assignee="$(resolve_pr_assignee "$REPO_PATH")"
  if [[ "$policy" != "off" && "$policy" != "optional" && -z "$assignee" ]]; then
    echo "$PREFIX ✗ BLOCKED: cannot resolve required PR assignee before creation."
    exit 2
  fi

  output_file="$(mktemp -t polaris-pr-create.XXXXXX)"
  set +e
  if declare -F polaris_github_pr_create_cli >/dev/null 2>&1; then
    polaris_github_pr_create_cli "$output_file" "${GH_ARGS[@]+"${GH_ARGS[@]}"}"
    rc=$?
  else
    echo "$PREFIX ✗ BLOCKED: GitHub PR create helper is unavailable." >&2
    rc=2
  fi
  set -e
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$output_file"
    exit "$rc"
  fi

  pr_ref="$(grep -Eo 'https://github\.com/[^[:space:]]+/pull/[0-9]+' "$output_file" | head -n 1 || true)"
  rm -f "$output_file"
  CREATED_PR_URL="$pr_ref"
  write_pr_create_evidence
  auto_assign_pr "$pr_ref" "$policy" "$assignee"
  verify_final_pr_assignee "$pr_ref" "$policy"
  if declare -F polaris_pr_review_label_add >/dev/null 2>&1; then
    polaris_pr_review_label_add "$REPO_PATH" "$pr_ref" "$PREFIX"
  fi
}

resolve_pr_create_evidence_repo() {
  local repo="$1"
  local common_git_dir=""
  if common_git_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
    if [[ "$(basename "$common_git_dir")" == ".git" ]]; then
      dirname "$common_git_dir"
      return
    fi
  fi
  printf '%s\n' "$repo"
}

write_pr_create_evidence() {
  local task_md=""
  local ticket=""
  local head_sha=""
  local evidence_repo=""
  local evidence_dir=""
  local evidence_path=""
  local parsed=""
  local gh_repo=""
  local pr_number=""
  local attempt=1

  task_md="$(resolve_task_md_for_writeback)"
  if [[ -z "$task_md" || ! -f "$task_md" ]]; then
    return 0
  fi
  if [[ -z "$CREATED_PR_URL" ]]; then
    echo "$PREFIX ✗ BLOCKED: PR was created but its URL could not be parsed; cannot write PR create evidence." >&2
    exit 2
  fi
  if ! parsed="$(parse_github_pr_url "$CREATED_PR_URL")"; then
    echo "$PREFIX ✗ BLOCKED: PR URL is not a GitHub PR URL; cannot write PR create evidence: $CREATED_PR_URL" >&2
    exit 2
  fi

  ticket="$(task_delivery_ticket "$task_md")" || {
    echo "$PREFIX ✗ BLOCKED: cannot resolve task identity for PR create evidence: $task_md" >&2
    exit 2
  }
  head_sha="$(git -C "$REPO_PATH" rev-parse HEAD)"
  evidence_repo="$(resolve_pr_create_evidence_repo "$REPO_PATH")"
  evidence_dir="${POLARIS_PR_CREATE_EVIDENCE_DIR:-$evidence_repo/.polaris/evidence/pr-create}"
  evidence_path="$evidence_dir/${ticket}-${head_sha}.json"
  gh_repo="${parsed%%$'\t'*}"
  pr_number="${parsed##*$'\t'}"

  while [[ "$attempt" -le 3 ]]; do
    if python3 - "$evidence_path" "$task_md" "$ticket" "$head_sha" "$CREATED_PR_URL" "$gh_repo" "$pr_number" "$BASE_BRANCH" "$PR_TITLE" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(
    evidence_path,
    task_md,
    task_id,
    head_sha,
    pr_url,
    gh_repo,
    pr_number,
    base_branch,
    pr_title,
) = sys.argv[1:10]

task_path = Path(task_md)
task_text = task_path.read_bytes()
payload = {
    "schema_version": 1,
    "writer": "polaris-pr-create.sh",
    "written_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "task_id": task_id,
    "task_md": str(task_path),
    "task_artifact_sha256": hashlib.sha256(task_text).hexdigest(),
    "head_sha": head_sha,
    "pr_url": pr_url,
    "github_repo": gh_repo,
    "pr_number": int(pr_number),
    "base_branch": base_branch,
    "title": pr_title,
    "gate_summary": {
        "work_source": "passed",
        "base_check": "passed" if base_branch else "not_applicable",
        "evidence": "passed",
        "ci_local": "passed_or_skipped",
        "body_template": "passed_or_not_applicable",
        "language": "passed_or_not_applicable",
    },
}

path = Path(evidence_path)
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_name(path.name + ".tmp")
tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
tmp.replace(path)
PY
    then
      echo "$PREFIX ✓ PR create evidence written: $evidence_path"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 0.1
  done

  echo "$PREFIX ✗ BLOCKED: failed to write PR create evidence after 3 attempts: $evidence_path" >&2
  exit 2
}

resolve_task_md_for_writeback() {
  local resolver="$SCRIPT_DIR/resolve-task-md.sh"
  local workspace_root=""
  local resolved=""
  local probe=""

  if [[ -n "$TASK_MD_PATH" && -f "$TASK_MD_PATH" ]]; then
    printf '%s\n' "$TASK_MD_PATH"
    return 0
  fi

  if [[ -x "$resolver" ]]; then
    resolved="$(cd "$REPO_PATH" && bash "$resolver" --scan-root "$REPO_PATH" --current 2>/dev/null | head -n 1 || true)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
    if declare -F resolve_specs_workspace_root >/dev/null 2>&1; then
      workspace_root="$(resolve_specs_workspace_root "$REPO_PATH" 2>/dev/null || true)"
      if [[ -n "$workspace_root" && "$workspace_root" != "$REPO_PATH" ]]; then
        resolved="$(cd "$REPO_PATH" && bash "$resolver" --scan-root "$workspace_root" --current 2>/dev/null | head -n 1 || true)"
        if [[ -n "$resolved" ]]; then
          printf '%s\n' "$resolved"
          return 0
        fi
      fi
    fi
    probe="$(cd "$REPO_PATH" && pwd)"
    while [[ "$probe" != "/" && -n "$probe" ]]; do
      if [[ -d "$probe/docs-manager/src/content/docs/specs" ]]; then
        resolved="$(cd "$REPO_PATH" && bash "$resolver" --scan-root "$probe" --current 2>/dev/null | head -n 1 || true)"
        if [[ -n "$resolved" ]]; then
          printf '%s\n' "$resolved"
          return 0
        fi
      fi
      probe="$(dirname "$probe")"
    done
  fi
}

task_delivery_ticket() {
  local task_md="$1"
  local parser="$SCRIPT_DIR/parse-task-md.sh"
  local ticket=""

  [[ -x "$parser" ]] || return 1
  # delivery_ticket_key is the canonical product-PR-identity atom (DP-238): Bug
  # source = real JIRA key, DP source = work_item_id. Do not read the legacy
  # task_jira_key alias, which holds the internal work_item_id for Bug sources
  # and would key PR-create evidence / deliverable on the leaked marker (AC-NEG5).
  ticket="$(bash "$parser" "$task_md" --no-resolve --field delivery_ticket_key 2>/dev/null || true)"
  case "$ticket" in
    ""|N/A|null)
      ticket="$(bash "$parser" "$task_md" --no-resolve --field task_id 2>/dev/null || true)"
      ;;
  esac
  [[ -n "$ticket" && "$ticket" != "N/A" && "$ticket" != "null" ]] || return 1
  printf '%s\n' "$ticket"
}

write_delivery_artifacts() {
  local task_md=""
  local head_sha=""
  local ticket=""
  local writer="$SCRIPT_DIR/write-deliverable.sh"
  local report_writer="$SCRIPT_DIR/write-task-verify-report.sh"

  task_md="$(resolve_task_md_for_writeback)"
  if [[ -z "$task_md" || ! -f "$task_md" ]]; then
    return 0
  fi

  if [[ -z "$CREATED_PR_URL" ]]; then
    echo "$PREFIX ✗ BLOCKED: PR was created but its URL could not be parsed; cannot write deliverable metadata." >&2
    exit 2
  fi
  if [[ ! -x "$writer" || ! -x "$report_writer" ]]; then
    echo "$PREFIX ✗ BLOCKED: delivery artifact writers are not executable." >&2
    exit 2
  fi

  head_sha="$(git -C "$REPO_PATH" rev-parse HEAD)"
  ticket="$(task_delivery_ticket "$task_md")" || {
    echo "$PREFIX ✗ BLOCKED: cannot resolve task identity for delivery artifact writeback: $task_md" >&2
    exit 2
  }

  bash "$writer" "$task_md" "$CREATED_PR_URL" OPEN "$head_sha"
  bash "$report_writer" --repo "$REPO_PATH" --ticket "$ticket" --task-md "$task_md" --head-sha "$head_sha" --status PASS >/dev/null
  echo "$PREFIX ✓ delivery metadata and verify report written for $ticket@$head_sha"
}

# --- Detect forbidden PR modes ---
if (( ${#GH_ARGS[@]} > 0 )); then
  for arg in "${GH_ARGS[@]}"; do
    if [[ "$arg" == "--draft" ]]; then
      echo "$PREFIX ✗ BLOCKED: draft PR creation is blocked in Polaris delivery flows."
      echo "$PREFIX Create a normal PR backed by a legal work source; document blockers in the PR body if needed."
      exit 2
    fi
  done
fi

# --- Detect non-ticket branch (skip legacy evidence gate only after source gate) ---
CURRENT_BRANCH="$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
IS_TICKET_BRANCH=1
[[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" =~ ^(main|master|develop|release/) ]] && IS_TICKET_BRANCH=0

# --- Gate runner ---
run_gate() {
  local name="$1"; shift
  local script="$GATES_DIR/$name"

  if [[ ! -x "$script" ]]; then
    echo "$PREFIX ⊘ $name not found, skipping"
    return 0
  fi

  if "$script" "$@"; then
    echo "$PREFIX ✓ ${name%.sh} passed"
  else
    local rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "$PREFIX ✗ ${name%.sh} FAILED (exit 2)"
      echo "$PREFIX PR creation aborted. Fix the issue above and retry."
      exit 2
    else
      echo "$PREFIX ⚠ ${name%.sh} warning (exit $rc), continuing"
    fi
  fi
}

# --- Mandatory source gate ---
SOURCE_GATE_ARGS=(--repo "$REPO_PATH")
if [[ -n "$TASK_MD_PATH" ]]; then
  SOURCE_GATE_ARGS+=(--task-md "$TASK_MD_PATH")
fi
run_gate gate-work-source.sh "${SOURCE_GATE_ARGS[@]}"

# --- Skip non-source gates ---
if [[ "$SKIP_GATES" == "1" ]]; then
  echo "$PREFIX ⚠ --skip-gates: non-source gates bypassed; source gate already passed"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "$PREFIX DRY_RUN: PR creation skipped"
    exit 0
  fi
  create_pr_and_assign
  write_delivery_artifacts
  exit 0
fi

# --- Run gates ---
echo "$PREFIX Running pre-flight gates..."

# Gate 1: base-check (only if --base provided)
if [[ -n "$BASE_BRANCH" ]]; then
  BASE_GATE_ARGS=(--repo "$REPO_PATH" --base "$BASE_BRANCH")
  if [[ "$AGGREGATE_RELEASE" == "1" ]]; then
    BASE_GATE_ARGS+=(--aggregate-release)
  fi
  run_gate gate-base-check.sh "${BASE_GATE_ARGS[@]}"
fi

# Gate 2: evidence (Layer B plus conditional Layer C VR; skip for non-ticket branches)
if [[ "$IS_TICKET_BRANCH" -eq 1 ]]; then
  EVIDENCE_GATE_ARGS=(--repo "$REPO_PATH")
  if [[ -n "$TASK_MD_PATH" ]]; then
    EVIDENCE_GATE_ARGS+=(--task-md "$TASK_MD_PATH")
  fi
  run_gate gate-evidence.sh "${EVIDENCE_GATE_ARGS[@]}"
fi

# Gate 3: ci-local (always)
run_gate gate-ci-local.sh --repo "$REPO_PATH"

# Gate 4: local-only docs-manager specs must not be tracked.
run_gate gate-no-tracked-specs.sh --repo "$REPO_PATH"

# Gate 5: Developer PR title (managed task branches only)
if [[ "$IS_TICKET_BRANCH" -eq 1 && -n "$PR_TITLE" ]]; then
  run_gate gate-pr-title.sh --repo "$REPO_PATH" --title "$PR_TITLE"
fi

# Gate 6: PR body preserves repo pull request template headings.
if [[ "$PR_BODY_SOURCE" == "file" ]]; then
  run_gate gate-pr-body-template.sh --repo "$REPO_PATH" --body-file "$PR_BODY_FILE"
elif [[ "$PR_BODY_SOURCE" == "body" ]]; then
  run_gate gate-pr-body-template.sh --repo "$REPO_PATH" --body "$PR_BODY"
fi

# Gate 7: PR title/body language policy via gate-pr-language.sh
# (central wrapper around validate-language-policy.sh).
if [[ -n "$PR_TITLE" || "$PR_BODY_SOURCE" == "file" || "$PR_BODY_SOURCE" == "body" ]]; then
  if [[ "$PR_BODY_SOURCE" == "file" ]]; then
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE" --body-file "$PR_BODY_FILE"
  elif [[ "$PR_BODY_SOURCE" == "body" ]]; then
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE" --body "$PR_BODY"
  else
    run_gate gate-pr-language.sh --repo "$REPO_PATH" --title "$PR_TITLE"
  fi
fi

# Gate 8: task changeset (managed task branches in changeset repos)
if [[ "$IS_TICKET_BRANCH" -eq 1 ]]; then
  run_gate gate-changeset.sh --repo "$REPO_PATH"
fi

echo "$PREFIX All gates passed — creating PR..."
if [[ "$DRY_RUN" == "1" ]]; then
  echo "$PREFIX DRY_RUN: PR creation skipped"
  exit 0
fi
create_pr_and_assign
write_delivery_artifacts
