#!/usr/bin/env bash
# lint-bash-variable-utf8-boundary.sh — deterministic gate against unsafe bash
# variable boundary: `$VAR<non-ASCII byte>`.
#
# Bash variable expansion does not stop at multi-byte UTF-8 continuation bytes
# when set -u is on. `$foo` followed by a CJK fullwidth byte parses as
# `$fooEF...` and triggers `unbound variable`. Use brace-delimited form
# `${VAR}<punctuation>` instead.
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
#       tokens with <file>:<line>.

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

# Pattern: `$VAR` (no braces) followed immediately by a non-ASCII byte.
# We require the variable to be an unbraced identifier — `${VAR}` is safe.
pattern = re.compile(rb'\$[A-Za-z_][A-Za-z0-9_]*([^\x00-\x7f])')

violations = []
for path in sys.argv[1:]:
    try:
        with open(path, "rb") as fh:
            for lineno, line in enumerate(fh, 1):
                m = pattern.search(line)
                if m:
                    violations.append((path, lineno))
    except OSError:
        # Path may not exist or be unreadable; skip silently.
        continue

if violations:
    for path, lineno in violations:
        sys.stderr.write(f"POLARIS_BASH_VAR_UTF8_BOUNDARY: {path}:{lineno}\n")
    sys.stderr.write(
        f"\n{len(violations)} violation(s): "
        "use brace-delimited form `${VAR}<punctuation>` instead of `$VAR<non-ASCII>`.\n"
    )
    sys.exit(2)

sys.exit(0)
PY
