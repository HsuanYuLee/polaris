#!/usr/bin/env bash
# Purpose: Verify the spine delivery gate blocks exactly one thing — a delivery
#          record describing a different commit than the one being pushed.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a record pinned to HEAD passes, a record pinned elsewhere
#          blocks, a touched source with no record yet passes as work in
#          progress, a push touching no source is disclaimed, and the ownership
#          query answers yes only for a source that has a record.

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

# Description: build a repo whose branch adds one source, and echo its path.
#   origin/main is a real local ref so the gate's range resolution has the same
#   shape it does in the live repo.
# Args: $1 = case name, $2 = source dir name
new_repo() {
  local name="$1" source_name="$2" repo="$WORK/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest
  echo base > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" branch -f origin/main HEAD
  mkdir -p "$repo/sources/$source_name/.spine"
  echo assertion > "$repo/sources/$source_name/index.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "add $source_name"
  printf '%s' "$repo"
}

# Description: write a delivery record pinned to a given head.
# Args: $1 = repo, $2 = source dir name, $3 = head sha
write_record() {
  python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": sys.argv[2], "head_sha": sys.argv[3]},
          open(sys.argv[1], "w"))
' "$1/sources/$2/.spine/delivery.json" "sources/$2" "$3"
}

echo "gate-spine-delivery selftest"

# A record pinned to the pushed commit is the whole point of recording one.
repo="$(new_repo current dp-current)"
write_record "$repo" dp-current "$(git -C "$repo" rev-parse HEAD)"
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a record pinned to HEAD should pass"
echo "  ok  record at HEAD passes"

# The failure this gate exists for: intent recorded, more commits landed, record
# never refreshed. Pushing now would hand the release tail the wrong commit.
repo="$(new_repo stale dp-stale)"
write_record "$repo" dp-stale "$(git -C "$repo" rev-parse HEAD)"
echo more >> "$repo/sources/dp-stale/index.md"
git -C "$repo" add -A
git -C "$repo" commit -qm "work after recording"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  fail "a record left behind by later commits should block"
fi
echo "  ok  record behind HEAD blocks"

# Judge may simply not have run yet; a work-in-progress push is legitimate. This
# gate checks staleness, not existence.
repo="$(new_repo wip dp-wip)"
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a touched source with no record yet should pass as work in progress"
echo "  ok  no record yet passes"

# A push touching nothing under sources/ is not this gate's business, and must
# not be silently adopted by it — gate-evidence still owns that shape.
repo="$(new_repo unrelated dp-unrelated)"
echo change >> "$repo/README.md"
git -C "$repo" add -A
git -C "$repo" commit -qm "unrelated change"
git -C "$repo" branch -f origin/main HEAD
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a push touching no source should pass"
if bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a push touching no source must not be claimed as a spine push"
fi
echo "  ok  non-spine push disclaimed"

# Ownership is earned by having a record, not by how the branch is named — the
# whole reason naming went back to being knowledge rather than a gate.
repo="$(new_repo owned dp-owned)"
if bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a source with no record must not be claimed as a spine push"
fi
write_record "$repo" dp-owned "$(git -C "$repo" rev-parse HEAD)"
bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1 \
  || fail "a source with a record should be claimed as a spine push"
echo "  ok  ownership tracks the record, not the branch name"

echo "PASS: gate-spine-delivery"
