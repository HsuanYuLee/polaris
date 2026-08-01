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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)           REPO_ROOT="${2:-}"; shift 2 ;;
    --is-spine-push)  IS_SPINE_PUSH_QUERY=1; shift ;;
    -h|--help)
      echo "Usage: gate-spine-delivery.sh [--repo <path>] [--is-spine-push]" >&2
      exit 0
      ;;
    *) shift ;;
  esac
done

[[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ -n "$HEAD_SHA" ]] || exit 0

# Description: echo the source directories this push touches, one per line.
#   Scoped to the range about to leave the machine, so unrelated sources sitting
#   at an older delivery head never block an unrelated push.
# Args:   none (reads REPO_ROOT / HEAD_SHA)
# Output: repo-relative source dirs, e.g. sources/DP-462-spine-cutover
touched_sources() {
  local base range
  base="$(git -C "$REPO_ROOT" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "$base" && "$base" != "$HEAD_SHA" ]]; then
    range="${base}..${HEAD_SHA}"
  else
    # No divergence from origin/main to compare against (a fresh branch pushed at
    # the same commit, or origin unavailable). Fall back to the tip commit alone;
    # an empty result then simply means this push carries no source change.
    range="${HEAD_SHA}^!"
  fi
  git -C "$REPO_ROOT" diff --name-only "$range" 2>/dev/null \
    | awk -F/ '$1 == "sources" && NF >= 2 { print $1 "/" $2 }' \
    | sort -u
}

# Collected with a read loop rather than mapfile: the stock macOS bash is 3.2 and
# has no mapfile, so a gate written with it would silently exit 127 on the very
# machine that runs the pre-push hook.
SOURCES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SOURCES+=("$line")
done < <(touched_sources)

# A push that touches no source is not a spine push; this gate has no opinion.
if [[ ${#SOURCES[@]} -eq 0 ]]; then
  [[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]] && exit 1
  exit 0
fi

# Description: echo the head_sha recorded in a source's delivery.json, or empty
#   when the source has no recorded delivery intent yet.
# Args: $1 = source dir (repo-relative)
recorded_head() {
  local record="$REPO_ROOT/$1/.spine/delivery.json"
  [[ -f "$record" ]] || return 0
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("head_sha",""))' \
    "$record" 2>/dev/null || true
}

if [[ "$IS_SPINE_PUSH_QUERY" -eq 1 ]]; then
  # Answer the ownership question only. A touched source with a delivery record
  # makes this a spine push, and this gate — not the task.md-shaped one — owns it.
  for source in "${SOURCES[@]}"; do
    [[ -n "$(recorded_head "$source")" ]] && exit 0
  done
  exit 1
fi

failures=0
for source in "${SOURCES[@]}"; do
  head="$(recorded_head "$source")"

  if [[ -z "$head" ]]; then
    echo "$PREFIX ${source}: no delivery intent recorded yet — work in progress, not blocked." >&2
    continue
  fi

  if [[ "$head" == "$HEAD_SHA" ]]; then
    echo "$PREFIX ✅ ${source}: delivery intent current @ ${HEAD_SHA:0:12}." >&2
    continue
  fi

  echo "$PREFIX BLOCKED: ${source} recorded its delivery intent at ${head:0:12}, but HEAD is ${HEAD_SHA:0:12}." >&2
  echo "$PREFIX The record the release tail reads describes a different commit than the one being pushed." >&2
  echo "$PREFIX Re-run judge's handoff step so the record and the commit agree:" >&2
  echo "$PREFIX   bash scripts/record-delivery-intent.sh --source ${source} --version-bump <bump> --summary '<line>'" >&2
  failures=$((failures + 1))
done

[[ "$failures" -eq 0 ]] || exit 2
exit 0
