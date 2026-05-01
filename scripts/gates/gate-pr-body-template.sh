#!/usr/bin/env bash
set -euo pipefail

# gate-pr-body-template.sh — PR body template conformance gate.
# Blocks PR creation when a repo has a pull request template but the supplied
# PR body does not preserve the template's level-2 section headings.
#
# Usage:
#   bash scripts/gates/gate-pr-body-template.sh [--repo <path>] (--body <body> | --body-file <path> | --pr <number-or-url>)
#
# Exit: 0 = pass/skip, 2 = block
# Bypass: POLARIS_SKIP_PR_BODY_TEMPLATE_GATE=1

PREFIX="[polaris gate-pr-body-template]"

REPO_ROOT=""
BODY=""
BODY_FILE=""
PR_REF=""
BODY_PROVIDED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; BODY_PROVIDED=1; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; BODY_PROVIDED=1; shift 2 ;;
    --pr) PR_REF="${2:-}"; BODY_PROVIDED=1; shift 2 ;;
    -h|--help)
      echo "Usage: bash scripts/gates/gate-pr-body-template.sh [--repo <path>] (--body <body> | --body-file <path> | --pr <number-or-url>)"
      exit 0
      ;;
    *) shift ;;
  esac
done

if [[ "${POLARIS_SKIP_PR_BODY_TEMPLATE_GATE:-}" == "1" ]]; then
  echo "$PREFIX POLARIS_SKIP_PR_BODY_TEMPLATE_GATE=1 — bypassing." >&2
  exit 0
fi

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$REPO_ROOT" ]] || exit 0

find_template() {
  local repo="$1"
  local candidate
  for candidate in \
    ".github/pull_request_template.md" \
    ".github/PULL_REQUEST_TEMPLATE.md" \
    ".github/PULL_REQUEST_TEMPLATE/default.md" \
    "docs/pull_request_template.md" \
    "pull_request_template.md"
  do
    if [[ -f "$repo/$candidate" ]]; then
      printf '%s\n' "$repo/$candidate"
      return 0
    fi
  done
}

template_path="$(find_template "$REPO_ROOT" || true)"
if [[ -z "$template_path" ]]; then
  # Repo has no template; pr-body-builder.md falls back to Polaris default, but
  # this gate intentionally only enforces concrete repo templates.
  exit 0
fi

if [[ "$BODY_PROVIDED" -ne 1 ]]; then
  # No explicit body argument. Let gh/GitHub apply its own template behavior.
  exit 0
fi

if [[ -n "$BODY_FILE" ]]; then
  if [[ -f "$BODY_FILE" ]]; then
    BODY="$(<"$BODY_FILE")"
  elif [[ -f "$REPO_ROOT/$BODY_FILE" ]]; then
    BODY="$(<"$REPO_ROOT/$BODY_FILE")"
  else
    echo "$PREFIX BLOCKED: --body-file does not exist: $BODY_FILE" >&2
    exit 2
  fi
fi

parse_pr_ref() {
  local pr_ref="$1"
  local repo_root="$2"

  python3 - "$pr_ref" "$repo_root" <<'PY'
import re
import subprocess
import sys

pr_ref, repo_root = sys.argv[1:3]
match = re.match(r"^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(?:[/?#].*)?$", pr_ref)
if match:
    owner, repo, number = match.groups()
    print(f"{owner}/{repo}\t{number}")
    raise SystemExit(0)

if re.match(r"^[0-9]+$", pr_ref):
    try:
        remote = subprocess.check_output(
            ["git", "-C", repo_root, "config", "--get", "remote.origin.url"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        raise SystemExit(1)
    remote = re.sub(r"^git@github\.com:", "", remote)
    remote = re.sub(r"^https://github\.com/", "", remote)
    remote = re.sub(r"\.git$", "", remote).strip("/")
    if re.match(r"^[^/]+/[^/]+$", remote):
        print(f"{remote}\t{pr_ref}")
        raise SystemExit(0)

raise SystemExit(1)
PY
}

if [[ -n "$PR_REF" ]]; then
  parsed_pr=""
  gh_repo=""
  gh_pr_number=""
  command -v gh >/dev/null 2>&1 || {
    echo "$PREFIX BLOCKED: gh CLI is required for --pr source." >&2
    exit 2
  }
  if ! parsed_pr="$(parse_pr_ref "$PR_REF" "$REPO_ROOT")"; then
    echo "$PREFIX BLOCKED: --pr must be a GitHub PR URL or number resolvable from repo origin: $PR_REF" >&2
    exit 2
  fi
  gh_repo="${parsed_pr%%$'\t'*}"
  gh_pr_number="${parsed_pr##*$'\t'}"
  if ! BODY="$(gh pr view "$gh_pr_number" --repo "$gh_repo" --json body --jq .body)"; then
    echo "$PREFIX BLOCKED: unable to read PR body for $PR_REF" >&2
    exit 2
  fi
fi

if [[ -z "$BODY" ]]; then
  cat >&2 <<EOF
$PREFIX BLOCKED: PR body is empty while repo template exists.
  Repo:     $REPO_ROOT
  Template: $template_path

Fix:
  Build the PR body from the repo template and pass it with --body-file.
EOF
  exit 2
fi

extract_headings_from_file() {
  awk '
    /^##[[:space:]]+/ {
      h=$0
      sub(/^##[[:space:]]+/, "", h)
      sub(/[[:space:]]+#+[[:space:]]*$/, "", h)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
      if (h != "") print h
    }
  ' "$1"
}

extract_headings_from_stdin() {
  awk '
    /^##[[:space:]]+/ {
      h=$0
      sub(/^##[[:space:]]+/, "", h)
      sub(/[[:space:]]+#+[[:space:]]*$/, "", h)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", h)
      if (h != "") print h
    }
  '
}

normalize_heading() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

template_headings=()
while IFS= read -r heading; do
  template_headings+=("$heading")
done < <(extract_headings_from_file "$template_path")

body_headings=()
while IFS= read -r heading; do
  body_headings+=("$heading")
done < <(printf '%s\n' "$BODY" | extract_headings_from_stdin)

if [[ "${#template_headings[@]}" -eq 0 ]]; then
  # A template without h2 headings cannot be mechanically checked.
  exit 0
fi

if [[ "$BODY" == *'\`'* ]]; then
  cat >&2 <<EOF
$PREFIX BLOCKED: PR body contains escaped Markdown backticks (\\\`).
  This usually means inline code was shell-escaped and will render as plain text.

Fix:
  Write the PR body to a temp markdown file and use --body-file.
EOF
  exit 2
fi

template_idx=0
for body_heading in "${body_headings[@]}"; do
  if [[ "$template_idx" -ge "${#template_headings[@]}" ]]; then
    break
  fi

  expected="$(normalize_heading "${template_headings[$template_idx]}")"
  actual="$(normalize_heading "$body_heading")"
  if [[ "$actual" == "$expected" ]]; then
    template_idx=$((template_idx + 1))
  fi
done

if [[ "$template_idx" -eq "${#template_headings[@]}" ]]; then
  echo "$PREFIX ✅ PR body preserves repo template headings." >&2
  exit 0
fi

missing=()
for (( i=template_idx; i<${#template_headings[@]}; i++ )); do
  missing+=("${template_headings[$i]}")
done

{
  echo "$PREFIX BLOCKED: PR body does not preserve repo template headings."
  echo "  Repo:     $REPO_ROOT"
  echo "  Template: $template_path"
  echo
  echo "Expected h2 headings, in order:"
  for heading in "${template_headings[@]}"; do
    echo "  - $heading"
  done
  echo
  echo "Actual h2 headings:"
  if [[ "${#body_headings[@]}" -eq 0 ]]; then
    echo "  (none)"
  else
    for heading in "${body_headings[@]}"; do
      echo "  - $heading"
    done
  fi
  echo
  echo "Missing or out-of-order from first mismatch:"
  for heading in "${missing[@]}"; do
    echo "  - $heading"
  done
  echo
  echo "Fix:"
  echo "  Build the body from the repo PR template and pass it with --body-file."
} >&2

exit 2
