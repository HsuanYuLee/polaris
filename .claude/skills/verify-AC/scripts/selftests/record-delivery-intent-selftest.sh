#!/usr/bin/env bash
# Purpose: Verify delivery intent can only be recorded against a signed, sealed
#          source, and that the record carries what the release tail reads.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a sealed source records its destination and head, a source
#          whose frozen assertions were altered after sealing is refused, a
#          source declaring no destination is refused, and an invalid version
#          bump or a missing summary is rejected before anything is written.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RECORD="$ROOT_DIR/scripts/record-delivery-intent.sh"
FENCE="$ROOT_DIR/scripts/frozen-assertion-fence.sh"
ORACLE="$ROOT_DIR/scripts/run-hardened-oracle.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Description: measure one assertion for real, so the evidence carries the
#   oracle's own producer stamp and the head of the repo it ran in. Writing the
#   JSON by hand here would test a check against a forgery it is meant to catch.
# Args: $1 = repo path, $2 = source dir (absolute), $3 = assertion id
measure() {
  local repo="$1" source="$2" aid="$3"
  (cd "$repo" && bash "$ORACLE" --command 'echo MEASURED' \
     --expect-evidence MEASURED \
     --evidence-out "$source/.spine/evidence/$aid.json" >/dev/null)
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: build a repo holding one source whose fence is sealed and
#   committed, and echo the source dir path (absolute).
# Args: $1 = case name, $2 = destination value ("" to omit the field entirely)
new_sealed_source() {
  local name="$1" destination="$2" repo="$WORK/$1" source
  source="$repo/sources/DP-000-selftest"
  mkdir -p "$source"
  git -C "$repo" init -q 2>/dev/null || { git init -q "$repo"; }
  git -C "$repo" config user.email selftest@example.com
  git -C "$repo" config user.name selftest

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

  bash "$FENCE" seal "$source/index.md" --by selftest >/dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seal selftest source"
  printf '%s' "$source"
}

echo "record-delivery-intent selftest"

# The happy path: a sealed source hands downstream a destination and a head.
source="$(new_sealed_source happy template)"
repo="$WORK/happy"
measure "$repo" "$source" A-P1
(cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
  --version-bump minor --summary 'a line a human will read' >/dev/null) \
  || fail "a sealed source with a destination should record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["destination"] == "template", d
assert d["version_bump"] == "minor", d
assert d["changelog_summary"] == "a line a human will read", d
assert len(d["head_sha"]) >= 12, d
' "$source/.spine/delivery.json" || fail "the record is missing what the release tail reads"
echo "  ok  sealed source records destination and head"

# Delivering against assertions nobody signed is worse than not delivering.
source="$(new_sealed_source tampered template)"
sed -i.bak 's/the thing holds/the thing does not hold/' "$source/index.md"
rm -f "$source/index.md.bak"
repo="$WORK/tampered"
if (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
     --version-bump patch --summary 'x' >/dev/null 2>&1); then
  fail "assertions altered after sealing should refuse to record"
fi
[[ -f "$source/.spine/delivery.json" ]] \
  && fail "a refused recording must not leave a record behind"
echo "  ok  altered assertions refuse to record"

# Without a destination there is no answer to where this ships, and a silent
# default would be exactly the third state the assertions forbid.
source="$(new_sealed_source nodest "")"
repo="$WORK/nodest"
if (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
     --version-bump patch --summary 'x' >/dev/null 2>&1); then
  fail "a source declaring no destination should refuse to record"
fi
echo "  ok  missing destination refuses to record"

# Argument validation happens before any source is read, so a typo cannot
# half-write a record.
source="$(new_sealed_source badargs template)"
repo="$WORK/badargs"
if (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
     --version-bump enormous --summary 'x' >/dev/null 2>&1); then
  fail "an invalid version bump should be rejected"
fi
if (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
     --version-bump patch >/dev/null 2>&1); then
  fail "a missing summary should be rejected"
fi
[[ -f "$source/.spine/delivery.json" ]] \
  && fail "a rejected invocation must not leave a record behind"
echo "  ok  invalid arguments rejected before writing"

# sources/ is the user's own repository nested inside the framework's, so the
# commit that ships and the commit that was judged come from different histories.
# Recording either one twice would pin the release tail to the wrong commit.
source="$(new_sealed_source twoheads template)"
repo="$WORK/twoheads"
(cd "$source/.." && git init -q && git config user.email selftest@example.com \
  && git config user.name selftest && git add -A && git commit -qm "sources of their own")
# The delivering repository moves on; the source repository does not.
echo "shipped work" >> "$repo/tool.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "the work being delivered"
measure "$repo" "$source" A-P1
(cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
  --version-bump patch --summary 'two histories' >/dev/null) \
  || fail "a source in its own repository should still record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
ship, judged = sys.argv[2], sys.argv[3]
assert d["head_sha"] == ship, f"head_sha must be what ships: {d}"
assert d["source_head_sha"] == judged, f"source_head_sha must be what was judged: {d}"
assert d["head_sha"] != d["source_head_sha"], "two histories collapsed into one"
' "$source/.spine/delivery.json" \
  "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$source/.." rev-parse HEAD)" \
  || fail "the record must name both heads, each from its own repository"
echo "  ok  the shipping head and the judged head come from their own repositories"

# An assertion nobody measured is an assertion nobody met. Before this check
# existed, "judge said PASS" travelled the whole way as prose — the last real
# delivery shipped with one of seven assertions carrying no evidence at all.
source="$(new_sealed_source noevidence template)"
repo="$WORK/noevidence"
out="$( (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
  --version-bump patch --summary 'x' 2>&1) )" && fail "an unmeasured assertion should refuse to record"
grep -Fq POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE <<<"$out" \
  || fail "missing evidence did not emit its marker; got: $out"
grep -Fq "A-P1: no evidence" <<<"$out" \
  || fail "the refusal must name which assertion is unmeasured; got: $out"
[[ -f "$source/.spine/delivery.json" ]] \
  && fail "a refused recording must not leave a record behind"
echo "  ok  an unmeasured assertion refuses to record, by name"

# Evidence proves a tree green, not a branch. Measurements taken before the last
# few commits say nothing about what is going out.
source="$(new_sealed_source stale template)"
repo="$WORK/stale"
measure "$repo" "$source" A-P1
echo "one more change after measuring" >> "$repo/tool.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "moved on after the measurement"
out="$( (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
  --version-bump patch --summary 'x' 2>&1) )" && fail "stale evidence should refuse to record"
grep -Fq "A-P1: measured at" <<<"$out" \
  || fail "the refusal must say which head was measured; got: $out"
echo "  ok  evidence from an earlier head refuses to record"

# A hand-written PASS is self-certification. The oracle pins its tools before
# trusting them and keeps the exit code; a JSON file is whoever typed it.
source="$(new_sealed_source handwritten template)"
repo="$WORK/handwritten"
mkdir -p "$source/.spine/evidence"
python3 - "$source/.spine/evidence/A-P1.json" "$(git -C "$repo" rev-parse HEAD)" <<'PY'
import json, sys
json.dump({"schema_version": 1, "producer": "me", "verdict": "PASS",
           "head_sha": sys.argv[2]}, open(sys.argv[1], "w"))
PY
out="$( (cd "$repo" && bash "$RECORD" --source sources/DP-000-selftest \
  --version-bump patch --summary 'x' 2>&1) )" && fail "hand-written evidence should refuse to record"
grep -Fq "not run-hardened-oracle.sh" <<<"$out" \
  || fail "the refusal must name the producer problem; got: $out"
echo "  ok  hand-written evidence refuses to record"

echo "PASS: record-delivery-intent"
