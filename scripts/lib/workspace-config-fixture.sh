#!/usr/bin/env bash
# scripts/lib/workspace-config-fixture.sh — selftest fixture helper that
# stages a minimal workspace-config.yaml inside a tmpdir, so selftests can
# run under POLARIS_WORKSPACE_ROOT=$tmp without depending on the live
# (gitignored) workspace-config.yaml at the repo root.
#
# Background (DP-230 D36 / AC36): selftests that exercise language policy
# wrappers (e.g. validate-spec-primary-doc-authoring-selftest.sh,
# validate-dp-plan-authoring-selftest.sh) previously failed with
# `language_unset` whenever the executing checkout did not already have a
# live workspace-config.yaml — for example fresh git clones, clean
# worktrees, or CI containers. Staging a minimal fixture lets the language
# policy resolver find `language: zh-TW` deterministically.
#
# Source (not execute) this file from selftests:
#
#   . "$ROOT_DIR/scripts/lib/workspace-config-fixture.sh"
#   tmpdir="$(mktemp -d)"
#   stage_minimal_workspace_config "$tmpdir"
#   POLARIS_WORKSPACE_ROOT="$tmpdir" bash other-selftest.sh
#
# The helper writes only two top-level fields by design:
#   language: zh-TW
#   user:
#     github_username: polaris-selftest
#
# Anything beyond those two fields belongs in caller-specific fixtures —
# this helper is the minimal baseline that satisfies the language policy
# resolver without leaking generic placeholders into other contracts.
#
# Live workspace-config isolation: callers MUST pass an explicit tmpdir
# path. The helper refuses to write to the workspace root, to any path
# already containing a workspace-config.yaml directly inside it (other
# than tmp-rooted ones), or outside a system tmp prefix; this prevents
# accidental overwrite of the maintainer's live ignored config.

set -u

# Public: stage_minimal_workspace_config <tmpdir>
#
# Writes <tmpdir>/workspace-config.yaml with the minimal two-field shape.
# Returns:
#   0 on success
#   2 on misuse (missing arg, not a directory, refuses live root)
#
# The function is idempotent: re-running on the same tmpdir overwrites
# the file with the same canonical content.
stage_minimal_workspace_config() {
  local tmpdir="${1:-}"

  if [[ -z "$tmpdir" ]]; then
    printf 'stage_minimal_workspace_config: missing tmpdir argument\n' >&2
    return 2
  fi

  if [[ ! -d "$tmpdir" ]]; then
    printf 'stage_minimal_workspace_config: not a directory: %s\n' "$tmpdir" >&2
    return 2
  fi

  # Refuse to clobber a real live workspace-config.yaml. The only safe
  # write target is a tmp-rooted directory; macOS uses /var/folders, Linux
  # uses /tmp. Anything outside those prefixes is rejected to keep this
  # helper from being misused to overwrite the maintainer checkout.
  local resolved
  resolved="$(cd "$tmpdir" 2>/dev/null && pwd -P)" || {
    printf 'stage_minimal_workspace_config: cannot resolve: %s\n' "$tmpdir" >&2
    return 2
  }

  case "$resolved" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
      :
      ;;
    *)
      printf 'stage_minimal_workspace_config: refuses non-tmp target: %s\n' "$resolved" >&2
      printf '  (only /tmp, /var/folders, or /private/tmp prefixes allowed)\n' >&2
      return 2
      ;;
  esac

  cat >"$resolved/workspace-config.yaml" <<'YAML'
# Minimal workspace-config.yaml staged by stage_minimal_workspace_config
# for selftests that need language policy resolution without depending on
# the live ignored workspace-config.yaml at the repo root.
language: "zh-TW"
user:
  github_username: "polaris-selftest"
YAML

  return 0
}
