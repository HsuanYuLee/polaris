#!/usr/bin/env bash
# validate-refinement-locked-scope.sh — DP-212 LOCKED scope guard (DP-298 T2:
# JSON-authority only; DP-311 T5: per-field acceptance_criteria granularity).
#
# Compares a refinement amendment diff against the LOCKED-protected JSON
# authority fields in `refinement.json`. The top-level fields `goal`,
# `background`, `decisions`, `scope` stay whole-field locked: any change exits
# 2 with `POLARIS_LOCKED_SCOPE_VIOLATION` on stderr.
#
# `acceptance_criteria` is compared per-AC-id (DP-311 T5):
#   - AC add / remove / id rename (id-set change) is a violation.
#   - Within each id-paired AC, every field except `verification.detail` is
#     locked (id / text / category / verification.method and any other field).
#     Only `acceptance_criteria[].verification.detail` may change during an
#     amendment.
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

# Whole-field locked top-level fields; acceptance_criteria is handled
# separately with per-AC-id / per-field granularity (DP-311 T5).
LOCKED_JSON_FIELDS=(
  "goal"
  "background"
  "decisions"
  "scope"
)

violations=()

# JSON diff: re-parse both sides. Whole-field compare for LOCKED_JSON_FIELDS;
# per-AC-id pairing + per-field compare for acceptance_criteria, where only
# verification.detail is amendable.
if git -C "$REPO" diff --quiet "$BASE_REF" "$HEAD_REF" -- "$REFINEMENT_JSON_REL"; then
  : # no json change
else
  json_violations="$(python3 - "$REPO" "$REFINEMENT_JSON_REL" "$BASE_REF" "$HEAD_REF" "${LOCKED_JSON_FIELDS[@]}" <<'PY'
import copy
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


def strip_verification_detail(ac):
    """Return a deep copy of an AC entry without verification.detail.

    Args:
        ac: one acceptance_criteria entry (dict).

    Returns:
        Deep copy of the entry with verification.detail removed, so the
        remaining structure can be deep-compared as the locked surface.
    """
    clone = copy.deepcopy(ac)
    verification = clone.get("verification")
    if isinstance(verification, dict):
        verification.pop("detail", None)
    return clone


def acceptance_criteria_problems(before_acs, after_acs):
    """Compare acceptance_criteria per-AC-id; only verification.detail is open.

    Args:
        before_acs: acceptance_criteria value at base ref.
        after_acs: acceptance_criteria value at head ref.

    Returns:
        List of human-readable violation strings (empty when compliant).
    """
    if before_acs == after_acs:
        return []
    # Non-list / missing on either side: fall back to whole-field lock.
    if not isinstance(before_acs, list) or not isinstance(after_acs, list):
        return ["refinement.json LOCKED field changed: acceptance_criteria"]

    problems = []

    def index_by_id(acs, side):
        indexed = {}
        for entry in acs:
            ac_id = entry.get("id") if isinstance(entry, dict) else None
            if not isinstance(ac_id, str) or not ac_id:
                problems.append(
                    f"refinement.json acceptance_criteria entry without usable id ({side}); cannot pair per-AC-id"
                )
                continue
            if ac_id in indexed:
                problems.append(
                    f"refinement.json acceptance_criteria duplicate id ({side}): {ac_id}"
                )
                continue
            indexed[ac_id] = entry
        return indexed

    before_by_id = index_by_id(before_acs, "base")
    after_by_id = index_by_id(after_acs, "head")
    if problems:
        return problems

    added = sorted(set(after_by_id) - set(before_by_id))
    removed = sorted(set(before_by_id) - set(after_by_id))
    for ac_id in added:
        problems.append(f"refinement.json acceptance_criteria AC added (locked): {ac_id}")
    for ac_id in removed:
        problems.append(f"refinement.json acceptance_criteria AC removed (locked): {ac_id}")

    for ac_id in sorted(set(before_by_id) & set(after_by_id)):
        before_locked = strip_verification_detail(before_by_id[ac_id])
        after_locked = strip_verification_detail(after_by_id[ac_id])
        if before_locked != after_locked:
            changed = sorted(
                key
                for key in set(before_locked) | set(after_locked)
                if before_locked.get(key) != after_locked.get(key)
            )
            problems.append(
                "refinement.json acceptance_criteria LOCKED field changed"
                f" ({ac_id}): {', '.join(changed)}"
            )

    return problems


before = show(base_ref) or {}
after = show(head_ref) or {}

problems = []
for field in fields:
    if before.get(field) != after.get(field):
        problems.append(f"refinement.json LOCKED field changed: {field}")

problems.extend(
    acceptance_criteria_problems(
        before.get("acceptance_criteria"), after.get("acceptance_criteria")
    )
)

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
