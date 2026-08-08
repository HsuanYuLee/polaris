#!/usr/bin/env bash
# Purpose: Verify the inventory enumerator reports what a delivery actually left
#          behind, and fails rather than flattering itself when it cannot.
# Inputs:  a throwaway git repository under mktemp.
# Outputs: PASS when the living document and the .spine state on disk are charged,
#          a changeset is charged, the work itself is listed but not charged,
#          kind follows the changed paths, and an unresolvable base fails loudly.

set -euo pipefail

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ENUM="$ROOT_DIR/scripts/enumerate-spine-inventory.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "enumerate-spine-inventory selftest"

REPO="$WORK/repo"
SRC="issues/DP-000-example"
mkdir -p "$REPO/$SRC/.spine" "$REPO/scripts" "$REPO/.changeset"
git -C "$REPO" init -q
git -C "$REPO" config user.email selftest@example.com
git -C "$REPO" config user.name selftest
printf 'seed\n' > "$REPO/seed"
git -C "$REPO" add -A
git -C "$REPO" commit -qm seed
BASE="$(git -C "$REPO" rev-parse HEAD)"

printf 'living document\n' > "$REPO/$SRC/index.md"
printf '{}\n' > "$REPO/$SRC/.spine/loop-state.json"
printf '{}\n' > "$REPO/$SRC/.spine/delivery.json"
mkdir -p "$REPO/fixture"
printf 'echo work\n' > "$REPO/fixture/thing.sh"
printf -- '---\nnote\n' > "$REPO/.changeset/example.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm work

( cd "$REPO" && bash "$ENUM" --issue "$SRC" --base "$BASE" >/dev/null 2>&1 ) \
  || fail "the enumerator refused a well-formed delivery"

python3 - "$REPO/$SRC/.spine/inventory.json" "$SRC" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
src = sys.argv[2]
forced = {a["path"] for a in data["artifacts"] if a["forced"]}
listed = {a["path"] for a in data["artifacts"]}

for path in (f"{src}/index.md", f"{src}/.spine/loop-state.json",
             f"{src}/.spine/delivery.json", ".changeset/example.md"):
    assert path in forced, f"{path} should be charged as forced"

# The work is what the delivery is for, not the toll the process charges.
assert "fixture/thing.sh" in listed, "the changed work file should still be listed"
assert "fixture/thing.sh" not in forced, "the work itself must not be charged"

# Every charged file has to say why the flow cannot finish without it; the cost
# floor check rejects a forced entry with no reason.
for a in data["artifacts"]:
    if a["forced"]:
        assert a.get("reason", "").strip(), f"{a['path']} is charged with no reason"

assert data["kind"] == "code", f"a delivery touching scripts/ is code work, got {data['kind']}"
PY
echo "  ok  living document, spine state and changeset are charged; the work is not"

# A ledger that is not on disk must not be invented: the toll is what the flow
# actually forced this time, not what it could force.
python3 - "$REPO/$SRC/.spine/inventory.json" "$SRC" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
paths = {a["path"] for a in data["artifacts"]}
assert f"{sys.argv[2]}/.spine/measurement-ledger.json" not in paths, \
    "an absent ledger must not be listed"
PY
echo "  ok  absent state is not invented"

# Docs-only work is a different floor, so the kind must follow the paths.
DOCS_REPO="$WORK/docs-repo"
mkdir -p "$DOCS_REPO/$SRC/.spine"
git -C "$DOCS_REPO" init -q
git -C "$DOCS_REPO" config user.email selftest@example.com
git -C "$DOCS_REPO" config user.name selftest
printf 'seed\n' > "$DOCS_REPO/seed"
git -C "$DOCS_REPO" add -A
git -C "$DOCS_REPO" commit -qm seed
DOCS_BASE="$(git -C "$DOCS_REPO" rev-parse HEAD)"
printf 'living document\n' > "$DOCS_REPO/$SRC/index.md"
git -C "$DOCS_REPO" add -A
git -C "$DOCS_REPO" commit -qm docs
( cd "$DOCS_REPO" && bash "$ENUM" --issue "$SRC" --base "$DOCS_BASE" >/dev/null 2>&1 ) \
  || fail "the enumerator refused a docs-only delivery"
python3 - "$DOCS_REPO/$SRC/.spine/inventory.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8"))["kind"] == "docs"
PY
echo "  ok  docs-only work is enumerated as docs"

# An unresolvable base would produce an empty diff, and an empty diff reads as
# "this delivery forced nothing" — the most flattering possible failure.
if ( cd "$REPO" && bash "$ENUM" --issue "$SRC" --base refs/heads/does-not-exist >/dev/null 2>&1 ); then
  fail "an unresolvable base should fail, not report an empty delivery"
fi
echo "  ok  an unresolvable base fails loudly"

if ( cd "$REPO" && bash "$ENUM" --issue issues/DP-999-absent >/dev/null 2>&1 ); then
  fail "a missing source should fail, not pass vacuously"
fi
echo "  ok  a missing source fails loudly"

# DP-482. A ticket lives in issues/ — the user's own repository — while its code
# lands in whatever product repo the work is for. Those are two trees, and this
# enumerator used to ask the one the caller happened to be standing in. It then
# answered "what did this delivery leave behind" from a history that contains
# none of the delivery, and the legacy-layer check reads that answer.
PAPERS="$WORK/papers"
CODE="$WORK/code"
mkdir -p "$PAPERS/issues/DP-001-elsewhere/.spine"
for tree in "$PAPERS" "$CODE"; do
  git -C "$tree" init -q 2>/dev/null || git init -q "$tree"
  git -C "$tree" config user.email selftest@example.com
  git -C "$tree" config user.name selftest
done
printf 'living document\n' > "$PAPERS/issues/DP-001-elsewhere/index.md"
printf '{}\n' > "$PAPERS/issues/DP-001-elsewhere/.spine/loop-state.json"
git -C "$PAPERS" add -A
git -C "$PAPERS" commit -qm "the paperwork, and nothing else"
printf 'seed\n' > "$CODE/seed"
git -C "$CODE" add -A
git -C "$CODE" commit -qm seed
CODE_BASE="$(git -C "$CODE" rev-parse HEAD)"
mkdir -p "$CODE/src"
printf 'echo the actual delivery\n' > "$CODE/src/feature.sh"
git -C "$CODE" add -A
git -C "$CODE" commit -qm "the work this ticket is for"

( cd "$PAPERS" && bash "$ENUM" --issue issues/DP-001-elsewhere --repo "$CODE" \
    --base "$CODE_BASE" >/dev/null 2>&1 ) \
  || fail "a ticket whose code landed in another tree should still enumerate"
python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
listed = {a["path"] for a in data["artifacts"]}
forced = {a["path"] for a in data["artifacts"] if a["forced"]}
assert "src/feature.sh" in listed, f"the delivery in the other tree was not seen: {listed}"
assert data["kind"] == "code", f"code landing elsewhere is still code: {data}"
assert "issues/DP-001-elsewhere/index.md" in forced, f"the ticket itself is still charged: {forced}"
' "$PAPERS/issues/DP-001-elsewhere/.spine/inventory.json" \
  || fail "the inventory must come from the tree the delivery landed in"
echo "  ok  單住在一棵樹、改動落在另一棵，清單看的是改動那一棵"

# Falling back is a guess, and a silent guess reads exactly like a known fact.
note="$( (cd "$PAPERS" && bash "$ENUM" --issue issues/DP-001-elsewhere \
  --base HEAD 2>&1 >/dev/null) )"
grep -Fq 'NOTE: --repo 沒有給' <<<"$note" \
  || fail "退回用單自己住的 repo 的時候要說出來；got: $note"
echo "  ok  沒有給 --repo 就說出它退回去問了哪一棵樹"

# DP-482. The default base was the literal string origin/main, so this refused
# every repository whose default branch is called something else — and the first
# real cross-repo delivery landed in one whose branch is master. That is not the
# ticket being wrong; it is this script assuming every repository in the world is
# shaped like the framework's own.
MASTERISH="$WORK/masterish"
mkdir -p "$MASTERISH/issues/DP-002-master/.spine"
git init -q "$MASTERISH"
git -C "$MASTERISH" config user.email selftest@example.com
git -C "$MASTERISH" config user.name selftest
printf 'living document\n' > "$MASTERISH/issues/DP-002-master/index.md"
git -C "$MASTERISH" add -A
git -C "$MASTERISH" commit -qm seed
git -C "$MASTERISH" update-ref refs/remotes/origin/master HEAD
printf 'echo work\n' > "$MASTERISH/tool.sh"
git -C "$MASTERISH" add -A
git -C "$MASTERISH" commit -qm work
note="$( (cd "$MASTERISH" && bash "$ENUM" --issue issues/DP-002-master 2>&1 >/dev/null) )" \
  || fail "a repository whose default branch is master should still enumerate: $note"
grep -Fq 'origin/master' <<<"$note" \
  || fail "退回去找預設分支的時候要說出它找到哪一個；got: $note"
python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
listed = {a["path"] for a in data["artifacts"]}
assert "tool.sh" in listed, f"the diff against origin/master saw nothing: {listed}"
' "$MASTERISH/issues/DP-002-master/.spine/inventory.json" \
  || fail "預設分支不叫 main 的 repo 量出來是一份空的交付"
echo "  ok  預設分支不叫 main 的 repo 也量得到"

echo "PASS: enumerate-spine-inventory"
