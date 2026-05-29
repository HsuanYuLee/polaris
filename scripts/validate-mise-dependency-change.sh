#!/usr/bin/env bash
# validate-mise-dependency-change.sh — D16 / AC11 mise dependency gate.
#
# Purpose: enforce that any `mise.toml` diff comes with a `DP-NNN` reference
# in the PR body. Framework workspace toolchain changes are governed by an
# owning DP (refinement / breakdown / engineering) — silent additions are
# not allowed.
#
# Modes:
#   --diff <ref>          Compare working tree (or staged index) against <ref>.
#                         Default base is HEAD when not provided.
#   --pr-body <path>      Path to a file containing the PR body to scan.
#   --pr-body-stdin       Read PR body from stdin (alternative to --pr-body).
#
# Behavior:
#   - If `mise.toml` is unchanged between base and HEAD → exit 0 (skip).
#   - If `mise.toml` is changed AND the PR body contains a `DP-NNN` token
#     matching regex `\bDP-[0-9]+\b` → exit 0 (PASS).
#   - If `mise.toml` is changed AND the PR body does NOT contain a valid
#     `DP-NNN` token → exit 2 + stderr `POLARIS_MISE_DEPENDENCY_DP_MISSING:{path}`.
#
# Exit codes:
#   0 — PASS or skip
#   2 — contract violation (mise.toml changed without DP reference) OR
#       usage error.
#
# Selftest: scripts/selftests/validate-mise-dependency-change-selftest.sh
#
# Examples:
#   bash scripts/validate-mise-dependency-change.sh --diff origin/main --pr-body /tmp/pr-body.md
#   gh pr view 123 --json body --jq .body \
#     | bash scripts/validate-mise-dependency-change.sh --diff origin/main --pr-body-stdin

set -euo pipefail

BASE_REF="HEAD"
PR_BODY_FILE=""
PR_BODY_FROM_STDIN=0
ROOT_DIR=""
MISE_PATH="mise.toml"
DIFF_FILES_OVERRIDE=""

usage() {
  cat >&2 <<'EOF'
usage: validate-mise-dependency-change.sh [--diff <ref>]
                                          [--pr-body <path> | --pr-body-stdin]
                                          [--root <dir>]
                                          [--mise-path <path>]
                                          [--diff-files-override <list>]

  --diff <ref>              Base ref for `git diff --name-only` comparison.
                            Default: HEAD.
  --pr-body <path>          Path to PR body file (will be scanned for DP-NNN).
  --pr-body-stdin           Read PR body from stdin.
  --root <dir>              Repository root (default: cwd).
  --mise-path <path>        Path to the mise manifest relative to --root.
                            Default: mise.toml.
  --diff-files-override <list>
                            Newline-separated explicit file list (selftest hook).
                            Skips `git diff` entirely.

Exit codes:
  0 — PASS or skip (no mise.toml change)
  2 — contract violation OR usage error
EOF
}

while (($#)); do
  case "$1" in
    --diff)
      BASE_REF="${2:?--diff requires a ref}"
      shift 2
      ;;
    --pr-body)
      PR_BODY_FILE="${2:?--pr-body requires a path}"
      shift 2
      ;;
    --pr-body-stdin)
      PR_BODY_FROM_STDIN=1
      shift
      ;;
    --root)
      ROOT_DIR="${2:?--root requires a dir}"
      shift 2
      ;;
    --mise-path)
      MISE_PATH="${2:?--mise-path requires a path}"
      shift 2
      ;;
    --diff-files-override)
      DIFF_FILES_OVERRIDE="${2:?--diff-files-override requires a list}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -n "$ROOT_DIR" ]]; then
  cd "$ROOT_DIR"
fi

if [[ -n "$DIFF_FILES_OVERRIDE" ]]; then
  diff_files="$DIFF_FILES_OVERRIDE"
else
  if ! diff_files="$(git diff --name-only "$BASE_REF" -- . 2>/dev/null)"; then
    echo "POLARIS_MISE_DEPENDENCY_GATE_USAGE: cannot diff against $BASE_REF" >&2
    exit 2
  fi
fi

# Skip when mise manifest is not in the change set.
if ! printf '%s\n' "$diff_files" | grep -Fxq "$MISE_PATH"; then
  echo "PASS: mise.toml unchanged; skip"
  exit 0
fi

# mise.toml changed — require PR body with DP-NNN reference.
body=""
if [[ "$PR_BODY_FROM_STDIN" -eq 1 ]]; then
  body="$(cat)"
elif [[ -n "$PR_BODY_FILE" ]]; then
  if [[ ! -f "$PR_BODY_FILE" ]]; then
    echo "POLARIS_MISE_DEPENDENCY_GATE_USAGE: PR body file missing: $PR_BODY_FILE" >&2
    exit 2
  fi
  body="$(cat "$PR_BODY_FILE")"
else
  echo "POLARIS_MISE_DEPENDENCY_DP_MISSING:$MISE_PATH" >&2
  echo "mise.toml changed but no --pr-body / --pr-body-stdin provided" >&2
  exit 2
fi

if printf '%s' "$body" | grep -Eq '\bDP-[0-9]+\b'; then
  echo "PASS: mise.toml change references an owning DP"
  exit 0
fi

echo "POLARIS_MISE_DEPENDENCY_DP_MISSING:$MISE_PATH" >&2
echo "mise.toml changed but PR body does not reference any DP-NNN" >&2
exit 2
