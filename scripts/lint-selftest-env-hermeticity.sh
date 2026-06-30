#!/usr/bin/env bash
# Purpose: deterministic gate against POLARIS_* env-leak hermeticity violations in
#   selftests. A selftest that spawns a Polaris child process anchored ONLY on a
#   fixture `--scan-root` (no explicit `--specs-source`) must neutralize the live
#   workspace env (`env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT`) on that
#   invocation; otherwise the child short-circuits to POLARIS_WORKSPACE_ROOT /
#   POLARIS_SPECS_ROOT (which the framework bash contract requires callers to
#   export) and resolves against the live workspace instead of the fixture —
#   making the selftest result depend on whether those vars were set in the
#   calling process (the DP-301 release-block class).
# Inputs:  CLI args = selftest paths to scan (default: scripts/selftests/*.sh +
#   scripts/*-selftest.sh under the workspace root). `--allowlist <path>` overrides
#   the default embedded allowlist (used by the selftest to drive fixtures).
# Outputs: stderr POLARIS_SELFTEST_ENV_LEAK tokens with <file>:<line>; exit code
#   (see below). Legitimately env-dependent selftests (e.g. a leak-guard test that
#   exports a decoy root on purpose) are enrolled in the embedded allowlist and
#   skipped.
#
# Rule (deterministic, static): a source line is a violation when ALL of:
#   (1) it spawns a Polaris child process — `bash "$0"`, `bash "$RESOLVER"`,
#       `bash "$<VAR>"`, `"$RESOLVER" ...`, or `bash <path-to-polaris-script>`;
#   (2) the same line anchors that child on a fixture scan-root via `--scan-root`;
#   (3) the same line does NOT pass an explicit `--specs-source` (an explicit
#       specs path makes the resolver hermetic regardless of inherited env);
#   (4) the same line does NOT neutralize the live env (`env -u
#       POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT`), and does NOT inline-export a fixture
#       POLARIS_WORKSPACE_ROOT for the child (an explicit fixture export is
#       likewise env-independent; such files are nonetheless enrolled in the
#       allowlist because they are deliberately env-dependent leak-guard tests).
# Comment lines (first non-blank byte `#`) are never executed → skipped.
# `--scan-dir` (a lint directory argument, not a workspace resolver anchor) is NOT
#   a fixture scan-root and is not flagged.
#
# Usage:
#   bash scripts/lint-selftest-env-hermeticity.sh [--allowlist <path>] [path ...]
#
# Exit:
#   0 — no violations
#   2 — at least one violation; stderr lists POLARIS_SELFTEST_ENV_LEAK tokens with
#       <file>:<line> plus a remediation hint. Fails closed (DP-325 AC-NF1):
#       missing inputs / unreadable allowlist do not silently pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default embedded allowlist: selftests that are intentionally env-dependent
# (e.g. leak-guard tests that export a decoy POLARIS_WORKSPACE_ROOT on purpose to
# prove the resolver does NOT honor it). Kept inline (not a sidecar file) so the
# allowlist and the gate ship as one Allowed-Files unit; `--allowlist` overrides
# this for the selftest's fixture-driven cases. Each entry MUST carry a rationale.
DEFAULT_ALLOWLIST="$(cat <<'ALLOW'
# path<TAB>rationale
# DP-322 leak-guard: deliberately exports POLARIS_WORKSPACE_ROOT="$DECOY" and
# asserts the resolver ignores it and resolves the --scan-root fixture instead.
# The export is the test stimulus, so this selftest is env-dependent by design.
scripts/selftests/resolve-task-md-by-branch-overlay-scan-root-selftest.sh	DP-322 decoy-root leak-guard test (export is the stimulus)
ALLOW
)"

ALLOWLIST=""

declare -a TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allowlist)
      [[ $# -ge 2 ]] || { echo "POLARIS_SELFTEST_ENV_LEAK: --allowlist requires a path" >&2; exit 2; }
      ALLOWLIST="$2"
      shift 2
      ;;
    --*)
      echo "POLARIS_SELFTEST_ENV_LEAK: unknown option: $1" >&2
      exit 2
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  while IFS= read -r -d '' p; do
    TARGETS+=("$p")
  done < <(
    find "${WORKSPACE_ROOT}/scripts/selftests" -type f -name '*.sh' -print0 2>/dev/null || true
  )
  while IFS= read -r -d '' p; do
    TARGETS+=("$p")
  done < <(
    find "${WORKSPACE_ROOT}/scripts" -maxdepth 1 -type f -name '*-selftest.sh' -print0 2>/dev/null || true
  )
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  # Fail closed (AC-NF1): an empty target set means the scan inputs are missing,
  # not that the tree is hermetic. A silent exit 0 would let an env-leak land
  # whenever the find inputs disappear.
  echo "POLARIS_SELFTEST_ENV_LEAK: no selftest targets resolved (missing scan inputs)" >&2
  exit 2
fi

# When an override allowlist file is supplied, materialize its content; otherwise
# use the embedded default. The python scanner receives the allowlist BODY (not a
# path) on the first arg so the embedded and file forms share one code path.
if [[ -n "$ALLOWLIST" ]]; then
  if [[ ! -r "$ALLOWLIST" ]]; then
    # Fail closed (AC-NF1): an explicitly requested allowlist that cannot be read
    # must not silently degrade to "no allowlist".
    echo "POLARIS_SELFTEST_ENV_LEAK: allowlist not readable: $ALLOWLIST" >&2
    exit 2
  fi
  ALLOWLIST_BODY="$(cat "$ALLOWLIST")"
else
  ALLOWLIST_BODY="$DEFAULT_ALLOWLIST"
fi

python3 - "$ALLOWLIST_BODY" "${TARGETS[@]}" <<'PY'
"""Purpose: static POLARIS_* env-leak hermeticity scanner for selftests.

Reads the allowlist BODY (first arg) listing selftest paths that legitimately
depend on POLARIS_* env, then scans each remaining selftest path (subsequent
args) for the env-leak class described in the wrapping shell script header. Emits
POLARIS_SELFTEST_ENV_LEAK tokens and exits 2 on any violation.
"""
import os
import re
import sys

allowlist_body = sys.argv[1]
target_paths = sys.argv[2:]

# A line spawns a Polaris child when it invokes a resolver/script directly or via
# `bash`. We require either an explicit `bash <something>` or a quoted-var command
# (`"$RESOLVER" ...` / `"$LINT" ...`) at a command position.
child_spawn_pattern = re.compile(
    rb'(\bbash\s+"?\$|\bbash\s+"?[^\s"]*\.sh|(?:^|[;&|]|\$\()\s*"\$[A-Za-z_][A-Za-z0-9_]*")'
)
# A child invocation is fixture-anchored on the leak vector when it carries
# `--scan-root` (the resolve-task-md workspace anchor). `--scan-dir` is a lint
# directory argument, not a workspace resolver anchor, so it is NOT a leak vector.
fixture_anchor_pattern = re.compile(rb'--scan-root\b')
# An explicit `--specs-source` makes the resolver hermetic regardless of inherited
# POLARIS_* env (the flag value wins), so such invocations are never a leak.
explicit_specs_source_pattern = re.compile(rb'--specs-source\b')
# Neutralized: the live env is explicitly unset for this invocation. `env` may
# unset several vars (`env -u RESOLVE -u POLARIS_WORKSPACE_ROOT ...`), so match the
# `-u POLARIS_WORKSPACE_ROOT` token anywhere on a line that also runs `env`.
env_unset_pattern = re.compile(
    rb'\benv\b(?=.*-u\s+POLARIS_WORKSPACE_ROOT)(?=.*-u\s+POLARIS_SPECS_ROOT)'
)
# Inline fixture export: an explicit `POLARIS_WORKSPACE_ROOT=<fixture> bash ...`
# is env-independent for that invocation. Files that do this on purpose (decoy
# leak-guard tests) are still enrolled in the allowlist with a rationale; the
# inline check is defense-in-depth so a single such line is not double-counted.
env_inline_export_pattern = re.compile(rb'\bPOLARIS_WORKSPACE_ROOT=')
comment_line_pattern = re.compile(rb'^\s*#')


def normalize(path):
    """Return a workspace-relative POSIX path for stable allowlist matching.

    Args:
        path: absolute or relative filesystem path to a selftest.

    Returns:
        The path made relative to the workspace root when possible, else the
        basename-bearing tail; always forward-slash separated.
    """
    ap = os.path.abspath(path)
    # Anchor relative paths on the `scripts/` segment so absolute worktree paths
    # and relative repo paths normalize to the same key.
    marker = os.sep + "scripts" + os.sep
    idx = ap.find(marker)
    if idx != -1:
        return ap[idx + 1:].replace(os.sep, "/")
    return ap.replace(os.sep, "/")


def load_allowlist(body):
    """Parse the env-hermeticity allowlist body.

    Args:
        body: allowlist text; each non-blank, non-'#' line's first whitespace
            field is a workspace-relative selftest path.

    Returns:
        A set of normalized allowlisted selftest paths.
    """
    allowed = set()
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        first = line.split()[0]
        allowed.add(first.replace(os.sep, "/"))
    return allowed


allowed = load_allowlist(allowlist_body)
violations = []
for path in target_paths:
    rel = normalize(path)
    if rel in allowed:
        continue
    try:
        with open(path, "rb") as fh:
            for lineno, line in enumerate(fh, 1):
                if comment_line_pattern.search(line):
                    continue
                if not child_spawn_pattern.search(line):
                    continue
                if not fixture_anchor_pattern.search(line):
                    continue
                if explicit_specs_source_pattern.search(line):
                    continue
                if env_unset_pattern.search(line) or env_inline_export_pattern.search(line):
                    continue
                violations.append((rel, lineno))
    except OSError:
        # A target that cannot be read is itself a fail-closed condition.
        sys.stderr.write(
            f"POLARIS_SELFTEST_ENV_LEAK: target unreadable: {path}\n"
        )
        sys.exit(2)

if violations:
    for rel, lineno in violations:
        sys.stderr.write(f"POLARIS_SELFTEST_ENV_LEAK: {rel}:{lineno}\n")
    sys.stderr.write(
        f"\n{len(violations)} selftest env-leak violation(s): a fixture-anchored "
        "Polaris child invocation must unset the live env "
        "(`env -u POLARIS_WORKSPACE_ROOT -u POLARIS_SPECS_ROOT bash \"$0\" "
        "--scan-root ...`) so the result is identical with or without "
        "POLARIS_WORKSPACE_ROOT exported. A selftest that legitimately depends on "
        "POLARIS_* env (e.g. a leak-guard test that exports a decoy root) must be "
        "enrolled in the embedded DEFAULT_ALLOWLIST in "
        "scripts/lint-selftest-env-hermeticity.sh with a rationale.\n"
    )
    sys.exit(2)

sys.exit(0)
PY
