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
  local repo="$1" issue="$2" aid="$3"
  (cd "$repo" && bash "$ORACLE" --command 'echo MEASURED' \
     --expect-evidence MEASURED \
     --evidence-out "$issue/.spine/evidence/$aid.json" >/dev/null)
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Description: build a repo holding one source whose fence is sealed and
#   committed, and echo the source dir path (absolute).
# Args: $1 = case name, $2 = destination value ("" to omit the field entirely)
new_sealed_issue() {
  local name="$1" destination="$2" repo="$WORK/$1" source
  issue="$repo/issues/DP-000-selftest"
  mkdir -p "$issue"
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
  } > "$issue/index.md"

  bash "$FENCE" seal "$issue/index.md" --by selftest >/dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -qm "seal selftest source"

  # 交付紀錄現在會枚舉這張單逼出了哪些檔案，而枚舉是拿 base 做 diff 的。沒有 base 就
  # 解不出交付內容，那是量不到——所以這個 fixture 要有一個 base，不然它量的是「拒絕」
  # 而不是「記得下來」。
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$issue"
}

echo "record-delivery-intent selftest"

# The happy path: a sealed source hands downstream a destination and a head.
issue="$(new_sealed_issue happy template)"
repo="$WORK/happy"
measure "$repo" "$issue" A-P1
(cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'a line a human will read' >/dev/null) \
  || fail "a sealed source with a destination should record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["destination"] == "template", d
assert d["summary"] == "a line a human will read", d
assert len(d["head_sha"]) >= 12, d
' "$issue/.spine/delivery.json" || fail "the record is missing what the release tail reads"
echo "  ok  sealed source records destination and head"

# 版本是釋出模型，可攜層連這個詞都不該認得（DP-467 H-P3）。這一條咬住的是「這裡沒有
# 版號詞彙」——紀錄裡不長出那個欄位，而且那個旗標遞進來會被當成不認得的參數擋掉。
# 上一輪把它做成選填並寫了一段理由，那是半套：一個只有一條釋出尾段看得懂的欄位，
# 只下載了這一支的人永遠不會寫出來。
issue="$(new_sealed_issue noversion template)"
repo="$WORK/noversion"
measure "$repo" "$issue" A-P1
(cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'delivered by ticket and deploy, no version to declare' >/dev/null) \
  || fail "a project with no version model should still be able to record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert "version_bump" not in d, d
assert len(d["head_sha"]) >= 12, d
' "$issue/.spine/delivery.json" || fail "the portable record must not carry a release model's vocabulary"
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     --summary 'x' --version-bump patch >/dev/null 2>&1); then
  fail "--version-bump must no longer be accepted here at all"
fi
echo "  ok  可攜層不認得版號這個詞"

# 交付到一半還在產出脊椎要取代的舊層，紀錄就寫不下去。這個 case 是接線的端到端證明：
# 檢查是由這支腳本呼叫的（不是散文叫人記得跑），而且它真的紅得起來——清單由枚舉器產生，
# 不是手餵的 fixture。
issue="$(new_sealed_issue legacy template)"
repo="$WORK/legacy"
mkdir -p "$repo/specs/design-plans/DP-999-x/tasks/T1"
echo "old layer" > "$repo/specs/design-plans/DP-999-x/tasks/T1/index.md"
git -C "$repo" add -A && git -C "$repo" commit -qm "still running the old machine"
measure "$repo" "$issue" A-P1
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     --summary 'x' >/dev/null 2>&1); then
  fail "a delivery still producing the old layer should refuse to record"
fi
[[ -f "$issue/.spine/delivery.json" ]] \
  && fail "a refused recording must not leave a record behind"
echo "  ok  a delivery still producing the old layer refuses to record"

# Delivering against assertions nobody signed is worse than not delivering.
issue="$(new_sealed_issue tampered template)"
sed -i.bak 's/the thing holds/the thing does not hold/' "$issue/index.md"
rm -f "$issue/index.md.bak"
repo="$WORK/tampered"
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     --summary 'x' >/dev/null 2>&1); then
  fail "assertions altered after sealing should refuse to record"
fi
[[ -f "$issue/.spine/delivery.json" ]] \
  && fail "a refused recording must not leave a record behind"
echo "  ok  altered assertions refuse to record"

# Without a destination there is no answer to where this ships, and a silent
# default would be exactly the third state the assertions forbid.
issue="$(new_sealed_issue nodest "")"
repo="$WORK/nodest"
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     --summary 'x' >/dev/null 2>&1); then
  fail "a source declaring no destination should refuse to record"
fi
echo "  ok  missing destination refuses to record"

# Argument validation happens before any source is read, so a typo cannot
# half-write a record.
issue="$(new_sealed_issue badargs template)"
repo="$WORK/badargs"
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     --summary 'x' --nonsense value >/dev/null 2>&1); then
  fail "an unknown flag should be rejected"
fi
if (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
     >/dev/null 2>&1); then
  fail "a missing summary should be rejected"
fi
[[ -f "$issue/.spine/delivery.json" ]] \
  && fail "a rejected invocation must not leave a record behind"
echo "  ok  invalid arguments rejected before writing"

# issues/ is the user's own repository nested inside the framework's, so the
# commit that ships and the commit that was judged come from different histories.
# Recording either one twice would pin the release tail to the wrong commit.
issue="$(new_sealed_issue twoheads template)"
repo="$WORK/twoheads"
(cd "$issue/.." && git init -q && git config user.email selftest@example.com \
  && git config user.name selftest && git add -A && git commit -qm "sources of their own")
# The delivering repository moves on; the source repository does not.
echo "shipped work" >> "$repo/tool.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "the work being delivered"
measure "$repo" "$issue" A-P1
(cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'two histories' >/dev/null) \
  || fail "a source in its own repository should still record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
ship, judged = sys.argv[2], sys.argv[3]
assert d["head_sha"] == ship, f"head_sha must be what ships: {d}"
assert d["issue_head_sha"] == judged, f"issue_head_sha must be what was judged: {d}"
assert d["head_sha"] != d["issue_head_sha"], "two histories collapsed into one"
' "$issue/.spine/delivery.json" \
  "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$issue/.." rev-parse HEAD)" \
  || fail "the record must name both heads, each from its own repository"
echo "  ok  the shipping head and the judged head come from their own repositories"

# An assertion nobody measured is an assertion nobody met. Before this check
# existed, "judge said PASS" travelled the whole way as prose — the last real
# delivery shipped with one of seven assertions carrying no evidence at all.
issue="$(new_sealed_issue noevidence template)"
repo="$WORK/noevidence"
out="$( (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'x' 2>&1) )" && fail "an unmeasured assertion should refuse to record"
grep -Fq POLARIS_DELIVERY_INTENT_EVIDENCE_INCOMPLETE <<<"$out" \
  || fail "missing evidence did not emit its marker; got: $out"
grep -Fq "A-P1: no evidence" <<<"$out" \
  || fail "the refusal must name which assertion is unmeasured; got: $out"
[[ -f "$issue/.spine/delivery.json" ]] \
  && fail "a refused recording must not leave a record behind"
echo "  ok  an unmeasured assertion refuses to record, by name"

# Evidence proves a tree green, not a branch. Measurements taken before the last
# few commits say nothing about what is going out.
issue="$(new_sealed_issue stale template)"
repo="$WORK/stale"
measure "$repo" "$issue" A-P1
echo "one more change after measuring" >> "$repo/tool.sh"
git -C "$repo" add -A
git -C "$repo" commit -qm "moved on after the measurement"
out="$( (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'x' 2>&1) )" && fail "stale evidence should refuse to record"
grep -Fq "$repo 現在在" <<<"$out" \
  || fail "the refusal must name the tree that moved on; got: $out"
grep -Fq "量完之後又有 commit 落下去了" <<<"$out" \
  || fail "the refusal must say the measurement was overtaken; got: $out"
echo "  ok  evidence from an earlier head refuses to record"

# DP-482. The delivered head used to be `git rev-parse HEAD` wherever this was
# invoked from. That is a different tree from the measured one the moment the
# oracle is pointed elsewhere with --cwd — a ticket living in issues/ while its
# code lands in a product repo is the ordinary case, not the exotic one — and the
# record then named a commit no measurement had ever seen.
issue="$(new_sealed_issue elsewhere template)"
repo="$WORK/elsewhere"
caller="$WORK/caller-not-the-measured-tree"
mkdir -p "$caller"
git init -q "$caller"
git -C "$caller" config user.email selftest@example.com
git -C "$caller" config user.name selftest
echo unrelated > "$caller/unrelated.txt"
git -C "$caller" add -A
git -C "$caller" commit -qm "a history that has nothing to do with the delivery"
(cd "$caller" && bash "$ORACLE" --command 'echo MEASURED' --cwd "$repo" \
   --expect-evidence MEASURED \
   --evidence-out "$issue/.spine/evidence/A-P1.json" >/dev/null)
(cd "$caller" && bash "$RECORD" --issue "$issue" \
  --summary 'measured over there' >/dev/null) \
  || fail "a delivery measured in another tree should still record"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["head_sha"] == sys.argv[2], f"head must come from the measured tree: {d}"
assert d["head_sha"] != sys.argv[3], "the head came from the caller, not the measurement"
assert "delivering_repo" not in d, f"delivering_repo is a second answer, and it is gone: {d}"
' "$issue/.spine/delivery.json" \
  "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$caller" rev-parse HEAD)" \
  || fail "the delivered head must be the tree the oracle measured"
echo "  ok  交付的 head 來自量測的那棵樹，不是呼叫者站的地方"

# A hand-written PASS is self-certification. The oracle pins its tools before
# trusting them and keeps the exit code; a JSON file is whoever typed it.
issue="$(new_sealed_issue handwritten template)"
repo="$WORK/handwritten"
mkdir -p "$issue/.spine/evidence"
python3 - "$issue/.spine/evidence/A-P1.json" "$(git -C "$repo" rev-parse HEAD)" <<'PY'
import json, sys
json.dump({"schema_version": 1, "producer": "me", "verdict": "PASS",
           "head_sha": sys.argv[2]}, open(sys.argv[1], "w"))
PY
out="$( (cd "$repo" && bash "$RECORD" --issue issues/DP-000-selftest \
  --summary 'x' 2>&1) )" && fail "hand-written evidence should refuse to record"
grep -Fq "not run-hardened-oracle.sh" <<<"$out" \
  || fail "the refusal must name the producer problem; got: $out"
echo "  ok  hand-written evidence refuses to record"

echo "PASS: record-delivery-intent"
