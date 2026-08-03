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
printf 'echo work\n' > "$REPO/scripts/thing.sh"
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
assert "scripts/thing.sh" in listed, "the changed work file should still be listed"
assert "scripts/thing.sh" not in forced, "the work itself must not be charged"

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

echo "PASS: enumerate-spine-inventory"
