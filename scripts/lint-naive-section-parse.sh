#!/usr/bin/env bash
# Purpose: A-class fail-closed lint (DP-345 D4) against naive markdown section
#   parsing — a blob-level substring search (`.find` / `.index` / `.split`) for a
#   `## heading` marker over markdown text that was NOT frontmatter-stripped. That
#   idiom mis-fires when a YAML frontmatter `description` literally contains a
#   `## heading` (the DP-344-T1 collision shape that motivated DP-345). The
#   canonical replacement line-anchors on `^## ` after stripping frontmatter
#   (parse-task-md.sh / refinement_common.py idiom).
# Inputs:  CLI args = paths to scan; or `--self-check` to scan the converged repo
#   tree (scripts/** + .claude/** sources). `--allowlist <file>` supplies
#   `<path>:<reason>` per-line exemptions for files that parse genuinely
#   frontmatter-less content (e.g. a CHANGELOG version block).
# Outputs: stderr `POLARIS_NAIVE_SECTION_PARSE: <file>:<line>` per violation.
# Exit:
#   0 — no violations (or all violations allowlisted)
#   2 — at least one un-allowlisted naive section parse; stderr lists tokens
#
# What is flagged (naive): a `.find(...)` / `.index(...)` / `.split(...)` whose
#   first string-literal argument contains a `##` heading marker — e.g.
#   `text.find("## Allowed Files")`, `text.find("\n## ")`, `text.split("\n## ")`.
#   These search the whole blob, so a frontmatter-embedded `## ...` matches first.
#
# What is NOT flagged (safe, AC-NEG1):
#   - line-anchored idioms: `awk '$0==heading'`, `re.compile(r"^## ", re.M)`,
#     `for line in text.splitlines(): line.startswith("## ")` — these use
#     `startswith` / `==` / `^`-anchored regex, never blob `.find`/`.index`/`.split`.
#   - path-string find: `path.find("/apps/")`, `s.find("src/content/docs/")` — the
#     literal carries no `##` marker, so it never matches.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALLOWLIST=""
SELF_CHECK=0
declare -a TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allowlist)
      ALLOWLIST="${2:-}"
      shift 2
      ;;
    --self-check)
      SELF_CHECK=1
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [[ "$SELF_CHECK" -eq 1 ]]; then
  while IFS= read -r -d '' p; do
    TARGETS+=("$p")
  done < <(
    find "${WORKSPACE_ROOT}/scripts" "${WORKSPACE_ROOT}/.claude" \
      -type f \( -name '*.py' -o -name '*.sh' -o -name '*.mjs' -o -name '*.ts' \) \
      -print0 2>/dev/null || true
  )
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  exit 0
fi

python3 - "${ALLOWLIST}" "${TARGETS[@]}" <<'PY'
import os
import re
import sys

allowlist_path = sys.argv[1]
targets = sys.argv[2:]

# Load <path>:<reason> allowlist. The reason is mandatory (it documents why the
# file is genuinely frontmatter-less); an entry without a non-empty reason is
# rejected so the allowlist can never become an undocumented blanket exemption.
# Allowlisted paths are matched by realpath, so a per-path entry can never become
# an over-broad directory wildcard.
allowed = set()
if allowlist_path:
    try:
        with open(allowlist_path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                path, sep, reason = line.partition(":")
                if not sep or not reason.strip():
                    sys.stderr.write(
                        f"POLARIS_NAIVE_SECTION_PARSE: malformed allowlist entry "
                        f"(need <path>:<reason>): {line}\n"
                    )
                    sys.exit(2)
                allowed.add(os.path.realpath(path.strip()))
    except OSError as exc:
        sys.stderr.write(f"POLARIS_NAIVE_SECTION_PARSE: cannot read allowlist: {exc}\n")
        sys.exit(2)

# A `.find` / `.index` / `.split` call whose argument begins with a string literal
# that contains a `##` heading marker. We match the method name, an opening paren,
# a string literal opener, then look for `##` (optionally after a leading `\n`)
# before the literal closes. The marker forms we care about are `## ` and `\n## `.
#
# Group 1: method name. We require the receiver to be a bare expression (not a
# regex object) by anchoring on `.<method>(` — `re.compile(...).search` does not
# use these blob methods.
naive_call = re.compile(
    r"""\.(find|index|split)\(\s*        # blob substring method
        (?:r|b|rb|br|f|fb|bf)?           # optional string prefix
        (['"])                           # opening quote (group 2)
        (?:\\n)?                         # optional leading newline anchor
        \#\#                             # the literal ## heading marker
    """,
    re.VERBOSE,
)

# A line whose only `##` occurrence is inside a `startswith(...)` / `==` / a
# `^##`-anchored regex is line-anchored and safe; those never use .find/.index/
# .split, so the naive_call regex already excludes them. No extra allowance
# needed — but we still skip comment-only lines to permit illustrative docs.
comment_line = re.compile(r"^\s*#")

violations = []
for path in targets:
    real = os.path.realpath(path)
    if real in allowed:
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if comment_line.search(line):
                    continue
                if naive_call.search(line):
                    violations.append((path, lineno))
    except OSError:
        continue

if violations:
    for path, lineno in violations:
        sys.stderr.write(f"POLARIS_NAIVE_SECTION_PARSE: {path}:{lineno}\n")
    sys.stderr.write(
        f"\n{len(violations)} naive section-parse violation(s): a blob-level "
        ".find/.index/.split for a `## heading` searches un-frontmatter-stripped "
        "text and mis-fires on a frontmatter-embedded heading. Strip frontmatter "
        "then line-anchor on `^## ` (parse-task-md.sh idiom). If the file parses "
        "genuinely frontmatter-less content, add a <path>:<reason> allowlist entry.\n"
    )
    sys.exit(2)

sys.exit(0)
PY
