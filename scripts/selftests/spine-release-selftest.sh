#!/usr/bin/env bash
# Purpose: Verify the release tail refuses everything it should before it can
#          reach anything irreversible, and that the destination decides how far
#          it would go.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a source with no record, an unknown destination, altered
#          assertions, or a record left behind by later commits are all refused,
#          and when the preview distinguishes workspace-bound from template-bound.
#
# Scope note: the execute path touches a remote, a template checkout and the
# GitHub API, so it is not exercised here. It is covered by actually running it,
# reported as the dogfood observation it is rather than dressed up as a test.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: build a repo carrying the real scripts plus one sealed source,
#   and echo the repo path. The scripts are symlinked so the selftest exercises
#   the live implementations rather than copies that could drift.
# Args: $1 = case name, $2 = destination value ("" to omit the field)
new_repo() {
  local name="$1" destination="$2" repo="$WORK/$1" source
  mkdir -p "$repo"
  ln -s "$ROOT_DIR/scripts" "$repo/scripts"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest

  source="$repo/sources/DP-000-selftest"
  mkdir -p "$source"
  {
    echo "---"
    echo "title: selftest source"
    [[ -n "$destination" ]] && echo "destination: $destination"
    echo "---"
    echo
    echo "<!-- POLARIS-FROZEN-A-BEGIN -->"
    echo "- A-P1 the thing holds."
    echo "<!-- POLARIS-FROZEN-A-END -->"
  } > "$source/index.md"

  bash "$ROOT_DIR/scripts/frozen-assertion-fence.sh" seal "$source/index.md" --by selftest >/dev/null
  echo "scripts" > "$repo/.gitignore"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" branch -f origin/main HEAD
  printf '%s' "$repo"
}

record() {
  # Description: record delivery intent inside a fixture repo.
  # Args: $1 = repo, $2 = version bump
  (cd "$1" && bash "$ROOT_DIR/scripts/record-delivery-intent.sh" \
    --source sources/DP-000-selftest --version-bump "$2" --summary 'a line' >/dev/null)
}

release() {
  # Description: run the release tail in preview mode inside a fixture repo.
  # Args: $1 = repo
  (cd "$1" && bash "$ROOT_DIR/scripts/spine-release.sh" \
    --repo "$1" --source sources/DP-000-selftest 2>&1)
}

echo "spine-release selftest"

# Nothing handed over means nothing to ship; this must not be read as "no work".
repo="$(new_repo norecord template)"
if release "$repo" >/dev/null 2>&1; then
  fail "a source with no delivery record should refuse to release"
fi
echo "  ok  no delivery record refuses"

# An unknown destination cannot be guessed into workspace or template.
repo="$(new_repo baddest template)"
record "$repo" minor
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["destination"] = "somewhere-else"
json.dump(d, open(p, "w"))
' "$repo/sources/DP-000-selftest/.spine/delivery.json"
if release "$repo" >/dev/null 2>&1; then
  fail "an unknown destination should refuse to release"
fi
echo "  ok  unknown destination refuses"

# Shipping against assertions that changed after signing is the failure the
# whole fence exists to prevent, so it is checked here too rather than trusted
# from whenever the record was written.
repo="$(new_repo tampered template)"
record "$repo" minor
sed -i.bak 's/the thing holds/the thing does not hold/' "$repo/sources/DP-000-selftest/index.md"
rm -f "$repo/sources/DP-000-selftest/index.md.bak"
if release "$repo" >/dev/null 2>&1; then
  fail "altered assertions should refuse to release"
fi
echo "  ok  altered assertions refuse"

# A record left behind by later commits describes different work than the one
# about to ship.
repo="$(new_repo stale template)"
record "$repo" minor
echo "later work" >> "$repo/sources/DP-000-selftest/notes.md"
git -C "$repo" add -A
git -C "$repo" commit -qm "work after recording"
if release "$repo" >/dev/null 2>&1; then
  fail "a record behind HEAD should refuse to release"
fi
echo "  ok  stale record refuses"

# The destination decides how far the tail goes. Workspace-bound work must not
# reach the template, the version, or a tag.
repo="$(new_repo workspace workspace)"
record "$repo" minor
out="$(release "$repo")" || fail "a workspace-bound source should preview: $out"
printf '%s' "$out" | grep -q 'workspace-bound' \
  || fail "the preview must say a workspace-bound source stops early"
printf '%s' "$out" | grep -qi 'sync to template' \
  && fail "a workspace-bound source must not plan a template sync"
echo "  ok  workspace destination stops before the template"

repo="$(new_repo template template)"
record "$repo" minor
out="$(release "$repo")" || fail "a template-bound source should preview: $out"
printf '%s' "$out" | grep -q 'sync to template' \
  || fail "a template-bound source must plan the full tail"
echo "  ok  template destination plans the full tail"

# Preview must be inert: no version, no tag, no commit beyond what the fixture had.
before="$(git -C "$repo" rev-parse HEAD)"
release "$repo" >/dev/null 2>&1 || true
[[ "$(git -C "$repo" rev-parse HEAD)" == "$before" ]] \
  || fail "preview must not commit anything"
echo "  ok  preview changes nothing"

echo "PASS: spine-release"
