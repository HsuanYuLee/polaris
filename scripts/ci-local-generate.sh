#!/usr/bin/env bash
# ci-local-generate.sh — Generate workspace-owned ci-local.sh from repo CI declarations.
#
# DP-032 D12 + DP-043. Tool-agnostic: parses .woodpecker/, .github/workflows/,
# .gitlab-ci.yml, .husky/, .pre-commit-config.yaml, and package.json scripts via
# the existing ci-contract-discover.sh, then emits a self-contained per-repo
# mirror script.
#
# DP-079 (2026-05-03): canonical output path is now workspace-owned
# `{company}/polaris-config/{project}/generated-scripts/ci-local.sh`.
# Repo-local `.claude/scripts/ci-local.sh` is legacy compatibility only.
#
# The generated script:
#   - Reads HEAD SHA + branch + CI context, derives /tmp/polaris-ci-local-{branch}-{head_sha}-{context}.json
#   - Cache hit (same head_sha + CI context + status PASS) → exit 0 immediately
#   - Otherwise runs each parsed install/lint/typecheck/test/coverage command in order
#   - Replays local CI/provider commands and skips external upload commands
#   - Writes evidence JSON and exits 0 (PASS) or 1 (FAIL)
#
# Usage:
#   scripts/ci-local-generate.sh --repo <path> [--out <path>] [--force] [--dry-run]
#
#   --repo     target repo root (must be a git checkout)
#   --out      output path (default: workspace-owned polaris-config generated script)
#   --force    overwrite existing output
#   --dry-run  print rendered script to stdout, write nothing

set -euo pipefail

REPO_DIR=""
OUT_PATH=""
FORCE=0
DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Single source of truth for the ci-local.sh workspace-owned path (DP-079).
# shellcheck source=lib/ci-local-path.sh
. "$SCRIPT_DIR/lib/ci-local-path.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --out) OUT_PATH="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '1,/^set -euo pipefail$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^!\/usr/d' -e '/^set -euo/d'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: ci-local-generate.sh --repo <path> [--out <path>] [--force] [--dry-run]" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"
[[ -z "$OUT_PATH" ]] && OUT_PATH="$(ci_local_path_for_repo "$REPO_DIR")"

DISCOVER="$SCRIPT_DIR/ci-contract-discover.sh"
if [[ ! -x "$DISCOVER" ]]; then
  echo "[ci-local-generate] ERROR: ci-contract-discover.sh not found or not executable at $DISCOVER" >&2
  exit 1
fi

CONTRACT_FILE=$(mktemp)
trap 'rm -f "$CONTRACT_FILE"' EXIT
"$DISCOVER" --repo "$REPO_DIR" > "$CONTRACT_FILE"

GENERATOR_HASH="$(shasum -a 256 "$0" | cut -c1-12)"
ENV_CLASSIFIER="$SCRIPT_DIR/ci-local-env-classify.py"

python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ci_ci_local_generate_1.py" "$REPO_DIR" "$OUT_PATH" "$FORCE" "$DRY_RUN" "$CONTRACT_FILE" "$GENERATOR_HASH" "$ENV_CLASSIFIER"
