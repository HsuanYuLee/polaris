#!/usr/bin/env bash
# Purpose: Verify the spine delivery gate blocks exactly one thing — a delivery
#          record describing a different commit than the one being pushed — and
#          that it decides relevance from the head the record names.
# Inputs:  Hermetic git repositories under mktemp.
# Outputs: PASS when a record pinned to HEAD passes, a record left behind by
#          later commits blocks, a record for work already in origin/main is
#          ignored, a repo with no record is disclaimed, a push that changes
#          nothing under issues/ is still recognised by its record, a record
#          whose ticket declared it lands elsewhere is announced but not judged
#          (and blocks when that ticket is the one being released), and --issue
#          keeps another ticket's record out of the verdict.

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

# 往上兩層是這支 skill 自己的目錄，所以下面的 $ROOT_DIR/scripts/X 指的是
# 這支 skill 帶著的那一份，不是 repo 根目錄的共用檔——共用檔已經沒有了。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/gate-spine-delivery.sh"
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
  mkdir -p "$repo/issues/ns/DP-000-selftest/.spine" "$repo/scripts"
  echo assertion > "$repo/issues/ns/DP-000-selftest/index.md"
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
json.dump({"schema_version": 1, "source": "issues/ns/DP-000-selftest",
           "head_sha": sys.argv[2]}, open(sys.argv[1], "w"))
' "$1/issues/ns/DP-000-selftest/.spine/delivery.json" "$2"
}

# Description: give a ticket the one declaration of where its work lands, the
#   same shape `spine-loop-state.sh init --where` writes.
# Args: $1 = repo, $2 = repo-relative issue dir, $3.. = declared landing values
declare_landing() {
  local repo="$1" issue="$2"
  shift 2
  python3 -c '
import json, sys
json.dump({"schema_version": 1,
           "workspace_identity": {"kind": "declared", "declared_landing": sys.argv[2:]},
           "knowledge_pack": {"pack": "swe-knowledge"}}, open(sys.argv[1], "w"))
' "$repo/$issue/.spine/loop-state.json" "$@"
}

# Description: add a commit that touches only scripts/, never issues/.
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
# in scripts/ or skills/, and only the record lives under issues/. Deciding
# relevance by which files changed missed real deliveries entirely, so the gate
# silently handed them to a gate that demands a task.md they cannot have.
if ! bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "a push changing nothing under issues/ must still be recognised by its record"
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

# A record pinned to a commit this repository does not contain used to fall
# through both ancestry tests and disappear, which read as "no record concerns
# this push" — and the release tail then announced "record current" from a check
# that had examined nothing. With no declaration to say the work belongs
# somewhere else, this gate cannot judge it, and unjudgeable is a refusal.
repo="$(new_repo foreignhead)"
commit_work_outside_sources "$repo" "work in progress"
write_record "$repo" "0000000000000000000000000000000000000001"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  fail "a record pinned to a commit that is not here should block"
fi
bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1 \
  || fail "an unusable record must stay owned here rather than pass to another gate"
refusal="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
printf '%s' "$refusal" | grep -q 'does not contain' \
  || fail "the refusal must say the recorded commit is not in this repository: $refusal"
printf '%s' "$refusal" | grep -q '沒有宣告過改動會落在哪' \
  || fail "拒絕的理由要說出「判不動」而不是「不是我的」：$refusal"
echo "  ok  a record pinned outside this repository blocks"

# DP-482. `issues/` is one directory shared by every repository its owner works
# in, so a ticket whose code landed in a product repo sits next to the
# framework's own records with a head that correctly is not here. That is not a
# stale record and it is not a broken one — the ticket said where it would land,
# and the gate reads that one declaration rather than deriving a second answer.
# Before this, a single product-repo delivery blocked every framework release.
repo="$(new_repo declaredelsewhere)"
commit_work_outside_sources "$repo" "framework work"
write_record "$repo" "0000000000000000000000000000000000000001"
declare_landing "$repo" issues/ns/DP-000-selftest /somewhere/else
bash "$GATE" --repo "$repo" >/dev/null 2>&1 \
  || fail "a record whose ticket declared it lands elsewhere must not block this repository"
skip="$(bash "$GATE" --repo "$repo" 2>&1 || true)"
printf '%s' "$skip" | grep -q '/somewhere/else' \
  || fail "跳過的那一份要連同它宣告的落腳處一起印出來，不然跳過看起來就跟判過一樣：$skip"
if bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1; then
  fail "someone else's record must not make this a spine push"
fi
echo "  ok  宣告落在別處的紀錄：印出來、不判、不擋"

# The other half of the same split. Announcing a foreign record is right when
# scanning everything; it is wrong when the caller named this ticket, because
# then "the commit is not here" means the release was started in the wrong
# place. spine-release.sh always names the ticket it is releasing.
if bash "$GATE" --repo "$repo" --issue issues/ns/DP-000-selftest >/dev/null 2>&1; then
  fail "naming a ticket whose commit is not in this repository should block"
fi
named="$(bash "$GATE" --repo "$repo" --issue issues/ns/DP-000-selftest 2>&1 || true)"
printf '%s' "$named" | grep -q '/somewhere/else' \
  || fail "被指名而擋下來的時候，訊息要說出這張單宣告的落腳處在哪：$named"
echo "  ok  指名一張落在別處的單就擋，並說出它該去哪"

# --issue is scoping, not a hint: releasing one ticket must not be held up by
# another ticket's record. Scanning every record and then working out which ones
# were this repo's business is what made a second "where does this land" answer
# necessary in the first place.
repo="$(new_repo scoped)"
commit_work_outside_sources "$repo" "work for A"
mkdir -p "$repo/issues/ns/DP-002-other/.spine"
echo assertion > "$repo/issues/ns/DP-002-other/index.md"
python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "issues/ns/DP-002-other",
           "head_sha": sys.argv[2]}, open(sys.argv[1], "w"))
' "$repo/issues/ns/DP-002-other/.spine/delivery.json" "$(git -C "$repo" rev-parse HEAD)"
commit_work_outside_sources "$repo" "work for B"
write_record "$repo" "$(git -C "$repo" rev-parse HEAD)"
if bash "$GATE" --repo "$repo" >/dev/null 2>&1; then
  fail "the unscoped scan must still see the stale record"
fi
bash "$GATE" --repo "$repo" --issue issues/ns/DP-000-selftest >/dev/null 2>&1 \
  || fail "another ticket's stale record must not block the ticket that was named"
echo "  ok  --issue 圈住判定範圍，別張單的紀錄不參與"

# 收斂完的單住在 {命名空間}/archive/。交付紀錄只有在收斂之後才寫得出來，而收斂那一刻
# 歸檔器就把單搬過去——所以只掃活躍區那一層的話，這道閘對每一次真實交付都會回
# 「這不是脊椎推送」，然後促進 main 被擋。2026-08-03 三張單全部撞上。
repo="$(new_repo archived)"
commit_work_outside_sources "$repo" "work in progress"
head="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$repo/issues/ns/archive/DP-001-archived/.spine"
echo assertion > "$repo/issues/ns/archive/DP-001-archived/index.md"
python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "issues/ns/archive/DP-001-archived",
           "destination": "template", "head_sha": sys.argv[2], "version_bump": "patch"},
          open(sys.argv[1], "w"))
' "$repo/issues/ns/archive/DP-001-archived/.spine/delivery.json" "$head"
bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1 \
  || fail "歸檔後的交付紀錄沒被看見——這道閘只掃了活躍區那一層"
bash "$GATE" --repo "$repo" --print-records 2>&1 | grep -q 'archive/DP-001-archived' \
  || fail "歸檔後的交付紀錄沒有被列出來"
echo "  ok  收斂歸檔後的交付紀錄仍然看得見"

# DP-481 把兩格版面換成六格，收斂並釋出的單住在 {命名空間}/released/{釋出日}/——比以前
# 多一層。以前這裡寫死兩種深度，多的那一層掃不到，而掃不到不會爆炸：它只會讓這道閘回
# 「這不是脊椎推送」，跟真的無關長得一模一樣。
repo="$(new_repo released_day)"
commit_work_outside_sources "$repo" "work in progress"
head="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$repo/issues/ns/released/2026-08-07/DP-002-shipped/.spine"
echo assertion > "$repo/issues/ns/released/2026-08-07/DP-002-shipped/index.md"
python3 -c '
import json, sys
json.dump({"schema_version": 1, "source": "issues/ns/released/2026-08-07/DP-002-shipped",
           "destination": "template", "head_sha": sys.argv[2], "version_bump": "patch"},
          open(sys.argv[1], "w"))
' "$repo/issues/ns/released/2026-08-07/DP-002-shipped/.spine/delivery.json" "$head"
bash "$GATE" --repo "$repo" --is-spine-push >/dev/null 2>&1 \
  || fail "released/{日期}/ 底下的交付紀錄沒被看見——枚舉又預設了深度"
bash "$GATE" --repo "$repo" --print-records 2>&1 | grep -q 'released/2026-08-07/DP-002-shipped' \
  || fail "released/{日期}/ 底下的交付紀錄沒有被列出來"
echo "  ok  released/{日期}/ 又多一層，交付紀錄照樣看得見"

echo "PASS: gate-spine-delivery"
