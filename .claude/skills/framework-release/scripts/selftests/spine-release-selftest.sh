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

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
# 這支住在 framework-release 底下，但它測的是「verify-ac 寫紀錄 → 這裡出貨」的握手。
# fixture 刻意用 verify-ac 真的那幾支，不自己捏一份——兩半各自對著自己的 fixture 綠燈，
# 第一次真的握手就斷，那是這個 source 已經踩過的坑。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFY_AC="$(cd "$(dirname "$0")/../../../verify-ac/scripts" && pwd)"
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
  # 一支最小的 skill，帶一支會過的 selftest。釋出尾段會跑全套 selftest（那是全 repo 唯一
  # 問「沒動到的那幾支還是綠的嗎」的地方），所以 fixture 要長得像一個真的 Polaris repo；
  # 一個沒有 .claude/skills 的樹會讓那一步回「量不到」，而那是對的。
  mkdir -p "$repo/.claude/skills/demo/selftests"
  echo '# demo' > "$repo/.claude/skills/demo/SKILL.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/.claude/skills/demo/selftests/demo-selftest.sh"
  git init -q "$repo"
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest

  issue="$repo/issues/ns/DP-000-selftest"
  mkdir -p "$issue"
  {
    echo "---"
    echo "title: selftest source"
    [[ -n "$destination" ]] && echo "destination: $destination"
    echo "---"
    echo
    echo "<!-- POLARIS-FROZEN-A-BEGIN -->"
    echo "- A-P1 the thing holds."
    echo "<!-- POLARIS-FROZEN-A-END -->"
  } > "$issue/index.md"

  bash "$VERIFY_AC/frozen-assertion-fence.sh" seal "$issue/index.md" --by selftest >/dev/null
  echo "scripts" > "$repo/.gitignore"
  git -C "$repo" add -A
  git -C "$repo" commit -qm base
  git -C "$repo" branch -f origin/main HEAD
  printf '%s' "$repo"
}

record() {
  # Description: record delivery intent inside a fixture repo. The fence's one
  #   assertion is measured first, at the head about to be recorded, because
  #   recording refuses an assertion nobody proved.
  # Args: $1 = repo
  #
  # 量測命令也要登錄——交付那條路會問「證據記的是不是這條斷言簽過的那一條」，而一張沒有
  # 登錄的單少的是一整層，不是一個可以跳過的欄位。
  bash "$VERIFY_AC/record-measurement-change.sh" record \
    --ledger "$1/issues/ns/DP-000-selftest/.spine/measurement-ledger.json" \
    --assertion-id A-P1 --new-command 'echo MEASURED' --baseline >/dev/null
  (cd "$1" && bash "$VERIFY_AC/run-hardened-oracle.sh" \
    --command 'echo MEASURED' --expect-evidence MEASURED \
    --evidence-out "$1/issues/ns/DP-000-selftest/.spine/evidence/A-P1.json" >/dev/null)
  (cd "$1" && bash "$VERIFY_AC/record-delivery-intent.sh" \
    --issue issues/ns/DP-000-selftest --summary 'a line' >/dev/null)
}

release() {
  # Description: run the release tail in preview mode inside a fixture repo.
  # Args: $1 = repo
  (cd "$1" && bash "$ROOT_DIR/scripts/spine-release.sh" \
    --repo "$1" --issue issues/ns/DP-000-selftest 2>&1)
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
record "$repo"
python3 -c '
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["destination"] = "somewhere-else"
json.dump(d, open(p, "w"))
' "$repo/issues/ns/DP-000-selftest/.spine/delivery.json"
if release "$repo" >/dev/null 2>&1; then
  fail "an unknown destination should refuse to release"
fi
echo "  ok  unknown destination refuses"

# Shipping against assertions that changed after signing is the failure the
# whole fence exists to prevent, so it is checked here too rather than trusted
# from whenever the record was written.
repo="$(new_repo tampered template)"
record "$repo"
sed -i.bak 's/the thing holds/the thing does not hold/' "$repo/issues/ns/DP-000-selftest/index.md"
rm -f "$repo/issues/ns/DP-000-selftest/index.md.bak"
if release "$repo" >/dev/null 2>&1; then
  fail "altered assertions should refuse to release"
fi
echo "  ok  altered assertions refuse"

# A record left behind by later commits describes different work than the one
# about to ship.
repo="$(new_repo stale template)"
# The record has to sit on a commit origin does not already have, otherwise it
# reads as shipped rather than stale and this case proves nothing.
echo "the work" >> "$repo/issues/ns/DP-000-selftest/notes.md"
git -C "$repo" add -A
git -C "$repo" commit -qm "the work being delivered"
record "$repo"
echo "later work" >> "$repo/issues/ns/DP-000-selftest/notes.md"
git -C "$repo" add -A
git -C "$repo" commit -qm "work after recording"
if release "$repo" >/dev/null 2>&1; then
  fail "a record behind HEAD should refuse to release"
fi
echo "  ok  stale record refuses"

# The destination decides how far the tail goes. Workspace-bound work must not
# reach the template, the version, or a tag.
repo="$(new_repo workspace workspace)"
record "$repo"
out="$(release "$repo")" || fail "a workspace-bound source should preview: $out"
printf '%s' "$out" | grep -q 'workspace-bound' \
  || fail "the preview must say a workspace-bound source stops early"
printf '%s' "$out" | grep -qi 'sync to template' \
  && fail "a workspace-bound source must not plan a template sync"
echo "  ok  workspace destination stops before the template"

# 一支紅的 selftest 不得跟著版本一起出去。這是全 repo 唯一問「沒動到的那幾支還是綠的嗎」
# 的地方——v4.17.0 帶著一支紅的出去，就是因為當時沒有任何地方問這句話。
repo="$(new_repo redselftest template)"
record "$repo"
printf '#!/usr/bin/env bash\nexit 1\n' \
  > "$repo/.claude/skills/demo/selftests/demo-selftest.sh"
out="$(release "$repo" 2>&1 || true)"
if release "$repo" >/dev/null 2>&1; then
  fail "a red selftest must stop the release"
fi
printf '%s' "$out" | grep -q 'POLARIS_SPINE_RELEASE_SELFTESTS_RED' \
  || fail "the release must say which check stopped it: $out"
printf '%s' "$out" | grep -q 'demo-selftest.sh' \
  || fail "the release must name the red selftest: $out"
echo "  ok  a red selftest stops the release and gets named"

repo="$(new_repo template template)"
record "$repo"
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

# "Has this version already been released?" has to be asked of origin. The
# template repository is a remote of the workspace and versions the same way, so
# its tags sit locally under identical names pointing at different commits. Asking
# the local namespace made the tail skip its own tag and still report success.
probe_repo="$WORK/tag-probe"
mkdir -p "$probe_repo"
ln -s "$ROOT_DIR/scripts" "$probe_repo/scripts"
git init -q "$probe_repo"
git -C "$probe_repo" config user.email selftest@example.com
git -C "$probe_repo" config user.name selftest
printf 'seed\n' > "$probe_repo/seed"
git -C "$probe_repo" add seed
git -C "$probe_repo" commit -qm seed

git init -q --bare "$WORK/origin.git"
git init -q --bare "$WORK/template.git"
git -C "$probe_repo" remote add origin "$WORK/origin.git"
git -C "$probe_repo" remote add template "$WORK/template.git"
git -C "$probe_repo" push -q origin HEAD:refs/heads/main

# The template releases v9.9.9 and the tag is fetched, exactly as it is in the
# real workspace. Origin has no such tag.
git -C "$probe_repo" tag v9.9.9
git -C "$probe_repo" push -q template v9.9.9

answer="$(bash "$ROOT_DIR/scripts/spine-release.sh" --repo "$probe_repo" --origin-has-tag v9.9.9)"
[[ -z "$answer" ]] \
  || fail "a tag that only the template has must not count as released on origin"
echo "  ok  a template-only tag does not read as released"

git -C "$probe_repo" push -q origin v9.9.9
answer="$(bash "$ROOT_DIR/scripts/spine-release.sh" --repo "$probe_repo" --origin-has-tag v9.9.9)"
[[ -n "$answer" ]] || fail "a tag origin actually has must read as released"
echo "  ok  a tag on origin reads as released"

echo "PASS: spine-release"
