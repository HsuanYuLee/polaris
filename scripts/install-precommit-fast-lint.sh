#!/usr/bin/env bash
# Purpose: inject (or update) a fast-lint slot into a git pre-commit hook so that
#          a commit running staged source files is gated by the cheap, narrow
#          "fast-lint" subset of the Polaris selftest tier manifest (DP-360 T2,
#          AC1 pre-commit segment). The slot is fail-closed: a staged violation,
#          a missing manifest cache, or a missing required tool blocks the commit
#          (no fail-open skip). Re-running is idempotent — the slot is delimited
#          by recognizable BEGIN/END markers and replaced in place, never appended
#          twice.
# Inputs:  $1 (optional) = target pre-commit hook path. Default:
#          "$REPO_ROOT/.git/hooks/pre-commit" where REPO_ROOT is the git toplevel
#          containing this script. During development / selftest you MUST pass a
#          fixture / temp hook path so the live hook is never mutated.
#          --remove  : strip the Polaris fast-lint slot from the target hook.
#          --status  : report whether the slot is present in the target hook.
# Outputs: writes / updates the target hook file (or removes the slot); prints a
#          one-line status to stdout. Exit 0 on success, exit 2 on contract /
#          argument error (fail-closed; POLARIS_* markers on stderr).
set -euo pipefail

# --- Named constants ---------------------------------------------------------
# Slot delimiters. The injected fast-lint block is bounded by these exact marker
# lines so the installer can locate, replace, or remove its own block without
# disturbing any other hook content (idempotency contract).
readonly SLOT_BEGIN_MARKER="# >>> polaris-fast-lint-slot (DP-360) >>>"
readonly SLOT_END_MARKER="# <<< polaris-fast-lint-slot (DP-360) <<<"
# Subset name emitted by the tier manifest that the commit hot path runs. The
# fast-lint subset is the cheapest (fast + narrow) selftest set per T1 (AC6).
readonly FAST_LINT_SUBSET="fast-lint"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTION="install"
TARGET_HOOK=""

die() {
  printf '%s\n' "$1" >&2
  exit 2
}

# --- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove)
      ACTION="remove"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    -h | --help)
      printf 'Usage: bash scripts/install-precommit-fast-lint.sh [<hook-path>] [--remove|--status]\n'
      exit 0
      ;;
    --*)
      die "POLARIS_FAST_LINT_INSTALL_ARG: unknown option: $1"
      ;;
    *)
      [[ -z "$TARGET_HOOK" ]] || die "POLARIS_FAST_LINT_INSTALL_ARG: multiple hook paths given"
      TARGET_HOOK="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_HOOK" ]]; then
  # Default to the live hook only when no explicit target is given. Callers that
  # exercise this installer (selftest, dev) MUST pass a fixture path.
  if ! git_toplevel="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
    die "POLARIS_FAST_LINT_INSTALL_NO_REPO: cannot resolve git toplevel from $ROOT_DIR; pass an explicit hook path"
  fi
  TARGET_HOOK="$git_toplevel/.git/hooks/pre-commit"
fi

# render_slot — print the fast-lint slot block (BEGIN..END inclusive) to stdout.
# The block is self-contained bash that runs inside the host pre-commit hook:
# it gates the commit on the fast-lint selftest subset whenever staged source
# files exist, and fails closed on missing manifest / missing tool / red subset.
# Side effects: none (pure stdout).
render_slot() {
  cat <<SLOT
$SLOT_BEGIN_MARKER
# Auto-injected by scripts/install-precommit-fast-lint.sh (DP-360 T2).
# Runs the cheap fast-lint selftest subset for staged commits. Fail-closed:
# a staged violation, a missing tier manifest cache, or a missing tool blocks
# the commit (never a fail-open skip). Do not hand-edit between the markers.
polaris_fast_lint_slot() {
  local repo_root manifest_script staged subset_out rc selftest
  repo_root="\$(git rev-parse --show-toplevel)"
  manifest_script="\$repo_root/scripts/selftest-tier-manifest.sh"

  # Nothing staged for commit -> nothing to lint -> clean pass.
  staged="\$(git diff --cached --name-only)"
  if [[ -z "\$staged" ]]; then
    return 0
  fi

  # The fast-lint subset producer must exist; absence is a contract failure,
  # not a reason to skip (fail-closed).
  if [[ ! -f "\$manifest_script" ]]; then
    printf 'POLARIS_FAST_LINT_MANIFEST_SCRIPT_MISSING:%s\n' "\$manifest_script" >&2
    return 2
  fi

  # bash is the slot interpreter (already running); require the tools the slot
  # invokes. git is assumed present (we are inside a git hook).
  if ! command -v bash >/dev/null 2>&1; then
    printf 'POLARIS_TOOL_MISSING:%s — run \`mise install\` to restore the Polaris runtime toolchain\n' bash >&2
    return 2
  fi

  # Resolve the fast-lint subset from the tier manifest. The emit step fails
  # closed (exit 2) when the manifest cache is missing/malformed; propagate
  # that as a blocked commit with the underlying POLARIS_* marker on stderr.
  if ! subset_out="\$(bash "\$manifest_script" --emit $FAST_LINT_SUBSET 2>&1)"; then
    printf '%s\n' "\$subset_out" >&2
    printf 'POLARIS_FAST_LINT_SUBSET_UNAVAILABLE: cannot resolve %s subset (run \`bash scripts/selftest-tier-manifest.sh --measure\` first)\n' "$FAST_LINT_SUBSET" >&2
    return 2
  fi

  # Run every fast-lint selftest. A red selftest fails the commit closed.
  rc=0
  while IFS= read -r selftest; do
    [[ -n "\$selftest" ]] || continue
    if [[ ! -f "\$repo_root/\$selftest" ]]; then
      printf 'POLARIS_FAST_LINT_SELFTEST_MISSING:%s\n' "\$selftest" >&2
      rc=2
      continue
    fi
    if ! bash "\$repo_root/\$selftest" >/dev/null 2>&1; then
      printf 'POLARIS_FAST_LINT_VIOLATION:%s\n' "\$selftest" >&2
      rc=1
    fi
  done <<<"\$subset_out"

  return "\$rc"
}
if ! polaris_fast_lint_slot; then
  echo "[polaris pre-commit] fast-lint slot blocked the commit (fail-closed)." >&2
  exit 1
fi
$SLOT_END_MARKER
SLOT
}

# slot_present — return 0 if the target hook already contains the fast-lint slot.
# Args: $1 = hook path. Side effects: none.
slot_present() {
  local hook="$1"
  [[ -f "$hook" ]] && grep -qF "$SLOT_BEGIN_MARKER" "$hook"
}

# strip_slot — print the target hook with the fast-lint slot block removed.
# Drops every line from BEGIN..END inclusive. Args: $1 = hook path.
# Side effects: none (pure stdout).
strip_slot() {
  local hook="$1"
  awk -v b="$SLOT_BEGIN_MARKER" -v e="$SLOT_END_MARKER" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip != 1 { print }
  ' "$hook"
}

# --- Actions -----------------------------------------------------------------
case "$ACTION" in
  status)
    if slot_present "$TARGET_HOOK"; then
      printf 'POLARIS_FAST_LINT_SLOT_PRESENT:%s\n' "$TARGET_HOOK"
    else
      printf 'POLARIS_FAST_LINT_SLOT_ABSENT:%s\n' "$TARGET_HOOK"
    fi
    ;;
  remove)
    if [[ ! -f "$TARGET_HOOK" ]]; then
      printf 'POLARIS_FAST_LINT_SLOT_ABSENT:%s\n' "$TARGET_HOOK"
      exit 0
    fi
    if slot_present "$TARGET_HOOK"; then
      tmp="$(mktemp)"
      strip_slot "$TARGET_HOOK" >"$tmp"
      cat "$tmp" >"$TARGET_HOOK"
      rm -f "$tmp"
      printf 'POLARIS_FAST_LINT_SLOT_REMOVED:%s\n' "$TARGET_HOOK"
    else
      printf 'POLARIS_FAST_LINT_SLOT_ABSENT:%s\n' "$TARGET_HOOK"
    fi
    ;;
  install)
    if [[ -f "$TARGET_HOOK" ]]; then
      if slot_present "$TARGET_HOOK"; then
        # Idempotent re-injection: strip the old slot first, then append a fresh
        # one. The hook stays single-slot regardless of how many times we run.
        tmp="$(mktemp)"
        strip_slot "$TARGET_HOOK" >"$tmp"
        cat "$tmp" >"$TARGET_HOOK"
        rm -f "$tmp"
      fi
      # Ensure the hook ends with a newline before appending the slot.
      [[ -s "$TARGET_HOOK" && "$(tail -c1 "$TARGET_HOOK")" == "" ]] || printf '\n' >>"$TARGET_HOOK"
      render_slot >>"$TARGET_HOOK"
    else
      # No existing hook: create a minimal strict-mode hook that hosts the slot.
      {
        printf '#!/usr/bin/env bash\n'
        printf 'set -euo pipefail\n\n'
        render_slot
      } >"$TARGET_HOOK"
    fi
    chmod +x "$TARGET_HOOK"
    printf 'POLARIS_FAST_LINT_SLOT_INSTALLED:%s\n' "$TARGET_HOOK"
    ;;
esac
