#!/usr/bin/env bash
# validate-refinement-locked-scope.sh — DP-212 LOCKED scope guard (DP-298 T2:
# JSON-authority only).
#
# Compares a refinement amendment diff against the LOCKED-protected JSON
# authority fields. If the diff touches the JSON top-level fields (`goal`,
# `background`, `decisions`, `scope`, `acceptance_criteria`) in
# `refinement.json`, the validator exits 2 with `POLARIS_LOCKED_SCOPE_VIOLATION`
# on stderr.
#
# DP-298 T2 removed the `refinement.md` `## Scope` / heading-diff business-read
# branch: `refinement.json` is the single authoritative source for LOCKED scope,
# and the derived `refinement.md` body is no longer read to make a LOCKED-scope
# decision (it is a render target, not authority). The only remaining reference
# to `refinement.md` in this guard is this comment — there is no executing path
# that reads its body.
#
# Usage:
#   scripts/validate-refinement-locked-scope.sh \
#     --container /absolute/path/to/DP-NNN-container \
#     --base-ref <git ref or commit before amendment> \
#     [--head-ref <git ref or commit after amendment, default HEAD>]
#
# Exit codes:
#   0  amendment touches only allowed JSON fields (or no diff)
#   1  invalid input / IO error
#   2  POLARIS_LOCKED_SCOPE_VIOLATION — amendment touched a LOCKED JSON field

set -euo pipefail

CONTAINER=""
BASE_REF=""
HEAD_REF="HEAD"
REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="${2:-}"; shift 2 ;;
    --base-ref)  BASE_REF="${2:-}"; shift 2 ;;
    --head-ref)  HEAD_REF="${2:-}"; shift 2 ;;
    --repo)      REPO="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '3,21p' "$0" >&2
      exit 1
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$CONTAINER" || -z "$BASE_REF" ]]; then
  echo "ERROR: --container and --base-ref are required" >&2
  exit 1
fi

if [[ ! -d "$CONTAINER" ]]; then
  echo "ERROR: container directory not found: $CONTAINER" >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(git -C "$CONTAINER" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: could not resolve git repo for $CONTAINER" >&2
  exit 1
fi

# Resolve symlinks on both sides so the repo-relative path comes out clean
# even when CONTAINER lives under /tmp (which macOS symlinks to /private/tmp).
CONTAINER_REAL="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$CONTAINER")"
REPO_REAL="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$REPO")"
REL_CONTAINER="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$CONTAINER_REAL" "$REPO_REAL")"
REPO="$REPO_REAL"

REFINEMENT_JSON_REL="${REL_CONTAINER%/}/refinement.json"

LOCKED_JSON_FIELDS=(
  "goal"
  "background"
  "decisions"
  "scope"
  "acceptance_criteria"
)

violations=()

# JSON diff: re-parse both sides and compare locked top-level fields. If any
# of those fields differ, that is a violation. Adds / removes count too.
if git -C "$REPO" diff --quiet "$BASE_REF" "$HEAD_REF" -- "$REFINEMENT_JSON_REL"; then
  : # no json change
else
  json_violations="$(python3 - "$REPO" "$REFINEMENT_JSON_REL" "$BASE_REF" "$HEAD_REF" "${LOCKED_JSON_FIELDS[@]}" <<'PY'
import json
import subprocess
import sys

repo, rel_path, base_ref, head_ref, *fields = sys.argv[1:]


def show(ref):
    try:
        out = subprocess.check_output(
            ["git", "-C", repo, "show", f"{ref}:{rel_path}"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None
    try:
        return json.loads(out.decode("utf-8"))
    except json.JSONDecodeError:
        return None


before = show(base_ref) or {}
after = show(head_ref) or {}

problems = []
for field in fields:
    if before.get(field) != after.get(field):
        problems.append(f"refinement.json LOCKED field changed: {field}")

print("\n".join(problems))
PY
)"
  if [[ -n "$json_violations" ]]; then
    while IFS= read -r v; do
      [[ -n "$v" ]] && violations+=("$v")
    done <<<"$json_violations"
  fi
fi

if [[ "${#violations[@]}" -gt 0 ]]; then
  echo "POLARIS_LOCKED_SCOPE_VIOLATION" >&2
  for v in "${violations[@]}"; do
    echo "  - $v" >&2
  done
  exit 2
fi

echo "PASS: refinement amendment respects LOCKED scope guard ($REL_CONTAINER)"
