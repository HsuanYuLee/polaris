#!/usr/bin/env bash
# Purpose: deterministic gate against two unsafe bash patterns that corrupt on
#   non-ASCII / UTF-8 byte boundaries — (1) bare variable boundary
#   `$VAR<non-ASCII byte>`, and (2) push refspec constructed by interpolating a
#   task-title-derived shell var (DP-307 D6/AC7).
# Inputs:  CLI args = paths to scan (default: scripts/** + .claude/** *.sh).
# Outputs: stderr POLARIS_BASH_VAR_UTF8_BOUNDARY / POLARIS_REFSPEC_VAR_INTERPOLATION
#   tokens with <file>:<line>; exit code (see below).
#
# (1) Bare variable boundary: bash variable expansion does not stop at multi-byte
# UTF-8 continuation bytes when set -u is on. `$foo` followed by a CJK fullwidth
# byte parses as `$fooEF...` and triggers `unbound variable`. Use brace-delimited
# form `${VAR}<punctuation>` instead.
#
# (2) Push refspec interpolation: a `git push` whose refspec embeds a shell var
# (`refs/heads/$VAR`, `$src:$dst`) corrupts when the branch name carries non-ASCII
# bytes (DP-272 incident). The safe construction reads the ref from git itself —
# `git symbolic-ref --short HEAD` / `git push origin HEAD:"$(...)"` — so the byte
# sequence comes straight from the ref store, never from a re-quoted var. DP-307
# D1-D3 make new branches pure ASCII; this gate is defense-in-depth for legacy
# CJK branches (e.g. DP-305) and covers engineering-branch-setup / polaris-pr-create.
#
# Usage:
#   bash scripts/lint-bash-variable-utf8-boundary.sh [path ...]
#
# If no path is given, scans `.claude/**/*.sh` + `scripts/**/*.sh` +
# `.claude/hooks/**/*.sh` under the workspace root.
#
# Exit:
#   0 — no violations
#   2 — at least one violation; stderr lists POLARIS_BASH_VAR_UTF8_BOUNDARY
#       and/or POLARIS_REFSPEC_VAR_INTERPOLATION tokens with <file>:<line>.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

declare -a TARGETS=()
if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  while IFS= read -r -d '' p; do
    TARGETS+=("$p")
  done < <(
    find "${WORKSPACE_ROOT}/scripts" "${WORKSPACE_ROOT}/.claude" \
      -type f -name '*.sh' -print0 2>/dev/null || true
  )
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  exit 0
fi

python3 - "$@" <<'PY' "${TARGETS[@]}"
import re
import sys

# Pattern (1): `$VAR` (no braces) followed immediately by a non-ASCII byte.
# We require the variable to be an unbraced identifier — `${VAR}` is safe.
boundary_pattern = re.compile(rb'\$[A-Za-z_][A-Za-z0-9_]*([^\x00-\x7f])')

# Pattern (2): a `git push` line whose refspec SOURCE side is built from an
# interpolated shell var. The DP-272 incident was
# `git push origin "refs/heads/$BRANCH:refs/heads/$BRANCH"` — the SOURCE ref
# (`refs/heads/$BRANCH`, before the first colon) carried a task-title-derived
# slug, so the byte stream was re-quoted from a var and corrupted on non-ASCII.
# The safe construction sources the push from git itself —
# `git push origin HEAD:"refs/heads/$b"` or `HEAD:"$(git symbolic-ref ...)"` —
# where the SOURCE is `HEAD` and only the explicit DEST names a (loop) var. A
# `HEAD:`-sourced push is therefore always safe; we only flag a var-interpolated
# SOURCE ref.
git_push_pattern = re.compile(rb'\bgit\b[^\n]*\bpush\b')
# A comment line (first non-blank byte is `#`) is never executed, so it cannot
# cause the runtime refspec corruption — skip it for the refspec check. This lets
# documentation/illustrative `git push refs/heads/$VAR:...` examples live in
# comments without tripping the gate.
comment_line_pattern = re.compile(rb'^\s*#')
# Strip flags/remote to isolate the refspec token(s): everything after the last
# whitespace run that is not an option. We approximate by scanning each
# whitespace-delimited token on the push line for a var-interpolated SOURCE.
# A token is an unsafe refspec source when, before its first `:` (or the whole
# token if no colon), it interpolates a var into a ref path or is a bare var
# ref. `HEAD` / `refs/...` literal sources, and `$(...)`-computed sources, are
# safe.
src_var_ref_pattern = re.compile(rb'^["\']?refs/(?:heads|remotes)/[^\s"\':]*\$\{?[A-Za-z_]')
src_bare_var_pattern = re.compile(rb'^["\']?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?["\']?:')
cmd_subst_pattern = re.compile(rb'\$\(')


def has_unsafe_refspec_source(line):
    """Return True when a `git push` line sources its refspec from an
    interpolated var (the DP-272 byte-corruption vector).

    Args:
        line: raw bytes of one source line.

    Returns:
        True when the SOURCE side of a refspec token is a var-interpolated ref;
        False for `HEAD:`-sourced pushes, literal refs, or `$(...)`-computed refs.
    """
    for token in line.split():
        if cmd_subst_pattern.search(token):
            continue
        if src_var_ref_pattern.search(token) or src_bare_var_pattern.search(token):
            return True
    return False


boundary_violations = []
refspec_violations = []
for path in sys.argv[1:]:
    try:
        with open(path, "rb") as fh:
            for lineno, line in enumerate(fh, 1):
                if boundary_pattern.search(line):
                    boundary_violations.append((path, lineno))
                if (
                    not comment_line_pattern.search(line)
                    and git_push_pattern.search(line)
                    and has_unsafe_refspec_source(line)
                ):
                    refspec_violations.append((path, lineno))
    except OSError:
        # Path may not exist or be unreadable; skip silently.
        continue

if boundary_violations or refspec_violations:
    for path, lineno in boundary_violations:
        sys.stderr.write(f"POLARIS_BASH_VAR_UTF8_BOUNDARY: {path}:{lineno}\n")
    for path, lineno in refspec_violations:
        sys.stderr.write(f"POLARIS_REFSPEC_VAR_INTERPOLATION: {path}:{lineno}\n")
    if boundary_violations:
        sys.stderr.write(
            f"\n{len(boundary_violations)} boundary violation(s): "
            "use brace-delimited form `${VAR}<punctuation>` instead of "
            "`$VAR<non-ASCII>`.\n"
        )
    if refspec_violations:
        sys.stderr.write(
            f"\n{len(refspec_violations)} refspec violation(s): construct the "
            "push refspec from git itself, e.g. "
            "`git push origin HEAD:\"$(git symbolic-ref --short HEAD)\"`, instead "
            "of interpolating a task-title-derived var into the refspec.\n"
        )
    sys.exit(2)

sys.exit(0)
PY
