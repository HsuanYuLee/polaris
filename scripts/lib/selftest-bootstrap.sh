#!/usr/bin/env bash
# scripts/lib/selftest-bootstrap.sh — DP-230 T6 selftest portability convention.
#
# Provides init_ROOT_DIR() helper that derives the framework ROOT_DIR from
# BASH_SOURCE instead of `git rev-parse --show-toplevel`. This makes selftests
# portable to fresh git clone scenarios, detached-HEAD release-tag worktrees,
# and submodule contexts where `git rev-parse --show-toplevel` either fails
# or returns a non-framework root.
#
# Usage (from scripts/selftests/<name>-selftest.sh):
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   # shellcheck source=../lib/selftest-bootstrap.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
#   init_ROOT_DIR "${BASH_SOURCE[0]}"
#   # ROOT_DIR is now exported and validated.
#
# Contract:
#   - init_ROOT_DIR derives the candidate root from $1 (caller BASH_SOURCE[0])
#     by walking two directories up (scripts/selftests/* → repo root).
#   - The candidate root MUST contain the sentinel file workspace-config.yaml.example.
#     Missing sentinel → fail-stop + stderr POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING.
#   - No fallback to pwd, $PWD, $CLAUDE_PROJECT_DIR, or `git rev-parse`. The
#     bootstrap fails closed so a misconfigured caller cannot silently resolve
#     to the wrong directory.
#   - Exports ROOT_DIR as both a shell variable and an environment variable so
#     downstream `python3 - "$ROOT_DIR"` heredocs and subprocess invocations
#     inherit it.

set -euo pipefail

# Sentinel file that must exist at the framework workspace root. Kept in sync
# with scripts/lib/workspace-config-root.sh and the workspace contract.
POLARIS_SELFTEST_ROOT_SENTINEL="workspace-config.yaml.example"

init_ROOT_DIR() {
  local caller="${1:-}"
  if [[ -z "$caller" ]]; then
    printf 'POLARIS_SELFTEST_BOOTSTRAP_CALLER_MISSING: init_ROOT_DIR requires the caller BASH_SOURCE[0]\n' >&2
    return 2
  fi

  # Derive candidate root from caller path. Caller lives in scripts/selftests/
  # (or scripts/lib/) — walk two parents up to land on the framework root.
  local caller_dir candidate
  caller_dir="$(cd "$(dirname "$caller")" && pwd)"
  candidate="$(cd "$caller_dir/../.." && pwd)"

  if [[ ! -d "$candidate" ]]; then
    printf 'POLARIS_SELFTEST_BOOTSTRAP_ROOT_NOT_FOUND: derived root does not exist: %s\n' "$candidate" >&2
    return 2
  fi

  if [[ ! -f "$candidate/$POLARIS_SELFTEST_ROOT_SENTINEL" ]]; then
    printf 'POLARIS_SELFTEST_BOOTSTRAP_SENTINEL_MISSING: sentinel %s not found under %s\n' \
      "$POLARIS_SELFTEST_ROOT_SENTINEL" "$candidate" >&2
    return 2
  fi

  ROOT_DIR="$candidate"
  export ROOT_DIR
}
