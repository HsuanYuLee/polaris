#!/usr/bin/env bash
# gate-spine-delivery.sh — the delivery-evidence gate for spine sources.
#
# Usage:
#   bash scripts/gates/gate-spine-delivery.sh [--repo <path>]
#   bash scripts/gates/gate-spine-delivery.sh [--repo <path>] --is-spine-push
#
# Exit: 0 = pass (or not a spine push), 2 = block.
#
# What this gate does and does not own
# ------------------------------------
# It owns exactly one question: does the recorded delivery intent still describe
# the commit being pushed?
#
# `record-delivery-intent.sh` writes {source}/.spine/delivery.json pinned to a
# head sha, after verifying the frozen assertion fence. That record is what the
# release tail reads. It goes stale the moment another commit lands, and nothing
# re-verifies it — the failure mode is recording intent, committing more, then
# pushing while believing the record still covers the work.
#
# It deliberately does NOT constrain branch or PR naming. Under the old model the
# branch name was the lookup key for a task.md, so a wrong name silently resolved
# to someone else's evidence and had to be gated. A spine source names itself
# inside delivery.json; identity lives in the artifact, not in the ref. Naming is
# a convention for humans reading a PR list, and belongs in repo knowledge next to
# every other naming convention — not in a gate.
#
# Known limit, stated rather than hidden: this checks staleness, not existence. A
# source pushed with no delivery.json at all passes here, because judge may simply
# not have run yet and a work-in-progress push is legitimate. Absence surfaces
# downstream instead — the release tail has nothing to read and cannot ship it.

set -euo pipefail

PREFIX="[polaris gate-spine-delivery]"
REPO_ROOT=""
IS_SPINE_PUSH_QUERY=0
PRINT_RECORDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           REPO_ROOT="${2:-}"; shift 2 ;;
    --is-spine-push)  IS_SPINE_PUSH_QUERY=1; shift ;;
    --print-records)  PRINT_RECORDS=1; shift ;;
    -h|--help)
      echo "Usage: gate-spine-delivery.sh [--repo <path>] [--is-spine-push] [--print-records]" >&2
      exit 0
      ;;
    *) shift ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$HEAD_SHA" ]] || exit 0

# Description: echo the source dirs whose delivery record concerns this push.
# Args:   none (reads REPO_ROOT / HEAD_SHA)
# Output: repo-relative source dirs, e.g. sources/DP-462-spine-cutover
#
# Relevance is decided by the head the record itself names, not by which files
# the push happens to touch. An earlier version matched paths under sources/ and
# was wrong: a spine source's work usually lands in scripts/ or skills/, and only
# the record lives under sources/, so real deliveries were not recognised as
# deliveries at all. The record already states which commit it is about — reading
# that is both simpler and correct, and it is the authoritative field the path
# heuristic was standing in for.
#
# A record is about this push when its head is the commit being pushed, or sits
# in the range about to leave the machine. A record whose head is already in
# origin/main describes work that shipped, and is none of this push's business.
relevant_records() {
  local record source head destination
  for record in "$REPO_ROOT"/sources/*/.spine/delivery.json; do
    [[ -f "$record" ]] || continue
    source="${record#"$REPO_ROOT/"}"
    source="${source%/.spine/delivery.json}"
    head="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("head_sha",""))' \
      "$record" 2>/dev/null || true)"
    [[ -n "$head" ]] || continue
    destination="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("destination",""))' \
      "$record" 2>/dev/null || true)"

    if [[ "$head" == "$HEAD_SHA" ]]; then
      printf '%s\t%s\t%s\n' "$source" current "$destination"
      continue
    fi
    # A head this repository does not contain cannot be reasoned about at all —
    # the ancestry tests below would both answer "no" and the record would drop
    # out silently, leaving the release tail to announce "record current" from an
    # empty check. It is unusable, which is a refusal, not an absence of opinion.
    if ! git -C "$REPO_ROOT" cat-file -e "${head}^{commit}" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$source" unknown_head "$destination"
      continue
    fi
    # Already contained in what the remote has: shipped, not stale.
    if git -C "$REPO_ROOT" merge-base --is-ancestor "$head" origin/main 2>/dev/null; then
      continue
    fi
    # In the range being pushed but not at its tip: work continued after the
    # second gate signed off, and the record no longer describes what ships.
    if git -C "$REPO_ROOT" merge-base --is-ancestor "$head" "$HEAD_SHA" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$source" stale "$destination"
    fi
  done
}

# Collected with a read loop rather than mapfile: the stock macOS bash is 3.2 and
# has no mapfile, so a gate written with it would silently exit 127 on the very
# machine that runs the pre-push hook.
SOURCES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SOURCES+=("$line")
done < <(relevant_records)

# Introspection: which records concern this push, as source \t state \t destination.
# Added for the leak gate, which no longer needs it; kept because "which record
# concerns this push" must have exactly one resolver, and a future second reader
# asking that question has to come here rather than grow its own.
if [[ "$PRINT_RECORDS" -eq 1 ]]; then
  for entry in "${SOURCES[@]:-}"; do
    [[ -n "$entry" ]] && printf '%s\n' "$entry"
  done
  exit 0
fi

# No record concerns this push, so this gate has no opinion and must not claim
# ownership — the task.md-shaped gates still own whatever this is.
if [[ ${#SOURCES[@]} -eq 0 ]]; then
  [[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]] && exit 1
  exit 0
fi

# Ownership is claimed for any push a record concerns, current or stale. Claiming
# only the current ones would hand a stale delivery back to a gate that cannot
# see the problem, and it would pass there.
[[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]] && exit 0

failures=0
for entry in "${SOURCES[@]}"; do
  # Fields are source \t state \t destination; read them positionally rather than
  # by trimming from the ends, which silently picked up the wrong field the moment
  # a third column arrived.
  IFS=$'\t' read -r source state _destination <<<"$entry"

  if [[ "$state" == "current" ]]; then
    echo "$PREFIX ✅ ${source}: delivery intent current @ ${HEAD_SHA:0:12}." >&2
    continue
  fi

  recorded="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("head_sha",""))' \
    "$REPO_ROOT/$source/.spine/delivery.json" 2>/dev/null || true)"
  if [[ "$state" == "unknown_head" ]]; then
    echo "$PREFIX BLOCKED: ${source} recorded its delivery intent at ${recorded:0:12}, which this repository does not contain." >&2
    echo "$PREFIX A record pinned to a commit that is not here describes work this push cannot be." >&2
    echo "$PREFIX Re-run judge's handoff step from the checkout that is shipping:" >&2
    echo "$PREFIX   bash scripts/record-delivery-intent.sh --source ${source} --version-bump <bump> --summary '<line>'" >&2
    failures=$((failures + 1))
    continue
  fi
  echo "$PREFIX BLOCKED: ${source} recorded its delivery intent at ${recorded:0:12}, but HEAD is ${HEAD_SHA:0:12}." >&2
  echo "$PREFIX The record the release tail reads describes a different commit than the one being pushed." >&2
  echo "$PREFIX Re-run judge's handoff step so the record and the commit agree:" >&2
  echo "$PREFIX   bash scripts/record-delivery-intent.sh --source ${source} --version-bump <bump> --summary '<line>'" >&2
  failures=$((failures + 1))
done

[[ "$failures" -eq 0 ]] || exit 2
exit 0
