#!/usr/bin/env bash
# Purpose: Verify the spine delivery gate blocks exactly one thing — a delivery
#          record describing a different commit than the one being pushed — and
#          that it decides relevance from the head the record names.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a record pinned to HEAD passes, a record left behind by
#          later commits blocks, a record for work already in origin/main is
#          ignored, a repo with no record is disclaimed, and a push that changes
#          nothing under sources/ is still recognised by its record.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gates/gate-spine-delivery.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: build a repo holding one source, and echo its path. origin/main is
#   a real local ref so ancestry resolution has the same shape as in a live repo.
# Args: $1 = case name
new_repo() {
  local repo="$WORK/$1"
  mkdir -p "$repo"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  mkdir -p "$repo/sources/DP-000-selftest/.spine" "$repo/scripts"
  echo assertion > "$repo/sources/DP-000-selftest/index.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" branch -f origin/main HEAD
  printf '%s' "$repo"
}

# Description: write a delivery record pinned to a given head.
# Args: $1 = repo, $2 = head sha
write_record() {
  python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "sources/DP-000-selftest",
           "head_sha": sys.argv[2]}, open(sys.argv[1], "w"))
' "$1/sources/DP-000-selftest/.spine/delivery.json" "$2"
}

# Description: add a commit that touches only scripts/, never sources/.
# Args: $1 = repo, $2 = message
commit_work_outside_sources() {
  echo "work $2" >> "$1/scripts/tool.sh"
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
}

echo "gate-spine-delivery selftest"

# A record pinned to the pushed commit is the whole point of recording one.
repo="$(new_repo current)"
commit_work_outside_sources "$repo" "deliverable"
write_record "$repo" "$(git -C "$repo" rev-parse HEAD)"
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a record pinned to HEAD should pass"
echo "  ok  record at HEAD passes"

# The regression this shape was written to prevent: a spine source's work lands
# in scripts/ or skills/, and only the record lives under sources/. Deciding
# relevance by which files changed missed real deliveries entirely, so the gate
# silently handed them to a gate that demands a task.md they cannot have.
if ! bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a push changing nothing under sources/ must still be recognised by its record"
fi
echo "  ok  relevance comes from the record, not from changed paths"

# The failure this gate exists for: intent recorded, more commits landed, record
# never refreshed. Pushing now would hand the release tail the wrong commit.
repo="$(new_repo stale)"
commit_work_outside_sources "$repo" "deliverable"
write_record "$repo" "$(git -C "$repo" rev-parse HEAD)"
commit_work_outside_sources "$repo" "work after recording"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  fail "a record left behind by later commits should block"
fi
bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1 \
  || fail "a stale record must still be owned here, not handed to another gate"
echo "  ok  record behind HEAD blocks, and stays owned"

# A record for work the remote already has describes something that shipped. It
# must not block every later push forever.
repo="$(new_repo shipped)"
commit_work_outside_sources "$repo" "shipped work"
write_record "$repo" "$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" branch -f origin/main HEAD
commit_work_outside_sources "$repo" "new unrelated work"
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a record for already-shipped work should not block a later push"
if bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a record for already-shipped work must not claim a later push"
fi
echo "  ok  already-shipped record ignored"

# Judge may simply not have run yet; this gate checks staleness, not existence,
# and must not adopt a push it knows nothing about.
repo="$(new_repo norecord)"
commit_work_outside_sources "$repo" "work in progress"
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a repo with no record should pass"
if bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a repo with no record must not be claimed as a spine push"
fi
echo "  ok  no record at all is disclaimed"

echo "PASS: gate-spine-delivery"
